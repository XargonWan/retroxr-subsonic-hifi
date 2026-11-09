## Pure-logic tests: the Subsonic API's URLs, auth and parsing (sb_api), radio (radio), the settings (sb_config)
## and the cache (sb_cache). Touches no node and no network:
##
##   godot --headless --path RetroXR --script res://mods/xenu.subsonic/tests/pure_tests.gd
##
## EXPECTED_CASES guards against a script error that stops the run early and still prints "0 failed".
extends SceneTree

const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")
const Radio = preload("res://mods/xenu.subsonic/scripts/radio.gd")
const Config = preload("res://mods/xenu.subsonic/scripts/sb_config.gd")
const Cache = preload("res://mods/xenu.subsonic/scripts/sb_cache.gd")

const EXPECTED_CASES := 101
const SCRATCH := "user://sb_pure_scratch"

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[sb-test] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[sb-test] FAIL ", what, ": got ", a, " want ", b)


func _init() -> void:
	_auth()
	_urls()
	_parsing()
	_radio()
	_config()
	_cache()
	print("[sb-test] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[sb-test] FAIL expected %d cases, ran %d (a script error stopped the run?)" % [EXPECTED_CASES, _cases])
		quit(1)
		return
	quit(1 if _failed > 0 else 0)


func _auth() -> void:
	# The worked example in the Subsonic API documentation: password "sesame", salt "c19b2d".
	_eq(Api.make_token("sesame", "c19b2d"), "26719a1196d2a940705a59634eb18eab", "token = md5(password + salt), the API's own example")
	_eq(Api.make_salt().length(), 12, "a salt is 12 hex characters")
	_check(Api.make_salt() != Api.make_salt(), "two salts differ")
	_eq(Api.normalize_server("audio.example.org"), "https://audio.example.org", "a bare host is https")
	_eq(Api.normalize_server("  https://audio.example.org/ "), "https://audio.example.org", "trailing slash and spaces go")
	_eq(Api.normalize_server("192.168.1.20:4533"), "http://192.168.1.20:4533", "a LAN address with a port is http")
	_eq(Api.normalize_server("localhost"), "http://localhost", "localhost is http")
	_eq(Api.normalize_server("http://nas.lan/music/rest"), "http://nas.lan/music", "a /rest tail is dropped")
	_eq(Api.normalize_server(""), "", "empty stays empty")


func _urls() -> void:
	var call: Array = Api.stream("abc 1", "mp3", 192)
	var u := Api.url("https://h", call[0], "RetroXR", "tok", "sal", call[1])
	_check(u.begins_with("https://h/rest/stream.view?u=RetroXR&t=tok&s=sal&v=1.16.1&c=RetroXR&f=json"), "the auth pairs come first: " + u)
	_check(u.ends_with("&id=abc%201&format=mp3&maxBitRate=192"), "the call's own pairs are encoded and ordered: " + u)
	var raw: Array = Api.stream("7")
	_eq(Api.query(raw[1]), "id=7&format=raw", "stream with no format asks for the raw file")
	_eq(Api.query((Api.stream("7", "", 128))[1]), "id=7&format=raw", "a bitrate cap without a transcode format is not sent")
	var red := Api.redact(u)
	_check(not red.contains("tok") and not red.contains("sal"), "redact hides token and salt: " + red)
	_check(red.contains("u=RetroXR") and red.contains("id=abc%201"), "redact keeps the user and the call")
	_check(Api.redact("https://h/rest/ping.view?u=a&p=secret&v=1").contains("p=***"), "redact hides a clear password")
	_eq(Api.query([["songId", 1], ["songId", 2]]), "songId=1&songId=2", "a key may repeat")
	_eq(Api.search("a&b")[1][0][1], "a&b", "search keeps the raw text for the encoder")
	_check(Api.query(Api.search("a&b")[1]).begins_with("query=a%26b"), "and the encoder escapes it")


