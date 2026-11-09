## The Subsonic REST API, pure: URLs, token auth, and the parsing of its JSON into rows. No node, no network.
## https://www.subsonic.org/pages/api.jsp ; Navidrome (and others) speak it with the OpenSubsonic additions.
##
## AUTH is the API's token scheme: every call carries `u` (user), `s` (a random salt) and
## `t = md5(password + salt)`. The password is never put in a URL: sign-in derives (salt, token) once and the
## pair is what is kept (sb_config.gd). The pair IS a credential for that server, so it is redacted from every
## logged URL (`redact`).
extends RefCounted

const API_VERSION := "1.16.1"
const CLIENT_NAME := "RetroXR"


## "audio.example.org" -> "https://audio.example.org"; an address that is a bare IP, localhost or carries a port
## is a LAN server and gets http. A scheme the player typed is kept. Trailing slashes and a "/rest" tail go.
static func normalize_server(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	if not (s.begins_with("http://") or s.begins_with("https://")):
		var host := s.get_slice("/", 0)
		var lan := host.begins_with("localhost") or host.contains(":") or _is_ipv4(host.get_slice(":", 0))
		s = ("http://" if lan else "https://") + s
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("/rest"):
		s = s.substr(0, s.length() - 5)
	return s


static func _is_ipv4(host: String) -> bool:
	var parts := host.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if p.is_empty() or not p.is_valid_int():
			return false
	return true


## 12 random hex characters: the salt of one sign-in.
static func make_salt() -> String:
	return Crypto.new().generate_random_bytes(6).hex_encode()


## The API's token: md5(password + salt), lower-case hex.
static func make_token(password: String, salt: String) -> String:
	return (password + salt).md5_text()


## `pairs` is [[key, value], ...] (an Array, so the order is the one written and a key may repeat: songId=1&songId=2).
static func query(pairs: Array) -> String:
	var parts := PackedStringArray()
	for p: Array in pairs:
		parts.append("%s=%s" % [str(p[0]).uri_encode(), str(p[1]).uri_encode()])
	return "&".join(parts)


## Full URL of a call: base + /rest/<endpoint>.view + the auth pairs + the call's own.
static func url(base: String, endpoint: String, user: String, token: String, salt: String, extra: Array = []) -> String:
	var pairs: Array = [["u", user], ["t", token], ["s", salt], ["v", API_VERSION], ["c", CLIENT_NAME], ["f", "json"]]
	pairs.append_array(extra)
	return "%s/rest/%s.view?%s" % [base, endpoint, query(pairs)]


## A URL as it may be written to a log: token, salt and a clear password are hidden.
static func redact(url_text: String) -> String:
	var rx := RegEx.new()
	rx.compile("([?&](?:t|s|p))=[^&\\s\"]*")
	return rx.sub(url_text, "$1=***", true)


# --- the calls -----------------------------------------------------------------------------------------

static func ping() -> Array:
	return ["ping", []]


static func get_artists() -> Array:
	return ["getArtists", []]


static func get_artist(id: String) -> Array:
	return ["getArtist", [["id", id]]]


static func get_album(id: String) -> Array:
	return ["getAlbum", [["id", id]]]


## `kind`: newest, recent, frequent, random, alphabeticalByName, alphabeticalByArtist, starred.
static func get_album_list(kind: String, size: int = 40, offset: int = 0) -> Array:
	return ["getAlbumList2", [["type", kind], ["size", size], ["offset", offset]]]


static func search(text: String, artists: int = 8, albums: int = 12, songs: int = 30) -> Array:
	return ["search3", [["query", text], ["artistCount", artists], ["albumCount", albums], ["songCount", songs]]]


static func get_playlists() -> Array:
	return ["getPlaylists", []]


static func get_playlist(id: String) -> Array:
	return ["getPlaylist", [["id", id]]]


## The audio itself. `format` "" asks for the file as it is (raw); "mp3" asks the server to transcode, with
## `max_bitrate` kbps (0 = the server's own choice).
static func stream(id: String, format: String = "", max_bitrate: int = 0) -> Array:
	var pairs: Array = [["id", id]]
	pairs.append(["format", format if not format.is_empty() else "raw"])
	if max_bitrate > 0 and not format.is_empty():
		pairs.append(["maxBitRate", max_bitrate])
	return ["stream", pairs]


## The stations the server keeps (Navidrome: Settings > Radios).
static func get_radio_stations() -> Array:
	return ["getInternetRadioStations", []]


static func cover_art(id: String, size: int = 256) -> Array:
	return ["getCoverArt", [["id", id], ["size", size]]]


# --- the answers ---------------------------------------------------------------------------------------

## {ok, code, message, body}: `body` is the "subsonic-response" dictionary. A "failed" status carries an error
## ({code, message}): 40 = wrong user or password, 41 = token auth not supported, 50 = not allowed, 70 = not found.
static func parse_response(data: Variant) -> Dictionary:
	if not (data is Dictionary) or not (data as Dictionary).has("subsonic-response"):
		return {"ok": false, "code": -1, "message": "not a Subsonic answer", "body": {}}
	var body: Dictionary = (data as Dictionary)["subsonic-response"]
	if str(body.get("status", "")) == "ok":
		return {"ok": true, "code": 0, "message": "", "body": body}
	var err: Dictionary = body.get("error", {}) if body.get("error") is Dictionary else {}
	return {"ok": false, "code": int(err.get("code", -1)), "message": str(err.get("message", "failed")), "body": body}


## A list that the API may send as a single object (its XML-derived JSON did, once) or leave out.
static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return [v]
	return []


## getArtists -> [{id, name, albums}] sorted as the server's index order (A, B, ...), articles ignored by the server.
static func artists(body: Dictionary) -> Array:
	var out: Array = []
	var root: Dictionary = body.get("artists", {}) if body.get("artists") is Dictionary else {}
	for idx: Variant in _arr(root.get("index")):
		for a: Variant in _arr((idx as Dictionary).get("artist")):
			var d: Dictionary = a
			out.append({"id": str(d.get("id", "")), "name": str(d.get("name", "?")),
				"albums": int(d.get("albumCount", 0))})
	return out


static func _album_row(d: Dictionary) -> Dictionary:
	return {"id": str(d.get("id", "")), "name": str(d.get("name", d.get("title", "?"))),
		"artist": str(d.get("artist", "")), "year": int(d.get("year", 0)), "songs": int(d.get("songCount", 0)),
		"duration": int(d.get("duration", 0)), "cover": str(d.get("coverArt", ""))}


## getArtist -> {artist, albums: [...]}
static func artist_albums(body: Dictionary) -> Dictionary:
	var root: Dictionary = body.get("artist", {}) if body.get("artist") is Dictionary else {}
	var rows: Array = []
	for a: Variant in _arr(root.get("album")):
		rows.append(_album_row(a))
	return {"artist": str(root.get("name", "")), "albums": rows}


## getAlbumList2 -> [album rows]
static func album_list(body: Dictionary) -> Array:
	var root: Dictionary = body.get("albumList2", {}) if body.get("albumList2") is Dictionary else {}
	var rows: Array = []
	for a: Variant in _arr(root.get("album")):
		rows.append(_album_row(a))
	return rows


static func song_row(d: Dictionary) -> Dictionary:
	return {"id": str(d.get("id", "")), "title": str(d.get("title", "?")), "artist": str(d.get("artist", "")),
		"album": str(d.get("album", "")), "track": int(d.get("track", 0)), "disc": int(d.get("discNumber", 1)),
		"duration": int(d.get("duration", 0)), "suffix": str(d.get("suffix", "")),
		"size": int(d.get("size", 0)), "cover": str(d.get("coverArt", "")), "bitrate": int(d.get("bitRate", 0))}


## getAlbum -> {album, artist, cover, songs: [...]} (songs in disc, track order)
static func album_songs(body: Dictionary) -> Dictionary:
	var root: Dictionary = body.get("album", {}) if body.get("album") is Dictionary else {}
	var rows: Array = []
	for s: Variant in _arr(root.get("song")):
		rows.append(song_row(s))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [a["disc"], a["track"]] < [b["disc"], b["track"]])
	return {"album": str(root.get("name", "")), "artist": str(root.get("artist", "")),
		"cover": str(root.get("coverArt", "")), "songs": rows}


