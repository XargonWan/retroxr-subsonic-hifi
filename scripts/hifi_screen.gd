## HifiScreen -- the Hi-Fi's LCD, 640 x 320: a header (back, title, home), six rows, a page column (up / down), a
## now-playing strip. It draws what the browser (hifi_browser.gd) holds and forwards presses into it; it holds no
## state of its own beyond the widgets. Loaded into an XRToolsViewport2DIn3D on the unit's face, so a laser or a
## click works its Buttons like any menu of the game.
##
## Colours are an LCD's: near-black blue with cyan text, amber for the cursor row.
extends Control

const Pages = preload("res://mods/xenu.subsonic/scripts/sb_pages.gd")
const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")

const SIZE := Vector2(640, 320)
const HEADER_H := 36.0
const ROW_H := 36.0
const ROWS_TOP := 40.0
const FOOT_TOP := 262.0
const SIDE_W := 52.0

const C_BG := Color(0.015, 0.05, 0.075)
const C_TEXT := Color(0.62, 0.96, 1.0)
const C_DIM := Color(0.34, 0.58, 0.66)
const C_ROW := Color(0.04, 0.11, 0.15)
const C_CURSOR := Color(0.55, 0.36, 0.05)
const C_CURSOR_TEXT := Color(1.0, 0.86, 0.5)
const C_WARN := Color(1.0, 0.78, 0.35)

var browser: RefCounted = null

var _title: Label = null
var _status: Label = null
var _back: Button = null
var _home: Button = null
var _rows: Array[Button] = []
var _row_sub: Array[Label] = []
var _up: Button = null
var _down: Button = null
var _hint: Label = null
var _kb_box: Control = null
var _kb_keys: Array = []          # [{btn, row, col}]
var _kb_text: Label = null
var _foot: Button = null
var _foot_title: Label = null
var _foot_sub: Label = null
var _foot_time: Label = null
var _bar: ColorRect = null
var _bar_fill: ColorRect = null
var _cover: TextureRect = null
var _now: Dictionary = {}
var _hifi: Object = null
# The Now playing page.
var _np_box: Control = null
var _np_cover: TextureRect = null
var _np_blank: Label = null
var _np_title: Label = null
var _np_artist: Label = null
var _np_album: Label = null
var _np_info: Label = null
var _np_next: Label = null
var _np_bar: ColorRect = null
var _np_fill: ColorRect = null
var _np_elapsed: Label = null
var _np_total: Label = null
var _np_prev: Button = null
var _np_play: Button = null
var _np_stop: Button = null
var _np_nextb: Button = null
var _np_shuffle: Button = null
var _np_repeat: Button = null
var _np_empty: Label = null
var _foot_nodes: Array[Control] = []
var _filter: ColorRect = null


func _ready() -> void:
	custom_minimum_size = SIZE
	_build()


const RETRO_SHADER := preload("res://mods/xenu.subsonic/scripts/retro_lcd.gdshader")

var _retro := true


## The retro LCD filter: the picture pulled toward grey, its blacks lifted, a cool cast and a faint pixel grid, as a
## small LCD of the early 2000s looks.
func set_retro(on: bool) -> void:
	_retro = on
	if _filter != null:
		_filter.visible = on


## Hand the screen its browser and the Hi-Fi it reads the now-playing line from.
func bind(a_browser: RefCounted, a_hifi: Object) -> void:
	browser = a_browser
	_hifi = a_hifi
	browser.changed.connect(refresh)
	if _hifi != null:
		set_retro(bool(_hifi.get("lcd_filter")))
	if _hifi != null and _hifi.has_signal("state_changed"):
		_hifi.connect("state_changed", refresh)
	refresh()


# --- building ------------------------------------------------------------------------------------------