func _parsing() -> void:
	var failed := Api.parse_response({"subsonic-response": {"status": "failed", "error": {"code": 40, "message": "Wrong username or password"}}})
	_check(not failed["ok"] and failed["code"] == 40 and failed["message"].begins_with("Wrong"), "a failed answer carries its error")
	_check(not Api.parse_response("nope")["ok"], "not a Subsonic answer is not ok")
	var ok := Api.parse_response({"subsonic-response": {"status": "ok", "version": "1.16.1"}})
	_check(ok["ok"], "an ok answer is ok")

	var artists := Api.artists({"artists": {"index": [
		{"name": "A", "artist": [{"id": "ar1", "name": "ABBA", "albumCount": 3}, {"id": "ar2", "name": "AC/DC", "albumCount": 1}]},
		{"name": "B", "artist": {"id": "ar3", "name": "Bjork"}}]}})
	_eq(artists.size(), 3, "three artists across two index letters (one given as a single object)")
	_eq(artists[0], {"id": "ar1", "name": "ABBA", "albums": 3}, "an artist row")
	_eq(artists[2]["name"], "Bjork", "a single object is read as a list of one")
	_eq(Api.artists({}).size(), 0, "no artists key is an empty list")

	var al := Api.artist_albums({"artist": {"name": "ABBA", "album": [
		{"id": "al1", "name": "Arrival", "artist": "ABBA", "year": 1976, "songCount": 10, "duration": 2400, "coverArt": "al-al1"}]}})
	_eq(al["artist"], "ABBA", "the artist's name")
	_eq(al["albums"][0], {"id": "al1", "name": "Arrival", "artist": "ABBA", "year": 1976, "songs": 10, "duration": 2400, "cover": "al-al1"}, "an album row")
	_eq(Api.album_list({"albumList2": {"album": [{"id": "x", "name": "N"}]}})[0]["name"], "N", "getAlbumList2 rows")

	var songs := Api.album_songs({"album": {"name": "Arrival", "artist": "ABBA", "coverArt": "c1", "song": [
		{"id": "s3", "title": "Three", "track": 3, "discNumber": 1, "duration": 200, "suffix": "flac"},
		{"id": "s1", "title": "One", "track": 1, "discNumber": 1, "duration": 180, "suffix": "mp3", "size": 5000, "bitRate": 320},
		{"id": "s9", "title": "Disc two", "track": 1, "discNumber": 2, "duration": 100, "suffix": "mp3"}]}})
	_eq(songs["songs"].map(func(s: Dictionary) -> String: return s["id"]), ["s1", "s3", "s9"], "songs come in disc, track order")
	_eq(songs["songs"][0]["bitrate"], 320, "a song's bitrate")
	_eq(songs["cover"], "c1", "the album's cover id")

	var found := Api.search_results({"searchResult3": {"artist": [{"id": "a", "name": "Aha"}], "song": [{"id": "s", "title": "T"}]}})
	_eq([found["artists"].size(), found["albums"].size(), found["songs"].size()], [1, 0, 1], "search3 results by kind")
	var pls := Api.playlists({"playlists": {"playlist": [{"id": "p1", "name": "Mix", "songCount": 4, "duration": 800}]}})
	_eq(pls[0], {"id": "p1", "name": "Mix", "songs": 4, "duration": 800}, "a playlist row")
	_eq(Api.playlist_songs({"playlist": {"name": "Mix", "entry": [{"id": "s1", "title": "One"}]}})["songs"][0]["title"], "One", "a playlist's songs")

	_eq(Api.cache_name({"id": "s1", "suffix": "FLAC"}), "s1.flac", "cache name: id + lower-case suffix")
	_eq(Api.cache_name({"id": "../../etc/passwd", "suffix": "mp3"}), "______etc_passwd.mp3", "cache name: nothing from the server can be a path")
	_eq(Api.cache_name({"id": "s1", "suffix": "flac"}, "mp3"), "s1.mp3", "cache name: a transcode names its own format")
	_eq(Api.cache_name({"id": "", "suffix": ""}), "unknown.audio", "cache name: empty id and suffix")
	_eq(Api.format_time(187), "3:07", "m:ss")
	_eq(Api.format_time(3729), "1:02:09", "h:mm:ss")
	_eq(Api.format_time(-4), "0:00", "never negative")


