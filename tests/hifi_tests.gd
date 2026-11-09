## The object and its TAB menu in the real game's classes, with no server: settings go to a scratch file, the only
## address used refuses connections at once (127.0.0.1:9), so no test ever touches the player's real login or network.
extends Node

const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const Body = preload("res://mods/xenu.subsonic/scripts/hifi_model.gd")
const HifiPanel = preload("res://mods/xenu.subsonic/scripts/hifi_options_panel.gd")
const EXPECTED_CASES := 83
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
	# With libVLC the track starts streaming at once; without it (CI) it is fetched first. Either way the end is the same.
	_check((hifi.status == "LOADING" and not hifi.is_playing) or hifi.is_playing, "a track not in the cache is on its way (%s)" % hifi.status)
	_check(hifi.has_track_skip() and hifi.has_scan(), "a library queue has skip and scan")
	await get_tree().create_timer(4.0).timeout
	_check(hifi.status == "NO LINK" and not hifi.is_playing, "a server that cannot be reached ends in NO LINK (status %s, playing %s)" % [hifi.status, hifi.is_playing])
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
	await _modes(hifi)
	await _stations(hifi, ui)
	await _now_playing(hifi)
	# The panel hides
	HifiPanel.toggle_for(hifi, cam)
	_check(not panel.visible, "TAB again closes the menu")
	# The queue API's guards
	hifi.play_songs([], 0)
	_check(hifi.source == SubsonicHifi.Source.RADIO, "an empty queue changes nothing")
	_check(hifi.song_at(0).is_empty(), "no song while a station is tuned")
	_finish()


func _body(hifi: SubsonicHifi) -> void:
	_check(hifi.body_triangles > 100 and hifi.body_triangles < 2000, "the body is a few hundred triangles, under the 2000 budget (%d)" % hifi.body_triangles)
	var gone := true
	for n: String in ["OpenButton", "RepeatButton", "ShuffleButton"]:
		gone = gone and hifi.get_node_or_null(n) == null
	_check(gone, "the base scene's tray-era keys are gone (no invisible hit boxes in front of the fascia)")
	var ok_keys := true
	var xs: Array[float] = []
	for row: Array in [Body.NAV_ROW, Body.TRANSPORT_ROW, [["ModeButton"], ["TapeEjectButton"], ["CdEjectButton"]]]:
		for spec: Array in row:
			var b := hifi.get_node_or_null(str(spec[0])) as VRButton
			if b == null:
				ok_keys = false
				continue
			# Its face is the unit's +Z, on the fascia, inside the fascia's width.
			ok_keys = ok_keys and b.transform.basis.y.is_equal_approx(Vector3(0, 0, 1)) \
				and is_equal_approx(b.position.z, Body.FRONT) and absf(b.position.x) < Body.W / 2.0 - Body.CAP.x / 2.0
			ok_keys = ok_keys and b.get_node("ButtonMesh").visible and b.get_node("ButtonMesh").mesh is BoxMesh
	_check(ok_keys, "every key exists, faces front, stands on the fascia and wears a cap")
	var overlap := false
	var spots := {}
	for row: Array in [Body.NAV_ROW, Body.TRANSPORT_ROW, [["ModeButton"], ["TapeEjectButton"], ["CdEjectButton"]]]:
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
	var screen := sv.get_child(0)
	_check(hifi.lcd_filter and screen._filter.visible, "the retro LCD filter is on by default")
	hifi.set_lcd_filter(false)
	_check(not screen._filter.visible and Config.load_all()["lcd_filter"] == false, "the TAB switch takes it off, and it is kept")
	hifi.set_lcd_filter(true)
	_check(screen._filter.visible, "and back on")


func _led_lit(hifi: SubsonicHifi, i: int) -> bool:
	var led := hifi.get_node("Model/Led_%s" % Body.LED_NAMES[i]) as MeshInstance3D
	return led.material_override == Body.led_material(i, true)


