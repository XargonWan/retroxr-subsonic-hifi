## The Subsonic REST client: one HTTPRequest per call, a callback per call, the sign-in as a ping with a freshly
## derived (salt, token).
##
## Every callback is `func(ok: bool, data: Variant, code: int)`. For `call_api`, `data` is the "subsonic-response"
## dictionary on success and the server's message (or ours) on failure; `code` is the HTTP status, or for a
## Subsonic-level failure the API's own error code (40 = wrong user/password, 70 = not found). 0 = no answer.
##
## A Subsonic server answers HTTP 200 even when it cannot serve a file (the body is then a JSON error), so a
## download is checked for that before it is called a success. Reachability is logged on its changes only; salt,
## token and password never reach a log (Api.redact).
extends Node

const Api = preload("res://mods/xenu.subsonic/scripts/sb_api.gd")

signal auth_failed
signal reachable_changed(reachable: bool)
## Signed in: `salt` and `token` are what to keep (never the password).
signal signed_in(user: String, salt: String, token: String)
signal sign_in_failed(message: String)

const TIMEOUT_SECONDS := 20.0
const DOWNLOAD_TIMEOUT_SECONDS := 120.0

var base := ""
var user := ""
var token := ""
var salt := ""
var reachable := true
var _inflight := 0


func configure(server: String, a_user: String = "", a_token: String = "", a_salt: String = "") -> void:
	base = Api.normalize_server(server)
	user = a_user
	token = a_token
	salt = a_salt


func has_login() -> bool:
	return not base.is_empty() and not user.is_empty() and not token.is_empty() and not salt.is_empty()


func inflight() -> int:
	return _inflight


## The URL of a call with this client's credentials (for libVLC, which cannot send headers). Never log it raw.
func url_for(call: Array) -> String:
	return Api.url(base, call[0], user, token, salt, call[1])


# --- sign in -------------------------------------------------------------------------------------------

## Derive (salt, token) from the password, ping with them, and keep them in this client on success. The password
## is used here and nowhere else: it is not stored, not logged, not sent.
func sign_in(a_user: String, password: String) -> void:
	if base.is_empty():
		sign_in_failed.emit("no server address")
		return
	var a_salt := Api.make_salt()
	var a_token := Api.make_token(password, a_salt)
	var ping := Api.ping()
	var url := Api.url(base, ping[0], a_user, a_token, a_salt, ping[1])
	_get_json(url, func(ok: bool, data: Variant, code: int) -> void:
		var r := Api.parse_response(data) if ok else {"ok": false, "code": code, "message": str(data)}
		if ok and r["ok"]:
			user = a_user
			salt = a_salt
			token = a_token
			print("[Subsonic] signed in as %s on %s" % [a_user, base])
			signed_in.emit(a_user, a_salt, a_token)
		else:
			var msg := _why(r)
			print("[Subsonic] sign-in refused: %s" % msg)
			sign_in_failed.emit(msg))


func _why(r: Dictionary) -> String:
	match int(r.get("code", -1)):
		40:
			return "wrong user name or password"
		41:
			return "this server does not accept token sign-in"
		0:
			return "no answer from the server"
	var m := str(r.get("message", ""))
	return m if not m.is_empty() else "the server refused"


# --- calls ---------------------------------------------------------------------------------------------

## A Subsonic call: `call` is [endpoint, pairs] from sb_api.
func call_api(call: Array, cb: Callable) -> void:
	if not has_login():
		_call(cb, false, "not signed in", 0)
		return
	var url := url_for(call)
	_get_json(url, func(ok: bool, data: Variant, code: int) -> void:
		if not ok:
			_call(cb, false, data, code)
			return
		var r := Api.parse_response(data)
		if r["ok"]:
			_call(cb, true, r["body"], 0)
			return
		print("[Subsonic] %s: %s (error %d)" % [call[0], r["message"], r["code"]])
		if r["code"] == 40 or r["code"] == 41:
			auth_failed.emit()
		_call(cb, false, _why(r), r["code"]))