func _style(color: Color, border := Color(0, 0, 0, 0), radius := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	return s


func _btn(text: String, rect: Rect2, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", C_CURSOR_TEXT)
	b.add_theme_color_override("font_disabled_color", C_DIM)
	b.add_theme_stylebox_override("normal", _style(C_ROW))
	b.add_theme_stylebox_override("hover", _style(Color(0.07, 0.20, 0.27), C_DIM))
	b.add_theme_stylebox_override("pressed", _style(C_CURSOR))
	b.add_theme_stylebox_override("disabled", _style(Color(0.02, 0.06, 0.09)))
	add_child(b)
	return b


func _label(rect: Rect2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.size = SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_back = _btn("◀", Rect2(4, 2, 52, HEADER_H - 2), 22)
	_back.pressed.connect(func() -> void: _nav("back"))
	_home = _btn("≡", Rect2(60, 2, 52, HEADER_H - 2), 22)
	_home.pressed.connect(func() -> void: _nav("menu"))
	_title = _label(Rect2(120, 2, 330, HEADER_H - 2), 22, C_TEXT)
	_status = _label(Rect2(450, 2, 186, HEADER_H - 2), 17, C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in Pages.PAGE_ROWS:
		var b := _btn("", Rect2(4, ROWS_TOP + i * ROW_H, SIZE.x - SIDE_W - 12, ROW_H - 3), 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot := i
		b.pressed.connect(func() -> void:
			if browser != null:
				browser.press_slot(slot))
		_rows.append(b)
		var sub := _label(Rect2(b.position.x + b.size.x * 0.52, b.position.y, b.size.x * 0.48 - 8, b.size.y), 15, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		_row_sub.append(sub)
	var sx := SIZE.x - SIDE_W - 4
	_up = _btn("▲", Rect2(sx, ROWS_TOP, SIDE_W, 3 * ROW_H - 3), 22)
	_up.pressed.connect(func() -> void: _page(-1))
	_down = _btn("▼", Rect2(sx, ROWS_TOP + 3 * ROW_H, SIDE_W, 3 * ROW_H - 3), 22)
	_down.pressed.connect(func() -> void: _page(1))
	_hint = _label(Rect2(14, ROWS_TOP + 60, SIZE.x - SIDE_W - 32, 100), 20, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.clip_text = false
	_build_keyboard()
	# The now-playing strip: a button (a tap opens Now playing), its text laid over it.
	_foot = _btn("", Rect2(4, FOOT_TOP, SIZE.x - 8, 54), 18)
	_foot.pressed.connect(func() -> void:
		if browser != null and browser.now_on():
			browser.activate(Pages.row("Now playing", "open", Pages.NOW)))
	_cover = TextureRect.new()
	_cover.position = Vector2(8, FOOT_TOP + 3)
	_cover.size = Vector2(48, 48)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	add_child(_cover)
	_foot_title = _label(Rect2(64, FOOT_TOP + 2, 430, 26), 20, C_TEXT)
	_foot_sub = _label(Rect2(64, FOOT_TOP + 26, 430, 22), 16, C_DIM)
	_foot_time = _label(Rect2(500, FOOT_TOP + 2, 130, 26), 18, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar = ColorRect.new()
	_bar.color = Color(0.09, 0.2, 0.26)
	_bar.position = Vector2(500, FOOT_TOP + 34)
	_bar.size = Vector2(126, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = C_CURSOR_TEXT
	_bar_fill.size = Vector2(0, 6)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_fill)
	_foot_nodes = [_foot, _cover, _foot_title, _foot_sub, _foot_time, _bar]
	_build_now()
	# The retro LCD look goes over everything else, takes no press, and is the TAB menu's to switch.
	_filter = ColorRect.new()
	_filter.size = SIZE
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter.material = ShaderMaterial.new()
	(_filter.material as ShaderMaterial).shader = RETRO_SHADER
	add_child(_filter)
	set_retro(_retro)


## The Now playing page: the cover, what plays, a seekable bar and the transport. Hidden on every other page.
func _build_now() -> void:
	_np_box = Control.new()
	_np_box.visible = false
	_np_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_np_box)
	var frame := ColorRect.new()
	frame.color = C_ROW
	frame.position = Vector2(8, 44)
	frame.size = Vector2(176, 176)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_box.add_child(frame)
	_np_blank = _label(Rect2(8, 44, 176, 176), 64, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_np_blank.text = "♪"
	_np_cover = TextureRect.new()
	_np_cover.position = Vector2(8, 44)
	_np_cover.size = Vector2(176, 176)
	_np_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_np_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_np_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_box.add_child(_np_cover)
	_np_title = _label(Rect2(196, 40, 436, 62), 21, C_TEXT)
	_np_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_np_title.clip_text = false
	_np_title.max_lines_visible = 2
	_np_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_np_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_np_artist = _label(Rect2(196, 104, 436, 24), 19, C_CURSOR_TEXT)
	_np_album = _label(Rect2(196, 127, 436, 20), 16, C_DIM)
	_np_info = _label(Rect2(196, 147, 436, 18), 15, C_DIM)
	_np_next = _label(Rect2(196, 165, 436, 18), 15, C_DIM)
	for l: Label in [_np_title, _np_artist, _np_album, _np_info, _np_next]:
		remove_child(l)
		_np_box.add_child(l)
	remove_child(_np_blank)
	_np_box.add_child(_np_blank)
	# The bar, and a taller invisible button over it to seek by (a laser is not a fingertip).
	_np_bar = ColorRect.new()
	_np_bar.color = Color(0.09, 0.2, 0.26)
	_np_bar.position = Vector2(196, 190)
	_np_bar.size = Vector2(432, 8)
	_np_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_box.add_child(_np_bar)
	_np_fill = ColorRect.new()
	_np_fill.color = C_CURSOR_TEXT
	_np_fill.size = Vector2(0, 8)
	_np_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_bar.add_child(_np_fill)
	var hit := Control.new()
	hit.position = Vector2(196, 180)
	hit.size = Vector2(432, 28)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.gui_input.connect(_on_bar_input.bind(hit))
	_np_box.add_child(hit)
	_np_elapsed = _label(Rect2(196, 206, 120, 18), 15, C_TEXT)
	_np_total = _label(Rect2(508, 206, 120, 18), 15, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	for l: Label in [_np_elapsed, _np_total]:
		remove_child(l)
		_np_box.add_child(l)
	_np_prev = _transport_button(Rect2(196, 226, 54, 32), "prev", func() -> void: _hifi_call("remote_prev"))
	_np_play = _transport_button(Rect2(256, 226, 54, 32), "play", func() -> void: _hifi_call("toggle_pause"))
	_np_stop = _transport_button(Rect2(316, 226, 54, 32), "stop", func() -> void: _hifi_call("remote_stop"))
	_np_nextb = _transport_button(Rect2(376, 226, 54, 32), "next", func() -> void: _hifi_call("remote_next"))
	_np_shuffle = _btn("SHUF", Rect2(446, 226, 84, 32), 15)
	_np_shuffle.pressed.connect(func() -> void:
		if _hifi != null:
			_hifi.call("set_shuffle", not bool(_hifi.get("shuffle"))))
	_np_repeat = _btn("REP", Rect2(536, 226, 92, 32), 15)
	_np_repeat.pressed.connect(func() -> void: _hifi_call("cycle_repeat"))
	for b: Button in [_np_shuffle, _np_repeat]:
		remove_child(b)
		_np_box.add_child(b)
	_np_empty = _label(Rect2(14, 100, 612, 80), 22, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_np_empty.text = "NOTHING IS PLAYING\nPick something from the menu"
	remove_child(_np_empty)
	_np_box.add_child(_np_empty)


func _transport_button(rect: Rect2, glyph: String, cb: Callable) -> Button:
	var b := _btn(TransportGlyphs.glyph(glyph), rect, 20)
	b.add_theme_font_override("font", TransportGlyphs.font())
	b.pressed.connect(cb)
	remove_child(b)
	_np_box.add_child(b)
	return b


func _hifi_call(method: String) -> void:
	if _hifi != null:
		_hifi.call(method)


func _on_bar_input(event: InputEvent, hit: Control) -> void:
	if _hifi == null or str(_now.get("source", "")) != "library":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hifi.call("seek_to", clampf(event.position.x / hit.size.x, 0.0, 1.0))


func _build_keyboard() -> void:
	_kb_box = Control.new()
	_kb_box.visible = false
	_kb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kb_box)
	_kb_text = _label(Rect2(8, ROWS_TOP, SIZE.x - 16, 34), 24, C_CURSOR_TEXT)
	remove_child(_kb_text)
	_kb_box.add_child(_kb_text)
	var y := ROWS_TOP + 38.0
	var kh := 33.0
	for r in Pages.KEY_ROWS.size():
		var keys: Array = Pages.KEY_ROWS[r]
		var wide := keys.size() < 6
		var kw := (SIZE.x - 16.0 - 4.0 * (keys.size() - 1)) / keys.size()
		for c in keys.size():
			var key: String = keys[c]
			var b := _btn(key, Rect2(8 + c * (kw + 4.0), y, kw, kh - 3.0), 19 if not wide else 20)
			remove_child(b)
			_kb_box.add_child(b)
			b.pressed.connect(func() -> void:
				if browser != null:
					browser.press_key(key))
			_kb_keys.append({"btn": b, "row": r, "col": c})
		y += kh


# --- presses -------------------------------------------------------------------------------------------

func _nav(cmd: String) -> void:
	if browser != null:
		browser.nav(cmd)


func _page(dir: int) -> void:
	if browser != null:
		browser.page_move(dir)


# --- drawing -------------------------------------------------------------------------------------------

## Redraw from the browser. Cheap and idempotent; called on every change and once a second for the clock.
func refresh() -> void:
	if browser == null or _rows.is_empty():
		return
	var p: Dictionary = browser.page()
	_title.text = str(p["title"])
	_back.disabled = browser.pages.depth() <= 1
	var kind: String = p["kind"]
	var keyboard := kind == Pages.SEARCH
	var now_page := kind == Pages.NOW
	_kb_box.visible = keyboard
	_np_box.visible = now_page
	for n in _foot_nodes:
		n.visible = not now_page
	for i in _rows.size():
		_rows[i].visible = not keyboard and not now_page
		_row_sub[i].visible = not keyboard and not now_page
	_up.visible = not keyboard and not now_page
	_down.visible = not keyboard and not now_page
	_now = _hifi.call("now_playing") if _hifi != null else {}
	if keyboard:
		_draw_keyboard(p)
	elif now_page:
		_hint.visible = false
		_draw_now()
	else:
		_draw_rows(p)
	_draw_status()
	if not now_page:
		_draw_foot()


func _draw_now() -> void:
	var on := not _now.is_empty()
	_np_empty.visible = not on
	for n: Control in [_np_cover, _np_blank, _np_title, _np_artist, _np_album, _np_info, _np_next, _np_bar,
			_np_elapsed, _np_total, _np_prev, _np_play, _np_stop, _np_nextb, _np_shuffle, _np_repeat]:
		n.visible = on
	if not on:
		return
	var radio := str(_now.get("source", "")) == "radio"
	var title := str(_now.get("title", ""))
	_np_title.text = title if title != "" else str(_now.get("station", ""))
	_np_artist.text = str(_now.get("artist", ""))
	_np_album.text = ("RADIO · %s" % str(_now.get("station", ""))) if radio else str(_now.get("album", ""))
	var info := ""
	if not radio:
		info = "track %d of %d" % [int(_now.get("index", 0)) + 1, int(_now.get("count", 1))]
		if str(_now.get("format", "")) != "":
			info += "  ·  " + str(_now["format"])
	_np_info.text = info
	_np_next.text = ("next: " + str(_now["next"])) if str(_now.get("next", "")) != "" else ""
	var tex: Variant = _hifi.get("cover") if _hifi != null else null
	_np_cover.texture = tex as Texture2D
	_np_cover.visible = tex != null
	_np_blank.visible = tex == null
	var length := float(_now.get("length", 0))
	var pos := float(_now.get("position", 0))
	if radio and length <= 0.0:
		_np_elapsed.text = "LIVE"
		_np_total.text = ""
		_np_fill.size.x = 0
	else:
		_np_elapsed.text = Api.format_time(int(pos))
		_np_total.text = Api.format_time(int(length))
		_np_fill.size.x = _np_bar.size.x * clampf(pos / length if length > 0.0 else 0.0, 0.0, 1.0)
	var paused := bool(_now.get("paused", false))
	_np_play.text = TransportGlyphs.glyph("play" if paused else "pause")
	_np_prev.disabled = radio
	_np_nextb.disabled = radio
	_np_shuffle.disabled = radio
	_np_repeat.disabled = radio
	var shuf := bool(_now.get("shuffle", false))
	_np_shuffle.text = "SHUF ON" if shuf else "SHUF"
	_np_shuffle.add_theme_color_override("font_color", C_CURSOR_TEXT if shuf else C_TEXT)
	var rep := int(_now.get("repeat", 0))
	_np_repeat.text = ["REPEAT", "REP ALL", "REP ONE"][rep]
	_np_repeat.add_theme_color_override("font_color", C_CURSOR_TEXT if rep > 0 else C_TEXT)


func _draw_rows(p: Dictionary) -> void:
	var shown: Array = browser.pages.visible(p)
	var cursor := int(p["cursor"])
	for i in Pages.PAGE_ROWS:
		var b := _rows[i]
		var sub := _row_sub[i]
		if i < shown.size():
			var row: Dictionary = shown[i]["row"]
			b.visible = true
			b.text = " " + str(row["text"])
			sub.text = str(row["sub"])
			var on_cursor: bool = int(shown[i]["index"]) == cursor
			b.add_theme_stylebox_override("normal", _style(C_CURSOR if on_cursor else C_ROW))
			b.add_theme_color_override("font_color", C_CURSOR_TEXT if on_cursor else C_TEXT)
			b.disabled = str(row["act"]) == "none"
			sub.visible = true
		else:
			b.visible = false
			sub.visible = false
	var more_up: bool = int(p["first"]) > 0
	var more_down: bool = int(p["first"]) + Pages.PAGE_ROWS < (p["rows"] as Array).size()
	_up.disabled = not more_up
	_down.disabled = not more_down
	_up.text = "▲"
	_down.text = "▼\n%d/%d" % [browser.pages.page_number(p), browser.pages.page_count(p)] if (p["rows"] as Array).size() > Pages.PAGE_ROWS else "▼"
	var note := ""
	if bool(p["loading"]):
		note = "LOADING…"
	elif str(p["error"]) != "":
		note = str(p["error"])
	elif (p["rows"] as Array).is_empty() and str(p["kind"]) != Pages.NOW:
		note = "NOTHING HERE"
	_hint.text = note
	_hint.visible = note != ""
	_hint.add_theme_color_override("font_color", C_WARN if str(p["error"]) != "" else C_DIM)


func _now_text() -> String:
	if _now.is_empty():
		return "NOTHING IS PLAYING"
	var t := "%s\n%s" % [str(_now.get("title", "")), str(_now.get("artist", ""))]
	if str(_now.get("source", "")) == "radio":
		t = "%s\n%s\n%s" % [str(_now.get("station", "")), str(_now.get("title", "")), str(_now.get("artist", ""))]
	return t + "\n\nOK pauses / plays"


func _draw_keyboard(p: Dictionary) -> void:
	_kb_text.text = (str(p["text"]) if str(p["text"]) != "" else "type to search") + "▏"
	_kb_text.add_theme_color_override("font_color", C_CURSOR_TEXT if str(p["text"]) != "" else C_DIM)
	var kb: Array = p.get("kb", [-1, -1])
	for k: Dictionary in _kb_keys:
		var on: bool = k["row"] == kb[0] and k["col"] == kb[1]
		(k["btn"] as Button).add_theme_stylebox_override("normal", _style(C_CURSOR if on else C_ROW))
		(k["btn"] as Button).add_theme_color_override("font_color", C_CURSOR_TEXT if on else C_TEXT)
	_hint.visible = false


func _draw_status() -> void:
	var s := ""
	if _hifi != null:
		s = str(_hifi.call("mode_name"))
		var st := str(_hifi.get("status"))
		if st != "":
			s += " · " + st
		var osd := str(_hifi.get("osd"))
		if osd != "":
			s = osd
	_status.text = s


func _draw_foot() -> void:
	if _now.is_empty():
		_foot_title.text = "—"
		_foot_sub.text = "stopped"
		_foot_time.text = ""
		_bar_fill.size.x = 0
		_cover.visible = false
		return
	var radio := str(_now.get("source", "")) == "radio"
	_foot_title.text = str(_now.get("title", "")) if str(_now.get("title", "")) != "" else str(_now.get("station", ""))
	_foot_sub.text = ("RADIO · %s · %s" % [str(_now.get("station", "")), str(_now.get("artist", ""))]) if radio else "%s · %s" % [str(_now.get("artist", "")), str(_now.get("album", ""))]
	var length := float(_now.get("length", 0))
	var pos := float(_now.get("position", 0))
	if radio:
		_foot_time.text = "LIVE"
		_bar_fill.size.x = 0
	else:
		_foot_time.text = "%s / %s" % [Api.format_time(int(pos)), Api.format_time(int(length))]
		_bar_fill.size.x = _bar.size.x * clampf(pos / length if length > 0.0 else 0.0, 0.0, 1.0)
	var tex: Variant = _hifi.get("cover") if _hifi != null else null
	_cover.texture = tex as Texture2D
	_cover.visible = tex != null
