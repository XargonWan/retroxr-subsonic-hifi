## Pictures of the Hi-Fi in a little room of its own (windowed; a headless renderer returns blanks):
##   OUT=dir godot --path RetroXR --resolution 320x240 --position 20,20 res://mods/xenu.subsonic/tests/body_render_probe.tscn
## Settings go to a scratch file so the player's real server is not touched. The screen shows a sample queue.
extends Node


func _ready() -> void:
	_run.call_deferred()


func _shot(vp: SubViewport, name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[probe] wrote %s.png" % name)


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", "user://sb_probe/settings.json")
	OS.set_environment("XENU_SB_CACHE", "user://sb_probe/cache")
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 520)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC   # the game's (tonemap_mode = 2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(light)
	var h := (load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene).instantiate() as SubsonicHifi
	vp.add_child(h)
	h.set("ignore_gravity", true)
	h.set("freeze", true)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0.30, 0.25, 0.80)
	cam.look_at(Vector3(0.0, 0.0, 0.0))
	print("[probe] body triangles: %d" % h.body_triangles)
	await _shot(vp, "hifi_three_quarter")
	# A sample page on the screen: an album with songs.
	var b = h.browser
	b.pages.push("album", "Arrival - ABBA")
	b.pages.set_rows(b.page(), b.Pages.song_rows([
		{"track": 1, "title": "When I Kissed the Teacher", "artist": "ABBA", "duration": 182},
		{"track": 2, "title": "Dancing Queen", "artist": "ABBA", "duration": 231},
		{"track": 3, "title": "My Love, My Life", "artist": "ABBA", "duration": 233}], "▶ Play album"))
	b.changed.emit()
	cam.position = Vector3(0.0, 0.0, 0.66)
	cam.fov = 38.0
	cam.look_at(Vector3(0.0, 0.0, 0.15))
	await _shot(vp, "hifi_front")
	# The search keyboard, and the radio list with the station on air marked.
	b.pages.push("search", "Search")
	b.page()["kb"] = [1, 3]
	b.page()["text"] = "abba"
	b.changed.emit()
	await _shot(vp, "hifi_keyboard")
	b.go_home()
	b.pages.push("radio", "Radio")
	b.pages.set_rows(b.page(), b.Pages.station_rows([{"name": "RADIODROME", "url": "a"}, {"name": "Jazz FM", "url": "b"}], "a"))
	b.changed.emit()
	h.status = "LOADING"
	h.state_changed.emit()
	await _shot(vp, "hifi_radio")
	# Now playing: a library track with a cover, then a station.
	var img := Image.create(192, 192, false, Image.FORMAT_RGB8)
	for y in 192:
		for x in 192:
			var d := Vector2(x - 96, y - 96).length()
			img.set_pixel(x, y, Color(0.9, 0.55, 0.15).lerp(Color(0.15, 0.1, 0.3), clampf(d / 140.0, 0.0, 1.0)) if d > 40 else Color(0.97, 0.95, 0.9))
	h.cover = ImageTexture.create_from_image(img)
	h.source = SubsonicHifi.Source.LIBRARY
	h.queue = [{"id": "a", "title": "Questo È Halloween (di \"Tim Burton's Nightmare Before Christmas\"/Colonna Sonora Originale)", "artist": "The Citizens of Halloween", "album": "Tim Burton's The Nightmare Before Christmas", "duration": 196, "suffix": "flac", "bitrate": 905, "track": 1},
		{"id": "b", "title": "Jack's Lament", "artist": "Danny Elfman", "album": "", "duration": 200, "suffix": "mp3", "bitrate": 320, "track": 2}]
	h._track_idx = 0
	h.is_playing = true
	h.shuffle = true
	h.repeat = 1
	b.go_home()
	b.activate({"text": "Now playing", "act": "open", "arg": "now"})
	cam.position = Vector3(0.0, 0.0, 0.66)
	cam.look_at(Vector3(0.0, 0.0, 0.15))
	await _shot(vp, "hifi_now_library")
	h.source = SubsonicHifi.Source.RADIO
	h.station = {"name": "RADIODROME", "url": "x"}
	h.radio_info = {"title": "Red World Coming Close", "artist": "Rekku", "album": "", "elapsed": 95, "duration": 200, "next_title": "Rekku - Another One"}
	h._radio_info_msec = Time.get_ticks_msec()
	h.state_changed.emit()
	await _shot(vp, "hifi_now_radio")
	h.is_playing = false
	h.state_changed.emit()
	b.go_home()
	cam.position = Vector3(-0.45, 0.15, 0.50)
	cam.look_at(Vector3(0.0, 0.0, 0.15))
	await _shot(vp, "hifi_left")
	cam.position = Vector3(-0.30, 0.20, -0.65)
	cam.look_at(Vector3(0.05, -0.02, -0.1))
	await _shot(vp, "hifi_back")
	get_tree().quit(0)
