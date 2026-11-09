## The screen's pages, pure: a navigation stack of pages, each a list of rows with a first-visible index and a
## cursor, the builders that turn parsed Subsonic data into rows, and the on-screen keyboard. No node, no network:
## hifi_screen.gd draws what this holds and sends the user's presses into it.
##
## A row is {text, sub, act, arg}: `act` names what pressing it does ("open", "play_album", "play_song", "play_station",
## "letter", "key", ...), `arg` is its payload. The screen turns acts into calls on the Hi-Fi.
extends RefCounted

## Rows on screen at once (the screen is 6 rows tall).
const PAGE_ROWS := 6

## Page kinds.
const HOME := "home"
const LETTERS := "letters"
const ARTISTS := "artists"
const ARTIST := "artist"
const ALBUMS := "albums"
const ALBUM := "album"
const SEARCH := "search"
const RESULTS := "results"
const PLAYLISTS := "playlists"
const PLAYLIST := "playlist"
const RADIO := "radio"
const NOW := "now"
const TRACKS := "tracks"

const ALBUM_KINDS := [["New albums", "newest"], ["Recently played", "recent"], ["Most played", "frequent"],
	["Random albums", "random"], ["Starred", "starred"]]

## The keyboard: rows of keys. "SPACE", "DEL", "GO" are the specials.
const KEY_ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "'"],
	["Z", "X", "C", "V", "B", "N", "M", "-", ".", "DEL"],
	["SPACE", "GO"],
]

var stack: Array = []        # of page Dictionaries, the last is showing


func _init() -> void:
	home()


# --- the stack -----------------------------------------------------------------------------------------

static var _next_id := 1


static func _page(kind: String, title: String, arg: Variant = null) -> Dictionary:
	_next_id += 1
	return {"id": _next_id, "kind": kind, "title": title, "arg": arg, "rows": [], "first": 0, "cursor": 0, "loading": false,
		"error": "", "text": ""}


func current() -> Dictionary:
	return stack[stack.size() - 1]


## Whether this very page is still on the stack (a reply that comes after the player left it is dropped).
func has_page(p: Dictionary) -> bool:
	for q: Dictionary in stack:
		if q["id"] == p["id"]:
			return true
	return false


func depth() -> int:
	return stack.size()


func home() -> void:
	stack = [_page(HOME, "NAVI-AZ95")]


## Open a page on top. It starts empty and, if `loading`, says so until set_rows / set_error.
func push(kind: String, title: String, arg: Variant = null, loading := false) -> Dictionary:
	var p := _page(kind, title, arg)
	p["loading"] = loading
	stack.append(p)
	return p


## Back one page. False at the home page (nothing to go back to).
func pop() -> bool:
	if stack.size() <= 1:
		return false
	stack.pop_back()
	return true


func set_rows(page: Dictionary, rows: Array) -> void:
	page["rows"] = rows
	page["loading"] = false
	page["error"] = ""
	page["first"] = clampi(int(page["first"]), 0, maxi(rows.size() - PAGE_ROWS, 0))
	page["cursor"] = clampi(int(page["cursor"]), 0, maxi(rows.size() - 1, 0))


func set_error(page: Dictionary, message: String) -> void:
	page["rows"] = []
	page["loading"] = false
	page["error"] = message


# --- paging and the cursor -----------------------------------------------------------------------------

## The rows now on screen: [{index, row}], index being the position in the page's list.
func visible(page: Dictionary = {}) -> Array:
	var p := current() if page.is_empty() else page
	var rows: Array = p["rows"]
	var out: Array = []
	for i in range(int(p["first"]), mini(int(p["first"]) + PAGE_ROWS, rows.size())):
		out.append({"index": i, "row": rows[i]})
	return out


func page_count(page: Dictionary = {}) -> int:
	var p := current() if page.is_empty() else page
	return maxi(1, ceili(float((p["rows"] as Array).size()) / PAGE_ROWS))


