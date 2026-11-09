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
const Body = preload("res://mods/xenu.subsonic/scripts/hifi_model.gd")
const Browser = preload("res://mods/xenu.subsonic/scripts/hifi_browser.gd")
const ScreenScene = preload("res://mods/xenu.subsonic/scenes/hifi_screen.tscn")
const ViewportScene = preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")

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
## REPEAT: 0 off, 1 the queue, 2 the track. SHUFFLE picks the next track at random among those not yet played.
const REPEAT_NAMES := ["off", "all", "one"]
var shuffle := false
var repeat := 0
## "" or a word for the screen: LOADING, NO LINK, ERROR ...
var status := ""
## Library tracks are asked of the server raw; with a format here (mp3) it transcodes, capped at `transcode_kbps`.
var transcode_format := ""
var transcode_kbps := 0

## The LCD's pages and what a press does; the screen draws it.
var browser: RefCounted = null
## The cover of what plays (a small texture), or null.
var cover: Texture2D = null
## Triangles the body draws (a test holds it to a budget).
var body_triangles := 0

var _screen: Node3D = null
var _covers := {}
var _tick: Timer = null
var _rng := RandomNumberGenerator.new()
var _played := {}               # queue indices played in this shuffle round
var _radio_art_url := ""
var _radio_info_msec := 0
## When the stream of the track playing was opened (0: it was played from the cache).
var _stream_started_msec := 0
var _loading_idx := -1
var _downloading := {}
var _radio_timer: Timer = null
var _radio_retries := 0
var _radio_wanted := false


## The scene is the base CD player's: its tray-era keys and its model go before the deck's own @onready lookups run
## (a node freed here is never found, so the base wires only what stays).
func _enter_tree() -> void:
	for n: String in ["OpenButton", "RewindButton", "FastForwardButton", "RepeatButton", "ShuffleButton", "Model"]:
		var c := get_node_or_null(n)
		if c != null:
			remove_child(c)
			c.queue_free()
	if get_node_or_null("Model") == null:
		var model := Node3D.new()
		model.name = "Model"
		add_child(model)
		move_child(model, 0)


func _ready() -> void:
	# The base deck wants a media group; nothing is ever seated here, the queue is the medium.
	_media_group = "subsonic_queue"
	super._ready()
	add_to_group("subsonic_hifi")
	# libVLC says when a stream cannot be opened; the base deck listens only for the end of a track.
	if _vlc != null and _vlc.has_signal("error"):
		_vlc.connect("error", _on_vlc_error)
	client = Client.new()
	client.name = "SubsonicClient"
	add_child(client)
	cache = Cache.open(Config.cache_dir(), Config.cache_bytes())
	var s := Config.load_all()
	client.configure(str(s.get("server", "")), str(s.get("user", "")), str(s.get("token", "")), str(s.get("salt", "")))
	set_quality(int(s.get("quality_kbps", 0)), false)
	shuffle = bool(s.get("shuffle", false))
	repeat = clampi(int(s.get("repeat", 0)), 0, 2)
	if client.has_login():
		refresh_server_stations.call_deferred()
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
	body_triangles = Body.build(self, get_node("Model"))
	var knob := get_node("LevelKnob") as VRKnob
	knob.value_changed.connect(set_phones_level)
	set_phones_level(knob.value)
	browser = Browser.new(self)
	for spec: Array in [["MenuButton", "menu"], ["BackButton", "back"], ["LeftButton", "left"], ["UpButton", "up"],
			["DownButton", "down"], ["RightButton", "right"], ["OkButton", "ok"]]:
		var cmd: String = spec[1]
		(get_node(str(spec[0])) as VRButton).button_pressed.connect(func() -> void:
			if _mains_gate(cmd.to_upper()):
				browser.nav(cmd))
	_build_screen()
	print("[Subsonic] %s: body of %d triangles" % [name, body_triangles])


