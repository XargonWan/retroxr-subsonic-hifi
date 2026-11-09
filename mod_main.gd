## Subsonic Hi-Fi NAVI-AZ95 -- a RetroXR mod.
##
## A hi-fi that plays a Subsonic-API music server (Navidrome and the like) and internet radio
## (Icecast / AzuraCast style streams) through RetroXR's own deck plumbing: line out, PHONES, power.
##
## The type string is written into save slots; it is permanent once anyone has used it.
extends RetroMod

const HIFI_TYPE := "xenu.subsonic:hifi"


func register(api: ModApi) -> void:
	api.log_line("registering")
	api.register_object(HIFI_TYPE, "res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn",
		{"label": "Subsonic Hi-Fi NAVI-AZ95"})