func page_number(page: Dictionary = {}) -> int:
	var p := current() if page.is_empty() else page
	return int(p["first"]) / PAGE_ROWS + 1


## Scroll a whole page (dir +1 / -1); the cursor goes with it.
func page_move(dir: int) -> void:
	var p := current()
	var rows: Array = p["rows"]
	var max_first := maxi(rows.size() - PAGE_ROWS, 0)
	p["first"] = clampi(int(p["first"]) + dir * PAGE_ROWS, 0, max_first)
	p["cursor"] = clampi(int(p["cursor"]), int(p["first"]), mini(int(p["first"]) + PAGE_ROWS - 1, maxi(rows.size() - 1, 0)))


## Move the cursor a row; the window follows it.
func cursor_move(dir: int) -> void:
	var p := current()
	var rows: Array = p["rows"]
	if rows.is_empty():
		return
	var c := clampi(int(p["cursor"]) + dir, 0, rows.size() - 1)
	p["cursor"] = c
	if c < int(p["first"]):
		p["first"] = c
	elif c >= int(p["first"]) + PAGE_ROWS:
		p["first"] = c - PAGE_ROWS + 1


## The row under the cursor, or {}.
func cursor_row() -> Dictionary:
	var p := current()
	var rows: Array = p["rows"]
	var c := int(p["cursor"])
	return rows[c] if c >= 0 and c < rows.size() else {}


## The row at an index of the visible window (0..PAGE_ROWS-1), or {}.
func row_at_slot(slot: int) -> Dictionary:
	var p := current()
	var i := int(p["first"]) + slot
	var rows: Array = p["rows"]
	if slot < 0 or slot >= PAGE_ROWS or i >= rows.size():
		return {}
	p["cursor"] = i
	return rows[i]


# --- row builders --------------------------------------------------------------------------------------

static func row(text: String, act: String, arg: Variant = null, sub := "") -> Dictionary:
	return {"text": text, "sub": sub, "act": act, "arg": arg}


static func home_rows(signed_in: bool, station_count: int, now_on: bool) -> Array:
	var rows: Array = []
	if now_on:
		rows.append(row("Now playing", "open", NOW))
	if signed_in:
		rows.append(row("Artists", "open", LETTERS))
		for k: Array in ALBUM_KINDS:
			rows.append(row(k[0], "albums", k[1]))
		rows.append(row("Playlists", "open", PLAYLISTS))
		rows.append(row("Search", "open", SEARCH))
	else:
		rows.append(row("Not signed in", "none", null, "open the TAB menu: Server"))
	rows.append(row("Radio", "open", RADIO, "%d station%s" % [station_count, "" if station_count == 1 else "s"]))
	return rows


## The home page of the CD and TAPE functions: what is in the bay, its tracks, EJECT, and the way to NET.
static func media_home_rows(mode_name: String, has_media: bool, label: String, track_count: int, now_on: bool) -> Array:
	var rows: Array = []
	if now_on:
		rows.append(row("Now playing", "open", NOW))
	if has_media:
		rows.append(row(label if label != "" else ("Disc" if mode_name == "CD" else "Cassette"), "none", null,
			"%d track%s" % [track_count, "" if track_count == 1 else "s"]))
		if track_count > 0:
			rows.append(row("Tracks", "open", TRACKS))
		rows.append(row("Eject", "eject"))
	else:
		rows.append(row("No disc" if mode_name == "CD" else "No cassette", "none", null, "put one in the bay below"))
	rows.append(row("Internet (NET)", "mode", 2))
	return rows


## A..Z and # (everything else), as rows for the letters page.
static func letter_rows() -> Array:
	var rows: Array = []
	for code in range(65, 91):
		rows.append(row(char(code), "letter", char(code)))
	rows.append(row("#", "letter", "#"))
	return rows


