extends SceneTree
## v0.5 (Ren): JOIN on the lobby list opens the in-place waiting room (rosters, field / game type / gun pickers,
## START MATCH, LEAVE) instead of dropping straight into the match. Offline (no server needed).
## Run: godot --headless --path . -s scripts/systems/test_lobby_waiting_room.gd
var f := 0
var fails: Array[String] = []
var flow: Node
var nl: Node
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		flow = root.get_node("/root/LobbyEntryFlow")
		nl = root.get_node("/root/NetworkLobby")
		flow.open_browser()
	if f == 4:
		flow.browser.navigate_on_join = false
		flow._on_lobby_join_requested({"id": "lobby_07", "name": "Lobby 07", "map": "woodsball_crash", "join_url": "https://x/?server=ws://127.0.0.1:9&room=lobby_07"})
	if f == 6:
		var wr: Control = flow.waiting_room
		_check(wr != null and wr.visible, "JOIN opens the waiting room")
		_check(not flow.browser.visible, "lobby list hidden behind it (no page navigation)")
		_check(nl.active_room == "lobby_07", "joined room lobby_07")
		_check(flow.is_open(), "still on the lobby menu, no match started")
		_check(not root.get_node("/root/GameManager").unload_guard_armed, "no leave-site warning in the lobby menus")
		wr.call("_on_conn", "LIVE", true)
		wr.apply_state({"room": "lobby_07", "selected_map": "woodsball_crash", "mode": "ctf", "bracket": "pump", "status": "waiting", "match": {"phase": "waiting"},
			"players": {11: {"name": "Tyler", "team": "ALPHA", "bracket": "speedball", "room": "lobby_07", "ready": true}, 12: {"name": "Friend", "team": "BRAVO", "bracket": "pump", "room": "lobby_07"}, 13: {"name": "Other", "team": "BRAVO", "room": "lobby_02"}}})
	if f == 8:
		var wr: Control = flow.waiting_room
		_check(wr._red_list.get_child_count() == 1 and wr._blue_list.get_child_count() == 1, "rosters show only this room's players by team")
		_check(wr._map_btns["woodsball_crash"].button_pressed and wr._mode_btns["ctf"].button_pressed and wr._gun_btns["pump"].button_pressed, "current field / game type / gun highlighted")
		_check(not wr._start_btn.disabled and wr._start_btn.text == "START MATCH", "START MATCH enabled while waiting")
		wr._on_countdown(5, {})
		_check(wr._countdown.visible and wr._countdown.text == "MATCH STARTS IN 5" and wr._start_btn.text in ["CANCEL START", "STARTING..."], "5s countdown shows; start button turns into cancel")
		wr._on_room_event("match_start_cancelled", {})
		_check(not wr._countdown.visible and wr._start_btn.text == "START MATCH", "cancel hides the countdown")
		wr._on_room_event("start_rejected", {"reason": "team_empty"})
		_check(wr._lock_note.text.begins_with("CAN'T START YET"), "team_empty refusal is explained")
		wr._ready_btn.button_pressed = true
		_check(nl.local_ready and wr._ready_btn.text == "READY  [X]", "READY toggle calls set_ready")
		wr.apply_state({"room": "lobby_07", "status": "in_match", "match": {"phase": "live"}, "players": {}})
		_check(wr._start_btn.disabled and wr._map_btns["speedball"].disabled, "settings + start locked once the match is live")
		wr.call("_press_leave")
	if f == 10:
		_check(flow.browser.visible and not flow.waiting_room.visible, "LEAVE goes back to the lobby list")
		flow._on_lobby_join_requested({"id": "lobby_03", "name": "Lobby 03", "join_url": "https://x/?server=ws://127.0.0.1:9&room=lobby_03"})
	if f == 12:
		nl.match_started_signal.emit("lobby_03", "speedball", false)
	if f == 14:
		_check(not flow.is_open(), "match start closes the lobby menu and drops you in")
		_check(root.get_node("/root/GameManager").unload_guard_armed, "leave-site warning armed only once the match starts")
		nl.room_event.emit("match_ended", {})
		_check(not root.get_node("/root/GameManager").unload_guard_armed, "warning disarmed after the match ends")
		print("=== [PASS] v0.5 lobby waiting room ===" if fails.is_empty() else "=== [FAIL] %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
