## A picture of each tab of the TAB menu (windowed; a headless renderer returns blanks):
##   OUT=dir godot --path RetroXR --resolution 320x240 --position 20,20 res://mods/xenu.subsonic/tests/menu_render_probe.tscn
extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", "user://sb_probe/settings.json")
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 620)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ui := (load("res://mods/xenu.subsonic/scenes/hifi_options_2d.tscn") as PackedScene).instantiate() as Control
	vp.add_child(ui)
	for i in 3:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	ui.populate({"status": "Connected to https://audio.example.org", "ok": true, "server": "https://audio.example.org",
		"user": "RetroXR", "signed_in": false, "stations": [{"name": "RADIODROME", "url": "https://r/public/radiodrome"},
		{"name": "Jazz FM with a rather long name", "url": "https://j/live"}], "cache_mb": 50, "cache_used": 23456789,
		"quality": 192, "ignore_gravity": false})
	for i in 3:
		await get_tree().process_frame
	var names := ["server", "radio", "cache", "unit"]
	for t in 4:
		ui._tabs.current_tab = t
		for i in 4:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.save_png("%s/menu_%s.png" % [out, names[t]])
		print("[probe] wrote menu_%s.png (%dx%d)" % [names[t], img.get_width(), img.get_height()])
	get_tree().quit(0)
