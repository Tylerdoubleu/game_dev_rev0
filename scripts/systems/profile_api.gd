class_name ProfileApi
extends Node
## v0.7 client helper for the anonymous profile API (server/profile_store.js, docs/NETWORK_EVENTS.md "v0.7 profile API").
## Add as a child, then call ensure_profile() / fetch_profile() / set_callsign() / save_career() / solo_award().
## The private token lives in user://profile.cfg (IndexedDB on the web build; clearing browser data loses the profile).
## After a create/load it is handed to NetworkLobby.set_profile_token() so the server can award online clout.
## Every reply arrives on `completed(action, status, data)`; e.g. set_callsign -> status 409 + {"error":"callsign_taken"}.
## API base: the same server NetworkLobby plays on (resolve_api_base), so a page served from test.jeetball.com saves to test.
## set_callsign / save_career / solo_award create a profile first when none is saved (completed("create", 201, ...) is
## emitted as usual), then continue. On a 401 the saved token is forgotten (memory + user://profile.cfg); those three
## actions then create a fresh profile once and retry once, so callers normally see only the retried reply.

signal completed(action: String, status: int, data: Dictionary)

const CFG_PATH := "user://profile.cfg"
var api_base: String = ""
var token: String = ""
var profile_id: String = ""
var profile: Dictionary = {}
var _creating := false
var _after_create: Array[Callable] = []
var _last_call: Dictionary = {}  # action -> [path, method, body] of the latest auto-create action, for the 401 retry
var _retrying: Dictionary = {}  # action -> true while its one 401 retry is in flight
var _retry_spent: Dictionary = {}  # action -> true after a retry still got 401; cleared by its next non-401 reply

const AUTO_CREATE_ACTIONS := ["set_callsign", "save_career", "solo_award"]

func _ready() -> void:
	if api_base.is_empty():
		api_base = resolve_api_base(get_node_or_null("/root/NetworkLobby"))
	_load()
	_share_token()

## The NetworkLobby server as an http(s) API base: current_ws_url when it came from ?server= / LOBBY_WS_URL / --server,
## else default_ws_url (stamped SERVER_URL; on the web the page's own host /ws unless github.io/itch; else live).
static func resolve_api_base(lobby: Object) -> String:
	if lobby == null:
		return LobbyBrowser.derive_api_base()
	var ws := String(lobby.get("current_ws_url")) if bool(lobby.get("server_from_url")) else String(lobby.get("default_ws_url"))
	return api_base_from_ws(ws) if not ws.strip_edges().is_empty() else LobbyBrowser.derive_api_base()

## "wss://test.jeetball.com/ws" -> "https://test.jeetball.com"; "ws://127.0.0.1:8080/ws" -> "http://127.0.0.1:8080".
static func api_base_from_ws(ws_url: String) -> String:
	return LobbyBrowser.derive_api_base(ws_url.strip_edges())

func has_profile() -> bool:
	return not token.is_empty()

## Creates a profile if none is saved, otherwise fetches the saved one.
func ensure_profile() -> void:
	if has_profile():
		fetch_profile()
	else:
		create_profile()

func create_profile() -> void:
	_creating = true
	_request("create", "/api/profile", HTTPClient.METHOD_POST, {})

func fetch_profile() -> void:
	_request("get", "/api/profile", HTTPClient.METHOD_GET, null)

func set_callsign(callsign: String) -> void:
	_authed("set_callsign", "/api/profile/callsign", HTTPClient.METHOD_PUT, {"callsign": callsign})

## career: opaque Dictionary (<= 32 KB as JSON), owned by career mode.
func save_career(career: Dictionary) -> void:
	_authed("save_career", "/api/profile/career", HTTPClient.METHOD_PUT, {"career": career})

## Solo clout (client-reported): kind "star" | "challenge" | "tier", id 1-64 chars of A-Z a-z 0-9 _ . : -
## Reply data: {awarded, clout, clout_by_source:{online, solo}}; 400 bad kind/id, 429 over 60/min.
func solo_award(kind: String, id: String) -> void:
	_authed("solo_award", "/api/profile/solo_award", HTTPClient.METHOD_POST, {"kind": kind, "id": id})

func fetch_public(callsign: String) -> void:
	_request("public", "/api/profile/public/" + callsign.uri_encode(), HTTPClient.METHOD_GET, null)

## Auto-creates a profile first when there is no token (one create shared by every call waiting on it).
func _authed(action: String, path: String, method: int, body) -> void:
	_last_call[action] = [path, method, body]
	if has_profile() and not _creating:
		_request(action, path, method, body)
		return
	_after_create.append(func(ok: bool, status: int, d: Dictionary) -> void:
		if ok:
			_request(action, path, method, body)
		else:
			_retrying.erase(action)
			completed.emit(action, status, d))
	if not _creating:
		create_profile()

## Subclasses (tests) may override this with canned replies; they must hand them to _on_reply().
func _request(action: String, path: String, method: int, body) -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty() and action != "create":
		headers.append("Authorization: Bearer " + token)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		http.queue_free()
		var data = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else {}
		var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
		_on_reply(action, code, d))
	var err := http.request(api_base + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		_on_reply(action, 0, {"error": "request_failed"})

func _on_reply(action: String, code: int, d: Dictionary) -> void:
	if code == 401 and action != "create":
		_forget_token()
		if action in AUTO_CREATE_ACTIONS and not _retrying.has(action) and not _retry_spent.has(action) and _last_call.has(action):
			_retrying[action] = true
			var c: Array = _last_call[action]
			_authed(action, c[0], c[1], c[2])
			return
		if _retrying.has(action):
			_retry_spent[action] = true  # a caller's own immediate re-try won't start a second create/retry round
	else:
		_retry_spent.erase(action)
	_retrying.erase(action)
	if action == "create" and code == 201:
		token = String(d.get("token", ""))
		profile_id = String(d.get("profile_id", ""))
		d.erase("token")
		_save()
		_share_token()
	if code == 200 and action in ["get", "set_callsign", "save_career"]:
		profile = d
	elif code == 200 and action == "solo_award" and not profile.is_empty():
		profile["clout"] = d.get("clout", profile.get("clout", 0))
		profile["clout_by_source"] = d.get("clout_by_source", profile.get("clout_by_source", {}))
	completed.emit(action, code, d)
	if action == "create":
		_creating = false
		var ok := code == 201 and has_profile()
		var waiting := _after_create.duplicate()
		_after_create.clear()
		for cb in waiting:
			(cb as Callable).call(ok, code, d)

## The server no longer knows this token (e.g. test data wiped): forget it so the next call makes a new profile.
func _forget_token() -> void:
	token = ""
	profile_id = ""
	profile = {}
	_save()
	_share_token()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		token = String(cfg.get_value("profile", "token", ""))
		profile_id = String(cfg.get_value("profile", "profile_id", ""))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "token", token)
	cfg.set_value("profile", "profile_id", profile_id)
	cfg.save(CFG_PATH)

func _share_token() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and nl.has_method("set_profile_token"):
		nl.call("set_profile_token", token)
