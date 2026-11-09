## A smoke test against REAL servers: sign in, list, fetch and cache one track, read the radio's now-playing.
## Not part of run_all.py (it needs the network and a login). The login comes from the environment, never a file:
##
##   SB_LIVE_URL=https://audio.example.org SB_LIVE_USER=u SB_LIVE_PASS=p [SB_LIVE_RADIO=https://r/public/x] \
##       python3 tests/run_live.py
extends Node

const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")
const Radio = preload("res://mods/xenu.subsonic/scripts/radio.gd")
const Client = preload("res://mods/xenu.subsonic/scripts/sb_client.gd")
const Cache = preload("res://mods/xenu.subsonic/scripts/sb_cache.gd")

var _fails := 0
var _client: Node = null


func _say(msg: String) -> void:
	print("[sb-live] ", msg)


func _ok(cond: bool, what: String) -> void:
	_say(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_fails += 1


## Wait for a callback-style call: returns [ok, data, code].
func _await_call(starter: Callable) -> Array:
	var box := {"done": false, "res": []}
	starter.call(func(ok: bool, data: Variant, code: int) -> void:
		box["res"] = [ok, data, code]
		box["done"] = true)
	var t := 0.0
	while not box["done"] and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	return box["res"] if box["done"] else [false, "timeout", 0]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var url := OS.get_environment("SB_LIVE_URL")
	var user := OS.get_environment("SB_LIVE_USER")
	var pw := OS.get_environment("SB_LIVE_PASS")
	var radio := OS.get_environment("SB_LIVE_RADIO")
	OS.set_environment("XENU_SB_CACHE", "user://sb_live_cache")
	_client = Client.new()
	add_child(_client)
	if not url.is_empty():
		_client.configure(url)
		var signed := {"done": false, "ok": false, "msg": ""}
		_client.signed_in.connect(func(_u: String, _s: String, _t: String) -> void:
			signed["done"] = true
			signed["ok"] = true)
		_client.sign_in_failed.connect(func(m: String) -> void:
			signed["done"] = true
			signed["msg"] = m)
		_client.sign_in(user, pw)
		while not signed["done"]:
			await get_tree().process_frame
		_ok(signed["ok"], "sign in as %s (%s)" % [user, signed["msg"]])
		if signed["ok"]:
			await _library()
	if not radio.is_empty():
		await _radio(radio)
	if OS.get_environment("SB_LIVE_PLAY") == "1":
		await _object(url, user, pw, radio)
	_say("%d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _library() -> void:
	var r := await _await_call(func(cb: Callable) -> void: _client.call_api(Api.get_artists(), cb))
	_ok(r[0], "getArtists")
	var artists := Api.artists(r[1]) if r[0] else []
	_ok(artists.size() > 0, "the library lists artists (%d)" % artists.size())
	r = await _await_call(func(cb: Callable) -> void: _client.call_api(Api.get_album_list("newest", 5), cb))
	var albums := Api.album_list(r[1]) if r[0] else []
	_ok(albums.size() > 0, "getAlbumList2 newest (%d)" % albums.size())
	if albums.is_empty():
		return
	r = await _await_call(func(cb: Callable) -> void: _client.call_api(Api.get_album(albums[0]["id"]), cb))
	var album := Api.album_songs(r[1]) if r[0] else {"songs": []}
	_ok(album["songs"].size() > 0, "getAlbum '%s' has songs (%d)" % [albums[0]["name"], album["songs"].size()])
	r = await _await_call(func(cb: Callable) -> void: _client.call_api(Api.search(albums[0]["artist"].get_slice(" ", 0)), cb))
	_ok(r[0] and Api.search_results(r[1])["songs"].size() >= 0, "search3")
	r = await _await_call(func(cb: Callable) -> void: _client.call_api(Api.get_playlists(), cb))
	_ok(r[0], "getPlaylists (%d)" % (Api.playlists(r[1]).size() if r[0] else -1))
	r = await _await_call(func(cb: Callable) -> void: _client.fetch_bytes(Api.cover_art(albums[0]["cover"], 128), cb))
	var img := Image.new()
	_ok(r[0] and (img.load_jpg_from_buffer(r[1]) == OK or img.load_png_from_buffer(r[1]) == OK), "getCoverArt decodes as an image")
	if album["songs"].is_empty():
		return
	var song: Dictionary = album["songs"][0]
	for cand: Dictionary in album["songs"]:
		if int(cand["duration"]) > 0 and int(cand["duration"]) < int(song["duration"]):
			song = cand
	_say("fetching '%s' (%d s)" % [song["title"], song["duration"]])
	var t0 := Time.get_ticks_msec()
	var cache: RefCounted = Cache.open("user://sb_live_cache", 50 * 1024 * 1024)
	var name := Api.cache_name(song, "mp3")
	r = await _await_call(func(cb: Callable) -> void: _client.download(Api.stream(song["id"], "mp3", 128), cache.part_path(name), cb))
	_ok(r[0], "stream (mp3, 128 kbps) downloads (%s, code %s, %d ms)" % [str(r[1]).left(60), str(r[2]), Time.get_ticks_msec() - t0])
	_ok(r[0] and cache.commit(name), "the download is committed to the cache")
	_ok(cache.has(name) and cache.size_of(name) > 10000, "and it is a real file (%d bytes)" % cache.size_of(name))
	_say("track '%s' cached as %s" % [song["title"], name])
	cache.clear()
	r = await _await_call(func(cb: Callable) -> void: _client.call_api(["getArtist", [["id", "does-not-exist"]]], cb))
	_ok(not r[0], "an unknown id is a failure, not a crash (%s)" % str(r[1]))


func _radio(public_url: String) -> void:
	var np_url := Radio.azuracast_nowplaying_url(public_url)
	_ok(not np_url.is_empty(), "the now-playing address is derived: %s" % np_url)
	var r := await _await_call(func(cb: Callable) -> void: _client.get_json(np_url, cb))
	var np := Radio.parse_azuracast(r[1]) if r[0] else {}
	_ok(not np.is_empty(), "AzuraCast now-playing parses")
	if np.is_empty():
		return
	_say("on air: %s - %s (%d of %d s) on %s" % [np["artist"], np["title"], np["elapsed"], np["duration"], np["station"]])
	_ok(np["listen_url"].begins_with("http"), "it names its stream: %s" % np["listen_url"])
	r = await _await_call(func(cb: Callable) -> void: _client.get_text(public_url.rstrip("/") + "/playlist.m3u", cb))
	_ok(r[0] and Radio.parse_m3u(r[1]).size() > 0, "its playlist.m3u lists a stream")
	r = await _await_call(func(cb: Callable) -> void: _client.get_text(public_url.rstrip("/") + "/playlist.pls", cb))
	_ok(r[0] and Radio.parse_pls(r[1]).size() > 0, "its playlist.pls lists a stream")


## The object: sign in through it, play the library track from the cache, then tune the radio.
func _object(url: String, user: String, pw: String, radio: String) -> void:
	var scene := load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene
	var hifi := scene.instantiate() as SubsonicHifi
	add_child(hifi)
	await get_tree().process_frame
	_ok(hifi._vlc != null, "libVLC is available to the deck")
	if hifi._vlc == null:
		return
	if not url.is_empty():
		hifi.set_server(url)
		var done := {"d": false, "ok": false, "m": ""}
		hifi.sign_in(user, pw, func(ok: bool, m: String) -> void:
			done["d"] = true
			done["ok"] = ok
			done["m"] = m)
		while not done["d"]:
			await get_tree().process_frame
		_ok(done["ok"], "the object signs in (%s)" % done["m"])
		var r := await _await_call(func(cb: Callable) -> void: hifi.client.call_api(Api.get_album_list("newest", 5), cb))
		var albums := Api.album_list(r[1])
		r = await _await_call(func(cb: Callable) -> void: hifi.client.call_api(Api.get_album(albums[0]["id"]), cb))
		var songs: Array = Api.album_songs(r[1])["songs"]
		hifi.play_songs(songs, 0)
		var t := 0.0
		while not hifi.is_playing and t < 90.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		_ok(hifi.is_playing, "the deck plays the first track once it is cached (status '%s', %.1f s)" % [hifi.status, t])
		await get_tree().create_timer(4.0).timeout
		var pos := hifi._vlc_time_sec()
		_ok(pos > 2.0, "and the position advances (%.1f s)" % pos)
		_ok(hifi.now_playing().get("title", "") == songs[0]["title"], "now_playing() names the track")
		hifi.stop()
		_ok(not hifi.is_playing, "STOP stops it")
	if not radio.is_empty():
		hifi.play_station({"name": "RADIODROME", "url": radio})
		await get_tree().create_timer(8.0).timeout
		_ok(hifi.is_playing, "the radio plays (status '%s')" % hifi.status)
		_ok(not hifi.radio_info.is_empty(), "and its now-playing is read: %s - %s" % [hifi.radio_info.get("artist", ""), hifi.radio_info.get("title", "")])
		var pos2 := hifi._vlc_time_sec()
		_say("radio position %.1f s" % pos2)
		hifi.stop()
	hifi.queue_free()