## search3 -> {artists, albums, songs}
static func search_results(body: Dictionary) -> Dictionary:
	var root: Dictionary = body.get("searchResult3", {}) if body.get("searchResult3") is Dictionary else {}
	var ars: Array = []
	for a: Variant in _arr(root.get("artist")):
		var d: Dictionary = a
		ars.append({"id": str(d.get("id", "")), "name": str(d.get("name", "?")), "albums": int(d.get("albumCount", 0))})
	var als: Array = []
	for a: Variant in _arr(root.get("album")):
		als.append(_album_row(a))
	var sgs: Array = []
	for s: Variant in _arr(root.get("song")):
		sgs.append(song_row(s))
	return {"artists": ars, "albums": als, "songs": sgs}


## getPlaylists -> [{id, name, songs, duration}]
static func playlists(body: Dictionary) -> Array:
	var root: Dictionary = body.get("playlists", {}) if body.get("playlists") is Dictionary else {}
	var rows: Array = []
	for p: Variant in _arr(root.get("playlist")):
		var d: Dictionary = p
		rows.append({"id": str(d.get("id", "")), "name": str(d.get("name", "?")),
			"songs": int(d.get("songCount", 0)), "duration": int(d.get("duration", 0))})
	return rows


## getPlaylist -> {name, songs}
static func playlist_songs(body: Dictionary) -> Dictionary:
	var root: Dictionary = body.get("playlist", {}) if body.get("playlist") is Dictionary else {}
	var rows: Array = []
	for s: Variant in _arr(root.get("entry")):
		rows.append(song_row(s))
	return {"name": str(root.get("name", "")), "songs": rows}


## getInternetRadioStations -> [{name, url, home}]; a row with no http(s) stream address is left out.
static func radio_stations(body: Dictionary) -> Array:
	var root: Dictionary = body.get("internetRadioStations", {}) if body.get("internetRadioStations") is Dictionary else {}
	var rows: Array = []
	for s: Variant in _arr(root.get("internetRadioStation")):
		var d: Dictionary = s
		var url := str(d.get("streamUrl", "")).strip_edges()
		if not (url.begins_with("http://") or url.begins_with("https://")):
			continue
		rows.append({"name": str(d.get("name", "")), "url": url, "home": str(d.get("homePageUrl", ""))})
	return rows


# --- small helpers -------------------------------------------------------------------------------------

## The file name a song is cached under: id + suffix, nothing from the server's strings that could be a path.
static func cache_name(song: Dictionary, transcode_format: String = "") -> String:
	var suffix := transcode_format if not transcode_format.is_empty() else str(song.get("suffix", ""))
	var safe_id := ""
	for ch in str(song.get("id", "")):
		safe_id += ch if (ch.is_valid_identifier() or ch == "-" or ch.is_valid_int()) else "_"
	if safe_id.is_empty():
		safe_id = "unknown"
	var safe_suffix := ""
	for ch in suffix.to_lower():
		if ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9":
			safe_suffix += ch
	return safe_id + ("." + safe_suffix if not safe_suffix.is_empty() else ".audio")


## 3:07 / 1:02:09
static func format_time(seconds: int) -> String:
	var s := maxi(seconds, 0)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