## Raw bytes of a call that answers with a file (getCoverArt). The same 200-with-a-JSON-error check applies.
func fetch_bytes(call: Array, cb: Callable) -> void:
	if not has_login():
		_call(cb, false, "not signed in", 0)
		return
	_request(url_for(call), "", TIMEOUT_SECONDS, func(ok: bool, bytes: Variant, code: int) -> void:
		if ok and _is_json_error(bytes as PackedByteArray):
			print("[Subsonic] %s: the server answered with an error instead of a file" % call[0])
			_call(cb, false, "the server could not serve it", code)
			return
		_call(cb, ok, bytes, code))


## Download a call's file into `dest` (a cache part path). Streams to disk (a track is megabytes).
func download(call: Array, dest: String, cb: Callable) -> void:
	if not has_login():
		_call(cb, false, "not signed in", 0)
		return
	_request(url_for(call), dest, DOWNLOAD_TIMEOUT_SECONDS, func(ok: bool, _d: Variant, code: int) -> void:
		if ok and _file_is_json_error(dest):
			print("[Subsonic] %s: the server answered with an error instead of a file" % call[0])
			DirAccess.remove_absolute(dest)
			_call(cb, false, "the server could not serve it", code)
			return
		if not ok:
			DirAccess.remove_absolute(dest)
		_call(cb, ok, dest, code))


## A plain GET of any JSON address with no Subsonic credentials (radio now-playing); `data` is the parsed JSON.
func get_json(url: String, cb: Callable) -> void:
	_get_json(url, cb, false)


## A plain GET returning the text (a .pls / .m3u).
func get_text(url: String, cb: Callable) -> void:
	_request(url, "", TIMEOUT_SECONDS, func(ok: bool, bytes: Variant, code: int) -> void:
		_call(cb, ok, (bytes as PackedByteArray).get_string_from_utf8() if ok else bytes, code))


# --- the request ---------------------------------------------------------------------------------------

func _get_json(url: String, cb: Callable, _subsonic := true) -> void:
	_request(url, "", TIMEOUT_SECONDS, func(ok: bool, bytes: Variant, code: int) -> void:
		if not ok:
			_call(cb, false, bytes, code)
			return
		var parsed: Variant = JSON.parse_string((bytes as PackedByteArray).get_string_from_utf8())
		if parsed == null:
			print("[Subsonic] %s: the answer is not JSON" % Api.redact(url))
			_call(cb, false, "the server's answer was not understood", code)
			return
		_call(cb, true, parsed, code))


## One HTTP GET. On success `data` is the body bytes (or `dest` stays on disk when one is given); on failure a
## message. HTTP errors other than 2xx are failures with their status.
func _request(url: String, dest: String, timeout: float, cb: Callable) -> void:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = timeout
	http.max_redirects = 5
	if not dest.is_empty():
		http.download_file = dest
	add_child(http)
	_inflight += 1
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray) -> void:
		_inflight -= 1
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[Subsonic] %s: no answer (result %d)" % [Api.redact(url), result])
			_set_reachable(false)
			_call(cb, false, "no answer from the server", 0)
			return
		_set_reachable(true)
		if code < 200 or code >= 300:
			print("[Subsonic] %s: HTTP %d" % [Api.redact(url), code])
			if code == 401 or code == 403:
				auth_failed.emit()
			_call(cb, false, "HTTP %d" % code, code)
			return
		_call(cb, true, bytes, code))
	var err := http.request(url)
	if err != OK:
		_inflight -= 1
		http.queue_free()
		print("[Subsonic] request not sent (%s): error %d" % [Api.redact(url), err])
		_set_reachable(false)
		_call(cb, false, "request failed (%d)" % err, 0)


static func _is_json_error(bytes: PackedByteArray) -> bool:
	if bytes.size() == 0 or bytes.size() > 4096:
		return false
	var text := bytes.get_string_from_utf8().strip_edges()
	return text.begins_with("{") and text.contains("subsonic-response")


static func _file_is_json_error(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 4096:
		return false
	return _is_json_error(f.get_buffer(int(f.get_length())))


func _call(cb: Callable, ok: bool, data: Variant, code: int) -> void:
	if cb.is_valid():
		cb.call(ok, data, code)


func _set_reachable(r: bool) -> void:
	if r == reachable:
		return
	reachable = r
	print("[Subsonic] server %s" % ("reachable again" if r else "UNREACHABLE"))
	reachable_changed.emit(r)
