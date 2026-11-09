## HifiOptions2D -- the Hi-Fi's TAB menu page: the server and who is signed in, the radio stations, the cache.
## Loaded into HifiOptionsPanel's SubViewport via XRToolsViewport2DIn3D. Built in code, in the game's MenuStyle.
##
## Emits (the panel turns them into calls on the Hi-Fi):
##   server_submitted(text)        the address was committed (Enter, the button, or focus left it)
##   sign_in_pressed(user, pass)   the password is read from its field, then the field is CLEARED
##   sign_out_pressed
##   station_added(name, url) / station_removed(url) / station_played(url)
##   cache_size_changed(mb) / cache_clear_pressed / quality_changed(kbps)  (0 = the file as it is)
##   ignore_gravity_toggled(on)    float in place
##   close_requested
##
## The PASSWORD is a LineEdit with `secret = true`; it is never stored anywhere.
extends Control

const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")

signal close_requested
signal server_submitted(text: String)
signal sign_in_pressed(user: String, password: String)
signal sign_out_pressed
signal station_added(name: String, url: String)
signal station_removed(url: String)
signal station_played(url: String)
signal cache_size_changed(mb: int)
signal cache_clear_pressed
signal quality_changed(kbps: int)
signal ignore_gravity_toggled(enabled: bool)

const COLOR_BG := Color(0.06, 0.08, 0.14, 0.96)
const COLOR_ROW := Color(0.65, 0.70, 0.85)
const COLOR_OK := Color(0.45, 1.0, 0.65)
const COLOR_WARN := Color(1.0, 0.80, 0.35)
const COLOR_DIM := Color(0.55, 0.58, 0.70)
## Choices of the quality row: label, kbps (0 = original file).
const QUALITIES := [["Original file", 0], ["MP3 320 kbps", 320], ["MP3 192 kbps", 192], ["MP3 128 kbps", 128], ["MP3 64 kbps", 64]]

