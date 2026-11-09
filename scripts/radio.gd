## Internet radio, pure: station rows, the playlist formats a station address may come as, and the now-playing
## information of the stations that publish it. No node, no network (the fetching is sb_client.gd's).
##
## A station is {name, url}. Its url is a stream (Icecast / Shoutcast / HLS) or a playlist (.pls, .m3u) that
## names one. AzuraCast (https://www.azuracast.com) also publishes what is playing as JSON at
## /api/nowplaying/<shortcode>, which `azuracast_nowplaying_url` derives from a public-player or stream address.
extends RefCounted

const MAX_STATIONS := 64
const MAX_NAME := 40


## A station row as the settings keep it, or {} when the url is not http(s). The name falls back to the host.
static func make_station(name: String, url: String) -> Dictionary:
	var u := url.strip_edges()
	if not (u.begins_with("http://") or u.begins_with("https://")):
		return {}
	if u.contains(" ") or u.length() > 500:
		return {}
	var n := name.strip_edges()
	if n.is_empty():
		n = host_of(u)
	return {"name": n.substr(0, MAX_NAME), "url": u}


static func host_of(url: String) -> String:
	var s := url.get_slice("://", 1) if url.contains("://") else url
	return s.get_slice("/", 0)


## The settings' list, cleaned: only valid rows, no repeated url, at most MAX_STATIONS.
static func clean_stations(rows: Variant) -> Array:
	var out: Array = []
	var seen := {}
	if not (rows is Array):
		return out
	for r: Variant in rows:
		if not (r is Dictionary):
			continue
		var st := make_station(str((r as Dictionary).get("name", "")), str((r as Dictionary).get("url", "")))
		if st.is_empty() or seen.has(st["url"]):
			continue
		seen[st["url"]] = true
		out.append(st)
		if out.size() >= MAX_STATIONS:
			break
	return out


# --- playlists ---------------------------------------------------------------------------------------

## Whether the address is a playlist to be read rather than a stream to be opened.
static func is_playlist_url(url: String) -> bool:
	var path := url.get_slice("?", 0).to_lower()
	return path.ends_with(".pls") or path.ends_with(".m3u") or path.ends_with(".asx")


## .pls -> stream urls in file order ([playlist] File1=...).
static func parse_pls(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.replace("\r\n", "\n").split("\n"):
		var line := raw.strip_edges()
		if line.to_lower().begins_with("file") and line.contains("="):
			var v := line.get_slice("=", 1).strip_edges()
			if v.begins_with("http://") or v.begins_with("https://"):
				out.append(v)
	return out


## Plain or extended .m3u -> stream urls in file order. A relative line is resolved against `base_url`. An HLS
## media playlist (#EXT-X-TARGETDURATION) is a stream itself, not a list of stations: [base_url].
static func parse_m3u(text: String, base_url: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if text.contains("#EXT-X-TARGETDURATION") or text.contains("#EXT-X-STREAM-INF"):
		if not base_url.is_empty():
			out.append(base_url)
		return out
	for raw in text.replace("\r\n", "\n").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("http://") or line.begins_with("https://"):
			out.append(line)
		elif not base_url.is_empty() and not line.contains("://"):
			out.append(base_url.get_base_dir().path_join(line))
	return out


# --- AzuraCast now-playing ---------------------------------------------------------------------------

## https://host/public/<shortcode>[/...] or https://host/listen/<shortcode>/<mount> -> https://host/api/nowplaying/<shortcode>
## ("" for an address that is neither).
static func azuracast_nowplaying_url(url: String) -> String:
	var scheme := url.get_slice("://", 0)
	if scheme != "http" and scheme != "https":
		return ""
	var rest := url.get_slice("://", 1)
	var host := rest.get_slice("/", 0)
	var parts := rest.get_slice("?", 0).trim_prefix(host).split("/", false)
	if parts.size() >= 2 and (parts[0] == "public" or parts[0] == "listen"):
		return "%s://%s/api/nowplaying/%s" % [scheme, host, parts[1]]
	return ""


## What AzuraCast's nowplaying JSON says: {station, listen_url, artist, title, album, art, elapsed, duration,
## next_title, is_live}. {} when it is not that JSON.
static func parse_azuracast(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	if not (d.get("station") is Dictionary) or not (d.get("now_playing") is Dictionary):
		return {}
	var st: Dictionary = d["station"]
	var np: Dictionary = d["now_playing"]
	var song: Dictionary = np.get("song", {}) if np.get("song") is Dictionary else {}
	var nxt: Dictionary = {}
	if d.get("playing_next") is Dictionary and (d["playing_next"] as Dictionary).get("song") is Dictionary:
		nxt = (d["playing_next"] as Dictionary)["song"]
	var live: Dictionary = d.get("live", {}) if d.get("live") is Dictionary else {}
	return {"station": str(st.get("name", "")), "listen_url": str(st.get("listen_url", "")),
		"artist": str(song.get("artist", "")), "title": str(song.get("title", song.get("text", ""))),
		"album": str(song.get("album", "")), "art": str(song.get("art", "")),
		"elapsed": int(np.get("elapsed", 0)), "duration": int(np.get("duration", 0)),
		"next_title": str(nxt.get("text", "")), "is_live": bool(live.get("is_live", false))}


## "Artist - Title" (an ICY StreamTitle) -> {artist, title}; with no " - " the whole text is the title.
static func split_stream_title(text: String) -> Dictionary:
	var t := text.strip_edges()
	var at := t.find(" - ")
	if at <= 0:
		return {"artist": "", "title": t}
	return {"artist": t.substr(0, at).strip_edges(), "title": t.substr(at + 3).strip_edges()}
