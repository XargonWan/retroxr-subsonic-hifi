## HifiOptionsPanel -- the Hi-Fi's floating menu (point at it and press the left thumbstick; Tab on a desktop).
## Built on demand as the Hi-Fi's child, as the Jellyfin decoder's is. The server, the login, the stations and the
## cache size live on the OBJECT and in its settings file; the panel only moves values between the 2D page and the
## Hi-Fi.
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://mods/xenu.subsonic/scenes/hifi_options_panel.tscn")
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const NODE_NAME := "HifiOptionsPanel"
## How far above the unit's origin the menu hangs (the base's own anchor lifts it clear of the box).
const FLOAT_HEIGHT := 0.3

var _hifi: Node3D = null
var _timer := 0.0

@onready var _viewport_node: XRToolsViewport2DIn3D = $HifiOptionsViewport


static func toggle_for(hifi: Node3D, camera: Node3D) -> void:
	if not is_instance_valid(hifi):
		return
	var panel := hifi.get_node_or_null(NODE_NAME)
	if panel == null:
		panel = PANEL_SCENE.instantiate()
		panel.name = NODE_NAME
		hifi.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(hifi, camera)


func show_for(hifi: Node3D, camera: Node3D) -> void:
	_hifi = hifi
	_camera = camera
	global_position = _anchor()
	visible = true
	_ensure_ui_connected()
	_populate()


func _get_ui() -> Control:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Control


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if ui == null:
		call_deferred("_ensure_ui_connected")
		return
	ui.close_requested.connect(hide_panel)
	ui.server_submitted.connect(func(text: String) -> void:
		if not text.strip_edges().is_empty() and Api_norm(text) != str(Config.load_all().get("server", "")):
			_hifi.call("set_server", text))
	ui.sign_in_pressed.connect(func(user: String, password: String) -> void:
		_hifi.call("sign_in", user, password))
	ui.sign_out_pressed.connect(func() -> void: _hifi.call("sign_out"))
	ui.station_added.connect(func(n: String, u: String) -> void:
		Config.add_station(n, u)
		_refresh())
	ui.station_removed.connect(func(u: String) -> void:
		Config.remove_station(u)
		_refresh())
	ui.station_played.connect(func(u: String) -> void:
		for st: Dictionary in _hifi.call("stations"):
			if st["url"] == u:
				_hifi.call("play_station", st))
	ui.stations_refresh_pressed.connect(func() -> void:
		_hifi.call("refresh_server_stations", func(_all: Array) -> void: _refresh()))
	ui.cache_size_changed.connect(func(mb: int) -> void:
		Config.set_value("cache_mb", mb)
		_hifi.call("apply_cache_size")
		_refresh())
	ui.cache_clear_pressed.connect(func() -> void:
		_hifi.call("clear_cache")
		_refresh())
	ui.quality_changed.connect(func(kbps: int) -> void:
		_hifi.call("set_quality", kbps)
		_refresh())
	ui.lcd_filter_changed.connect(func(on: bool) -> void: _hifi.call("set_lcd_filter", on))
	ui.ignore_gravity_toggled.connect(func(on: bool) -> void: _hifi.call("set_ignore_gravity", on))
	_hifi.state_changed.connect(_refresh)
	_ui_connected = true


static func Api_norm(text: String) -> String:
	return preload("res://mods/xenu.subsonic/scripts/sb_api.gd").normalize_server(text)


func _populate() -> void:
	if _get_ui() == null:
		call_deferred("_populate")
		return
	_refresh()


func _refresh() -> void:
	var ui := _get_ui()
	if ui == null or not is_instance_valid(_hifi):
		return
	var s: Dictionary = Config.load_all()
	var signed := bool(_hifi.call("is_signed_in"))
	var status := str(_hifi.get("status"))
	var text := "Not signed in"
	var ok := false
	if signed:
		text = "Connected to %s" % str(s.get("server", ""))
		ok = true
	elif not str(s.get("server", "")).is_empty():
		text = "Server set: sign in"
	if not status.is_empty():
		text = status.capitalize() + (" — " + text if not signed else "")
		ok = false
	ui.populate({
		"status": text, "ok": ok,
		"server": str(s.get("server", "")), "user": str(s.get("user", "")), "signed_in": signed,
		"stations": _hifi.call("stations"), "cache_mb": s["cache_mb"],
		"cache_used": int((_hifi.get("cache") as RefCounted).call("total_bytes")),
		"quality": int(s.get("quality_kbps", 0)),
		"ignore_gravity": bool(_hifi.call("get_ignore_gravity")), "lcd_filter": bool(_hifi.get("lcd_filter")),
	})


func _while_shown(delta: float) -> void:
	# The cache grows while a track downloads; the menu keeps up once a second.
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_refresh()


func _target_node() -> Node3D:
	return _hifi


func _float_height() -> float:
	return FLOAT_HEIGHT
