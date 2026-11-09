## The screen's browser (hifi_browser.gd) against a stand-in for the Hi-Fi: what each press fetches, queues and tunes,
## that a stale answer never rewrites the page now showing, and the keyboard. No server, no game objects:
##
##   godot --headless --path RetroXR --script res://mods/xenu.subsonic/tests/browser_tests.gd
extends SceneTree

const Browser = preload("res://mods/xenu.subsonic/scripts/hifi_browser.gd")
const Pages = preload("res://mods/xenu.subsonic/scripts/sb_pages.gd")
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")

const EXPECTED_CASES := 56

var _cases := 0
var _failed := 0


class FakeClient extends Node:
	var canned := {}
	var held: Array = []        # replies kept back until release()
	var hold := false
	var asked: Array = []

	func call_api(call: Array, cb: Callable) -> void:
		asked.append(call[0])
		var reply: Array = [bool(canned.has(call[0])), canned.get(call[0], "NO SUCH CALL"), 0]
		if hold:
			held.append([cb, reply])
		else:
			cb.call(reply[0], reply[1], reply[2])

	func release() -> void:
		for h: Array in held:
			(h[0] as Callable).call(h[1][0], h[1][1], h[1][2])
		held.clear()


class FakeHifi extends RefCounted:
	var client := FakeClient.new()
	var signed := true
	var playing := {}
	var source := 0
	var station := {}
	var played: Array = []
	var tuned: Array = []
	var paused_toggles := 0
	var mode := 2
	var media := false
	var tracks: Array = ["One", "Two"]
	var ejected := 0
	var goto: Array = []
	var modes: Array = []
	var merged: Array = [{"name": "Jazz", "url": "https://j/live", "source": "user"}]
	var refresh_cbs: Array = []

	func stations() -> Array:
		return merged

	func mode_name() -> String:
		return ["CD", "TAPE", "NET"][mode]

	func has_media_in_bay() -> bool:
		return media

	func media_label() -> String:
		return "Disc X"

	func media_tracks() -> Array:
		return tracks

	func remote_goto_track(i: int) -> void:
		goto.append(i)

	func eject_current() -> void:
		ejected += 1

	func set_mode(m: int) -> void:
		modes.append(m)
		mode = m

	func refresh_server_stations(cb: Callable = Callable()) -> void:
		refresh_cbs.append(cb)

	func finish_refresh() -> void:
		for cb: Callable in refresh_cbs:
			cb.call(merged)
		refresh_cbs.clear()

	func is_signed_in() -> bool:
		return signed

	func now_playing() -> Dictionary:
		return playing

	func play_songs(songs: Array, start: int) -> void:
		played.append([songs.size(), start, songs[start]["id"] if start < songs.size() else ""])

	func play_station(st: Dictionary) -> void:
		tuned.append(st["url"])

	func toggle_pause() -> void:
		paused_toggles += 1


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-browser] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[sb-browser] FAIL ", what, ": got ", a, " want ", b)



