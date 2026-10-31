extends SceneTree
## v0.7 ProfileApi: API base selection + auto-create / 401 recovery against a local node server it starts itself
## (server/server.js, AUTO_START_GODOT=0, temp DATA_DIR; killed by PID at the end). user://profile.cfg is restored after.
## Run: godot --headless --path . -s res://scripts/systems/test_profile_api.gd
const PORT := 19417
const BOGUS := "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
var fails: Array[String] = []
var events: Array = []
var server_pid := -1
var cfg_backup: Variant = null

class FakeLobby extends RefCounted:
	var server_from_url := false
	var current_ws_url := "ws://127.0.0.1:9080/ws"
	var default_ws_url := ""

## Canned replies (no HTTP, no user:// I/O): every authed call 401s while always_401.
class StubApi extends ProfileApi:
	var calls: Array = []
	var always_401 := true
	func _ready() -> void:
		pass
	func _save() -> void:
		pass
	func _request(action: String, _path: String, _method: int, _body) -> void:
		calls.append(action)
		if action == "create":
			_on_reply(action, 201, {"profile_id": "p_s", "token": "e".repeat(64)})
		else:
			_on_reply(action, 401 if always_401 else 200, {})

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _initialize() -> void:
	_run.call_deferred()

func _lobby(from_url: bool, current: String, def: String) -> FakeLobby:
	var l := FakeLobby.new()
	l.server_from_url = from_url
	l.current_ws_url = current
	l.default_ws_url = def
	return l

func _test_base() -> void:
	print("base selection")
	_check(ProfileApi.resolve_api_base(_lobby(false, "ws://127.0.0.1:9080/ws", "wss://test.jeetball.com/ws")) == "https://test.jeetball.com", "no ?server=: default_ws_url (stamped test) -> https://test.jeetball.com")
	_check(ProfileApi.resolve_api_base(_lobby(false, "wss://test.jeetball.com/ws", "wss://test.jeetball.com/ws")) == "https://test.jeetball.com", "unstamped page on test.jeetball.com (default = page host /ws) -> test")
	_check(ProfileApi.resolve_api_base(_lobby(true, "wss://my.box.example/ws", "wss://play.jeetball.com/ws")) == "https://my.box.example", "server_from_url: current_ws_url wins")
	_check(ProfileApi.resolve_api_base(_lobby(true, "ws://127.0.0.1:8080/ws", "wss://play.jeetball.com/ws")) == "http://127.0.0.1:8080", "ws:// -> http:// with port")
	_check(ProfileApi.resolve_api_base(_lobby(false, "ws://127.0.0.1:9080/ws", "wss://play.jeetball.com/ws")) == "https://play.jeetball.com", "live default")
	_check(ProfileApi.resolve_api_base(null) == LobbyBrowser.derive_api_base(), "no NetworkLobby: LobbyBrowser.derive_api_base()")
	_check(ProfileApi.resolve_api_base(_lobby(false, "", "")) == LobbyBrowser.derive_api_base(), "empty urls: LobbyBrowser fallback")
	var nl: Node = root.get_node_or_null("NetworkLobby")
	_check(nl != null and ProfileApi.resolve_api_base(nl) == LobbyBrowser.derive_api_base(String(nl.default_ws_url)), "real NetworkLobby (desktop, no --server): default_ws_url")

func _new_api(base: String) -> ProfileApi:
	var a := ProfileApi.new()
	a.api_base = base
	a.completed.connect(func(action: String, status: int, d: Dictionary) -> void: events.append([action, status, d]))
	root.add_child(a)
	return a

func _wait_for(action: String, a: ProfileApi, timeout_s := 8.0) -> Array:
	var t := 0.0
	while t < timeout_s:
		for e in events:
			if e[0] == action:
				return e
		await process_frame
		t += 1.0 / 60.0
	return [action, -1, {}]

func _saved_token() -> String:
	var c := ConfigFile.new()
	return String(c.get_value("profile", "token", "")) if c.load(ProfileApi.CFG_PATH) == OK else ""

func _actions() -> Array:
	return events.map(func(e): return e[0])

func _start_server() -> bool:
	var data := "/tmp/pb_profile_api_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(data)
	server_pid = OS.create_process("env", ["AUTO_START_GODOT=0", "HTTP_PORT=%d" % PORT, "PORT=%d" % PORT, "DATA_DIR=" + data,
		"LOBBY_STATE_FILE=" + data + "/lobbies.json", "CORS_ORIGINS=http://localhost", "node", ProjectSettings.globalize_path("res://server/server.js")])
	for i in 50:
		await create_timer(0.1).timeout
		var h := HTTPRequest.new()
		root.add_child(h)
		h.request("http://127.0.0.1:%d/api/profile/public/nobody" % PORT)
		var r: Array = await h.request_completed
		h.queue_free()
		if r[1] == 404:
			return true
	return false