func _build_screen() -> void:
	var vp := ViewportScene.instantiate()
	vp.name = "Screen"
	vp.screen_size = Body.SCREEN
	vp.scene = ScreenScene
	vp.viewport_size = Vector2(640, 320)
	vp.unshaded = true
	vp.update_mode = XRToolsViewport2DIn3D.UpdateMode.UPDATE_THROTTLED
	vp.throttle_fps = 12.0
	vp.position = Vector3(Body.SCREEN_AT.x, Body.SCREEN_AT.y, Body.FRONT + 0.0031)
	add_child(vp)
	_screen = vp
	_bind_screen.call_deferred(0)


## The 2D page appears a frame after the viewport does: wait for it, then hand it the browser.
func _bind_screen(attempt: int) -> void:
	if not is_instance_valid(_screen):
		return
	var sv := _screen.get_node_or_null("Viewport") as SubViewport
	if sv == null or sv.get_child_count() == 0:
		if attempt < 120:
			get_tree().create_timer(0.05).timeout.connect(_bind_screen.bind(attempt + 1))
		else:
			print("[Subsonic] %s: the screen never came up" % name)
		return
	var ui := sv.get_child(0)
	ui.call("bind", browser, self)
	browser.refresh_home()
	state_changed.connect(func() -> void:
		if browser.pages.depth() == 1:
			browser.refresh_home())
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(func() -> void:
		if is_playing:
			state_changed.emit())
	add_child(_tick)
	_tick.start()


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
	if norm != client.base:
		# Another server: what the old one listed is no longer ours to show.
		Config.set_value("server_stations", null)
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
		refresh_server_stations()
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


# --- radio stations: the player's own, merged with the server's -------------------------------------------

## Every station on offer: the player's own first, then the ones the server keeps (Radio.merge). Rows are
## {name, url, source}, source "user" or "server".
func stations() -> Array:
	var s := Config.load_all()
	return Radio.merge(s["server_stations"], s["stations"])


## Ask the server for its stations and keep them (settings, so they show at once next time and without a network).
## `done` is called with the merged list when the answer is in; a failure keeps what was kept and logs it.
func refresh_server_stations(done: Callable = Callable()) -> void:
	if not client.has_login():
		if done.is_valid():
			done.call(stations())
		return
	client.call_api(Api.get_radio_stations(), func(ok: bool, data: Variant, _code: int) -> void:
		if ok:
			var rows := Api.radio_stations(data)
			Config.set_value("server_stations", rows if not rows.is_empty() else null)
			print("[Subsonic] %s: the server lists %d radio station(s)" % [name, rows.size()])
			state_changed.emit()
		else:
			print("[Subsonic] %s: could not read the server's radio stations (%s)" % [name, str(data)])
		if done.is_valid():
			done.call(stations()))


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
	_played = {}
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
			_radio_info_msec = Time.get_ticks_msec()
			_load_radio_art(str(info.get("art", "")))
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
			# Not in the cache: play it AS IT COMES (libVLC opens the stream; a slow server is heard after a second
			# instead of after the whole file), and fill the cache behind it for next time.
			if _stream_now(song):
				return
			_fetch(_track_idx, true)
			return
		_stream_started_msec = 0
		cache.touch(cname)
		_prefetch(_track_idx + 1)
		_load_cover(str(song.get("cover", "")))
	_loading_idx = -1
	if status == "LOADING":
		status = ""
	super.play()
	state_changed.emit()


## The OK key on the Now playing page: pause what is on, or carry on.
func toggle_pause() -> void:
	if is_playing and not _paused:
		_on_pause_pressed()
	else:
		_on_play_pressed()


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
	cover = null
	if is_playing:
		super.stop()


## Start the track from the server's stream. This is the base play()'s open-and-go, with the stream address (which
## carries the login) opened but never logged. False if libVLC could not be started on it.
func _stream_now(song: Dictionary) -> bool:
	if not _mains_gate("play") or _vlc == null:
		return false
	var url: String = client.url_for(Api.stream(str(song["id"]), transcode_format, transcode_kbps))
	if not _vlc.open(url, false):
		print("[Subsonic] %s: libVLC would not open the stream of '%s'" % [name, song.get("title", "?")])
		return false
	_stream_started_msec = Time.get_ticks_msec()
	_log_event("streaming track %d of %d: '%s' (not in the cache yet)" % [_track_idx + 1, queue.size(), song.get("title", "?")])
	_vlc.play()
	_vlc.set_volume(100)
	is_playing = true
	_paused = false
	_scan_dir = 0
	_loading_idx = -1
	status = ""
	if _emitter:
		_emitter.flush()
		_apply_volume()
	_update_status()
	_load_cover(str(song.get("cover", "")))
	# The cache is filled once the stream has had the server to itself for a moment, then the next track is fetched.
	var idx := _track_idx
	var q := queue
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if q == queue and idx < queue.size():
			_fetch(idx, false)
			_prefetch(idx + 1))
	state_changed.emit()
	return true


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


