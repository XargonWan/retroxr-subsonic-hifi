## A disc and a cassette in the unit's bays, saved with the game's own ScenePersistence and put back: they come back
## seated, in the bays, and the cassette plays on. Run with tests/run_all.py (Godot through the host).
extends Node

const TYPE := "xenu.subsonic:hifi"
const SCRATCH := "user://sb_persist"
const EXPECTED_CASES := 7
const Body = preload("res://mods/xenu.subsonic/scripts/hifi_model.gd")

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-persist] FAIL ", what)


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _album(dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in ["01 First.mp3", "02 Second.mp3"]:
		var h := FileAccess.open(dir + "/" + f, FileAccess.WRITE)
		h.store_8(0)
	return ProjectSettings.globalize_path(dir)


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", SCRATCH + "/settings.json")
	OS.set_environment("XENU_SB_CACHE", SCRATCH + "/cache")
	DirAccess.make_dir_recursive_absolute(SCRATCH + "/cache")
	DirAccess.remove_absolute(SCRATCH + "/settings.json")
	ScenePersistence.register_mod_object(TYPE, "res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn", "xenu.subsonic")
	var sp := ScenePersistence.new("arcade")
	var root := Node3D.new()
	add_child(root)
	var hifi := (load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene).instantiate() as SubsonicHifi
	hifi.set_meta(ScenePersistence.MOD_TYPE_META, TYPE)
	root.add_child(hifi)
	var cam := Camera3D.new()
	root.add_child(cam)
	await _frames(3)
	var disc := (load("res://Scenes/Objects/media/audio_disc.tscn") as PackedScene).instantiate() as Node3D
	disc.set("album_path", _album(SCRATCH + "/cd"))
	disc.set("album_label", "Test Disc")
	root.add_child(disc)
	var tape := (load("res://Scenes/Objects/media/audio_cassette.tscn") as PackedScene).instantiate() as Node3D
	tape.set("album_path", _album(SCRATCH + "/tape"))
	tape.set("album_label", "Test Tape")
	root.add_child(tape)
	await _frames(2)
	hifi.restore_media(disc)
	hifi.restore_media(tape, 0.0, 0)
	await _frames(3)
	var ids := {hifi: 0, disc: 1, tape: 2}
	var recs: Array = []
	for n: Node in [hifi, disc, tape]:
		recs.append(sp.serialize_node(n, ids[n], ids))
	_check(recs[0].get("type") == TYPE and recs[0].has("media"), "the deck is saved as the deck it is, with a medium in it (%s)" % str(recs[0].keys()))
	root.queue_free()
	await _frames(3)
	var root2 := Node3D.new()
	add_child(root2)
	var cam2 := Camera3D.new()
	root2.add_child(cam2)
	var spawned := sp.instantiate_objects(root2, JSON.parse_string(JSON.stringify(recs)))
	await _frames(6)
	var h2: SubsonicHifi = null
	var d2: Node3D = null
	var t2: Node3D = null
	for n in spawned.values():
		if n is SubsonicHifi:
			h2 = n
		elif n.is_in_group("audio_cassette"):
			t2 = n
		elif n.is_in_group("audio_disc"):
			d2 = n
	_check(h2 != null and d2 != null and t2 != null, "the unit, the disc and the cassette all come back")
	if h2 == null or d2 == null or t2 == null:
		_finish()
		return
	_check(h2.mode == SubsonicHifi.Mode.TAPE and h2._slot_tape.has_media() and h2._slot_tape.get_media() == t2, "the cassette is in the TAPE bay and the unit on TAPE")
	_check(h2.has_media_in_bay() and h2._tracks.size() == 2, "its tracks are read")
	_check(h2._tape_autoplay_pending or h2.is_playing, "and it plays on (or will, once there is power)")
	var seat := h2.to_local(t2.global_position)
	_check(t2.is_visible_in_tree() and seat.distance_to(Vector3(Body.TAPE_AT.x, Body.TAPE_AT.y, 0.1389)) < 0.01, "the cassette stands on the door's seat (%s)" % str(seat))
	# The disc was not named by the deck's entry (it names one medium): it is put in its bay a moment after the load.
	var t := 0.0
	while not h2._slot_cd.has_media() and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(h2._slot_cd.has_media() and h2._slot_cd.get_media() == d2, "the disc is put in the CD bay (%s)" % str(h2.to_local(d2.global_position)))
	_finish()


func _finish() -> void:
	print("[sb-persist] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-persist] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
