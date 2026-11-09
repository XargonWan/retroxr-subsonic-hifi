## SubsonicHifi -- the object. A RetroAudioPlayer (the shared deck: transport, PCM into line out / PHONES,
## power, netplay host authority) with no tray and no disc: its "album" is a queue of Subsonic tracks, or one
## radio station, handed to the base as `_tracks`.
##
## LIBRARY: the base plays `_tracks` as local files, so a track is downloaded into the cache first (sb_cache.gd)
## and `_tracks` holds the cache paths; `play()` is the one gate every path goes through (PLAY, NEXT, an advance
## at the end of a track), so it fetches what is missing and plays when it has come. The next track is fetched
## ahead. RADIO: `_tracks` is the stream's address, which libVLC opens as it opens a file (the base hands it
## through `globalize_path`, which leaves a URL alone).
##
## What is on is ASKED (`now_playing()`), never announced into the world as text.
##
## Netplay is not wired: remote media are not transferred, and the base's host push assumes a seated disc or tape.
## A peer has an empty queue, so the base ignores the host's track change. OWED.
class_name SubsonicHifi
extends RetroAudioPlayer

const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")
const Radio = preload("res://mods/xenu.subsonic/scripts/radio.gd")
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const Cache = preload("res://mods/xenu.subsonic/scripts/sb_cache.gd")
const Client = preload("res://mods/xenu.subsonic/scripts/sb_client.gd")
const OptionsPanel = preload("res://mods/xenu.subsonic/scripts/hifi_options_panel.gd")

enum Source { NONE, LIBRARY, RADIO }

## Something the screen shows changed: the queue, the status, the station's now-playing, the login.
signal state_changed

const RADIO_POLL_SECONDS := 10.0
const RADIO_RETRIES := 3
## How long after a dropped stream the retry waits.
const RADIO_RETRY_SECONDS := 2.0

var client: Node = null
var cache: RefCounted = null
var source := Source.NONE
var queue: Array = []
var station: Dictionary = {}
## AzuraCast's now-playing for the station on air ({} for a station that publishes none).
var radio_info: Dictionary = {}
## "" or a word for the screen: LOADING, NO LINK, ERROR ...
var status := ""
## Library tracks are asked of the server raw; with a format here (mp3) it transcodes, capped at `transcode_kbps`.
var transcode_format := ""
var transcode_kbps := 0

var _loading_idx := -1
var _downloading := {}
var _radio_timer: Timer = null
var _radio_retries := 0
var _radio_wanted := false


func _ready() -> void:
	# The base deck wants a media group; nothing is ever seated here, the queue is the medium.
	_media_group = "subsonic_queue"
	super._ready()
	add_to_group("subsonic_hifi")
	client = Client.new()
	client.name = "SubsonicClient"
	add_child(client)
	cache = Cache.open(Config.cache_dir(), Config.cache_bytes())
	var s := Config.load_all()
	client.configure(str(s.get("server", "")), str(s.get("user", "")), str(s.get("token", "")), str(s.get("salt", "")))
	set_quality(int(s.get("quality_kbps", 0)), false)
	client.auth_failed.connect(func() -> void:
		print("[Subsonic] %s: the server no longer accepts the saved login" % name)
		status = "SIGN IN"
		state_changed.emit())
	_radio_timer = Timer.new()
	_radio_timer.wait_time = RADIO_POLL_SECONDS
	_radio_timer.one_shot = false
	_radio_timer.timeout.connect(_poll_radio)
	add_child(_radio_timer)
	print("[Subsonic] %s: ready (server %s, %s, cache %d MB, vlc %s)" % [name,
		client.base if not client.base.is_empty() else "none",
		"signed in" if client.has_login() else "not signed in", int(s["cache_mb"]), _vlc != null])


## No tray, no disc: take the base scene's snap zone out of play so a disc cannot be dropped on a box that has no
## slot. (The node stays: RetroAudioPlayer reads it with an @onready.)
func _setup_loader() -> void:
	if _media_slot != null:
		_media_slot.enabled = false
		_media_slot.visible = false


func _log_tag() -> String:
	return "Subsonic"


func deck_save_type() -> String:
	return "xenu.subsonic:hifi"


## The TAB menu (the spawn menu asks every object that has this).
func toggle_options_ui(camera: Node3D) -> void:
	OptionsPanel.toggle_for(self, camera)


## Library tracks are asked of the server in the file's own format (0), or transcoded to mp3 at `kbps`. It applies from
## the next queue (the cache names a track by its format).
func set_quality(kbps: int, save := true) -> void:
	transcode_kbps = maxi(kbps, 0)
	transcode_format = "mp3" if transcode_kbps > 0 else ""
	if save:
		Config.set_value("quality_kbps", transcode_kbps if transcode_kbps > 0 else null)
		print("[Subsonic] %s: quality %s" % [name, "original" if transcode_kbps == 0 else "mp3 %d kbps" % transcode_kbps])


# --- the login -----------------------------------------------------------------------------------------

