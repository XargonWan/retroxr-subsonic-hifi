## Cut-out renders (transparent background) of the Hi-Fi: side and three-quarter, cropped to the model.
##   OUT=dir godot --path RetroXR --resolution 320x240 --position 20,20 res://mods/xenu.subsonic/tests/cutout_render_probe.tscn
## Windowed (a headless renderer returns blanks). Settings go to a scratch file, the real server is not touched.
extends Node

const SIZE := Vector2i(2400, 1600)


func _ready() -> void:
	_run.call_deferred()


func _meshes(n: Node, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
		acc.append(n)
	for c in n.get_children():
		_meshes(c, acc)


## World-space AABB of every visible mesh under `root`.
func _aabb(root: Node3D) -> AABB:
	var list: Array = []
	_meshes(root, list)
	var box := AABB()
	var first := true
	for m: MeshInstance3D in list:
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _shot(vp: SubViewport, name: String) -> void:
	for i in 10:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var r := img.get_used_rect()
	var pad := 24
	r = r.grow(pad).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img = img.get_region(r)
	img.save_png("%s/%s.png" % [out, name])
	print("[probe] wrote %s.png %s (model rect %s)" % [name, img.get_size(), r])


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", "user://sb_probe/settings.json")
	OS.set_environment("XENU_SB_CACHE", "user://sb_probe/cache")
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.64)
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -120, 0)
	fill.light_energy = 0.35
	vp.add_child(fill)
	var h := (load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene).instantiate() as SubsonicHifi
	vp.add_child(h)
	h.set("ignore_gravity", true)
	h.set("freeze", true)
	# The screen shows a track playing with a cover, not the "Not signed in" page.
	var img := Image.create(192, 192, false, Image.FORMAT_RGB8)
	for y in 192:
		for x in 192:
			var d := Vector2(x - 96, y - 96).length()
			img.set_pixel(x, y, Color(0.9, 0.55, 0.15).lerp(Color(0.15, 0.1, 0.3), clampf(d / 140.0, 0.0, 1.0)) if d > 40 else Color(0.97, 0.95, 0.9))
	h.cover = ImageTexture.create_from_image(img)
	h.source = SubsonicHifi.Source.LIBRARY
	h.queue = [{"id": "a", "title": "Dancing Queen", "artist": "ABBA", "album": "Arrival", "duration": 231, "suffix": "flac", "bitrate": 905, "track": 2}]
	h._track_idx = 0
	h.is_playing = true
	h.browser.activate({"text": "Now playing", "act": "open", "arg": "now"})
	var cam := Camera3D.new()
	cam.fov = 18.0
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)
	for i in 4:
		await get_tree().process_frame
	var box := _aabb(h)
	var c := box.get_center()
	var radius := box.size.length() * 0.5
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.8
	print("[probe] aabb %s centre %s radius %.3f dist %.2f" % [box, c, radius, dist])
	# +Z is the front of the unit (the body probe looks at it from z > 0), +X its right-hand side.
	var views := {
		"hifi_cutout_side": Vector3(1.0, 0.04, 0.0),
		"hifi_cutout_three_quarter": Vector3(0.62, 0.22, 0.75),
	}
	for name: String in views:
		var dir: Vector3 = (views[name] as Vector3).normalized()
		cam.position = c + dir * dist
		cam.look_at(c)
		await _shot(vp, name)
	get_tree().quit(0)
