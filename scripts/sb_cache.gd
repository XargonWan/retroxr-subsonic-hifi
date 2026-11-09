## The track cache: a folder of downloaded songs held under a byte cap, least recently used out first.
##
## Pure files, no node: the client downloads into `part_path(name)` and calls `commit(name)`; the player asks
## `has` / `path` / `touch`; `trim(protect)` brings the folder back under the cap WITHOUT touching the names it is
## told to protect (what is playing and what is queued next: a file being played is never pulled from under libVLC).
##
## Recency is a counter kept in index.json beside the files, not a file time (Godot cannot set one, and a counter
## makes the order exact in a test). A file not in the index counts as oldest. A `.part` left by a download that
## never finished is deleted when the cache is opened.
extends RefCounted

const INDEX_NAME := "index.json"
const PART_SUFFIX := ".part"

var dir := ""
var cap_bytes := 50 * 1024 * 1024
var _clock := 0
var _used: Dictionary = {}     # name -> counter at its last use


static func open(a_dir: String, a_cap_bytes: int) -> RefCounted:
	var c: RefCounted = load("res://mods/xenu.subsonic/scripts/sb_cache.gd").new()
	c.dir = a_dir
	c.cap_bytes = maxi(a_cap_bytes, 0)
	DirAccess.make_dir_recursive_absolute(a_dir)
	c._load_index()
	c._drop_partials()
	return c


func path(name: String) -> String:
	return dir.path_join(name)


func part_path(name: String) -> String:
	return dir.path_join(name + PART_SUFFIX)


func has(name: String) -> bool:
	return size_of(name) > 0


func size_of(name: String) -> int:
	var f := FileAccess.open(path(name), FileAccess.READ)
	return 0 if f == null else int(f.get_length())


## Note a use of `name` (a play or a prefetch hit): it moves to the young end.
func touch(name: String) -> void:
	_clock += 1
	_used[name] = _clock
	_save_index()


## A finished download: `<name>.part` becomes `<name>`. False (and the part removed) when it is empty.
func commit(name: String) -> bool:
	var part := part_path(name)
	var f := FileAccess.open(part, FileAccess.READ)
	var bytes := 0 if f == null else int(f.get_length())
	f = null
	if bytes <= 0:
		DirAccess.remove_absolute(part)
		print("[Subsonic] cache: %s came down empty, dropped" % name)
		return false
	var err := DirAccess.rename_absolute(part, path(name))
	if err != OK:
		print("[Subsonic] cache: could not move %s into place (error %d)" % [name, err])
		DirAccess.remove_absolute(part)
		return false
	touch(name)
	return true


func names() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f != INDEX_NAME and not f.ends_with(PART_SUFFIX):
			out.append(f)
	return out


func total_bytes() -> int:
	var total := 0
	for n in names():
		total += size_of(n)
	return total


## Delete the least recently used files until the folder is within the cap, never the ones in `protect`.
## Returns the names removed. If the protected files alone exceed the cap it stops there and says so.
func trim(protect: Array = []) -> PackedStringArray:
	var removed := PackedStringArray()
	var total := total_bytes()
	if total <= cap_bytes:
		return removed
	var order: Array = Array(names())
	order.sort_custom(func(a: String, b: String) -> bool:
		var ua := int(_used.get(a, 0))
		var ub := int(_used.get(b, 0))
		return ua < ub if ua != ub else a < b)
	for n: String in order:
		if total <= cap_bytes:
			break
		if n in protect:
			continue
		var sz := size_of(n)
		if DirAccess.remove_absolute(path(n)) == OK:
			total -= sz
			_used.erase(n)
			removed.append(n)
	if total > cap_bytes:
		print("[Subsonic] cache: %d bytes held against a cap of %d (what is playing is kept)" % [total, cap_bytes])
	if not removed.is_empty():
		print("[Subsonic] cache: trimmed %d file(s) to fit %d bytes" % [removed.size(), cap_bytes])
		_save_index()
	return removed


## Delete everything but `protect`. Returns the names removed.
func clear(protect: Array = []) -> PackedStringArray:
	var removed := PackedStringArray()
	for n in names():
		if n in protect:
			continue
		if DirAccess.remove_absolute(path(n)) == OK:
			_used.erase(n)
			removed.append(n)
	_save_index()
	print("[Subsonic] cache: cleared %d file(s)" % removed.size())
	return removed


func set_cap(bytes: int) -> void:
	cap_bytes = maxi(bytes, 0)


# --- the index -----------------------------------------------------------------------------------------

func _load_index() -> void:
	var f := FileAccess.open(dir.path_join(INDEX_NAME), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	_clock = int((parsed as Dictionary).get("clock", 0))
	var used: Variant = (parsed as Dictionary).get("used", {})
	if used is Dictionary:
		for k: Variant in (used as Dictionary):
			_used[str(k)] = int((used as Dictionary)[k])


func _save_index() -> void:
	var f := FileAccess.open(dir.path_join(INDEX_NAME), FileAccess.WRITE)
	if f == null:
		print("[Subsonic] cache: could not write the index in %s" % dir)
		return
	f.store_string(JSON.stringify({"clock": _clock, "used": _used}))


func _drop_partials() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(PART_SUFFIX):
			DirAccess.remove_absolute(dir.path_join(f))
			print("[Subsonic] cache: removed an unfinished download (%s)" % f)
