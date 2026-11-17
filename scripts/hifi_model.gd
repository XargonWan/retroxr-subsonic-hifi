## The Hi-Fi's body, built in code from primitives (a few hundred triangles; the room also holds cabinets): a graphite
## chassis with a brushed-silver fascia in three zones, top to bottom:
##   - the LCD at the left and the CASSETTE bay at the right,
##   - a band under them: the two key rows (menu / navigation, transport) at the left, MODE with its three LEDs, then
##     VOLUME and PHONES at the right,
##   - the CD bay across the foot of the fascia.
## Original geometry; the supplied NAVI reference model is not used (it carries no licence).
##
## The unit's frame is the base CD player's: origin at the middle of the body, +Z out of the front, +Y up. The jacks the
## shared deck code looks up by name (AudioLOut / AudioROut on the back, PhonesOut and LevelKnob on the front) are
## SEATED here, and the keys are the base scene's own VRButtons (so the deck code that connects PLAY / PAUSE / STOP /
## PREV / NEXT / REW / FF finds them) dressed with caps and glyphs, plus the ones this unit adds.
##
## A key follows the game's VRButton convention: the node is turned a quarter about X so its +Y is the unit's +Z (its
## face), it presses along -Y, and the cap and its box are laid out in that turned frame.
extends RefCounted

const W := 0.43
const H := 0.24
const D := 0.30
## The two small speakers built into the sides of the unit: each this wide, as high and as deep as the unit. The unit
## is FULL_W across with them; W is the fascia, which the keys, the LCD and the bays are laid out on.
const SPK_W := 0.055
const FULL_W := W + 2.0 * SPK_W
const FRONT := D / 2.0
const BACK := -D / 2.0

## The layout is the player's mockup, measured in its pixels (709 x 391 over the 0.43 m fascia, 0.606 mm a pixel).
## The LCD's glass and the centre of its window (top left).
const SCREEN := Vector2(0.200, 0.100)
const SCREEN_AT := Vector2(-0.0945, 0.0457)

## The cassette bay (top right): the opening's centre and size (a cassette is 100.4 x 63.8 mm) and its EJECT key.
const TAPE_AT := Vector2(0.1207, 0.0479)
const TAPE_OPENING := Vector2(0.120, 0.080)
const TAPE_EJECT_AT := Vector2(0.200, 0.0167)
## The CD bay (across the foot): the plate, the slot in it (a disc is 120 mm) and its EJECT key.
const CD_PLATE_AT := Vector2(-0.043, -0.0857)
const CD_PLATE := Vector2(0.317, 0.0364)
const CD_AT := Vector2(-0.0634, -0.0848)
const CD_SLOT := Vector2(0.148, 0.009)
const CD_EJECT_AT := Vector2(0.144, -0.0857)

## A key's cap (w x h x depth) and how far it stands out of the fascia at rest.
const CAP := Vector3(0.0215, 0.0150, 0.0060)
const PROUD := 0.0030
const TRAVEL := 0.0015
## The transport row under the screen: the first column's centre, the pitch and the row's height.
const KEY_X0 := -0.1747
const KEY_PITCH := 0.0262
const ROW_TRANSPORT_Y := -0.0245
## The navigation keys, a column at the right of the screen: x, and the first key's y and the pitch down.
const NAV_X := 0.0264
const NAV_Y0 := 0.0942
const NAV_PITCH := 0.0188

## MODE: its key and, above it, three LEDs with their names.
const MODE_AT := Vector2(0.0524, -0.044)
const MODE_CAP := Vector3(0.034, 0.016, 0.006)
const LED_Y := -0.0252
const LED_XS := [0.0314, 0.0454, 0.0594, 0.0734]
const LED_NAMES := ["CD", "TAPE", "NET", "FM"]

## PHONES at the left of the pair, the big VOLUME knob at the right (it has the room there).
const PHONES_AT := Vector2(0.0975, -0.041)
const KNOB_AT := Vector2(0.1645, -0.0416)
const KNOB_RADIUS := 0.0195
const KNOB_HEIGHT := 0.016

## The navigation keys, top to bottom: node name, glyph, and a word where the cap prints one instead of a glyph. (There
## is no OK: PLAY opens the row the cursor was moved to. NOW opens, and closes again, the Now playing page.)
const NAV_COLUMN := [["MenuButton", "menu"], ["BackButton", "left"], ["UpButton", "up"], ["DownButton", "down"],
	["NowButton", "", "NOW"]]