func _radio() -> void:
	_eq(Radio.make_station("  Jazz  ", "https://x.org/live.mp3"), {"name": "Jazz", "url": "https://x.org/live.mp3"}, "a station row")
	_eq(Radio.make_station("", "http://radio.example.org:8000/stream")["name"], "radio.example.org:8000", "no name -> the host")
	_check(Radio.make_station("x", "ftp://x").is_empty(), "only http(s)")
	_check(Radio.make_station("x", "https://a b").is_empty(), "no spaces in a url")
	_eq(Radio.make_station("A".repeat(80), "https://x.org/s")["name"].length(), Radio.MAX_NAME, "a long name is cut")
	var cleaned := Radio.clean_stations([{"name": "A", "url": "https://a/1"}, {"name": "dup", "url": "https://a/1"}, "junk", {"url": "nope"}, {"name": "B", "url": "https://b/2"}])
	_eq(cleaned.map(func(s: Dictionary) -> String: return s["name"]), ["A", "B"], "clean_stations drops junk and repeats")
	_eq(Radio.clean_stations("not a list"), [], "a non-list is empty")
	_check(Radio.is_playlist_url("https://x/p/playlist.pls?x=1") and Radio.is_playlist_url("http://x/a.M3U"), "playlist addresses")
	_check(not Radio.is_playlist_url("https://x/radio.mp3"), "a stream is not a playlist")
	_eq(Radio.parse_pls("[playlist]\nNumberOfEntries=2\nFile1=https://x/a\nTitle1=A\nFile2=http://x/b\nfile3=notaurl\n"), PackedStringArray(["https://x/a", "http://x/b"]), "pls files")
	_eq(Radio.parse_m3u("#EXTM3U\n#EXTINF:-1,Name\nhttps://x/a.mp3\n\nhttps://x/b\n"), PackedStringArray(["https://x/a.mp3", "https://x/b"]), "m3u lines")
	_eq(Radio.parse_m3u("rel/a.mp3\n", "https://h/p/list.m3u"), PackedStringArray(["https://h/p/rel/a.mp3"]), "a relative line resolves against the playlist")
	_eq(Radio.parse_m3u("#EXTM3U\n#EXT-X-TARGETDURATION:6\nseg1.ts\n", "https://h/live.m3u8"), PackedStringArray(["https://h/live.m3u8"]), "an HLS media playlist is the stream itself")
	_eq(Radio.azuracast_nowplaying_url("https://radio.example.org/public/radiodrome"), "https://radio.example.org/api/nowplaying/radiodrome", "public player -> nowplaying api")
	_eq(Radio.azuracast_nowplaying_url("https://radio.example.org/listen/radiodrome/radio.mp3"), "https://radio.example.org/api/nowplaying/radiodrome", "stream url -> nowplaying api")
	_eq(Radio.azuracast_nowplaying_url("https://example.org/stream.mp3"), "", "not an AzuraCast address")
	_eq(Radio.azuracast_nowplaying_url("ftp://x/public/y"), "", "wrong scheme")
	_check(Radio.is_azuracast_page("https://r.org/public/radiodrome") and Radio.is_azuracast_page("https://r.org/public/radiodrome/embed"), "a public player page is recognised")
	_check(not Radio.is_azuracast_page("https://r.org/listen/radiodrome/radio.mp3") and not Radio.is_azuracast_page("https://r.org/public/radiodrome/playlist.m3u"), "a stream and a playlist are not pages")
	_check(not Radio.is_azuracast_page("https://x.org/stream.mp3"), "an ordinary address is not a page")
	var np := Radio.parse_azuracast({"station": {"name": "RADIODROME", "listen_url": "https://r/listen/x/radio.mp3"},
		"now_playing": {"elapsed": 237, "duration": 671, "song": {"artist": "The Chemical Brothers", "title": "Push the Button", "text": "The Chemical Brothers - Push the Button", "art": "https://r/art/1"}},
		"playing_next": {"song": {"text": "Next - Song"}}, "live": {"is_live": false}})
	_eq([np["station"], np["artist"], np["title"], np["elapsed"], np["duration"], np["next_title"]], ["RADIODROME", "The Chemical Brothers", "Push the Button", 237, 671, "Next - Song"], "azuracast now-playing")
	_eq(np["listen_url"], "https://r/listen/x/radio.mp3", "and its stream url")
	_eq(Radio.parse_azuracast({"foo": 1}), {}, "not azuracast json is empty")
	_eq(Radio.split_stream_title("Daft Punk - One More Time"), {"artist": "Daft Punk", "title": "One More Time"}, "ICY title split")
	_eq(Radio.split_stream_title("Just a title"), {"artist": "", "title": "Just a title"}, "ICY title with no artist")


