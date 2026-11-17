## Signing in and using the library against tests/mock_subsonic.py (it checks the token like Navidrome does; run_all.py
## starts it on the host). The unit signs in through its own code, browses NET, and a second unit that reads the saved
## login (a reloaded scene) browses it too.
extends Node

const URL := "http://127.0.0.1:4599"
const SCRATCH := "user://sb_login"
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const Pages = preload("res://mods/xenu.subsonic/scripts/sb_pages.gd")

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-login] FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _wait(box: Dictionary, key: String, seconds := 8.0) -> void:
	var t := 0.0
	while not box.has(key) and t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _unit() -> SubsonicHifi:
	var h := (load("res://mods/xenu.subsonic/scenes/subsonic_hifi.tscn") as PackedScene).instantiate() as SubsonicHifi
	add_child(h)
	await _frames(3)
	return h


## Open a NET page through the browser and wait for its rows or its error.
func _page(h: SubsonicHifi, row: Dictionary) -> Dictionary:
	h.browser.go_home()
	h.browser.activate(row)
	var p: Dictionary = h.browser.page()
	var t := 0.0
	while bool(p["loading"]) and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	return p


func _run() -> void:
	OS.set_environment("XENU_SB_SETTINGS", SCRATCH + "/settings.json")
	OS.set_environment("XENU_SB_CACHE", SCRATCH + "/cache")
	DirAccess.make_dir_recursive_absolute(SCRATCH + "/cache")
	DirAccess.remove_absolute(SCRATCH + "/settings.json")
	var h := await _unit()
	h.set_server(URL)
	var box := {}
	h.sign_in("u", "wrong", func(ok: bool, msg: String) -> void: box["bad"] = [ok, msg])
	await _wait(box, "bad")
	_check(box.has("bad") and not box["bad"][0] and "wrong" in str(box["bad"][1]), "a wrong password is refused, and says so")
	h.sign_in("u", "pw", func(ok: bool, msg: String) -> void: box["good"] = [ok, msg])
	await _wait(box, "good")
	_check(box.has("good") and box["good"][0], "the right password signs in (%s)" % str(box.get("good", "no answer")))
	_check(h.is_signed_in() and h.status == "", "the unit is signed in with no status left over (%s)" % h.status)
	# A second press of the button comes with its password field already cleared: it must not undo the login.
	var second := {}
	h.sign_in("u", "", func(ok: bool, msg: String) -> void: second["r"] = [ok, msg])
	await _frames(2)
	_check(second.has("r") and second["r"][0] and h.is_signed_in() and h.status == "" and h.sign_in_error == "", "a press with an empty password after a login that worked changes nothing")
	var s := Config.load_all()
	_check(str(s.get("token", "")) == (("pw" + str(s.get("salt", ""))).md5_text()) and str(s.get("user", "")) == "u", "the settings keep the user, the salt and the token the server accepts")
	var p := await _page(h, Pages.row("New albums", "albums", "newest"))
	_check(str(p["error"]) == "" and (p["rows"] as Array).size() == 1, "NET: an album list opens (%s)" % str(p["error"]))
	p = await _page(h, Pages.row("Playlists", "open", Pages.PLAYLISTS))
	_check(str(p["error"]) == "", "NET: Playlists opens (%s)" % str(p["error"]))
	p = await _page(h, Pages.row("Artists", "open", Pages.LETTERS))
	h.browser.activate(Pages.row("A", "letter", "A"))
	p = h.browser.page()
	var t := 0.0
	while bool(p["loading"]) and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(str(p["error"]) == "" and (p["rows"] as Array).size() == 1, "NET: Artists A opens (%s)" % str(p["error"]))
	_check(h.status == "", "no call asked for a new sign-in (%s)" % h.status)
	# The scene is reloaded: a unit that starts from the saved login uses it.
	h.queue_free()
	await _frames(3)
	var again := await _unit()
	_check(again.is_signed_in() and again.client.user == "u", "a unit that starts reads the saved login")
	p = await _page(again, Pages.row("New albums", "albums", "newest"))
	_check(str(p["error"]) == "" and (p["rows"] as Array).size() == 1, "and NET works for it (%s)" % str(p["error"]))
	_check(again.status == "", "with no new sign-in asked for (%s)" % again.status)
	print("[sb-login] %d cases, %d failed" % [_cases, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
