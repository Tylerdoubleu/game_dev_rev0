extends SceneTree
## v0.7 CallsignEntry on Tim's ProfileApi: client-side rule mirrors the server, first save creates the profile,
## 409 -> CALLSIGN TAKEN, 400 -> BAD NAME, no server -> kept + retried, 401 -> fresh profile once, fits 1280x720.
var fails: Array = []
func _check(ok: bool, what: String) -> void:
	print(("  [ok] " if ok else "  [FAIL] ") + what)
	if not ok: fails.append(what)

const TOKEN := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

## ProfileApi with the HTTP swapped for canned replies (Tim's reply handling is used as-is). No user:// I/O.
class FakeApi extends ProfileApi:
	var calls: Array = []
	var replies: Dictionary = {}  # action -> [status, body] (else a default)
	func _ready() -> void:
		pass
	func _save() -> void:
		pass
	func _request(action: String, path: String, method: int, body) -> void:
		calls.append({"action": action, "path": path, "method": method, "body": body, "token": token})
		var r: Array = replies.get(action, [])
		if r.is_empty():
			match action:
				"create": r = [201, {"profile_id": "p_1", "token": TOKEN, "callsign": null, "clout": 0, "career": null}]
				"set_callsign": r = [200, {"profile_id": "p_1", "callsign": body["callsign"], "clout": 40, "stats": {}}]
				_: r = [200, {"profile_id": "p_1", "callsign": null, "clout": 40, "stats": {}}]
		_on_reply(action, r[0], r[1].duplicate())

var frames := 0
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		_run()
	return false

func _run() -> void:
	for good in ["Viper", "abc", "X_9-z", "ABCDEFGHIJKLMNOP"]:
		_check(CallsignEntry.is_valid_callsign(good), "valid: " + good)
	for bad in ["ab", "ABCDEFGHIJKLMNOPQ", "has space", "émile", "no!", "", "a.b"]:
		_check(not CallsignEntry.is_valid_callsign(bad), "invalid: '" + bad + "'")

	var api := FakeApi.new()
	var ce := CallsignEntry.new()
	ce.close_on_save = false
	ce.bind_api(api)
	root.add_child(api)
	root.add_child(ce)
	var saved := [""]
	ce.callsign_saved.connect(func(n: String) -> void: saved[0] = n)

	ce.open("")
	_check(ce.visible and ce.state == CallsignEntry.State.IDLE, "opens idle")
	_check(ce._save_btn.disabled, "SAVE off while empty")
	ce._field.text = "no way"; ce._on_text_changed("no way")
	_check(ce._save_btn.disabled, "SAVE off for a bad name")
	ce.submit()
	_check(ce.state == CallsignEntry.State.INVALID and api.calls.is_empty(), "bad name never reaches the server")

	ce._field.text = "Viper"; ce._on_text_changed("Viper")
	ce.submit()
	_check(api.calls.size() == 2 and api.calls[0]["action"] == "create", "no profile yet -> create first")
	_check(api.calls[1]["action"] == "set_callsign" and api.calls[1]["token"] == TOKEN and api.calls[1]["body"] == {"callsign": "Viper"}, "then PUT callsign with the new token")
	_check(ce.state == CallsignEntry.State.SAVED and saved[0] == "Viper", "200 -> SAVED + callsign_saved")

	api.replies["set_callsign"] = [409, {"error": "callsign_taken"}]
	ce._field.text = "Taken1"; ce._on_text_changed("Taken1")
	ce.submit()
	_check(ce.state == CallsignEntry.State.TAKEN and ce._status.text == "CALLSIGN TAKEN", "409 -> CALLSIGN TAKEN")
	_check(ce.pending == "", "409 is not retried")
	_check(api.calls[-1]["action"] == "set_callsign" and api.calls.size() == 3, "existing profile -> no second create")
	ce._field.text = "Taken2"; ce._on_text_changed("Taken2")
	_check(ce.state == CallsignEntry.State.IDLE, "typing clears the error")

	api.replies["set_callsign"] = [400, {"error": "invalid_callsign"}]
	ce.submit()
	_check(ce.state == CallsignEntry.State.INVALID and ce._status.text == "BAD NAME", "400 -> BAD NAME")

	api.replies["set_callsign"] = [0, {"error": "request_failed"}]
	ce._field.text = "Ghost"; ce._on_text_changed("Ghost")
	ce.submit()
	_check(ce.state == CallsignEntry.State.OFFLINE and ce.pending == "Ghost", "no server -> OFFLINE, name kept")
	api.replies.erase("set_callsign")
	ce._send(ce.pending)  # what the retry timer does
	_check(ce.state == CallsignEntry.State.SAVED and ce.pending == "" and saved[0] == "Ghost", "retry saves it once the server is back")

	# 401: token no longer known -> fresh profile once, then the PUT again
	var n := api.calls.size()
	api.replies["set_callsign"] = [401, {"error": "unauthorized"}]
	ce._field.text = "Reborn"; ce._on_text_changed("Reborn")
	ce.submit()
	_check(api.calls.size() == n + 3 and api.calls[n + 1]["action"] == "create", "401 -> create once, PUT again")
	_check(ce.state == CallsignEntry.State.ERROR, "second 401 stops (no loop)")
	api.replies.erase("set_callsign")

	var need: Vector2 = ce._board.get_combined_minimum_size()
	_check(need.x <= 1280 and need.y <= 720, "board fits 1280x720 (%s)" % need)
	ce.close()
	_check(not ce.visible, "BACK closes")
	print("=== [%s] v0.7 callsign entry ===" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	quit(0 if fails.is_empty() else 1)