## The transport keys: the base scene's own (REW and FF are kept: a tape and a disc scan), in order along the row.
const TRANSPORT_ROW := [["RewindButton", "rew"], ["PrevButton", "prev"], ["PlayButton", "play"], ["PauseButton", "pause"],
	["StopButton", "stop"], ["NextButton", "next"], ["FastForwardButton", "ff"]]

const GRAPHITE := Color(0.15, 0.155, 0.17)
const SILVER := Color(0.80, 0.82, 0.85)
const KEY_PLASTIC := Color(0.58, 0.60, 0.64)
const GLYPH := Color(0.06, 0.07, 0.09)
const PRINT := Color(0.16, 0.17, 0.20)
## The mode LEDs when lit (CD, TAPE, NET) and when dark.
const LED_ON := [Color(0.35, 0.75, 1.0), Color(1.0, 0.62, 0.15), Color(0.35, 1.0, 0.45), Color(1.0, 0.35, 0.35)]
const LED_OFF := Color(0.07, 0.075, 0.08)

static var _mats := {}


static func _mat(key: String, color: Color, metallic := 0.0, rough := 0.5) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	_mats[key] = m
	return m


static func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## A LED's material at a given state: unshaded and emissive when lit, a dark lens when not.
static func led_material(index: int, lit: bool) -> StandardMaterial3D:
	var key := "led%d%s" % [index, "on" if lit else "off"]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = (LED_ON[index] if lit else LED_OFF)
	if lit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = LED_ON[index]
		m.emission_energy_multiplier = 2.0
	else:
		m.roughness = 0.3
	_mats[key] = m
	return m


## Build the body under `model` (a Node3D named Model on the unit) and dress the unit's scene nodes. Returns the
## number of triangles drawn, for the test that holds it to its budget.
static func build(host: Node3D, model: Node3D) -> int:
	var graphite := _mat("graphite", GRAPHITE, 0.2, 0.5)
	var silver := _mat("silver", SILVER, 0.3, 0.4)
	var black := _mat("black", Color(0.012, 0.014, 0.018), 0.0, 0.25)
	_box(model, "Chassis", Vector3(W - 0.004, H - 0.006, D - 0.012), Vector3(0.0, 0.0, -0.006), graphite)
	_box(model, "Fascia", Vector3(W, H, 0.012), Vector3(0.0, 0.0, FRONT - 0.006), silver)
	_box(model, "TopPlate", Vector3(W - 0.012, 0.004, D - 0.02), Vector3(0.0, H / 2.0 - 0.001, -0.012), graphite)
	# The LCD: a black bezel box standing 1.5 mm out of the fascia, the glass set into it.
	_box(model, "Bezel", Vector3(SCREEN.x + 0.016, SCREEN.y + 0.016, 0.0030), Vector3(SCREEN_AT.x, SCREEN_AT.y, FRONT + 0.0015), black)
	# The cassette bay: a dark pocket the cassette goes into, in a thin frame.
	_box(model, "TapeFrame", Vector3(TAPE_OPENING.x + 0.008, TAPE_OPENING.y + 0.008, 0.0016), Vector3(TAPE_AT.x, TAPE_AT.y, FRONT + 0.0008), _mat("frame", Color(0.30, 0.31, 0.34), 0.3, 0.4))
	_box(model, "TapePocket", Vector3(TAPE_OPENING.x, TAPE_OPENING.y, 0.0022), Vector3(TAPE_AT.x, TAPE_AT.y, FRONT + 0.0011), black)
	# The CD bay: a plate across the foot with the slot in it.
	_box(model, "CdPlate", Vector3(CD_PLATE.x, CD_PLATE.y, 0.0016), Vector3(CD_PLATE_AT.x, CD_PLATE_AT.y, FRONT + 0.0008), _mat("frame", Color(0.30, 0.31, 0.34), 0.3, 0.4))
	_box(model, "CdSlot", CD_SLOT_BOX, Vector3(CD_AT.x, CD_AT.y, FRONT + 0.0014), black)
	for fx in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			var foot := MeshInstance3D.new()
			foot.name = "Foot"
			var cm := CylinderMesh.new()
			cm.top_radius = 0.016
			cm.bottom_radius = 0.018
			cm.height = 0.008
			cm.radial_segments = 10
			cm.rings = 1
			foot.mesh = cm
			foot.material_override = black
			foot.position = Vector3(fx * (FULL_W / 2.0 - 0.035), -H / 2.0 - 0.004, fz * (D / 2.0 - 0.04))
			model.add_child(foot)
	# PHONES is a hole: black inside, a disc just clear of the fascia under the socket's own collar.
	var hole := MeshInstance3D.new()
	hole.name = "PhonesHole"
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0034
	hm.bottom_radius = 0.0034
	hm.height = 0.0004
	hm.radial_segments = 14
	hm.rings = 1
	hole.mesh = hm
	hole.material_override = black
	hole.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(PHONES_AT.x, PHONES_AT.y, FRONT + 0.0006))
	model.add_child(hole)
	_leds(model)
	_silkscreen(model)
	var tris := _dress_keys(host)
	_seat_jacks(host)
	_fit_shapes(host)
	var cord := Node3D.new()
	cord.name = "PowerCordExit"
	cord.position = Vector3(-0.15, -0.08, BACK)
	model.add_child(cord)
	return tris + _triangles(model)