## The cover of what plays: asked of the server once per cover (kept in memory, 24 at most), 192 px.
func _load_cover(id: String) -> void:
	cover = null
	if id.is_empty() or not client.has_login():
		return
	if _covers.has(id):
		cover = _covers[id]
		return
	client.fetch_bytes(Api.cover_art(id, 192), func(ok: bool, bytes: Variant, _code: int) -> void:
		if not ok:
			return
		var tex := _texture_from(bytes as PackedByteArray)
		if tex == null:
			return
		if _covers.size() >= 24:
			_covers.erase(_covers.keys()[0])
		_covers[id] = tex
		if source == Source.LIBRARY and str(song_at(_track_idx).get("cover", "")) == id:
			cover = tex
			state_changed.emit())


## The picture a station's now-playing names (AzuraCast: the song's art). One fetch per address.
func _load_radio_art(url: String) -> void:
	if url == _radio_art_url:
		return
	_radio_art_url = url
	cover = null
	if url.is_empty() or not (url.begins_with("http://") or url.begins_with("https://")):
		return
	if _covers.has(url):
		cover = _covers[url]
		return
	client.get_bytes(url, func(ok: bool, bytes: Variant, _code: int) -> void:
		if not ok or url != _radio_art_url or source != Source.RADIO:
			return
		var tex := _texture_from(bytes as PackedByteArray)
		if tex == null:
			return
		if _covers.size() >= 24:
			_covers.erase(_covers.keys()[0])
		_covers[url] = tex
		cover = tex
		state_changed.emit())


func _texture_from(data: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if img.load_jpg_from_buffer(data) != OK and img.load_png_from_buffer(data) != OK and img.load_webp_from_buffer(data) != OK:
		print("[Subsonic] %s: a picture that is no image I know (%d bytes)" % [name, data.size()])
		return null
	return ImageTexture.create_from_image(img)


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


## What plays when the track ends: the same track (REPEAT ONE), a random one not yet played (SHUFFLE; REPEAT ALL
## starts a new round), the next (REPEAT ALL wraps) or nothing (-1). A station never ends: a dropped stream is retried.
func _track_after(idx: int) -> int:
	if source != Source.LIBRARY or queue.is_empty():
		return -1
	if repeat == 2:
		return idx
	return _pick_next(idx, repeat == 1)


func _pick_next(idx: int, wrap: bool) -> int:
	if shuffle:
		_played[idx] = true
		var left: Array = []
		for i in queue.size():
			if not _played.has(i) and i != idx:
				left.append(i)
		if left.is_empty():
			if not wrap or queue.size() < 2:
				return -1
			_played = {idx: true}
			for i in queue.size():
				if i != idx:
					left.append(i)
		return int(left[_rng.randi_range(0, left.size() - 1)])
	if idx + 1 < queue.size():
		return idx + 1
	return 0 if wrap else -1


## NEXT on the unit or the screen: the next track by the same rule, and past the end of a queue only with REPEAT ALL.
func _on_next_pressed() -> void:
	if not _mains_gate("NEXT"):
		return
	_log_event("pressed NEXT")
	if not has_track_skip():
		return
	var n := _pick_next(_track_idx, repeat == 1)
	if n >= 0:
		_goto_track(n)


func set_shuffle(on: bool) -> void:
	shuffle = on
	_played = {}
	Config.set_value("shuffle", on if on else null)
	print("[Subsonic] %s: shuffle %s" % [name, "on" if on else "off"])
	state_changed.emit()


## off -> all -> one -> off
func cycle_repeat() -> void:
	repeat = (repeat + 1) % 3
	Config.set_value("repeat", repeat if repeat > 0 else null)
	print("[Subsonic] %s: repeat %s" % [name, REPEAT_NAMES[repeat]])
	state_changed.emit()


## Jump to a fraction (0..1) of the track playing. A station has nothing to seek in.
func seek_to(fraction: float) -> void:
	if source != Source.LIBRARY or not is_playing or _vlc == null:
		return
	_vlc.set_position(clampf(fraction, 0.0, 1.0))
	state_changed.emit()


func _rebuild_tracks() -> void:
	# The queue is the album; there is no folder to read.
	pass


## libVLC could not open or keep a stream. A station is retried like a dropped one; a library stream is NO LINK.
func _on_vlc_error() -> void:
	if not is_playing:
		return
	if source == Source.RADIO:
		_on_track_finished()
		return
	if source == Source.LIBRARY and _stream_started_msec > 0:
		_stream_started_msec = 0
		is_playing = false
		_paused = false
		status = "NO LINK"
		print("[Subsonic] %s: libVLC could not play the stream of '%s'" % [name, song_at(_track_idx).get("title", "?")])
		_update_status()
		state_changed.emit()


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
	if _stream_started_msec > 0 and source == Source.LIBRARY and Time.get_ticks_msec() - _stream_started_msec < 6000 \
			and _vlc_time_sec() < 1.0:
		# The stream ended before it began: the server did not answer (or refused). Say so; do not run on to the next track.
		_stream_started_msec = 0
		is_playing = false
		_paused = false
		status = "NO LINK"
		print("[Subsonic] %s: the stream of '%s' did not start" % [name, song_at(_track_idx).get("title", "?")])
		_update_status()
		state_changed.emit()
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
			_radio_info_msec = Time.get_ticks_msec()
			_load_radio_art(str(info.get("art", "")))
			state_changed.emit())