func _init() -> void:
	OS.set_environment("XENU_SB_SETTINGS", "user://sb_browser_scratch/settings.json")
	DirAccess.make_dir_recursive_absolute("user://sb_browser_scratch")
	DirAccess.remove_absolute("user://sb_browser_scratch/settings.json")
	var h := FakeHifi.new()
	h.client.canned = {
		"getArtists": {"artists": {"index": [{"name": "A", "artist": [{"id": "ar1", "name": "ABBA", "albumCount": 2}, {"id": "ar2", "name": "Aha", "albumCount": 1}]}, {"name": "B", "artist": [{"id": "ar3", "name": "Bjork"}]}]}},
		"getArtist": {"artist": {"name": "ABBA", "album": [{"id": "al1", "name": "Arrival", "year": 1976, "songCount": 2}]}},
		"getAlbum": {"album": {"name": "Arrival", "artist": "ABBA", "song": [
			{"id": "s1", "title": "Dancing Queen", "track": 2, "duration": 230, "artist": "ABBA", "suffix": "mp3"},
			{"id": "s0", "title": "Knowing Me", "track": 1, "duration": 240, "artist": "ABBA", "suffix": "mp3"}]}},
		"getAlbumList2": {"albumList2": {"album": [{"id": "al9", "name": "Newest", "artist": "X", "year": 2026}]}},
		"getPlaylists": {"playlists": {"playlist": [{"id": "p1", "name": "Mix", "songCount": 3}]}},
		"getPlaylist": {"playlist": {"name": "Mix", "entry": [{"id": "s5", "title": "Five", "track": 0, "duration": 100}]}},
		"search3": {"searchResult3": {"song": [{"id": "r1", "title": "Take On Me", "artist": "Aha", "album": "HH"}, {"id": "r2", "title": "Second", "artist": "Aha", "album": "HH"}]}},
	}
	var b := Browser.new(h)
	var changes := [0]
	b.changed.connect(func() -> void: changes[0] += 1)
	_home(b, h)
	_library(b, h)
	_search(b, h)
	_radio_and_misc(b, h)
	_media_modes(b, h)
	_stale(h)
	print("[sb-browser] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-browser] FAIL expected %d cases, ran %d (a script error stopped the run?)" % [EXPECTED_CASES, _cases])
		quit(1)
		return
	quit(1 if _failed > 0 else 0)


func _texts(b: RefCounted) -> Array:
	return (b.page()["rows"] as Array).map(func(r: Dictionary) -> String: return r["text"])


func _home(b: RefCounted, h: FakeHifi) -> void:
	b.refresh_home()
	_eq(_texts(b)[0], "Artists", "signed in: home starts with Artists")
	h.signed = false
	b.refresh_home()
	_eq(_texts(b), ["Not signed in", "Radio"], "signed out: home says so and keeps the radio")
	b.nav("ok")
	_eq(b.pages.depth(), 1, "OK on the not-signed-in row does nothing")
	h.signed = true
	h.playing = {"title": "x"}
	b.refresh_home()
	_eq(_texts(b)[0], "Now playing", "something on: home offers Now playing")
	h.playing = {}
	b.refresh_home()


func _library(b: RefCounted, h: FakeHifi) -> void:
	b.nav("ok")                      # the cursor is on Artists
	_eq(b.page()["kind"], Pages.LETTERS, "OK on Artists opens the letters")
	_eq((b.page()["rows"] as Array).size(), 27, "A-Z and #")
	b.nav("ok")                      # letter A
	_eq(b.page()["kind"], Pages.ARTISTS, "a letter opens its artists")
	_eq(_texts(b), ["ABBA", "Aha"], "the artists of A, from getArtists")
	_eq(h.client.asked, ["getArtists"], "the artist list was asked of the server once")
	b.nav("back")
	b.nav("down")
	b.nav("ok")                      # letter B
	_eq(_texts(b), ["Bjork"], "letter B")
	_eq(h.client.asked, ["getArtists"], "and the list was NOT asked again")
	b.nav("back")
	b.nav("back")
	b.go_home()
	_eq(b.pages.depth(), 1, "MENU goes home")
	b.nav("down")                    # New albums
	b.nav("ok")
	_eq([b.page()["kind"], _texts(b)], [Pages.ALBUMS, ["Newest"]], "an album list opens")
	b.nav("ok")                      # open the album
	_eq([b.page()["kind"], _texts(b)], [Pages.ALBUM, ["▶ Play album", "1. Knowing Me", "2. Dancing Queen"]], "an album lists its songs in track order after Play album")
	b.nav("down")
	b.nav("down")                    # the cursor on "2. Dancing Queen"... row 2
	b.nav("ok")
	_eq(h.played, [[2, 1, "s1"]], "a song plays the album's queue from that song")
	b.nav("up")
	b.nav("up")
	b.nav("ok")                      # Play album
	_eq(h.played[1], [2, 0, "s0"], "Play album starts at the first track")
	b.go_home()
	b.pages.push(Pages.ARTIST, "x", "ar1", true)
	b.pages.pop()
	b.activate({"text": "Playlists", "act": "open", "arg": Pages.PLAYLISTS})
	_eq(_texts(b), ["Mix"], "playlists")
	b.nav("ok")
	_eq([b.page()["kind"], _texts(b)], [Pages.PLAYLIST, ["▶ Play playlist", "Five"]], "a playlist's songs")
	b.go_home()
	b.activate({"text": "Dancing", "act": "artist", "arg": "ar1"})
	_eq(_texts(b), ["Arrival"], "an artist's albums")
	_eq(b.page()["rows"][0]["sub"], "1976", "without the artist's name, the year")
	b.go_home()
	b.nav("right")
	_eq(b.page()["first"], 3, "the nine-row home pages down to its last window")
	b.activate({"text": "Radio", "act": "open", "arg": Pages.RADIO})
	b.nav("right")
	_eq(b.page()["first"], 0, "paging a one-row list stays on page one")


