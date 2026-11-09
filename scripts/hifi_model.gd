## The Hi-Fi's body, built in code from primitives (a few hundred triangles; the room also holds cabinets): a
## graphite chassis with a brushed-silver fascia, a bezelled LCD window, two rows of keys, PHONES with its LEVEL
## knob, four feet. Original geometry; the supplied NAVI reference model is not used (it carries no licence).
##
## The unit's frame is the base CD player's: origin at the middle of the body, +Z out of the front, +Y up. The
## jacks the shared deck code looks up by name (AudioLOut / AudioROut on the back, PhonesOut and LevelKnob on the
## front) are SEATED here, on this body, and the keys are the base scene's own VRButtons (so the deck code that
## connects PLAY / PAUSE / STOP / PREV / NEXT finds them) dressed with caps and glyphs.
##
## A key follows the game's VRButton convention: the node is turned a quarter about X so its +Y is the unit's +Z
## (its face), it presses along -Y, and the cap and its box are laid out in that turned frame.
extends RefCounted

const W := 0.43
const H := 0.15
const D := 0.30
const FRONT := D / 2.0
const BACK := -D / 2.0

## The LCD's glass and the centre of its window.
const SCREEN := Vector2(0.200, 0.100)
const SCREEN_AT := Vector2(-0.095, 0.004)

## A key's cap (w x h x depth) and how far it stands out of the fascia at rest.
const CAP := Vector3(0.0215, 0.0150, 0.0060)
const PROUD := 0.0030
const TRAVEL := 0.0015
## Column pitch of the key rows and where the first row of the cluster starts.
const KEY_X0 := 0.0415
const KEY_PITCH := 0.0262
const ROW_NAV_Y := 0.046
const ROW_TRANSPORT_Y := 0.016

const PHONES_AT := Vector2(0.178, -0.050)
const KNOB_AT := Vector2(0.128, -0.050)

## The nav keys, in order along their row (left to right): node name, glyph.
const NAV_ROW := [["MenuButton", "menu"], ["BackButton", "left"], ["LeftButton", "rew"], ["UpButton", "up"],
	["DownButton", "down"], ["RightButton", "ff"], ["OkButton", "ok"]]
## The transport keys the base scene already has, in order along their row.
const TRANSPORT_ROW := [["PrevButton", "prev"], ["PlayButton", "play"], ["PauseButton", "pause"],
	["StopButton", "stop"], ["NextButton", "next"]]

const GRAPHITE := Color(0.15, 0.155, 0.17)
const SILVER := Color(0.80, 0.82, 0.85)
const KEY_PLASTIC := Color(0.58, 0.60, 0.64)
const GLYPH := Color(0.06, 0.07, 0.09)
const PRINT := Color(0.16, 0.17, 0.20)

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


## Build the body under `model` (a Node3D named Model on the unit) and dress the unit's scene nodes. Returns the
## number of triangles drawn, for the test that holds it to its budget.
static func build(host: Node3D, model: Node3D) -> int:
	var graphite := _mat("graphite", GRAPHITE, 0.2, 0.5)
	var silver := _mat("silver", SILVER, 0.3, 0.4)
	var black := _mat("black", Color(0.012, 0.014, 0.018), 0.0, 0.25)
	# The chassis, a little shorter and shallower than the fascia, which stands proud in front and over the top.
	_box(model, "Chassis", Vector3(W - 0.004, H - 0.006, D - 0.012), Vector3(0.0, 0.0, -0.006), graphite)
	_box(model, "Fascia", Vector3(W, H, 0.012), Vector3(0.0, 0.0, FRONT - 0.006), silver)
	_box(model, "TopPlate", Vector3(W - 0.012, 0.004, D - 0.02), Vector3(0.0, H / 2.0 - 0.001, -0.012), graphite)
	# The LCD: a black bezel box standing 1.5 mm out of the fascia, the glass set into it.
	_box(model, "Bezel", Vector3(SCREEN.x + 0.016, SCREEN.y + 0.016, 0.0030), Vector3(SCREEN_AT.x, SCREEN_AT.y, FRONT + 0.0015), black)
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
			foot.position = Vector3(fx * (W / 2.0 - 0.04), -H / 2.0 - 0.004, fz * (D / 2.0 - 0.04))
			model.add_child(foot)
	_silkscreen(model)
	var tris := _dress_keys(host)
	_seat_jacks(host)
	_fit_shapes(host)
	var cord := Node3D.new()
	cord.name = "PowerCordExit"
	cord.position = Vector3(-0.15, -0.045, BACK)
	model.add_child(cord)
	return tris + _triangles(model)