func _run() -> void:
	var c := ConfigFile.new()
	if c.load(ProfileApi.CFG_PATH) == OK:
		cfg_backup = [c.get_value("profile", "token", ""), c.get_value("profile", "profile_id", "")]
	_test_base()
	if not await _start_server():
		_check(false, "local node server started on %d" % PORT)
		_finish()
		return
	var base := "http://127.0.0.1:%d" % PORT

	print("no token: set_callsign auto-creates, then continues")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProfileApi.CFG_PATH))
	events.clear()
	var a := _new_api(base)
	a.token = ""
	a.set_callsign("Auto_%d" % (randi() % 9000 + 1000))
	var e := await _wait_for("set_callsign", a)
	_check(e[1] == 200 and String(e[2].get("callsign", "")).begins_with("Auto_"), "set_callsign 200 after auto-create (got %s)" % e[1])
	_check(_actions() == ["create", "set_callsign"], "events create -> set_callsign (%s)" % str(_actions()))
	_check(a.has_profile() and _saved_token() == a.token, "new token saved to user://profile.cfg")

	print("no token: queued calls share one create")
	events.clear()
	a.token = ""
	a.solo_award("star", "q1")
	a.save_career({"stars": 1})
	await _wait_for("save_career", a)
	await _wait_for("solo_award", a)
	_check(_actions().count("create") == 1, "one create for two waiting calls (%s)" % str(_actions()))
	var sa: Array = events.filter(func(x): return x[0] == "solo_award")[0]
	_check(sa[1] == 200 and int(sa[2].get("awarded", -1)) == 100, "solo_award 200 awarded 100")
	var sc: Array = events.filter(func(x): return x[0] == "save_career")[0]
	_check(sc[1] == 200 and sc[2].get("career", {}).get("stars") == 1.0, "save_career 200")

	for act in ["set_callsign", "save_career", "solo_award"]:
		print("401 on %s: forget token, create once, retry once" % act)
		events.clear()
		a.token = BOGUS
		a._save()
		match act:
			"set_callsign": a.set_callsign("Re_%d" % (randi() % 9000 + 1000))
			"save_career": a.save_career({"k": 2})
			"solo_award": a.solo_award("tier", "t1")
		e = await _wait_for(act, a)
		_check(e[1] == 200, "%s retried -> 200 (got %s)" % [act, e[1]])
		_check(_actions() == ["create", act], "caller never sees the 401 (%s)" % str(_actions()))
		_check(a.token != BOGUS and a.has_profile() and _saved_token() == a.token, "fresh token in memory + cfg")

	print("401 that survives the retry: reported once, no loop")
	var fk := StubApi.new()
	root.add_child(fk)
	fk.token = BOGUS
	var got := []
	fk.completed.connect(func(act: String, st: int, _d: Dictionary) -> void: got.append([act, st]))
	fk.solo_award("star", "z")
	_check(fk.calls == ["solo_award", "create", "solo_award"], "PUT, create, PUT (%s)" % str(fk.calls))
	_check(got == [["create", 201], ["solo_award", 401]], "caller sees create 201 then the 401 (%s)" % str(got))
	fk.calls.clear()
	fk.solo_award("star", "z")
	_check(fk.calls == ["create", "solo_award"], "caller's own re-try: auto-create (token was dropped) but no second retry round (%s)" % str(fk.calls))
	fk.always_401 = false
	fk.solo_award("star", "z")
	fk.always_401 = true
	fk.calls.clear()
	fk.solo_award("star", "z")
	_check(fk.calls == ["solo_award", "create", "solo_award"], "after a success, a later 401 gets its retry again (%s)" % str(fk.calls))

	print("401 on get: token cleared (memory + cfg), no retry")
	events.clear()
	a.token = BOGUS
	a._save()
	a.fetch_profile()
	e = await _wait_for("get", a)
	_check(e[1] == 401 and a.token == "" and _saved_token() == "", "get 401 clears token")
	_check(_actions() == ["get"], "no auto-create on get (%s)" % str(_actions()))

	print("auto-create fails (server down): the action reports the failure")
	events.clear()
	var dead := _new_api("http://127.0.0.1:1")
	dead.token = ""
	dead.solo_award("star", "x")
	e = await _wait_for("solo_award", dead)
	_check(e[1] == 0, "solo_award status 0 when create fails (got %s)" % e[1])
	_finish()

func _finish() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
	if cfg_backup != null:
		var c := ConfigFile.new()
		c.set_value("profile", "token", cfg_backup[0])
		c.set_value("profile", "profile_id", cfg_backup[1])
		c.save(ProfileApi.CFG_PATH)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ProfileApi.CFG_PATH))
	print("RESULT: %s" % ("PASS" if fails.is_empty() else "FAIL %d: %s" % [fails.size(), ", ".join(fails)]))
	quit(0 if fails.is_empty() else 1)