var _tabs: TabContainer = null
var _status: Label = null
var _server_edit: LineEdit = null
var _user_edit: LineEdit = null
var _pass_edit: LineEdit = null
var _sign_in_btn: Button = null
var _sign_out_btn: Button = null
var _signed_label: Label = null
var _stations_box: VBoxContainer = null
var _st_name: LineEdit = null
var _st_url: LineEdit = null
var _st_note: Label = null
var _cache_label: Label = null
var _cache_size_label: Label = null
var _cache_minus: Button = null
var _cache_plus: Button = null
var _quality: OptionButton = null
var _float_check: VRToggle = null
var _suppress := false
var _cache_mb := Config.CACHE_MB_DEFAULT
var _stations_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	MenuStyle.close_button(MenuStyle.title_row(outer, "Subsonic Hi-Fi NAVI-AZ95"), func() -> void: close_requested.emit())
	outer.add_child(HSeparator.new())
	_status = Label.new()
	_status.text = "Not signed in"
	_status.add_theme_font_size_override("font_size", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	outer.add_child(_tabs)
	_build_server_tab(_tab("Server"))
	_build_radio_tab(_tab("Radio"))
	_build_cache_tab(_tab("Cache"))
	var more := _tab("Unit")
	_float_check = MenuStyle.float_toggle(more)
	_float_check.toggled.connect(func(on: bool) -> void:
		if not _suppress:
			ignore_gravity_toggled.emit(on))


func _tab(title: String) -> VBoxContainer:
	var scroll := MenuStyle.vscroll()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func scroll_active(pixels: float) -> void:
	var cur := _tabs.get_current_tab_control() as ScrollContainer if _tabs != null else null
	if cur != null:
		cur.scroll_vertical += int(pixels)


func _note(parent: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", COLOR_DIM)
	parent.add_child(l)
	return l


func _field_row(parent: Container, caption: String, placeholder: String, secret := false) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_font_size_override("font_size", 18)
	row.add_child(edit)
	return edit


func _button(parent: Container, text: String, cb: Callable, height := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# --- Server ---------------------------------------------------------------------------------------------

func _build_server_tab(root: VBoxContainer) -> void:
	_note(root, "Any server that speaks the Subsonic API: Navidrome, Airsonic, Gonic ... The password is used once to sign in and is never saved; only a key the server gives back is.")
	_server_edit = _field_row(root, "Server", "audio.example.org")
	_server_edit.text_submitted.connect(func(t: String) -> void: server_submitted.emit(t))
	_server_edit.focus_exited.connect(func() -> void: server_submitted.emit(_server_edit.text))
	_user_edit = _field_row(root, "User", "name")
	_pass_edit = _field_row(root, "Password", "password", true)
	_sign_in_btn = _button(root, "Sign in", func() -> void:
		sign_in_pressed.emit(_user_edit.text.strip_edges(), _pass_edit.text)
		_pass_edit.text = "")
	_signed_label = Label.new()
	_signed_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_signed_label)
	_sign_out_btn = _button(root, "Sign out", func() -> void: sign_out_pressed.emit())


# --- Radio ----------------------------------------------------------------------------------------------

func _build_radio_tab(root: VBoxContainer) -> void:
	_note(root, "Internet radio: an Icecast/Shoutcast stream, a .pls/.m3u playlist, or an AzuraCast public player page (https://host/public/station).")
	_stations_box = VBoxContainer.new()
	_stations_box.add_theme_constant_override("separation", 4)
	root.add_child(_stations_box)
	root.add_child(HSeparator.new())
	_st_name = _field_row(root, "Name", "My station")
	_st_url = _field_row(root, "Address", "https://...")
	_button(root, "Add station", func() -> void:
		var url := _st_url.text.strip_edges()
		if not (url.begins_with("http://") or url.begins_with("https://")):
			_st_note.text = "The address must start with http:// or https://"
			_st_note.add_theme_color_override("font_color", COLOR_WARN)
			return
		station_added.emit(_st_name.text.strip_edges(), url)
		_st_name.text = ""
		_st_url.text = ""
		_st_note.text = "Added."
		_st_note.add_theme_color_override("font_color", COLOR_OK))
	_st_note = _note(root, "")


func _set_stations(list: Array) -> void:
	var key := JSON.stringify(list)
	if key == _stations_key:
		return
	_stations_key = key
	for c in _stations_box.get_children():
		c.queue_free()
	if list.is_empty():
		_note(_stations_box, "No stations yet. Add one below.")
		return
	for st: Dictionary in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_stations_box.add_child(row)
		var play := Button.new()
		play.text = "▶ " + str(st["name"])
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play.clip_text = true
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.custom_minimum_size = Vector2(0, 40)
		play.add_theme_font_size_override("font_size", 18)
		var url: String = st["url"]
		play.pressed.connect(func() -> void: station_played.emit(url))
		row.add_child(play)
		var del := Button.new()
		del.text = "×"
		del.custom_minimum_size = Vector2(48, 40)
		del.pressed.connect(func() -> void: station_removed.emit(url))
		row.add_child(del)


# --- Cache ----------------------------------------------------------------------------------------------

func _build_cache_tab(root: VBoxContainer) -> void:
	_note(root, "Tracks you play are kept here so they start at once and play without the network. The oldest are removed when the cache is full.")
	_cache_label = Label.new()
	_cache_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_cache_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var cap := Label.new()
	cap.text = "Size limit"
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", COLOR_ROW)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	_cache_minus = Button.new()
	_cache_minus.text = "−"
	_cache_minus.custom_minimum_size = Vector2(56, 44)
	_cache_minus.pressed.connect(func() -> void: cache_size_changed.emit(Config.step_cache_mb(_cache_mb, -1)))
	row.add_child(_cache_minus)
	_cache_size_label = Label.new()
	_cache_size_label.custom_minimum_size = Vector2(110, 0)
	_cache_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cache_size_label.add_theme_font_size_override("font_size", 20)
	row.add_child(_cache_size_label)
	_cache_plus = Button.new()
	_cache_plus.text = "+"
	_cache_plus.custom_minimum_size = Vector2(56, 44)
	_cache_plus.pressed.connect(func() -> void: cache_size_changed.emit(Config.step_cache_mb(_cache_mb, 1)))
	row.add_child(_cache_plus)
	_button(root, "Clear cache", func() -> void: cache_clear_pressed.emit())
	root.add_child(HSeparator.new())
	var qrow := HBoxContainer.new()
	root.add_child(qrow)
	var ql := Label.new()
	ql.text = "Quality"
	ql.add_theme_font_size_override("font_size", 18)
	ql.add_theme_color_override("font_color", COLOR_ROW)
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(ql)
	_quality = OptionButton.new()
	_quality.add_theme_font_size_override("font_size", 18)
	for q: Array in QUALITIES:
		_quality.add_item(str(q[0]))
	_quality.item_selected.connect(func(i: int) -> void:
		if not _suppress:
			quality_changed.emit(int(QUALITIES[i][1])))
	qrow.add_child(_quality)
	_note(root, "A lower quality asks the server to transcode: smaller downloads, more tracks in the cache. It applies from the next queue.")


# --- from the Hi-Fi -------------------------------------------------------------------------------------

## Fill the page from the Hi-Fi's state: {status, ok, server, user, signed_in, stations, cache_mb, cache_used,
## quality, ignore_gravity}. Safe to call as often as it likes: a field being typed in is left alone.
func populate(s: Dictionary) -> void:
	if _status == null:
		return
	_suppress = true
	_status.text = str(s["status"])
	_status.add_theme_color_override("font_color", COLOR_OK if bool(s["ok"]) else COLOR_WARN)
	if not _server_edit.has_focus():
		_server_edit.text = str(s["server"])
	if not _user_edit.has_focus() and _user_edit.text.is_empty():
		_user_edit.text = str(s["user"])
	var signed := bool(s["signed_in"])
	_sign_in_btn.visible = not signed
	_pass_edit.get_parent().visible = not signed
	_user_edit.get_parent().visible = not signed
	_sign_out_btn.visible = signed
	_signed_label.visible = signed
	_signed_label.text = "Signed in as %s" % str(s["user"])
	_set_stations(s["stations"])
	_cache_mb = int(s["cache_mb"])
	_cache_size_label.text = "%d MB" % _cache_mb if _cache_mb < 1000 else "%.1f GB" % (_cache_mb / 1000.0)
	_cache_label.text = "In the cache: %s of %s" % [_mb(int(s["cache_used"])), _cache_size_label.text]
	_cache_minus.disabled = _cache_mb <= Config.CACHE_MB_MIN
	_cache_plus.disabled = _cache_mb >= Config.CACHE_MB_MAX
	var kbps := int(s["quality"])
	for i in QUALITIES.size():
		if int(QUALITIES[i][1]) == kbps:
			_quality.select(i)
	_float_check.button_pressed = bool(s["ignore_gravity"])
	_suppress = false


static func _mb(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)