## The sort letter of an artist's name: its first letter, an article skipped, "#" for a digit or a symbol.
static func letter_of(name: String) -> String:
	var n := name.strip_edges().to_upper()
	for article in ["THE ", "A ", "AN "]:
		if n.begins_with(article) and n.length() > article.length() + 1:
			n = n.substr(article.length())
			break
	if n.is_empty():
		return "#"
	var c := n.substr(0, 1)
	return c if c >= "A" and c <= "Z" else "#"


static func artist_rows(artists: Array, letter: String) -> Array:
	var rows: Array = []
	for a: Dictionary in artists:
		if letter_of(str(a["name"])) == letter:
			rows.append(row(str(a["name"]), "artist", a["id"], "%d album%s" % [a["albums"], "" if a["albums"] == 1 else "s"]))
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["text"]).naturalnocasecmp_to(str(y["text"])) < 0)
	return rows


static func album_rows(albums: Array, with_artist := true) -> Array:
	var rows: Array = []
	for a: Dictionary in albums:
		var sub := ""
		if with_artist and not str(a["artist"]).is_empty():
			sub = str(a["artist"])
		if int(a["year"]) > 0:
			sub += (" · " if not sub.is_empty() else "") + str(a["year"])
		rows.append(row(str(a["name"]), "album", a["id"], sub))
	return rows


## An album page: a "play all" row, then its songs.
static func song_rows(songs: Array, play_all_label := "▶ Play all") -> Array:
	var rows: Array = []
	if songs.is_empty():
		return rows
	rows.append(row(play_all_label, "play_all", 0, "%d track%s" % [songs.size(), "" if songs.size() == 1 else "s"]))
	var i := 0
	for s: Dictionary in songs:
		var num := "%d. " % s["track"] if int(s["track"]) > 0 else ""
		var dur := preload("res://mods/xenu.subsonic/scripts/sb_api.gd").format_time(int(s["duration"]))
		rows.append(row(num + str(s["title"]), "play_song", i, "%s · %s" % [str(s["artist"]), dur] if not str(s["artist"]).is_empty() else dur))
		i += 1
	return rows


static func playlist_rows(lists: Array) -> Array:
	var rows: Array = []
	for p: Dictionary in lists:
		rows.append(row(str(p["name"]), "playlist", p["id"], "%d track%s" % [p["songs"], "" if p["songs"] == 1 else "s"]))
	return rows


static func station_rows(stations: Array, on_air: String = "") -> Array:
	var rows: Array = []
	for st: Dictionary in stations:
		var sub := "" if not st.has("source") else ("server" if st["source"] == "server" else "yours")
		rows.append(row(("● " if st["url"] == on_air else "") + str(st["name"]), "play_station", st["url"], sub))
	if rows.is_empty():
		rows.append(row("No stations yet", "none", null, "add them in the TAB menu: Radio"))
	return rows


## Search results as one list: artists, then albums, then songs (a song plays the song list from there).
static func result_rows(res: Dictionary) -> Array:
	var rows: Array = []
	for a: Dictionary in res["artists"]:
		rows.append(row(str(a["name"]), "artist", a["id"], "artist"))
	for a: Dictionary in res["albums"]:
		rows.append(row(str(a["name"]), "album", a["id"], "album · " + str(a["artist"])))
	var i := 0
	for s: Dictionary in res["songs"]:
		rows.append(row(str(s["title"]), "play_result", i, "%s · %s" % [s["artist"], s["album"]]))
		i += 1
	if rows.is_empty():
		rows.append(row("Nothing found", "none"))
	return rows


# --- the keyboard --------------------------------------------------------------------------------------

## Apply a key to the typed text: "DEL" removes the last character, "SPACE" adds a space, "GO" and anything else
## that is not a character is left to the caller (returned unchanged). Capped at 40 characters.
static func type_key(text: String, key: String) -> String:
	match key:
		"DEL":
			return text.substr(0, maxi(text.length() - 1, 0))
		"SPACE":
			return text if text.length() >= 40 or text.is_empty() else text + " "
		"GO":
			return text
	if key.length() != 1 or text.length() >= 40:
		return text
	return text + key.to_lower()
