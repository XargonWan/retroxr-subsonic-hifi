## The object and its TAB menu in the real game's classes, with no server: settings go to a scratch file, the only
## address used refuses connections at once (127.0.0.1:9), so no test ever touches the player's real login or network.
extends Node

const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const HifiPanel = preload("res://mods/xenu.subsonic/scripts/hifi_options_panel.gd")
const EXPECTED_CASES := 38
const SCRATCH := "user://sb_hifi_scratch"

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-hifi] FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", SCRATCH + "/settings.json")
	OS.set_environment("XENU_SB_CACHE", SCRATCH + "/cache")
	DirAccess.make_dir_recursive_absolute(SCRATCH + "/cache")
	DirAccess.remove_absolute(SCRATCH + "/settings.json")
	for f in DirAccess.get_files_at(SCRATCH + "/cache"):
		DirAccess.remove_absolute(SCRATCH + "/cache/" + f)
	var hifi := (load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene).instantiate() as SubsonicHifi
	add_child(hifi)
	var cam := Camera3D.new()
	add_child(cam)
	await _frames(2)
	_check(not hifi.is_signed_in(), "a fresh Hi-Fi is not signed in")
	_check(hifi.cache.cap_bytes == 50 * 1024 * 1024, "its cache is 50 MB by default")
	_check(not hifi.has_track_skip() and not hifi.has_scan(), "with nothing queued there is no skip and no scan")
	_check(hifi.now_playing().is_empty(), "nothing is on")
	hifi.set_server("http://127.0.0.1:9")
	_check(hifi.client.base == "http://127.0.0.1:9" and Config.load_all()["server"] == "http://127.0.0.1:9", "the server is set on the client and kept")

	HifiPanel.toggle_for(hifi, cam)
	await _frames(12)
	var panel := hifi.get_node_or_null("HifiOptionsPanel")
	_check(panel != null and panel.visible, "TAB opens the menu")
	var ui: Control = panel._get_ui() if panel != null else null
	_check(ui != null, "its page is built")
	if ui == null:
		_finish()
		return
	_check(ui._server_edit.text == "http://127.0.0.1:9", "the page shows the server")
	_check(ui._pass_edit.secret, "the password field is secret")
	# Stations
	ui.station_added.emit("Jazz", "https://j.example/live")
	ui.station_added.emit("Bad", "nope")
	await _frames(2)
	_check(Config.load_all()["stations"].size() == 1, "a station added in the menu is kept, an invalid one is not")
	_check(ui._stations_box.get_child_count() == 1 and ui._stations_box.get_child(0) is HBoxContainer, "and listed on the Radio tab with its row")
	ui.station_removed.emit("https://j.example/live")
	await _frames(2)
	_check(Config.load_all()["stations"].is_empty(), "a station removed in the menu is gone")
	# Cache
	ui.cache_size_changed.emit(100)
	await _frames(2)
	_check(Config.load_all()["cache_mb"] == 100 and hifi.cache.cap_bytes == 100 * 1024 * 1024, "the cache size from the menu reaches the settings and the cache")
	_check(ui._cache_size_label.text == "100 MB", "and its label")
	var f := FileAccess.open(SCRATCH + "/cache/x.mp3", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4]))
	f = null
	ui.cache_clear_pressed.emit()
	await _frames(2)
	_check(not hifi.cache.has("x.mp3"), "Clear cache empties it")
	ui.quality_changed.emit(192)
	_check(hifi.transcode_format == "mp3" and hifi.transcode_kbps == 192 and int(Config.load_all()["quality_kbps"]) == 192, "quality reaches the Hi-Fi and the settings")
	ui.quality_changed.emit(0)
	_check(hifi.transcode_format == "" and not Config.load_all().has("quality_kbps"), "original quality removes the setting")
	# Sign in: the password is read, cleared, and never written; the refused connection is a failure, not a crash.
	ui._user_edit.text = "RetroXR"
	ui._pass_edit.text = "hunter2-secret"
	ui._sign_in_btn.pressed.emit()
	_check(ui._pass_edit.text.is_empty(), "the password field is cleared on sign in")
	await get_tree().create_timer(2.0).timeout
	_check(not hifi.is_signed_in() and hifi.status == "SIGN IN FAILED", "a refused connection fails the sign in (%s)" % hifi.status)
	var saved := FileAccess.get_file_as_string(SCRATCH + "/settings.json")
	_check(not saved.contains("hunter2") and not saved.contains("password"), "the password is in no file")
	# Playing with no way to fetch: the queue says so, and nothing plays.
	var songs := [{"id": "s1", "title": "One", "artist": "A", "album": "B", "duration": 100, "suffix": "mp3", "track": 1, "disc": 1}]
	hifi.client.configure("http://127.0.0.1:9", "u", "t", "s")
	hifi.play_songs(songs, 0)
	_check(hifi.status == "LOADING" and not hifi.is_playing, "a track not in the cache shows LOADING and does not play yet")
	_check(hifi.has_track_skip() and hifi.has_scan(), "a library queue has skip and scan")
	await get_tree().create_timer(2.0).timeout
	_check(hifi.status == "NO LINK" and not hifi.is_playing, "a download that cannot be made ends in NO LINK (%s)" % hifi.status)
	hifi.stop()
	_check(hifi.status == "NO LINK" or hifi.status == "", "STOP after that does not crash")
	# A station
	hifi.play_station({"name": "Nowhere", "url": "http://127.0.0.1:9/stream.mp3"})
	_check(hifi.source == SubsonicHifi.Source.RADIO and not hifi.has_track_skip() and not hifi.has_scan(), "a station has no skip and no scan")
	hifi.stop()
	_check(hifi.source == SubsonicHifi.Source.RADIO and not hifi.is_playing, "STOP leaves the station tuned but silent")
	hifi.sign_out()
	_check(not Config.has_login(Config.load_all()), "sign out forgets the key")
	# The body
	_body(hifi)
	# The panel hides
	HifiPanel.toggle_for(hifi, cam)
	_check(not panel.visible, "TAB again closes the menu")
	# The queue API's guards
	hifi.play_songs([], 0)
	_check(hifi.source == SubsonicHifi.Source.RADIO, "an empty queue changes nothing")
	_check(hifi.song_at(0).is_empty(), "no song while a station is tuned")
	_finish()