func _search(b: RefCounted, h: FakeHifi) -> void:
	b.go_home()
	b.activate({"text": "Search", "act": "open", "arg": Pages.SEARCH})
	_eq(b.page()["kind"], Pages.SEARCH, "the search page")
	for k in ["A", "H", "A", "SPACE", "Z", "DEL"]:
		b.press_key(k)
	_eq(b.page()["text"], "aha ", "typed text is lower case, DEL removes the last character")
	b.nav("down")                    # keyboard cursor: row 1
	_eq(b.page()["kb"], [1, 0], "the cross moves over the keyboard")
	b.nav("right")
	b.nav("ok")                      # row 1, col 1 is "W"
	_eq(b.page()["text"], "aha w", "OK types the key under the cursor")
	b.nav("back")
	_eq(b.page()["kind"], Pages.HOME, "BACK leaves the keyboard")
	b.activate({"text": "Search", "act": "open", "arg": Pages.SEARCH})
	b.press_key("GO")
	_eq(b.page()["kind"], Pages.SEARCH, "GO with nothing typed does nothing")
	for k in ["A", "H", "A"]:
		b.press_key(k)
	b.press_key("GO")
	_eq([b.page()["kind"], b.page()["arg"]], [Pages.RESULTS, "aha"], "GO searches")
	_eq(_texts(b), ["Take On Me", "Second"], "results")
	b.nav("down")
	b.nav("ok")
	_eq(h.played[-1], [1, 0, "r2"], "a result plays from itself to the end of the results")