func set_server(address: String) -> void:
	var norm := Api.normalize_server(address)
	Config.set_value("server", norm)
	client.configure(norm, client.user, client.token, client.salt)
	state_changed.emit()


## Sign in; the (salt, token) the server accepts is kept, the password is not. `done(ok, message)` is optional.
func sign_in(user: String, password: String, done: Callable = Callable()) -> void:
	status = "SIGNING IN"
	state_changed.emit()
	var on_ok := func(u: String, salt: String, token: String) -> void:
		Config.set_value("user", u)
		Config.set_value("salt", salt)
		Config.set_value("token", token)
		status = ""
		state_changed.emit()
		if done.is_valid():
			done.call(true, "")
	var on_fail := func(msg: String) -> void:
		status = "SIGN IN FAILED"
		state_changed.emit()
		if done.is_valid():
			done.call(false, msg)
	client.signed_in.connect(on_ok, CONNECT_ONE_SHOT)
	client.sign_in_failed.connect(on_fail, CONNECT_ONE_SHOT)
	client.sign_in(user, password)


func sign_out() -> void:
	stop()
	Config.forget_login()
	client.configure(client.base, client.user, "", "")
	state_changed.emit()


func is_signed_in() -> bool:
	return client.has_login()


# --- the queue -----------------------------------------------------------------------------------------

## Play `songs` (rows from Api.album_songs / search / playlist) from index `start`.
func play_songs(songs: Array, start: int = 0) -> void:
	if songs.is_empty():
		print("[Subsonic] %s: nothing to play" % name)
		return
	_halt()
	source = Source.LIBRARY
	queue = songs.duplicate()
	station = {}
	radio_info = {}
	_radio_wanted = false
	_radio_timer.stop()
	_tracks = PackedStringArray()
	for song: Dictionary in queue:
		_tracks.append(cache.path(_cache_name(song)))
	_track_idx = clampi(start, 0, queue.size() - 1)
	print("[Subsonic] %s: queue of %d, starting at %d" % [name, queue.size(), _track_idx + 1])
	state_changed.emit()
	play()


## Play a station ({name, url}). A playlist address is read first and the first stream in it played.
func play_station(st: Dictionary) -> void:
	if st.is_empty() or str(st.get("url", "")).is_empty():
		return
	_halt()
	source = Source.RADIO
	station = st
	queue = []
	radio_info = {}
	_radio_retries = 0
	_radio_wanted = true
	_track_idx = 0
	_tracks = PackedStringArray()
	status = "LOADING"
	print("[Subsonic] %s: tuning to %s" % [name, st.get("name", "?")])
	state_changed.emit()
	var url := str(st["url"])
	if Radio.is_azuracast_page(url):
		# A public player page is HTML: the stream is the one its now-playing API names.
		client.get_json(Radio.azuracast_nowplaying_url(url), func(ok: bool, data: Variant, _code: int) -> void:
			if not _radio_wanted or station != st:
				return
			var info := Radio.parse_azuracast(data) if ok else {}
			if info.is_empty() or str(info["listen_url"]).is_empty():
				print("[Subsonic] %s: %s is a station page but names no stream" % [name, url])
				status = "NO STREAM"
				state_changed.emit()
				return
			radio_info = info
			print("[Subsonic] %s: %s is an AzuraCast page, its stream is %s" % [name, url, info["listen_url"]])
			_start_radio(str(info["listen_url"]))
			state_changed.emit())
	elif Radio.is_playlist_url(url):
		client.get_text(url, func(ok: bool, text: Variant, _code: int) -> void:
			if not _radio_wanted or station != st:
				return
			var found := PackedStringArray()
			if ok:
				found = Radio.parse_pls(str(text)) if url.get_slice("?", 0).to_lower().ends_with(".pls") else Radio.parse_m3u(str(text), url)
			if found.is_empty():
				print("[Subsonic] %s: no stream in the playlist %s" % [name, url])
				status = "NO STREAM"
				state_changed.emit()
				return
			_start_radio(found[0]))
	else:
		_start_radio(url)
	_poll_radio()
	_radio_timer.start()


func _start_radio(stream_url: String) -> void:
	_tracks = PackedStringArray([stream_url])
	_track_idx = 0
	status = ""
	play()


func _cache_name(song: Dictionary) -> String:
	return Api.cache_name(song, transcode_format)


## The song at a queue index, or {}.
func song_at(idx: int) -> Dictionary:
	return queue[idx] if source == Source.LIBRARY and idx >= 0 and idx < queue.size() else {}


# --- playing -------------------------------------------------------------------------------------------

## Every path to a sound goes through here. A library track not in the cache is fetched first.
func play() -> void:
	if source == Source.LIBRARY and _track_idx >= 0 and _track_idx < queue.size():
		var song: Dictionary = queue[_track_idx]
		var cname := _cache_name(song)
		if not cache.has(cname):
			_fetch(_track_idx, true)
			return
		cache.touch(cname)
		_prefetch(_track_idx + 1)
	_loading_idx = -1
	if status == "LOADING":
		status = ""
	super.play()
	state_changed.emit()


