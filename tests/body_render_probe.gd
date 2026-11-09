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
	cam.position = Vector3(0.20, 0.25, 0.62)
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
	cam.position = Vector3(0.0, 0.03, 0.55)
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
	cam.position = Vector3(-0.36, 0.12, 0.40)
	cam.look_at(Vector3(0.0, 0.0, 0.15))
	await _shot(vp, "hifi_left")
	cam.position = Vector3(-0.25, 0.20, -0.55)
	cam.look_at(Vector3(0.05, -0.02, -0.1))
	await _shot(vp, "hifi_back")
	get_tree().quit(0)
