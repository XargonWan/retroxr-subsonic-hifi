## The browser behind the Hi-Fi's screen: the pages model (sb_pages.gd) plus what a press DOES -- fetching a page's
## data from the server, queueing a song, tuning a station -- and the unit's own keys (cross, OK, BACK, MENU).
##
## The screen only draws what is here and forwards presses; nothing in this file knows about nodes or drawing, so
## it is tested with a stand-in for the Hi-Fi (a Dictionary of Callables is not needed: `hifi` is duck-typed and the
## tests hand it a small object with the same methods).
##
## A fetch is dropped if its page has been left by the time the answer comes (a stale answer never rewrites the
## page now showing).
extends RefCounted

const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")
const Pages = preload("res://mods/xenu.subsonic/scripts/sb_pages.gd")
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")

signal changed

var pages = Pages.new()
var hifi: Object = null
## getArtists, once per sign-in.
var _artists: Array = []
var _artists_loaded := false


func _init(a_hifi: Object = null) -> void:
	hifi = a_hifi


# --- reading -------------------------------------------------------------------------------------------

func page() -> Dictionary:
	return pages.current()


func now_on() -> bool:
	return hifi != null and not (hifi.call("now_playing") as Dictionary).is_empty()


func signed_in() -> bool:
	return hifi != null and bool(hifi.call("is_signed_in"))


## Rebuild the home page's rows (it depends on the login, the stations and what is playing).
func refresh_home() -> void:
	var p: Dictionary = pages.stack[0]
	pages.set_rows(p, Pages.home_rows(signed_in(), (Config.load_all()["stations"] as Array).size(), now_on()))
	changed.emit()


# --- keys of the unit and presses on the screen ----------------------------------------------------------

## "up" "down" "left" "right" "ok" "back" "menu". On a list: up/down move the cursor, left/right turn the page. On the
## keyboard all four move over the keys.
func nav(cmd: String) -> void:
	var p := page()
	if p["kind"] == Pages.SEARCH:
		_keyboard_nav(p, cmd)
		return
	match cmd:
		"up":
			pages.cursor_move(-1)
		"down":
			pages.cursor_move(1)
		"left":
			pages.page_move(-1)
		"right":
			pages.page_move(1)
		"ok":
			if p["kind"] == Pages.NOW:
				if hifi != null:
					hifi.call("toggle_pause")
			else:
				var r: Dictionary = pages.cursor_row()
				if not r.is_empty():
					activate(r)
		"back":
			back()
		"menu":
			go_home()
	changed.emit()


func back() -> void:
	pages.pop()
	_fix_home()
	changed.emit()


func go_home() -> void:
	pages.home()
	refresh_home()


func _fix_home() -> void:
	if pages.depth() == 1:
		refresh_home()


## A tap on a visible row (slot 0..5).
func press_slot(slot: int) -> void:
	var r: Dictionary = pages.row_at_slot(slot)
	if r.is_empty():
		return
	activate(r)


func page_move(dir: int) -> void:
	pages.page_move(dir)
	changed.emit()


# --- what a row does -----------------------------------------------------------------------------------

func activate(r: Dictionary) -> void:
	var arg: Variant = r.get("arg")
	match str(r["act"]):
		"open":
			_open(str(arg), str(r["text"]))
		"albums":
			_albums(str(arg), str(r["text"]))
		"letter":
			_artists_page(str(arg))
		"artist":
			_artist(str(arg), str(r["text"]))
		"album":
			_album(str(arg), str(r["text"]))
		"playlist":
			_playlist(str(arg), str(r["text"]))
		"play_all", "play_song":
			_play_from_page(int(arg))
		"play_result":
			_play_result(int(arg))
		"play_station":
			for st: Dictionary in Config.load_all()["stations"]:
				if st["url"] == str(arg):
					hifi.call("play_station", st)
					print("[Subsonic] screen: tuning %s" % st["name"])
			changed.emit()
		_:
			pass


func _open(kind: String, title: String) -> void:
	match kind:
		Pages.LETTERS:
			var p: Dictionary = pages.push(Pages.LETTERS, "Artists")
			pages.set_rows(p, Pages.letter_rows())
		Pages.SEARCH:
			pages.push(Pages.SEARCH, "Search")
			pages.current()["kb"] = [0, 0]
		Pages.RADIO:
			var p: Dictionary = pages.push(Pages.RADIO, "Radio")
			var on_air := ""
			if hifi != null and int(hifi.get("source")) == 2 and not (hifi.get("station") as Dictionary).is_empty():
				on_air = str((hifi.get("station") as Dictionary).get("url", ""))
			pages.set_rows(p, Pages.station_rows(Config.load_all()["stations"], on_air))
		Pages.PLAYLISTS:
			var p: Dictionary = pages.push(Pages.PLAYLISTS, title, null, true)
			_call(Api.get_playlists(), p, func(body: Dictionary) -> void:
				pages.set_rows(p, Pages.playlist_rows(Api.playlists(body))))
		Pages.NOW:
			pages.push(Pages.NOW, "Now playing")
	changed.emit()