func _body(hifi: SubsonicHifi) -> void:
	var Body = preload("res://mods/xenu.subsonic/scripts/hifi_model.gd")
	_check(hifi.body_triangles > 100 and hifi.body_triangles < 2000, "the body is a few hundred triangles, under the 2000 budget (%d)" % hifi.body_triangles)
	var gone := true
	for n: String in ["OpenButton", "RewindButton", "FastForwardButton", "RepeatButton", "ShuffleButton"]:
		gone = gone and hifi.get_node_or_null(n) == null
	_check(gone, "the base scene's tray-era keys are gone (no invisible hit boxes in front of the fascia)")
	var ok_keys := true
	var xs: Array[float] = []
	for row: Array in [Body.NAV_ROW, Body.TRANSPORT_ROW]:
		for spec: Array in row:
			var b := hifi.get_node_or_null(str(spec[0])) as VRButton
			if b == null:
				ok_keys = false
				continue
			# Its face is the unit's +Z, on the fascia, inside the fascia's width.
			ok_keys = ok_keys and b.transform.basis.y.is_equal_approx(Vector3(0, 0, 1)) \
				and is_equal_approx(b.position.z, Body.FRONT) and absf(b.position.x) < Body.W / 2.0 - Body.CAP.x / 2.0
			ok_keys = ok_keys and b.get_node("ButtonMesh").visible and b.get_node("ButtonMesh").mesh is BoxMesh
	_check(ok_keys, "all twelve keys exist, face front, stand on the fascia and wear a cap")
	var overlap := false
	var spots := {}
	for row: Array in [Body.NAV_ROW, Body.TRANSPORT_ROW]:
		for spec: Array in row:
			var b := hifi.get_node(str(spec[0])) as VRButton
			for k: Vector2 in spots:
				if absf(k.x - b.position.x) < Body.CAP.x and absf(k.y - b.position.y) < Body.CAP.y:
					overlap = true
			spots[Vector2(b.position.x, b.position.y)] = true
	_check(not overlap, "no two caps overlap")
	var lo := hifi.get_node("AudioLOut") as Node3D
	var ph := hifi.get_node("PhonesOut") as Node3D
	_check(lo.position.z < -Body.D / 2.0 and ph.position.z > Body.D / 2.0 - 0.001, "the line out is on the back, PHONES on the front")
	var up := hifi.get_node("UpButton") as VRButton
	var before: int = hifi.browser.page()["cursor"]
	hifi.browser.refresh_home()
	hifi.browser.pages.stack[0]["cursor"] = 0
	up.button_pressed.emit()
	var down := hifi.get_node("DownButton") as VRButton
	down.button_pressed.emit()
	down.button_pressed.emit()
	_check(hifi.browser.page()["cursor"] == 1, "the keys reach the browser (down, down, up: row 1; was %d)" % before)
	var knob := hifi.get_node("LevelKnob") as VRKnob
	knob.set_value(0.4)
	_check(is_equal_approx(hifi.phones_level, 0.4), "the LEVEL knob sets the headphones' level")
	var sv := hifi.get_node("Screen/Viewport") as SubViewport
	_check(sv != null and sv.get_child_count() == 1 and sv.get_child(0).get("browser") == hifi.browser, "the screen is up and bound to the browser")


func _finish() -> void:
	print("[sb-hifi] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-hifi] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