func stop() -> void:
	_loading_idx = -1
	if source == Source.RADIO:
		_radio_wanted = false
	if status == "LOADING":
		status = ""
	super.stop()
	state_changed.emit()


## Stop what is on without forgetting the queue's identity (a new source is about to replace it).
func _halt() -> void:
	_loading_idx = -1
	if is_playing:
		super.stop()


func _fetch(idx: int, then_play: bool) -> void:
	var song: Dictionary = queue[idx]
	var cname := _cache_name(song)
	if then_play:
		_loading_idx = idx
		status = "LOADING"
		state_changed.emit()
	if _downloading.has(cname):
		return
	_downloading[cname] = true
	print("[Subsonic] %s: fetching '%s' (%s)" % [name, song.get("title", "?"), cname])
	var call := Api.stream(str(song["id"]), transcode_format, transcode_kbps)
	var queue_ref := queue
	client.download(call, cache.part_path(cname), func(ok: bool, _data: Variant, code: int) -> void:
		_downloading.erase(cname)
		if ok and cache.commit(cname):
			var protect: Array = [cname, _cache_name(queue_ref[mini(idx + 1, queue_ref.size() - 1)])]
			cache.trim(protect)
			if then_play and _loading_idx == idx and queue_ref == queue and _track_idx == idx:
				play()
			return
		print("[Subsonic] %s: could not fetch '%s' (code %d)" % [name, song.get("title", "?"), code])
		if then_play and _loading_idx == idx:
			_loading_idx = -1
			status = "NO LINK" if code == 0 else "ERROR"
			state_changed.emit())


func _prefetch(idx: int) -> void:
	if idx < queue.size() and not cache.has(_cache_name(queue[idx])):
		_fetch(idx, false)


## The cache's size changed in the TAB menu (or its contents should be looked at).
func apply_cache_size() -> void:
	cache.set_cap(Config.cache_bytes())
	cache.trim(_protected())
	state_changed.emit()


func clear_cache() -> void:
	cache.clear(_protected())
	state_changed.emit()


func _protected() -> Array:
	var keep: Array = []
	if source == Source.LIBRARY:
		for i in [_track_idx, _track_idx + 1]:
			if i >= 0 and i < queue.size():
				keep.append(_cache_name(queue[i]))
	return keep


# --- the base deck's questions --------------------------------------------------------------------------

func has_track_skip() -> bool:
	return source == Source.LIBRARY


func has_scan() -> bool:
	return source == Source.LIBRARY


## A queue plays to its end, then stops; a station never ends (a dropped stream is retried).
func _track_after(idx: int) -> int:
	return idx + 1 if source == Source.LIBRARY and idx + 1 < queue.size() else -1


func _rebuild_tracks() -> void:
	# The queue is the album; there is no folder to read.
	pass


func _on_track_finished() -> void:
	if source == Source.RADIO and _radio_wanted and not NetworkManager.is_client():
		# A radio does not end: the stream dropped. Try again a few times, then say so.
		is_playing = false
		_radio_retries += 1
		if _radio_retries > RADIO_RETRIES:
			print("[Subsonic] %s: %s dropped %d times, giving up" % [name, station.get("name", "?"), RADIO_RETRIES])
			_radio_wanted = false
			status = "NO LINK"
			state_changed.emit()
			return
		print("[Subsonic] %s: %s dropped, retrying (%d of %d)" % [name, station.get("name", "?"), _radio_retries, RADIO_RETRIES])
		status = "LOADING"
		state_changed.emit()
		get_tree().create_timer(RADIO_RETRY_SECONDS).timeout.connect(func() -> void:
			if _radio_wanted and source == Source.RADIO:
				play())
		return
	super._on_track_finished()
	state_changed.emit()


# --- radio now-playing ---------------------------------------------------------------------------------

func _poll_radio() -> void:
	if source != Source.RADIO or not _radio_wanted:
		_radio_timer.stop()
		return
	var api_url := Radio.azuracast_nowplaying_url(str(station.get("url", "")))
	if api_url.is_empty() and not _tracks.is_empty():
		api_url = Radio.azuracast_nowplaying_url(_tracks[0])
	if api_url.is_empty():
		return
	var asked := station
	client.get_json(api_url, func(ok: bool, data: Variant, _code: int) -> void:
		if not ok or station != asked:
			return
		var info := Radio.parse_azuracast(data)
		if info != radio_info:
			radio_info = info
			state_changed.emit())


# --- what other mods may ask ---------------------------------------------------------------------------

## {} when nothing is on. title / artist / album, `position` and `length` in seconds (0 for a station), `source`.
func now_playing() -> Dictionary:
	if not is_playing:
		return {}
	if source == Source.RADIO:
		var np := radio_info
		return {"source": "radio", "station": str(station.get("name", "")), "title": str(np.get("title", "")),
			"artist": str(np.get("artist", "")), "album": "", "position": 0.0, "length": 0.0}
	var song := song_at(_track_idx)
	return {"source": "library", "title": str(song.get("title", "")), "artist": str(song.get("artist", "")),
		"album": str(song.get("album", "")), "position": _vlc_time_sec(), "length": float(song.get("duration", 0))}