## The unit's own speakers: a cabinet each side of the fascia with a cloth grille over a woofer and a tweeter. The sound
## comes from here while nothing is cabled to the unit's outputs (subsonic_hifi.gd, _apply_channel_gains).
static func _speakers(model: Node3D, cabinet: Material) -> void:
	var grille := _mat("grille", Color(0.62, 0.64, 0.68), 0.0, 0.9)
	var cone := _mat("cone", Color(0.10, 0.105, 0.115), 0.0, 0.8)
	for side in [-1.0, 1.0]:
		var x: float = side * (W / 2.0 + SPK_W / 2.0)
		var tag := "L" if side < 0.0 else "R"
		_box(model, "Speaker_%s" % tag, Vector3(SPK_W, H, D), Vector3(x, 0.0, 0.0), cabinet)
		_box(model, "Grille_%s" % tag, Vector3(SPK_W - 0.012, H - 0.024, 0.0025), Vector3(x, 0.0, FRONT + 0.00125), grille)
		for ring: Array in [["Woofer", 0.017, -0.026], ["Tweeter", 0.0075, 0.068]]:
			var cyl := MeshInstance3D.new()
			cyl.name = "%s_%s" % [ring[0], tag]
			var cm := CylinderMesh.new()
			cm.top_radius = float(ring[1])
			cm.bottom_radius = float(ring[1])
			cm.height = 0.0008
			cm.radial_segments = 18
			cm.rings = 1
			cyl.mesh = cm
			cyl.material_override = cone
			cyl.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(x, float(ring[2]), FRONT + 0.0029))
			model.add_child(cyl)


## The base game's cassette deck model, as its three levels of detail; empty when this game does not have it.
static func tape_door_scenes() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for f: String in TAPE_DECK_LEVELS:
		var scene := load(TAPE_DECK_DIR + f) as PackedScene if ResourceLoader.exists(TAPE_DECK_DIR + f) else null
		if scene == null:
			return [] as Array[PackedScene]
		out.append(scene)
	return out


## A slab `z0..z1` deep, `size` across, with a rectangular opening through it: four boxes round the hole.
static func _frame(parent: Node3D, node_name: String, size: Vector2, hole: Rect2, z0: float, z1: float, mat: Material) -> void:
	var depth := z1 - z0
	var zc := (z0 + z1) / 2.0
	var l := -size.x / 2.0
	var r := size.x / 2.0
	var b := -size.y / 2.0
	var t := size.y / 2.0
	var hx0 := hole.position.x
	var hx1 := hole.end.x
	var hy0 := hole.position.y
	var hy1 := hole.end.y
	_box(parent, node_name + "_L", Vector3(hx0 - l, size.y, depth), Vector3((l + hx0) / 2.0, 0.0, zc), mat)
	_box(parent, node_name + "_R", Vector3(r - hx1, size.y, depth), Vector3((hx1 + r) / 2.0, 0.0, zc), mat)
	_box(parent, node_name + "_T", Vector3(hx1 - hx0, t - hy1, depth), Vector3((hx0 + hx1) / 2.0, (hy1 + t) / 2.0, zc), mat)
	_box(parent, node_name + "_B", Vector3(hx1 - hx0, hy0 - b, depth), Vector3((hx0 + hx1) / 2.0, (b + hy0) / 2.0, zc), mat)