func _albums(kind: String, title: String) -> void:
	var p: Dictionary = pages.push(Pages.ALBUMS, title, kind, true)
	_call(Api.get_album_list(kind, 60), p, func(body: Dictionary) -> void:
		pages.set_rows(p, Pages.album_rows(Api.album_list(body))))
	changed.emit()


func _artists_page(letter: String) -> void:
	var p: Dictionary = pages.push(Pages.ARTISTS, "Artists " + letter, letter, not _artists_loaded)
	if _artists_loaded:
		pages.set_rows(p, Pages.artist_rows(_artists, letter))
	else:
		_call(Api.get_artists(), p, func(body: Dictionary) -> void:
			_artists = Api.artists(body)
			_artists_loaded = true
			pages.set_rows(p, Pages.artist_rows(_artists, letter)))
	changed.emit()


func _artist(id: String, title: String) -> void:
	var p: Dictionary = pages.push(Pages.ARTIST, title, id, true)
	_call(Api.get_artist(id), p, func(body: Dictionary) -> void:
		var d := Api.artist_albums(body)
		pages.set_rows(p, Pages.album_rows(d["albums"], false)))
	changed.emit()


func _album(id: String, title: String) -> void:
	var p: Dictionary = pages.push(Pages.ALBUM, title, id, true)
	_call(Api.get_album(id), p, func(body: Dictionary) -> void:
		var d := Api.album_songs(body)
		p["songs"] = d["songs"]
		pages.set_rows(p, Pages.song_rows(d["songs"], "▶ Play album")))
	changed.emit()


func _playlist(id: String, title: String) -> void:
	var p: Dictionary = pages.push(Pages.PLAYLIST, title, id, true)
	_call(Api.get_playlist(id), p, func(body: Dictionary) -> void:
		var d := Api.playlist_songs(body)
		p["songs"] = d["songs"]
		pages.set_rows(p, Pages.song_rows(d["songs"], "▶ Play playlist")))
	changed.emit()


func _play_from_page(index: int) -> void:
	var songs: Array = page().get("songs", [])
	if songs.is_empty():
		return
	print("[Subsonic] screen: playing '%s' track %d of %d" % [page()["title"], index + 1, songs.size()])
	hifi.call("play_songs", songs, index)
	changed.emit()


func _play_result(index: int) -> void:
	var songs: Array = page().get("songs", [])
	if songs.is_empty():
		return
	hifi.call("play_songs", songs.slice(index), 0)
	changed.emit()


## Ask the server; the answer fills `p` unless the player has left it. `fill` gets the response body.
func _call(call: Array, p: Dictionary, fill: Callable) -> void:
	if hifi == null or not signed_in():
		pages.set_error(p, "SIGN IN (TAB MENU)")
		return
	(hifi.get("client") as Node).call("call_api", call, func(ok: bool, data: Variant, _code: int) -> void:
		if not pages.has_page(p):
			return
		if ok:
			fill.call(data)
		else:
			pages.set_error(p, str(data).to_upper().left(40))
		changed.emit())


# --- search --------------------------------------------------------------------------------------------

func press_key(key: String) -> void:
	var p := page()
	if p["kind"] != Pages.SEARCH:
		return
	if key == "GO":
		_search(str(p["text"]))
		return
	p["text"] = Pages.type_key(str(p["text"]), key)
	changed.emit()


func _search(text: String) -> void:
	var q := text.strip_edges()
	if q.is_empty():
		return
	var p: Dictionary = pages.push(Pages.RESULTS, "“%s”" % q, q, true)
	_call(Api.search(q), p, func(body: Dictionary) -> void:
		var res := Api.search_results(body)
		p["songs"] = res["songs"]
		pages.set_rows(p, Pages.result_rows(res)))
	changed.emit()


func _keyboard_nav(p: Dictionary, cmd: String) -> void:
	var kb: Array = p.get("kb", [0, 0])
	var rows: Array = Pages.KEY_ROWS
	var r := int(kb[0])
	var c := int(kb[1])
	match cmd:
		"up":
			r = maxi(r - 1, 0)
		"down":
			r = mini(r + 1, rows.size() - 1)
		"left":
			c -= 1
		"right":
			c += 1
		"ok":
			press_key(str((rows[r] as Array)[clampi(c, 0, (rows[r] as Array).size() - 1)]))
			return
		"back":
			back()
			return
		"menu":
			go_home()
			return
	c = clampi(c, 0, (rows[r] as Array).size() - 1)
	p["kb"] = [r, c]
	changed.emit()