# --- what other mods may ask ---------------------------------------------------------------------------

## {} when nothing is on. For another mod and for the screen: title / artist / album, `position` and `length` in
## seconds (0 for a station), `source` ("library" | "radio"), and for the screen `paused`, `index` / `count` in the
## queue, `format` ("FLAC 1000 kbps"), `next` (what comes next), `shuffle`, `repeat`.
func now_playing() -> Dictionary:
	if not is_playing:
		return {}
	if source == Source.RADIO:
		var np := radio_info
		return {"source": "radio", "station": str(station.get("name", "")), "title": str(np.get("title", "")),
			"artist": str(np.get("artist", "")), "album": str(np.get("album", "")), "position": _radio_position(np),
			"length": float(np.get("duration", 0)), "paused": is_paused(), "index": 0, "count": 0, "format": "",
			"next": str(np.get("next_title", "")), "shuffle": false, "repeat": 0}
	var song := song_at(_track_idx)
	var fmt := str(song.get("suffix", "")).to_upper()
	if int(song.get("bitrate", 0)) > 0:
		fmt += (" " if not fmt.is_empty() else "") + "%d kbps" % int(song["bitrate"])
	var after := _pick_preview()
	return {"source": "library", "title": str(song.get("title", "")), "artist": str(song.get("artist", "")),
		"album": str(song.get("album", "")), "position": _vlc_time_sec(), "length": float(song.get("duration", 0)),
		"paused": is_paused(), "index": _track_idx, "count": queue.size(), "format": fmt,
		"next": str(song_at(after).get("title", "")) if after >= 0 else "", "shuffle": shuffle, "repeat": repeat}


## How far into the song on air: what AzuraCast said at the last poll, run on by the time since (it is asked every 10 s).
func _radio_position(np: Dictionary) -> float:
	var at := float(np.get("elapsed", 0)) + (Time.get_ticks_msec() - _radio_info_msec) / 1000.0
	var dur := float(np.get("duration", 0))
	return minf(at, dur) if dur > 0.0 else at


## What would play after this track if nothing changed, for "next" on the screen (a shuffle is not previewed).
func _pick_preview() -> int:
	if shuffle:
		return -1
	if repeat == 2:
		return _track_idx
	if _track_idx + 1 < queue.size():
		return _track_idx + 1
	return 0 if repeat == 1 and queue.size() > 1 else -1