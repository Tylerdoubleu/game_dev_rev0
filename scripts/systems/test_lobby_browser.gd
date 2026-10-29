extends SceneTree
## v0.5 lobby browser: parses Tim's /api/lobbies shape, builds one row per lobby, quick-join picks the fullest
## waiting lobby with room, full lobbies can't be joined, and wss -> https API base derivation.
## Run: godot --headless --path . -s scripts/systems/test_lobby_browser.gd
const SAMPLE := '{"lobbies":[{"id":"lobby_01","name":"Lobby 01","map":"speedball","players":{"red":3,"blue":4},"max_per_team":5,"status":"waiting","bots":false,"join_url":"https://x/?room=lobby_01"},{"id":"lobby_02","name":"Lobby 02","map":"woodsball_crash","mode":"ctf_bo5","players":{"red":5,"blue":5},"max_per_team":5,"status":"full","bots":false,"join_url":"https://x/?room=lobby_02"},{"id":"lobby_03","name":"Lobby 03","map":"woodsball_crash","players":{"red":2,"blue":2},"max_per_team":5,"status":"in_match","bots":true,"join_url":"https://x/?room=lobby_03"},{"id":"lobby_04","name":"Lobby 04","map":"speedball","mode":"deathmatch_10","players":{"red":1,"blue":0},"max_per_team":5,"status":"waiting","bots":false,"join_url":"https://x/?room=lobby_04"}]}'
var b: LobbyBrowser
var f := 0
var fails: Array[String] = []
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)
func _initialize() -> void:
	b = LobbyBrowser.new()
	b.api_base = ""
	root.add_child(b)
func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		var list := LobbyBrowser.parse_lobbies(SAMPLE)
		_check(list.size() == 4, "parses 4 lobbies")
		_check(String(LobbyBrowser.pick_quick_join(list).get("id")) == "lobby_01", "quick-join picks fullest waiting lobby with room")
		_check(LobbyBrowser.pick_quick_join([list[1], list[2]]).is_empty(), "no quick-join when only full / in-match")
		_check(LobbyBrowser.derive_api_base("wss://abc.pr.edgegap.net:31351/ws") == "https://abc.pr.edgegap.net:31351", "wss -> https api base")
		b.set_lobbies(list)
	if f == 6:
		var rows := b.find_children("Row_*", "", true, false)
		_check(rows.size() == 4, "one row per lobby")
		var full_btn := b.find_child("Row_lobby_02", true, false).find_child("JoinButton", true, false) as Button
		_check(full_btn.disabled, "full lobby JOIN disabled")
		var joined := []
		b.lobby_join_requested.connect(func(e): joined.append(e["id"]))
		b.quick_join()
		_check(joined == ["lobby_01"], "quick-join emits lobby_01")
		b.set_lobbies([], "SERVER OFFLINE")
		_check(b.find_children("Row_*", "", true, false).size() <= 4, "offline clears list")
		print("=== [PASS] v0.5 lobby browser ===" if fails.is_empty() else "=== [FAIL] %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
