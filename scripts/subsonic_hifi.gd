## SubsonicHifi -- the object. A RetroAudioPlayer (the shared deck: transport, PCM into line out / PHONES,
## power, netplay host authority) with no tray and no disc: its "album" is a queue of Subsonic tracks or a radio
## station, handed to the base as `_tracks`.
##
## Step 1 skeleton: it only proves the loader accepts the pack and the base deck code runs on a scene with no
## medium. Everything else (client, cache, screen, menu) lands in the following commits.
class_name SubsonicHifi
extends RetroAudioPlayer


func _ready() -> void:
	# The base deck wants a media group; nothing is ever seated here, the queue is the medium.
	_media_group = "subsonic_queue"
	super._ready()
	add_to_group("subsonic_hifi")
	print("[Subsonic] %s: ready (skeleton)" % name)


## No tray, no disc: take the base scene's snap zone out of play so a disc cannot be dropped on a box that has no
## slot. (The node stays: RetroAudioPlayer reads it with an @onready.)
func _setup_loader() -> void:
	if _media_slot != null:
		_media_slot.enabled = false
		_media_slot.visible = false


func _log_tag() -> String:
	return "Subsonic"


func deck_save_type() -> String:
	return "xenu.subsonic:hifi"