## Stand the cassette deck model's door in the opening (its centre on TAPE_AT; both models have their front at the
## same depth), and hide the rest of that deck.
static func _tape_door(host: Node3D, scenes: Array[PackedScene]) -> void:
	var tm := ApplianceModel.new()
	tm.name = "TapeModel"
	tm.level_scenes = scenes
	tm.position = Vector3(TAPE_AT.x - TAPE_DOOR_CENTRE.x, TAPE_AT.y - TAPE_DOOR_CENTRE.y, 0.0)
	host.add_child(tm)
	for part_name: String in TAPE_DECK_PARTS_HIDDEN:
		tm.hide_part(part_name)


const CD_SLOT_BOX := Vector3(CD_SLOT.x, CD_SLOT.y, 0.0022)


## The three mode LEDs (small boxes on the fascia, named Led_CD / Led_TAPE / Led_NET), all dark; the unit lights one.
static func _leds(model: Node3D) -> void:
	for i in LED_NAMES.size():
		var led := _box(model, "Led_%s" % LED_NAMES[i], Vector3(0.0055, 0.0035, 0.0016), Vector3(LED_XS[i], LED_Y, FRONT + 0.0008), led_material(i, false))
		led.set_meta(&"led_index", i)


static func _silkscreen(model: Node3D) -> void:
	var top := FRONT + 0.0004
	var left := _label("SUBSONIC  Hi-Fi", 44, PRINT)
	left.position = Vector3(-0.148, 0.110, top)
	model.add_child(left)
	var right := _label("NAVI-AZ95", 44, PRINT)
	right.position = Vector3(0.1476, 0.110, top)
	model.add_child(right)
	var tape := _label("CASSETTE", 30, Color(0.34, 0.35, 0.40))
	tape.position = Vector3(TAPE_AT.x, TAPE_AT.y - TAPE_OPENING.y / 2.0 - 0.0076, top)
	model.add_child(tape)
	var eject_t := _label("EJECT", 26, PRINT)
	eject_t.position = Vector3(TAPE_EJECT_AT.x, TAPE_EJECT_AT.y - 0.0139, top)
	model.add_child(eject_t)
	var cd := _label("COMPACT  DISC", 30, Color(0.34, 0.35, 0.40))
	cd.position = Vector3(-0.0937, -0.059, top)
	model.add_child(cd)
	var eject_c := _label("EJECT", 26, PRINT)
	eject_c.position = Vector3(CD_EJECT_AT.x, CD_EJECT_AT.y - 0.0128, top)
	model.add_child(eject_c)
	for i in LED_NAMES.size():
		var t := _label(LED_NAMES[i], 22, PRINT)
		t.position = Vector3(LED_XS[i], LED_Y + 0.0072, top)
		model.add_child(t)
	var phones := _label("PHONES", 28, PRINT)
	phones.position = Vector3(PHONES_AT.x - 0.001, -0.0215, top)
	model.add_child(phones)
	var level := _label("VOLUME", 28, PRINT)
	level.position = Vector3(KNOB_AT.x, KNOB_AT.y + KNOB_RADIUS + 0.0055, top)
	model.add_child(level)
	# The scale: the knob sweeps 270 degrees from 0 (marker at the lower left) to 100 (lower right), 50 straight up, so the
	# percentage on the screen is where the marker stands. Printed at both ends and at the top, in the dead angle's corners.
	for spec: Array in [["0", 135.0], ["100", -135.0]]:
		var a := deg_to_rad(float(spec[1]))
		var tick := _label(str(spec[0]), 22, PRINT)
		tick.position = Vector3(KNOB_AT.x - sin(a) * (KNOB_RADIUS + 0.0075), KNOB_AT.y + cos(a) * (KNOB_RADIUS + 0.0075), top)
		model.add_child(tick)


static func _label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00018
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.outline_size = 0
	return l


# --- keys ----------------------------------------------------------------------------------------------

## Where a key of the transport row stands: column `i` at height `y`, in the unit's frame, on the fascia.
static func key_at(i: int, y: float) -> Vector3:
	return Vector3(KEY_X0 + i * KEY_PITCH, y, FRONT)


