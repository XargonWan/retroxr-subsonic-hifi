## The mod registers through the game's own ModApi, is offered on the SPAWN menu, and its scene instantiates as a
## RetroAudioPlayer with no medium. Run with tests/run_all.py (Godot through the host).
extends Node

const EXPECTED_CASES := 11
const TYPE := "xenu.subsonic:hifi"

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-reg] FAIL ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://mods/xenu.subsonic/mod.json"))
	_check(json is Dictionary, "mod.json parses")
	var manifest := ModManifest.parse(json as Dictionary)
	_check(manifest != null and manifest.id == "xenu.subsonic", "the manifest is valid and named xenu.subsonic")
	_check(manifest.claims.is_empty(), "it claims no shipped file")
	var script := load(manifest.entry) as GDScript
	_check(script != null, "the entry script loads")
	var api := ModApi.new(manifest, ModHooks.new(get_tree()))
	# Run with --no-mods, so nothing has registered it yet; a loader that already did would make this a duplicate.
	(script.new() as RetroMod).register(api)
	_check(not api.failed(), "registering raised no problem: %s" % api.errors_text())
	_check(ScenePersistence.is_mod_object(TYPE), "%s is a registered object" % TYPE)
	var scene := load(ScenePersistence.mod_object_scene(TYPE)) as PackedScene
	_check(scene != null, "its scene loads")
	var labels := []
	for item: Dictionary in SpawnCatalog.mod_spawnables():
		labels.append(item["label"])
	_check("Subsonic Hi-Fi NAVI-AZ95" in labels, "it is on the SPAWN menu")
	var tokens := []
	for row in SpawnCatalog.objects():
		tokens.append(str(row[1]))
	_check("mod:%s" % TYPE in tokens, "the Objects tab spawns it as mod:%s" % TYPE)
	var hifi := scene.instantiate()
	add_child(hifi)
	await get_tree().process_frame
	_check(hifi is RetroAudioPlayer and hifi.is_in_group("subsonic_hifi"), "it is a RetroAudioPlayer in its own group")
	_check(hifi.get_node_or_null("CdBay") is MediaSlot and hifi.get_node_or_null("TapeBay") is MediaSlot, "it has a CD bay and a cassette bay")
	hifi.queue_free()
	print("[sb-reg] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-reg] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