static func _silkscreen(model: Node3D) -> void:
	var left := _label("SUBSONIC  Hi-Fi", 44, PRINT)
	left.position = Vector3(-0.150, 0.0665, FRONT + 0.0004)
	model.add_child(left)
	var right := _label("NAVI-AZ95", 44, PRINT)
	right.position = Vector3(0.150, 0.0665, FRONT + 0.0004)
	model.add_child(right)
	var cd := _label("STREAMING  COMPACT  DISC  PLAYER", 30, Color(0.34, 0.35, 0.40))
	cd.position = Vector3(-0.115, -0.0675, FRONT + 0.0004)
	model.add_child(cd)
	# The back: a plate round the line out, and its legend (facing out of the back: a half turn about Y).
	var plate := _box(model, "JackPlate", Vector3(0.080, 0.052, 0.002), Vector3(0.124, -0.040, BACK - 0.001), _mat("silver", SILVER, 0.3, 0.4))
	plate.name = "JackPlate"
	# [text, x, y]: the legend above the jacks, and L / R below them.
	for spec: Array in [["LINE OUT", 0.124, -0.0195], ["L", 0.110, -0.0545], ["R", 0.138, -0.0545]]:
		var t := _label(str(spec[0]), 30 if spec[0] == "LINE OUT" else 36, PRINT)
		t.rotation = Vector3(0.0, PI, 0.0)
		t.position = Vector3(float(spec[1]), float(spec[2]), BACK - 0.0022)
		model.add_child(t)
	var phones := _label("PHONES", 28, PRINT)
	phones.position = Vector3(PHONES_AT.x - 0.001, PHONES_AT.y + 0.0185, FRONT + 0.0004)
	model.add_child(phones)
	var level := _label("LEVEL", 28, PRINT)
	level.position = Vector3(KNOB_AT.x, KNOB_AT.y + 0.0225, FRONT + 0.0004)
	model.add_child(level)


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

## Where a key stands: column `i` of a row at height `y`, in the unit's frame, on the fascia.
static func key_at(i: int, y: float) -> Vector3:
	return Vector3(KEY_X0 + i * KEY_PITCH, y, FRONT)


## Dress the base scene's transport keys and add the navigation row. Returns the triangles of the caps.
static func _dress_keys(host: Node3D) -> int:
	var template := host.get_node("PlayButton") as VRButton
	var tris := 0
	for i in TRANSPORT_ROW.size():
		var spec: Array = TRANSPORT_ROW[i]
		var b := host.get_node(str(spec[0])) as VRButton
		tris += _cap(b, key_at(i, ROW_TRANSPORT_Y), str(spec[1]))
	for i in NAV_ROW.size():
		var spec: Array = NAV_ROW[i]
		var b := template.duplicate() as VRButton
		b.name = str(spec[0])
		host.add_child(b)
		tris += _cap(b, key_at(i, ROW_NAV_Y), str(spec[1]))
	return tris


## Put `b` at `at` (its origin on the fascia, its face turned to +Z), give it a cap, a box, a glyph and a press.
static func _cap(b: VRButton, at: Vector3, glyph: String) -> int:
	var turn := Basis(Vector3.RIGHT, PI / 2.0)
	b.transform = Transform3D(turn, at)
	# In the turned frame the cap's depth is along local Y and its height along local Z.
	var local_size := Vector3(CAP.x, CAP.z, CAP.y)
	var centre := Vector3(0.0, -CAP.z / 2.0 + PROUD, 0.0)
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
	b.trigger_radius = Vector2(CAP.x, CAP.y).length() * 0.5 + 0.003
	var legend := b.get_node_or_null("ButtonLabel") as Node3D
	if legend != null:
		legend.visible = false
	var old := cap.get_node_or_null("Glyph")
	if old != null:
		old.free()
	var label := Label3D.new()
	label.name = "Glyph"
	label.font = TransportGlyphs.font()
	label.text = TransportGlyphs.glyph(glyph)
	label.font_size = 40
	label.pixel_size = 0.00020
	label.modulate = GLYPH
	label.shaded = false
	label.double_sided = false
	# A Label3D faces +Z; the cap's face is its +Y, and "up" on the cap is the unit's +Y (local -Z).
	label.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, CAP.z / 2.0 + 0.0004, 0.0))
	cap.add_child(label)
	return 12


# --- jacks, knob, boxes ----------------------------------------------------------------------------------

static func _seat_jacks(host: Node3D) -> void:
	# The line out on the back (white L, red R), as the base CD player has it: the zones stand 9 mm out of the back.
	var l := host.get_node("AudioLOut") as Node3D
	var r := host.get_node("AudioROut") as Node3D
	l.position = Vector3(0.110, -0.040, BACK - 0.009)
	r.position = Vector3(0.138, -0.040, BACK - 0.009)
	# PHONES on the front, its plug seating flush with the fascia, and the LEVEL knob beside it.
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
	cm.top_radius = 0.0125
	cm.bottom_radius = 0.0135
	cm.height = 0.014
	cm.radial_segments = 16
	cm.rings = 1
	cyl.mesh = cm
	cyl.material_override = _mat("knob", Color(0.09, 0.095, 0.105), 0.4, 0.4)
	# The knob turns about its own +Z: the cylinder's axis (Y) is laid along it, its middle half a height out.
	cyl.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.0, 0.007))
	pivot.add_child(cyl)
	var mark := _box(pivot, "KnobMark", Vector3(0.0025, 0.009, 0.0015), Vector3(0.0, 0.0065, 0.0145), _mat("mark", Color(0.92, 0.92, 0.95)))
	mark.name = "KnobMark"
	var shape := knob.get_node("CollisionShape3D") as CollisionShape3D
	var sb := BoxShape3D.new()
	sb.size = Vector3(0.027, 0.027, 0.014)
	shape.shape = sb
	shape.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.007))
	knob.engage_radius = 0.03


static func _fit_shapes(host: Node3D) -> void:
	var body := host.get_node("CollisionShape3D") as CollisionShape3D
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H, D)
	body.shape = bs
	var ptr := host.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	var ps := BoxShape3D.new()
	# The ray's box stops at the fascia less what the keys and the screen stand in: nothing padded past the drawing.
	ps.size = Vector3(W, H, D)
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