## Dress the base scene's transport keys and add the navigation row, MODE and the two EJECT keys. Returns the triangles
## of the caps.
static func _dress_keys(host: Node3D) -> int:
	var template := host.get_node("PlayButton") as VRButton
	var tris := 0
	for i in TRANSPORT_ROW.size():
		var spec: Array = TRANSPORT_ROW[i]
		var b := host.get_node(str(spec[0])) as VRButton
		tris += _cap(b, key_at(i, ROW_TRANSPORT_Y), str(spec[1]))
	for i in NAV_COLUMN.size():
		var spec: Array = NAV_COLUMN[i]
		var b := template.duplicate() as VRButton
		b.name = str(spec[0])
		host.add_child(b)
		tris += _cap(b, Vector3(NAV_X, NAV_Y0 - i * NAV_PITCH, FRONT), str(spec[1]), str(spec[2]) if spec.size() > 2 else "")
	var mode := template.duplicate() as VRButton
	mode.name = "ModeButton"
	host.add_child(mode)
	tris += _cap(mode, Vector3(MODE_AT.x, MODE_AT.y, FRONT), "", "MODE", MODE_CAP)
	for spec: Array in [["TapeEjectButton", TAPE_EJECT_AT], ["CdEjectButton", CD_EJECT_AT]]:
		var e := template.duplicate() as VRButton
		e.name = str(spec[0])
		host.add_child(e)
		tris += _cap(e, Vector3(spec[1].x, spec[1].y, FRONT), "eject")
	return tris


## Put `b` at `at` (its origin on the fascia, its face turned to +Z), give it a cap, a box, a glyph (or a word) and a press.
static func _cap(b: VRButton, at: Vector3, glyph: String, word := "", cap_size := CAP) -> int:
	var turn := Basis(Vector3.RIGHT, PI / 2.0)
	b.transform = Transform3D(turn, at)
	# In the turned frame the cap's depth is along local Y and its height along local Z.
	var local_size := Vector3(cap_size.x, cap_size.z, cap_size.y)
	var centre := Vector3(0.0, -cap_size.z / 2.0 + PROUD, 0.0)
	var cap := b.get_node("ButtonMesh") as MeshInstance3D
	var bm := BoxMesh.new()
	bm.size = local_size
	cap.mesh = bm
	cap.material_override = _mat("key", KEY_PLASTIC, 0.0, 0.5)
	cap.transform = Transform3D(Basis.IDENTITY, centre)
	cap.visible = true
	for i in cap.get_surface_override_material_count():
		cap.set_surface_override_material(i, null)
	var shape := b.get_node("CollisionShape3D") as CollisionShape3D
	var sb := BoxShape3D.new()
	sb.size = local_size
	shape.shape = sb
	shape.transform = cap.transform
	b.depress_axis = Vector3(0, -1, 0)
	b.depress_depth = TRAVEL
	b.set_button_mesh(cap)
	cap.visible = true
	b.press_gate = ApplianceModel.footprint_gate(cap, 0.001, 0.003, 1)
	b.trigger_radius = Vector2(cap_size.x, cap_size.y).length() * 0.5 + 0.003
	var legend := b.get_node_or_null("ButtonLabel") as Node3D
	if legend != null:
		legend.visible = false
	var old := cap.get_node_or_null("Glyph")
	if old != null:
		old.free()
	var label := Label3D.new()
	label.name = "Glyph"
	if word.is_empty():
		label.font = TransportGlyphs.font()
		label.text = TransportGlyphs.glyph(glyph)
		label.font_size = 40
		label.pixel_size = 0.00020
	else:
		label.text = word
		label.font_size = 30
		label.pixel_size = 0.00020
	label.modulate = GLYPH
	label.shaded = false
	label.double_sided = false
	# A Label3D faces +Z; the cap's face is its +Y, and "up" on the cap is the unit's +Y (local -Z).
	label.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, cap_size.z / 2.0 + 0.0004, 0.0))
	cap.add_child(label)
	return 12


# --- jacks, knob, boxes ----------------------------------------------------------------------------------

## The back's analog 5.1 line out, the consumer colour code on the base game's own phono sockets: the scene's AudioLOut and
## AudioROut are FL and FR (the pair the deck code looks up by name), and four more stand beside them for C, SUB, SL and
## SR. Seen from behind the row reads FL FR C SUB SL SR left to right (the unit's +X is the viewer's left from there).
## The cable graph (AvSource.resolve) already takes any of the six cabled to a loudspeaker cabinet as that channel's cabinet.
const JACKS_OUT := [["AudioLOut", RcaPort.Channel.AUDIO_L, "FL"], ["AudioROut", RcaPort.Channel.AUDIO_R, "FR"],
	["AudioCOut", RcaPort.Channel.AUDIO_C, "C"], ["AudioLfeOut", RcaPort.Channel.AUDIO_LFE, "SUB"],
	["AudioSlOut", RcaPort.Channel.AUDIO_SL, "SL"], ["AudioSrOut", RcaPort.Channel.AUDIO_SR, "SR"]]