func _make_album(dir: String, names: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for n: String in names:
		var f := FileAccess.open(dir + "/" + n, FileAccess.WRITE)
		f.store_string("x")


func _modes(hifi: SubsonicHifi) -> void:
	# The LEDs: one lit, the mode on.
	_check(hifi.mode == SubsonicHifi.Mode.INTERNET and _led_lit(hifi, 2) and not _led_lit(hifi, 0) and not _led_lit(hifi, 1), "the unit starts on NET with its LED lit and the others dark")
	var mode_key := hifi.get_node("ModeButton") as VRButton
	mode_key.button_pressed.emit()
	_check(hifi.mode == SubsonicHifi.Mode.CD and _led_lit(hifi, 0) and not _led_lit(hifi, 2), "MODE steps NET to CD and moves the LED")
	_check(hifi.source == SubsonicHifi.Source.MEDIA and hifi.has_track_skip(), "CD is a disc source, with skip")
	mode_key.button_pressed.emit()
	_check(hifi.mode == SubsonicHifi.Mode.TAPE and _led_lit(hifi, 1) and hifi.plays_sides() and not hifi.has_track_skip() and hifi.has_scan(), "then TAPE: a tape plays sides, scans and does not skip")
	mode_key.button_pressed.emit()
	_check(hifi.mode == SubsonicHifi.Mode.INTERNET, "and back to NET")
	# What NET was left on comes back.
	hifi.source = SubsonicHifi.Source.LIBRARY
	hifi.queue = [{"id": "q0", "title": "Q0", "suffix": "mp3"}, {"id": "q1", "title": "Q1", "suffix": "mp3"}]
	hifi._tracks = PackedStringArray(["a", "b"])
	hifi.set_mode(SubsonicHifi.Mode.CD)
	_check(hifi.source == SubsonicHifi.Source.MEDIA and hifi.queue.size() == 2, "leaving NET keeps its queue")
	hifi.set_mode(SubsonicHifi.Mode.INTERNET)
	_check(hifi.source == SubsonicHifi.Source.LIBRARY and hifi._tracks.size() == 2, "coming back to NET takes the queue up again")
	hifi.source = SubsonicHifi.Source.NONE
	hifi.queue = []
	hifi._net_source = SubsonicHifi.Source.NONE
	hifi._tracks = PackedStringArray()
	# PLAY with nothing in the bay says so and plays nothing.
	hifi.set_mode(SubsonicHifi.Mode.CD)
	hifi.play()
	_check(hifi.status == "NO DISC" and not hifi.is_playing, "PLAY on CD with no disc says NO DISC")
	hifi.set_mode(SubsonicHifi.Mode.TAPE)
	hifi.play()
	_check(hifi.status == "NO TAPE" and not hifi.is_playing, "and on TAPE, NO TAPE")
	hifi.set_mode(SubsonicHifi.Mode.INTERNET)
	# A real disc and a real cassette into their bays.
	var dir := SCRATCH + "/album"
	_make_album(dir, ["01 First.mp3", "02 Second.mp3"])
	var disc := (load("res://Scenes/Objects/media/audio_disc.tscn") as PackedScene).instantiate()
	disc.set("album_path", ProjectSettings.globalize_path(dir))
	disc.set("album_label", "Test Disc")
	add_child(disc)
	hifi._slot_cd.restore(disc)
	await _frames(3)
	_check(hifi.mode == SubsonicHifi.Mode.CD and hifi.has_media_in_bay(), "a disc put in the bay (nothing playing) takes the unit to CD")
	_check(hifi._tracks.size() == 2 and hifi.media_label() == "Test Disc" and hifi.has_track_skip(), "its tracks are read as a CD's are")
	_check(hifi.media_tracks() == ["01 First", "02 Second"], "and named without their extension")
	hifi.browser.go_home()
	var home: Array = hifi.browser.page()["rows"].map(func(r: Dictionary) -> String: return r["text"])
	_check("Tracks" in home and "Eject" in home and "Internet (NET)" in home, "the CD home page offers Tracks, Eject and NET (%s)" % str(home))
	hifi.is_playing = true
	var np := hifi.now_playing()
	_check(np["source"] == "media" and np["title"] == "01 First" and np["album"] == "Test Disc" and np["format"] == "CD" and np["next"] == "02 Second" and np["count"] == 2, "now_playing() names the track, the disc and the next track")
	hifi.is_playing = false
	var tape := (load("res://Scenes/Objects/media/audio_cassette.tscn") as PackedScene).instantiate()
	tape.set("album_path", ProjectSettings.globalize_path(dir))
	tape.set("album_label", "Test Tape")
	add_child(tape)
	# With the CD playing, a cassette put in waits: the mode does not change under it.
	hifi.is_playing = true
	hifi._slot_tape.restore(tape)
	await _frames(3)
	_check(hifi.mode == SubsonicHifi.Mode.CD, "a cassette put in while the CD plays does not take the unit over")
	hifi.is_playing = false
	hifi.set_mode(SubsonicHifi.Mode.TAPE)
	await _frames(2)
	_check(hifi.has_media_in_bay() and hifi.plays_sides() and hifi._tracks.size() == 2 and not hifi.has_track_skip(), "MODE to TAPE takes up the waiting cassette: side A's tracks, no skip")
	hifi.is_playing = true
	np = hifi.now_playing()
	_check(np["format"] == "TAPE  SIDE A" and np["title"] == "01 First", "a tape says its side")
	hifi.is_playing = false
	# Taking the cassette out of its bay empties that function only.
	hifi._on_tape_out()
	_check(not hifi.has_media_in_bay() and hifi._tracks.is_empty(), "a cassette out leaves the tape function empty")
	hifi.set_mode(SubsonicHifi.Mode.CD)
	_check(hifi.has_media_in_bay(), "while the disc is still in its own bay")
	# NET content asked for from another function switches to NET.
	hifi.play_station({"name": "Nowhere", "url": "http://127.0.0.1:9/stream.mp3"})
	_check(hifi.mode == SubsonicHifi.Mode.INTERNET and hifi.source == SubsonicHifi.Source.RADIO, "tuning a station from CD goes to NET")
	hifi.stop()
	hifi.station = {}
	hifi.source = SubsonicHifi.Source.NONE
	hifi._net_source = SubsonicHifi.Source.NONE
	disc.queue_free()
	tape.queue_free()


func _stations(hifi: SubsonicHifi, ui: Control) -> void:
	Config.set_value("stations", [])
	Config.add_station("Mine", "https://mine.example/live")
	Config.set_value("server_stations", [{"name": "Theirs", "url": "https://theirs.example/live"}, {"name": "Mine on the server", "url": "https://mine.example/live"}])
	_check(hifi.stations().map(func(s: Dictionary) -> String: return s["name"]) == ["Mine", "Theirs"], "the stations are the player's own then the server's, a shared url once")
	hifi.state_changed.emit()
	await _frames(2)
	var rows: Array = ui._stations_box.get_children()
	_check(rows.size() == 2 and rows[0].get_child_count() == 2 and rows[1].get_child_count() == 1, "the menu lists both; only the player's own has a remove button")
	_check(rows[1].get_child(0).text.contains("SERVER"), "and the server's is marked")
	ui.station_removed.emit("https://theirs.example/live")
	await _frames(2)
	_check(hifi.stations().size() == 2, "removing a server station from the menu changes nothing (it is the server's)")
	hifi.client.configure("http://127.0.0.1:9", "u", "t", "s")
	var box := {"list": null}
	hifi.refresh_server_stations(func(all: Array) -> void: box["list"] = all)
	await get_tree().create_timer(2.0).timeout
	_check(box["list"] != null and (box["list"] as Array).size() == 2, "a refresh that cannot reach the server keeps what was kept")


func _now_playing(hifi: SubsonicHifi) -> void:
	var songs: Array = []
	for i in 4:
		songs.append({"id": "n%d" % i, "title": "Song %d" % i, "artist": "Artist", "album": "Album", "duration": 100 + i, "suffix": "flac", "bitrate": 900, "track": i + 1, "disc": 1, "cover": ""})
	hifi.source = SubsonicHifi.Source.LIBRARY
	hifi.queue = songs
	hifi._track_idx = 1
	# What plays next, by each setting.
	hifi.shuffle = false
	hifi.repeat = 0
	_check(hifi._track_after(1) == 2 and hifi._track_after(3) == -1, "the queue plays on and stops at its end")
	hifi.repeat = 1
	_check(hifi._track_after(3) == 0, "REPEAT ALL wraps")
	hifi.repeat = 2
	_check(hifi._track_after(2) == 2, "REPEAT ONE plays the same track")
	hifi.repeat = 0
	hifi.shuffle = true
	hifi._played = {}
	var seen := {}
	var idx := 0
	var ended := false
	for n in 10:
		var nxt := hifi._track_after(idx)
		if nxt < 0:
			ended = true
			break
		seen[nxt] = true
		idx = nxt
	_check(ended and seen.size() == 3 and not seen.has(0), "SHUFFLE plays every other track once, then stops (%s)" % str(seen.keys()))
	hifi.repeat = 1
	hifi._played = {}
	var more := true
	for n in 12:
		more = more and hifi._track_after(idx) >= 0
	_check(more, "SHUFFLE with REPEAT ALL never runs out")
	hifi.shuffle = false
	hifi.repeat = 0
	# What the screen is told.
	hifi.is_playing = true
	var np := hifi.now_playing()
	_check(np["title"] == "Song 1" and np["index"] == 1 and np["count"] == 4 and np["format"] == "FLAC 900 kbps" and np["next"] == "Song 2" and not np["paused"], "now_playing() carries the track, its place, format and the next one")
	hifi.set_shuffle(true)
	hifi.cycle_repeat()
	np = hifi.now_playing()
	_check(np["shuffle"] and np["repeat"] == 1 and np["next"] == "", "and the shuffle and repeat state, with no next when shuffled")
	_check(Config.load_all()["shuffle"] == true and int(Config.load_all()["repeat"]) == 1, "which are kept in the settings")
	hifi.set_shuffle(false)
	hifi.cycle_repeat()
	hifi.cycle_repeat()
	_check(hifi.repeat == 0 and not Config.load_all().has("repeat"), "REPEAT cycles back to off")
	# The page.
	var ui := hifi.get_node("Screen/Viewport").get_child(0)
	hifi.browser.go_home()
	hifi.browser.activate({"text": "Now playing", "act": "open", "arg": "now"})
	await _frames(2)
	_check(ui._np_box.visible and ui._np_title.text == "Song 1" and ui._np_artist.text == "Artist", "the Now playing page shows the title and artist")
	_check(ui._np_info.text.begins_with("track 2 of 4") and ui._np_info.text.contains("FLAC"), "and where it is in the queue and what it is")
	_check(ui._np_next.text == "next: Song 2", "and what comes next")
	_check(ui._np_play.text == TransportGlyphs.glyph("pause"), "the play key shows PAUSE while it plays")
	hifi._paused = true
	hifi.state_changed.emit()
	await _frames(2)
	_check(ui._np_play.text == TransportGlyphs.glyph("play"), "and PLAY once paused")
	hifi._paused = false
	hifi.source = SubsonicHifi.Source.RADIO
	hifi.station = {"name": "Radio X", "url": "https://x/live"}
	hifi.radio_info = {"title": "On Air", "artist": "DJ", "album": "", "elapsed": 10, "duration": 200, "next_title": "Later"}
	hifi.state_changed.emit()
	await _frames(2)
	_check(ui._np_title.text == "On Air" and ui._np_album.text.contains("Radio X") and ui._np_prev.disabled and ui._np_shuffle.disabled, "a station shows what is on air, with skip and shuffle off")
	_check(ui._np_total.text == "3:20" and ui._np_next.text == "next: Later", "and AzuraCast's length and next song")
	hifi.is_playing = false
	hifi.state_changed.emit()
	await _frames(2)
	_check(ui._np_empty.visible and not ui._np_title.visible, "with nothing on the page says so")
	hifi.browser.go_home()


func _finish() -> void:
	print("[sb-hifi] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-hifi] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
