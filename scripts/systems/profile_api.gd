class_name ProfileApi
extends Node
## v0.7 client helper for the anonymous profile API (server/profile_store.js, docs/NETWORK_EVENTS.md "v0.7 profile API").
## Add as a child, then call ensure_profile() / fetch_profile() / set_callsign() / save_career().
## The private token lives in user://profile.cfg (IndexedDB on the web build; clearing browser data loses the profile).
## After a create/load it is handed to NetworkLobby.set_profile_token() so the server can award online clout.
## Every reply arrives on `completed(action, status, data)`; e.g. set_callsign -> status 409 + {"error":"callsign_taken"}.

signal completed(action: String, status: int, data: Dictionary)

const CFG_PATH := "user://profile.cfg"
var api_base: String = ""
var token: String = ""
var profile_id: String = ""
var profile: Dictionary = {}

func _ready() -> void:
	if api_base.is_empty():
		api_base = LobbyBrowser.derive_api_base()
	_load()
	_share_token()

func has_profile() -> bool:
	return not token.is_empty()

## Creates a profile if none is saved, otherwise fetches the saved one.
func ensure_profile() -> void:
	if has_profile():
		fetch_profile()
	else:
		create_profile()

func create_profile() -> void:
	_request("create", "/api/profile", HTTPClient.METHOD_POST, {})

func fetch_profile() -> void:
	_request("get", "/api/profile", HTTPClient.METHOD_GET, null)

func set_callsign(callsign: String) -> void:
	_request("set_callsign", "/api/profile/callsign", HTTPClient.METHOD_PUT, {"callsign": callsign})

## career: opaque Dictionary (<= 32 KB as JSON), owned by career mode.
func save_career(career: Dictionary) -> void:
	_request("save_career", "/api/profile/career", HTTPClient.METHOD_PUT, {"career": career})

func fetch_public(callsign: String) -> void:
	_request("public", "/api/profile/public/" + callsign.uri_encode(), HTTPClient.METHOD_GET, null)

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
		completed.emit(action, 0, {"error": "request_failed"})

func _on_reply(action: String, code: int, d: Dictionary) -> void:
	if action == "create" and code == 201:
		token = String(d.get("token", ""))
		profile_id = String(d.get("profile_id", ""))
		d.erase("token")
		_save()
		_share_token()
	elif action == "get" and code == 401:
		# The server no longer knows this token (e.g. test data wiped): forget it so ensure_profile() makes a new one.
		token = ""
		profile_id = ""
		_save()
	if code == 200 and action in ["get", "set_callsign", "save_career"]:
		profile = d
	completed.emit(action, code, d)

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