func _radio_and_misc(b: RefCounted, h: FakeHifi) -> void:
	b.go_home()
	b.activate({"text": "Radio", "act": "open", "arg": Pages.RADIO})
	_eq(_texts(b), ["Jazz"], "the stations on offer")
	h.merged = [{"name": "Jazz", "url": "https://j/live", "source": "user"}, {"name": "Plaza", "url": "http://p/hls", "source": "server"}]
	h.finish_refresh()
	_eq(_texts(b), ["Jazz", "Plaza"], "the server's own list is asked again and the page follows it")
	_eq([b.page()["rows"][0]["sub"], b.page()["rows"][1]["sub"]], ["yours", "server"], "each row says whose it is")
	b.nav("down")
	b.nav("ok")
	_eq(h.tuned, ["http://p/hls"], "a server station tunes like any other")
	b.nav("up")
	b.nav("ok")
	_eq(h.tuned, ["http://p/hls", "https://j/live"], "OK tunes the station (after the server one)")
	h.source = 2
	h.station = {"name": "Jazz", "url": "https://j/live"}
	b.go_home()
	b.activate({"text": "Radio", "act": "open", "arg": Pages.RADIO})
	h.finish_refresh()
	_eq(_texts(b), ["● Jazz", "Plaza"], "the radio page again, the one on air marked")
	h.station = {"name": "Jazz", "url": "https://j/live"}
	h.source = 2
	b.go_home()
	b.activate({"text": "Radio", "act": "open", "arg": Pages.RADIO})
	_eq(_texts(b)[0], "● Jazz", "the station on air is marked")
	var left: Dictionary = b.page()
	b.nav("back")
	h.merged = [{"name": "Late", "url": "u", "source": "server"}]
	h.finish_refresh()
	_check((left["rows"] as Array).size() == 2, "a radio page the player has left is not rewritten by the late answer")
	b.go_home()
	b.activate({"text": "Now playing", "act": "open", "arg": Pages.NOW})
	b.nav("ok")
	_eq(h.paused_toggles, 1, "OK on Now playing pauses or resumes")
	b.go_home()
	var n: int = b.pages.depth()
	b.nav("back")
	_eq(b.pages.depth(), n, "BACK at home stays at home")
	h.signed = false
	b.activate({"text": "Artists", "act": "open", "arg": Pages.PLAYLISTS})
	_eq(b.page()["error"], "SIGN IN (TAB MENU)", "a fetch while signed out says to sign in")
	h.signed = true
	h.client.canned.erase("getPlaylists")
	b.go_home()
	b.activate({"text": "Playlists", "act": "open", "arg": Pages.PLAYLISTS})
	_check(str(b.page()["error"]).length() > 0 and (b.page()["rows"] as Array).is_empty(), "a failed fetch shows its error and no rows")


func _media_modes(b: RefCounted, h: FakeHifi) -> void:
	h.mode = 0
	h.media = false
	b.go_home()
	_eq(_texts(b), ["No disc", "Internet (NET)"], "CD with an empty bay: say so, and offer NET")
	h.media = true
	b.go_home()
	_eq(_texts(b), ["Disc X", "Tracks", "Eject", "Internet (NET)"], "CD with a disc: its label, Tracks, Eject, NET")
	_eq(b.page()["rows"][0]["sub"], "2 tracks", "and how many tracks it has")
	b.nav("down")
	b.nav("ok")
	_eq([b.page()["kind"], _texts(b)], [Pages.TRACKS, ["1. One", "2. Two"]], "Tracks lists the disc")
	b.nav("down")
	b.nav("ok")
	_eq(h.goto, [1], "a track on the list plays that track")
	b.go_home()
	b.nav("down")
	b.nav("down")
	b.nav("ok")
	_eq(h.ejected, 1, "Eject ejects")
	b.go_home()
	b.nav("down")
	b.nav("down")
	b.nav("down")
	b.nav("ok")
	_eq(h.modes, [2], "Internet (NET) switches function")
	h.mode = 2
	b.go_home()
	_eq(_texts(b)[0], "Artists", "and the NET home page is back")


func _stale(h: FakeHifi) -> void:
	var b := Browser.new(h)
	h.client.canned["getAlbumList2"] = {"albumList2": {"album": [{"id": "al1", "name": "Late", "artist": "X"}]}}
	h.client.hold = true
	b.activate({"text": "New albums", "act": "albums", "arg": "newest"})
	_check(b.page()["loading"], "a page waiting for the server is loading")
	var abandoned: Dictionary = b.page()
	b.nav("back")
	b.activate({"text": "Random", "act": "albums", "arg": "random"})
	var showing: Dictionary = b.page()
	h.client.release()
	_eq(_texts(b), ["Late"], "the answer for the page showing fills it")
	_check(showing["rows"].size() == 1, "and only that one")
	_check(abandoned["loading"] and abandoned["rows"].is_empty(), "the page the player left was not filled by its late answer")
	_check(b.pages.depth() == 2, "the abandoned page's answer did not add anything")
	h.client.free()