func _config() -> void:
	OS.set_environment("XENU_SB_SETTINGS", SCRATCH + "/settings.json")
	OS.set_environment("XENU_SB_CACHE", SCRATCH + "/cache")
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	DirAccess.remove_absolute(SCRATCH + "/settings.json")
	var s := Config.load_all()
	_eq(s["cache_mb"], 50, "the cache defaults to 50 MB")
	_eq(Config.cache_bytes(), 50 * 1024 * 1024, "and 50 MB is in bytes")
	_eq(s["stations"], [], "no stations to begin with")
	_check(not Config.has_login(s), "no login to begin with")
	_eq(Config.clamp_cache_mb(1), Config.CACHE_MB_MIN, "the cache is at least the minimum")
	_eq(Config.clamp_cache_mb(99999), Config.CACHE_MB_MAX, "and at most the maximum")
	_eq(Config.clamp_cache_mb("junk"), 50, "junk falls back to the default")
	_eq(Config.step_cache_mb(50, 1), 100, "stepper up from 50")
	_eq(Config.step_cache_mb(50, -1), 25, "stepper down from 50")
	_eq(Config.step_cache_mb(10, -1), 10, "stepper stops at the bottom")
	_eq(Config.step_cache_mb(2000, 1), 2000, "stepper stops at the top")
	_eq(Config.step_cache_mb(60, 1), 100, "a value between steps goes from the step below it")
	Config.set_value("server", "https://audio.example.org")
	Config.set_value("user", "RetroXR")
	Config.set_value("token", "t")
	Config.set_value("salt", "s")
	_check(Config.has_login(Config.load_all()), "a login with server, user, token and salt")
	Config.forget_login()
	var after := Config.load_all()
	_check(not Config.has_login(after) and after["user"] == "RetroXR", "forget_login drops salt and token, keeps who")
	_check(not FileAccess.get_file_as_string(SCRATCH + "/settings.json").contains("password"), "no password key is ever written")
	Config.add_station("Jazz", "https://j/live")
	Config.add_station("Rock", "https://r/live")
	Config.add_station("Jazz FM", "https://j/live")
	var list: Array = Config.load_all()["stations"]
	_eq(list.map(func(x: Dictionary) -> String: return x["name"]), ["Jazz FM", "Rock"], "adding a known url renames it, order kept")
	Config.add_station("bad", "nope")
	_eq(Config.load_all()["stations"].size(), 2, "an invalid station is refused")
	_eq(Config.remove_station("https://j/live").size(), 1, "a station is removed by url")
	Config.set_value("cache_mb", 100)
	_eq(Config.cache_bytes(), 100 * 1024 * 1024, "the cache size is saved")


func _write(path: String, size: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1]) if size == 1 else _bytes(size))


func _bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


func _cache() -> void:
	var dir := SCRATCH + "/lru"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	_write(dir + "/stale.mp3.part", 10)
	var c: RefCounted = Cache.open(dir, 250)
	_check(not FileAccess.file_exists(dir + "/stale.mp3.part"), "an unfinished download is dropped at open")
	for n in ["a.mp3", "b.mp3", "c.mp3"]:
		_write(c.part_path(n), 100)
		_check(c.commit(n), "commit %s" % n)
	_eq(c.total_bytes(), 300, "three files of 100 bytes")
	_check(c.has("a.mp3") and not c.has("nope.mp3"), "has")
	c.touch("a.mp3")                          # a is now the youngest; b is the oldest
	var gone: PackedStringArray = c.trim([])
	_eq(Array(gone), ["b.mp3"], "trim removes the least recently used first")
	_eq(c.total_bytes(), 200, "and stops once under the cap")
	_write(c.part_path("d.mp3"), 100)
	c.commit("d.mp3")                         # 300 again; oldest is c
	gone = c.trim(["c.mp3"])
	_eq(Array(gone), ["a.mp3"], "a protected file is skipped, the next oldest goes")
	_check(c.has("c.mp3") and c.has("d.mp3"), "protected and young files stay")
	c.set_cap(50)
	gone = c.trim(["c.mp3", "d.mp3"])
	_eq(gone.size(), 0, "when the protected files alone exceed the cap nothing protected is removed")
	_write(c.part_path("empty.mp3"), 0)
	_check(not c.commit("empty.mp3") and not c.has("empty.mp3"), "an empty download is refused")
	var reopened: RefCounted = Cache.open(dir, 250)
	reopened.touch("d.mp3")
	_write(reopened.part_path("e.mp3"), 100)
	reopened.commit("e.mp3")
	_eq(Array(reopened.trim([])), ["c.mp3"], "recency survives a reopen (index.json)")
	_eq(Array(reopened.clear(["e.mp3"])), ["d.mp3"], "clear keeps what is protected")
	_check(not reopened.names().has("index.json"), "the index is not a cached file")
