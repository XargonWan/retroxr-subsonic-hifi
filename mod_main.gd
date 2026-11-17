## Subsonic Hi-Fi NAVI-AZ95 -- a RetroXR mod.
##
## A hi-fi that plays a Subsonic-API music server (Navidrome and the like) and internet radio
## (Icecast / AzuraCast style streams) through RetroXR's own deck plumbing: line out, PHONES, power.
##
## The type string is written into save slots; it is permanent once anyone has used it.
extends RetroMod

const HIFI_TYPE := "xenu.subsonic:hifi"
const SPAWN_TAB := "electronics"


func register(api: ModApi) -> void:
	api.log_line("registering")
	var menu := {"label": "Subsonic Hi-Fi NAVI-AZ95"}
	# A hi-fi belongs on the SPAWN menu's Electronics tab. A RetroXR without tabs ignores the key and lists it under
	# Objects; one with tabs but no Electronics would fail the registration on it, so ask only where it exists.
	if has_electronics_tab():
		menu["tab"] = SPAWN_TAB
		api.log_line("[Subsonic] SPAWN menu: Electronics tab")
	else:
		api.log_line("[Subsonic] SPAWN menu: this RetroXR has no Electronics tab, falling back to Objects")
	api.register_object(HIFI_TYPE, "res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn", menu)


## Does the running RetroXR's SpawnCatalog offer an Electronics tab? Read as data, so a build without SPAWN_TABS
## still parses this script.
static func has_electronics_tab() -> bool:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class", "") != "SpawnCatalog":
			continue
		var catalog := load(str(entry.get("path", ""))) as GDScript
		if catalog == null:
			break
		var tabs: Variant = catalog.get_script_constant_map().get("SPAWN_TABS", null)
		return tabs is Dictionary and (tabs as Dictionary).has(SPAWN_TAB)
	return false