const JACK_X0 := 0.1
const JACK_PITCH := 0.0185
const JACK_Y := -0.062
const PORT_SCENE := "res://Scenes/Objects/cables/rca_port.tscn"


static func _surround_row(host: Node3D) -> void:
	var first := host.get_node("AudioLOut") as RcaPort
	var scene := load(PORT_SCENE) as PackedScene
	var ports: Array = []
	var words := {}
	for i in JACKS_OUT.size():
		var spec: Array = JACKS_OUT[i]
		var port := host.get_node_or_null(str(spec[0])) as RcaPort
		if port == null:
			port = scene.instantiate() as RcaPort
			port.name = str(spec[0])
			port.channel = spec[1]
			port.direction = RcaPort.Direction.OUT
			port.transform = first.transform
			host.add_child(port)
		port.position = Vector3(JACK_X0 - i * JACK_PITCH, JACK_Y, BACK - 0.009)
		ports.append(port)
		words[spec[1]] = spec[2]
	var legend := AvLegend.attach(host, ports)
	if legend != null:
		legend.name = "AvLegend5_1"
		legend.heading_override = "5.1 OUT"
		legend.word_override = words
		legend.rebuild()


static func _seat_jacks(host: Node3D) -> void:
	# The line out on the back (white L, red R), as the base CD player has it: the zones stand 9 mm out of the back.
	_surround_row(host)
	# PHONES on the front, its plug seating flush with the fascia, and the VOLUME knob beside it.
	var ph := host.get_node("PhonesOut") as Node3D
	ph.position = Vector3(PHONES_AT.x, PHONES_AT.y, FRONT + 0.001 - 0.00075)
	var knob := host.get_node("LevelKnob") as VRKnob
	knob.position = Vector3(KNOB_AT.x, KNOB_AT.y, FRONT)
	var pivot := knob.get_node("KnobPivot") as Node3D
	for c in pivot.get_children():
		c.free()
	var cyl := MeshInstance3D.new()
	cyl.name = "KnobCap"
	var cm := CylinderMesh.new()
	cm.top_radius = KNOB_RADIUS
	cm.bottom_radius = KNOB_RADIUS + 0.001
	cm.height = KNOB_HEIGHT
	cm.radial_segments = 20
	cm.rings = 1
	cyl.mesh = cm
	cyl.material_override = _mat("knob", Color(0.09, 0.095, 0.105), 0.4, 0.4)
	# The knob turns about its own +Z: the cylinder's axis (Y) is laid along it, its middle half a height out.
	cyl.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.0, KNOB_HEIGHT / 2.0))
	pivot.add_child(cyl)
	var mark := _box(pivot, "KnobMark", Vector3(0.003, KNOB_RADIUS * 0.6, 0.0015), Vector3(0.0, KNOB_RADIUS * 0.62, KNOB_HEIGHT + 0.0005), _mat("mark", Color(0.92, 0.92, 0.95)))
	mark.name = "KnobMark"
	var shape := knob.get_node("CollisionShape3D") as CollisionShape3D
	var sb := BoxShape3D.new()
	sb.size = Vector3(KNOB_RADIUS * 2.0 + 0.002, KNOB_RADIUS * 2.0 + 0.002, KNOB_HEIGHT)
	shape.shape = sb
	shape.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, KNOB_HEIGHT / 2.0))
	knob.engage_radius = KNOB_RADIUS + 0.014


static func _fit_shapes(host: Node3D) -> void:
	var body := host.get_node("CollisionShape3D") as CollisionShape3D
	var bs := BoxShape3D.new()
	bs.size = Vector3(FULL_W, H, D)
	body.shape = bs
	var ptr := host.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	var ps := BoxShape3D.new()
	ps.size = Vector3(FULL_W, H, D)
	ptr.shape = ps


## Triangles drawn by the meshes under `node` (indexed or not), for the budget test.
static func _triangles(node: Node) -> int:
	var n := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mesh := (c as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				n += (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		stack.append_array(c.get_children())
	return n
