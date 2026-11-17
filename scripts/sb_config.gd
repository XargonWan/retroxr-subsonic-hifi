## Where the hi-fi keeps what it needs between launches: the server, who signed in, the salt + token that sign-in
## gave, the cache size and the radio stations. One file for the mod (`user://mods/xenu.subsonic/settings.json`),
## never the room's save slot: slots are shared, and salt + token are a key to somebody's library.
##
## THE PASSWORD IS NEVER WRITTEN. It lives in the menu's field while typed and in the derivation of (salt, token)
## at sign-in; the pair is what is kept. `forget_login()` throws it away.
##
## The environment redirects the files for tests (XENU_SB_SETTINGS, XENU_SB_CACHE): a test never touches the
## player's real settings or cache.
extends RefCounted

const Radio = preload("res://mods/xenu.subsonic/scripts/radio.gd")

const MOD_ID := "xenu.subsonic"
const FILE := "user://mods/xenu.subsonic/settings.json"
const CACHE_DIR := "user://mods/xenu.subsonic/cache"

const CACHE_MB_DEFAULT := 50
## The steps the TAB menu offers (MB). Any value in the file is clamped into the range.
const CACHE_MB_STEPS := [10, 25, 50, 100, 250, 500, 1000, 2000]
const CACHE_MB_MIN := 10
const CACHE_MB_MAX := 2000


static func _file() -> String:
	var over := OS.get_environment("XENU_SB_SETTINGS")
	return over if not over.is_empty() else FILE


static func cache_dir() -> String:
	var over := OS.get_environment("XENU_SB_CACHE")
	return over if not over.is_empty() else CACHE_DIR


static func load_all() -> Dictionary:
	var s: Dictionary = JsonStore.read_dict(_file(), MOD_ID)
	var url := OS.get_environment("XENU_SB_URL")
	if not url.is_empty():
		s["server"] = url
	s["cache_mb"] = clamp_cache_mb(s.get("cache_mb", CACHE_MB_DEFAULT))
	s["stations"] = Radio.clean_stations(s.get("stations", []))
	s["server_stations"] = Radio.clean_stations(s.get("server_stations", []))
	return s


static func save_all(s: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_file().get_base_dir())
	if not JsonStore.write_dict(_file(), s, MOD_ID):
		push_warning("[Subsonic] could not write %s" % _file())


## Change one key and write the file. null or "" removes the key.
static func set_value(key: String, value: Variant) -> void:
	var s := load_all()
	if value == null or (value is String and (value as String).is_empty()):
		s.erase(key)
	else:
		s[key] = value
	save_all(s)


static func clamp_cache_mb(v: Variant) -> int:
	var n := CACHE_MB_DEFAULT
	if v is int or v is float:
		n = int(v)
	return clampi(n, CACHE_MB_MIN, CACHE_MB_MAX)


static func cache_bytes() -> int:
	return int(load_all()["cache_mb"]) * 1024 * 1024


## The next step up (dir +1) or down (-1) from `mb` on the TAB menu's list.
static func step_cache_mb(mb: int, dir: int) -> int:
	var steps: Array = CACHE_MB_STEPS
	var best := 0
	for i in steps.size():
		if int(steps[i]) <= mb:
			best = i
	return int(steps[clampi(best + dir, 0, steps.size() - 1)])


static func has_login(s: Dictionary) -> bool:
	return not str(s.get("server", "")).is_empty() and not str(s.get("user", "")).is_empty() \
		and not str(s.get("token", "")).is_empty() and not str(s.get("salt", "")).is_empty()


static func forget_login() -> void:
	var s := load_all()
	s.erase("token")
	s.erase("salt")
	s.erase("server_stations")
	save_all(s)


## Add (or rename, if the url is known) a station. Returns the cleaned list.
static func add_station(name: String, url: String) -> Array:
	var st := Radio.make_station(name, url)
	var s := load_all()
	var list: Array = s["stations"]
	if st.is_empty():
		return list
	for i in list.size():
		if (list[i] as Dictionary)["url"] == st["url"]:
			list[i] = st
			s["stations"] = list
			save_all(s)
			return list
	list.append(st)
	s["stations"] = Radio.clean_stations(list)
	save_all(s)
	return s["stations"]


static func remove_station(url: String) -> Array:
	var s := load_all()
	var list: Array = []
	for st: Dictionary in s["stations"]:
		if st["url"] != url:
			list.append(st)
	s["stations"] = list
	save_all(s)
	return list


# --- what was playing -----------------------------------------------------------------------------------

## The longest queue kept between launches (a window of it round the track on, when it is longer).
const LAST_QUEUE_MAX := 300
## The song fields kept, with the type each comes back as.
const _SONG_KEYS := {"id": "", "title": "?", "artist": "", "album": "", "track": 0, "disc": 1, "duration": 0,
	"suffix": "", "size": 0, "cover": "", "bitrate": 0}


## A saved queue, cleaned: only rows with an id, only the fields a song row has, each of its own type.
static func clean_queue(rows: Variant) -> Array:
	var out: Array = []
	if not (rows is Array):
		return out
	for r: Variant in rows:
		if not (r is Dictionary) or str((r as Dictionary).get("id", "")).is_empty():
			continue
		var song := {}
		for k: String in _SONG_KEYS:
			var def: Variant = _SONG_KEYS[k]
			var v: Variant = (r as Dictionary).get(k, def)
			song[k] = str(v) if def is String else int(v)
		out.append(song)
		if out.size() >= LAST_QUEUE_MAX:
			break
	return out


## The queue to write down and where the track on stands in it: the whole queue, or LAST_QUEUE_MAX of it from a little
## before the track on when it is longer.
static func window_queue(queue: Array, track: int) -> Dictionary:
	var start := 0
	if queue.size() > LAST_QUEUE_MAX:
		start = clampi(track - 20, 0, queue.size() - LAST_QUEUE_MAX)
	return {"queue": queue.slice(start, start + LAST_QUEUE_MAX), "track": track - start}
