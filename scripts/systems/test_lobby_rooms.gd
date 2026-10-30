extends SceneTree
## v0.5 server room logic (no sockets needed): drives the NetworkLobby autoload as a dedicated server with
## synthetic peer ids and checks the /api/lobbies IPC document, team balancing, lobby settings and match rules.
## Run: godot --headless --path . -s res://scripts/systems/test_lobby_rooms.gd
## Writes the real room-state document to /tmp/pb_godot_lobby_state.json for server/test (GODOT_LOBBY_STATE).
const PORT := 19192
const STATE_PATH := "/tmp/pb_godot_lobby_state.json"
var L: Node
var f := 0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _reg(pid: int, room: String, team: String = "", name: String = "", map_id: String = "", mode_id: String = "") -> void:
	L._server_register_peer(pid, name if name != "" else "P%d" % pid, team, "speedball", true, room, map_id, mode_id)

func _team(pid: int) -> String:
	return String(L.players.get(pid, {}).get("team", ""))

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	L = root.get_node("NetworkLobby")
	L.start_dedicated_server(PORT)
	L.outbound_capture = []
	L.break_countdown_ms = 0
	L.match_countdown_ms = 0 # rules tests start instantly; _test_ready_and_countdown covers the 3 s countdown
	_test_ipc_document()
	for t in ["_test_team_balance", "_test_lobby_settings", "_test_deathmatch", "_test_ctf_best_of_5", "_test_ctf_round_timer", "_test_break_and_callouts", "_test_bots_test_mode", "_test_hit_validation", "_test_ready_and_countdown"]:
		if has_method(t):
			L.start_dedicated_server(PORT + 1 + f)
			L.outbound_capture = []
			L.match_countdown_ms = 0
			L.break_countdown_ms = 0
			f += 1
			call(t)
	print("=== [PASS] v0.5 lobby rooms ===" if fails.is_empty() else "=== [FAIL] lobby rooms: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true

func _test_ipc_document() -> void:
	print("--- /api/lobbies IPC document ---")
	_reg(101, "lobby_01", "ALPHA")
	_reg(102, "lobby_01", "BRAVO")
	_reg(103, "lobby_01", "BRAVO")
	_reg(201, "lobby_04", "", "", "woodsball_crash", "ctf")
	_reg(301, "friends")
	var list: Array = L.get_public_lobby_list()
	_check(list.size() == 10, "10 permanent lobbies listed (ad-hoc 'friends' hidden)")
	var l1: Dictionary = list[0]
	_check(l1.keys() == ["id", "name", "map", "mode", "players", "max_per_team", "status", "bots"], "row keys %s" % [l1.keys()])
	_check(l1["id"] == "lobby_01" and l1["name"] == "Lobby 01" and l1["map"] == "speedball" and l1["mode"] == "deathmatch", "lobby_01 identity/settings")
	_check(int(l1["players"]["red"]) + int(l1["players"]["blue"]) == 3 and l1["max_per_team"] == 5 and l1["status"] == "waiting" and l1["bots"] == false, "lobby_01 counts/status %s" % [l1])
	_check(list[1]["map"] == "woodsball_crash", "lobby_02 defaults to woodsball_crash")
	_check(list[3]["map"] == "woodsball_crash" and list[3]["mode"] == "ctf", "first joiner's ?map=&mode= set lobby_04")
	for i in 7:
		_reg(110 + i, "lobby_01")
	_check(L.get_public_lobby_list()[0]["status"] == "full", "10 players -> full")
	(L.outbound_capture as Array).clear()
	_reg(199, "lobby_01")
	_check(not L.peer_room.has(199), "11th player rejected from a full lobby")
	var rej := (L.outbound_capture as Array).filter(func(m): return m["peer"] == 199 and m["method"] == "cl_room_event" and m["args"][0] == "join_rejected")
	_check(rej.size() == 1, "join_rejected event sent to the 11th player")
	_reg(901, "lobby_99")
	_check(not L.rooms.has("lobby_99"), "unknown lobby_NN is rejected, not created")
	_check(L.write_lobby_state_file(STATE_PATH), "state file written")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	_check(typeof(doc) == TYPE_DICTIONARY and doc["lobbies"].size() == 10 and doc["max_per_team"] == 5 and float(doc["generated_at"]) > 1.7e9, "state document parses with generated_at")
	_check(int(doc["private_rooms"]) == 1 and int(doc["connected_peers"]) == 12, "doc counts private rooms / peers (%s/%s)" % [doc["private_rooms"], doc["connected_peers"]])
	L._server_remove_peer(301)
	_check(not L.rooms.has("friends"), "ad-hoc room deleted when empty")
	for pid in [201]:
		L._server_remove_peer(pid)
	_check(L.rooms["lobby_04"]["settings"]["mode"] == "deathmatch" and L.rooms["lobby_04"]["settings"]["map"] == "woodsball_crash", "empty permanent lobby resets to its defaults")

## ---------------------------------------------------------------------------------------------------------------
## helpers for rules tests (synthetic peers; the rules clock is driven by L.rules_clock_override_ms)
var ev: Array = []
var clock_ms: int = 1000000

func _on_ev(n: String, d: Dictionary) -> void:
	ev.append({"event": n, "data": d})

func _events(n: String, rid: String = "") -> Array:
	return ev.filter(func(e): return e["event"] == n and (rid == "" or String(e["data"].get("room", "")) == rid))

func _begin(title: String) -> void:
	print("--- %s ---" % title)
	ev.clear()
	if not L.room_event.is_connected(_on_ev):
		L.room_event.connect(_on_ev)
	clock_ms += 100000
	L.rules_clock_override_ms = clock_ms

func _advance(ms: int) -> void:
	clock_ms += ms
	L.rules_clock_override_ms = clock_ms
	L._server_tick(0.016)

func _state(pid: int, pos: Vector3, stance: int = 0) -> void:
	L._server_on_player_state(pid, pos, 0.0, 0.0, 0.0, stance, false)

func _shoot(pid: int, origin: Vector3, target: Vector3, speed: float = 290.0) -> void:
	L._server_on_fire(pid, origin, (target - origin).normalized(), speed)

## Valid elimination of v by s: v stands at vpos, s 8 m away (+z), fires at v's chest and reports the hit.
func _kill(s: int, v: int, vpos: Vector3 = Vector3(12, 0, 20)) -> void:
	_state(v, vpos)
	var spos := vpos + Vector3(0, 0, 8)
	_state(s, spos)
	var chest := vpos + Vector3(0, 1.2, 0)
	_shoot(s, spos + Vector3(0, 1.4, 0), chest)
	L._server_on_hit_report(s, v, chest)

func _alive(pid: int) -> bool:
	return bool(L.players[pid].get("alive", true))

func _sent(pid: int, method: String) -> Array:
	return (L.outbound_capture as Array).filter(func(m): return int(m["peer"]) == pid and m["method"] == method)

func _test_team_balance() -> void:
	_begin("auto team balance")
	var want := ["ALPHA", "BRAVO", "BRAVO", "ALPHA", "ALPHA", "BRAVO"]
	var req := ["", "", "BRAVO", "BRAVO", "", "red"]
	for i in 6:
		_reg(1 + i, "lobby_01", req[i])
	var got := []
	for i in 6:
		got.append(_team(1 + i))
	_check(got == want, "join order -> smaller team, ties to red, unbalancing team= ignored (%s)" % [got])
	_reg(6, "lobby_01", "ALPHA")
	_check(_team(6) == "BRAVO", "re-register asking for the bigger team is ignored")
	_reg(1, "lobby_01", "BRAVO")
	_check(_team(1) == "ALPHA", "switch that would make teams 2-4 is ignored")
	for pid in [2, 3, 6]:
		L._server_remove_peer(pid)
	var moves: Array = L._rebalance_room_teams(L.rooms["lobby_01"])
	_check(moves.size() == 1 and _team(5) == "BRAVO", "3v0 rebalances the latest joiner (5) to blue (%s)" % [moves])
	# READY takes a team spot: the side with fewer READY players.
	for pid in [61, 62, 63]:
		_reg(pid, "lobby_09")
		L._server_set_ready(pid, false) # _reg joins READY; start from the bench
	var t61 := _team(61)
	L._server_set_ready(61, true)
	_check(_team(61) == t61, "first READY keeps its side")
	L._server_set_ready(63, true) # 63 joined red (tie) but red already has a ready player
	_check(_team(63) != t61, "second READY goes to the side with fewer READY players (%s vs %s)" % [_team(63), t61])
	var prc := _events("player_ready_changed").filter(func(e): return int(e["data"]["peer"]) == 63 and bool(e["data"]["ready"]))
	_check(prc.size() == 1 and String(prc[0]["data"]["team"]) == _team(63), "player_ready_changed carries the team")
	_check(_events("teams_rebalanced", "lobby_01").size() == 1, "teams_rebalanced event emitted")
	_reg(7, "lobby_01", "BRAVO")
	_check(_team(7) == "BRAVO", "honoured team= request when it does not unbalance (2v1 -> 2v2)")
	# Match start rebalances a 2v0 room.
	_reg(11, "lobby_02")
	_reg(12, "lobby_02")
	_reg(13, "lobby_02")
	L._server_remove_peer(12)
	_check(_team(11) == "ALPHA" and _team(13) == "ALPHA", "lobby_02 is 2v0 after a leave")
	L._server_request_start(11, "speedball")
	_check(_team(13) == "BRAVO" and bool(L.rooms["lobby_02"]["match"]["active"]), "match start rebalanced 13 to blue")
	_reg(13, "lobby_02", "ALPHA")
	_check(_team(13) == "BRAVO", "no team switching mid-match")
	_reg(14, "lobby_02")
	_check(_team(14) == "ALPHA", "mid-match joiner goes to the smaller team (tie -> red)")
	_reg(15, "lobby_02", "ALPHA")
	_check(_team(15) == "BRAVO", "mid-match joiner asking for the bigger team is balanced to blue")
	# Team caps: 5v4 -> the 10th player goes to blue even when asking for red.
	for i in 9:
		_reg(20 + i, "lobby_03")
	_reg(29, "lobby_03", "ALPHA")
	var c: Dictionary = L.room_team_counts(L.rooms["lobby_03"])
	_check(int(c["ALPHA"]) == 5 and int(c["BRAVO"]) == 5, "10 players split 5v5 (%s)" % [c])

func _test_lobby_settings() -> void:
	_begin("lobby settings (any player, validated, locked at start)")
	_reg(21, "lobby_03")
	_reg(22, "lobby_03")
	L._server_set_room_settings(22, "woodsball_crash", "")
	var s: Dictionary = L.rooms["lobby_03"]["settings"]
	_check(s["map"] == "woodsball_crash" and s["mode"] == "deathmatch", "player 22 changes the map only")
	L._server_set_room_settings(21, "", "ctf")
	_check(s["map"] == "woodsball_crash" and s["mode"] == "ctf", "player 21 changes the mode only")
	var ch := _events("room_settings_changed", "lobby_03")
	_check(ch.size() == 2 and int(ch[0]["data"]["by"]) == 22 and ch[1]["data"]["mode"] == "ctf", "room_settings_changed emitted per change with who changed it")
	L._server_set_room_settings(21, "moon_base", "capture_the_moon")
	_check(s["map"] == "woodsball_crash" and s["mode"] == "ctf", "invalid map/mode ignored")
	var syncs := _sent(22, "sync_lobby_state")
	_check(not syncs.is_empty() and syncs[-1]["args"][0]["mode"] == "ctf" and syncs[-1]["args"][0]["map"] == "woodsball_crash", "room snapshot synced to the other player")
	(L.outbound_capture as Array).clear()
	L._server_request_start(21, "pump")
	var n21 := _sent(21, "notify_match_start")
	var n22 := _sent(22, "notify_match_start")
	_check(n21.size() == 1 and n21[0]["args"][1] == "pump" and n22.size() == 1 and n22[0]["args"][1] == "speedball", "bracket stays per player at match start")
	L._server_set_room_settings(22, "speedball", "")
	_check(s["map"] == "woodsball_crash", "settings locked once the match started")
	var rej := _sent(22, "cl_room_event").filter(func(m): return m["args"][0] == "settings_rejected")
	_check(rej.size() == 1, "settings_rejected sent to the player")
	_check(_events("round_started", "lobby_03").size() == 1, "round_started at match start")

func _test_deathmatch() -> void:
	_begin("deathmatch: first team to 10 kills")
	for pid in [31, 32, 33, 34]:
		_reg(pid, "lobby_05")
	_check(_team(31) == "ALPHA" and _team(32) == "BRAVO", "teams alternate")
	_kill(31, 32)
	var pe := _events("player_eliminated", "lobby_05")
	_check(pe.size() == 1 and pe[0]["data"]["scored"] == false and int(L.players[31]["kills"]) == 0, "waiting-room hit is practice (not scored)")
	_advance(1100)
	_check(_alive(32), "practice respawn")
	L._server_request_start(31, "speedball")
	_check(_events("round_started", "lobby_05").size() == 1, "round_started")
	_kill(31, 33)
	_check(_alive(33) and _events("player_eliminated", "lobby_05").size() == 1, "friendly fire rejected")
	for k in 9:
		_kill(31, 32)
		if k == 0:
			_check(not _alive(32), "kill 1 registered")
			_kill(32, 33) # 32 is dead until its 1 s respawn: its shot must be rejected
			_check(int(L.rejected_shots.get("shooter_dead", 0)) == 1 and _alive(33), "dead shooter's shot rejected")
		_advance(1100)
	_check(int(L.rooms["lobby_05"]["match"]["kills"]["ALPHA"]) == 9 and _events("match_ended", "lobby_05").is_empty(), "9 kills: match continues")
	_kill(31, 32)
	var me := _events("match_ended", "lobby_05")
	_check(me.size() == 1 and me[0]["data"]["winner"] == "ALPHA" and me[0]["data"]["score"] == {"red": 10, "blue": 0}, "10th kill ends the match for red (%s)" % [me])
	_check(not bool(L.rooms["lobby_05"]["match"]["active"]) and L.rooms["lobby_05"]["match"]["phase"] == "waiting", "room back to waiting")
	_check(int(L.players[31]["kills"]) == 10 and int(L.players[32]["deaths"]) == 10, "per-player kills/deaths tracked")

func _test_ctf_best_of_5() -> void:
	_begin("ctf: one life, best of 5")
	for pid in [41, 42, 43, 44]:
		_reg(pid, "lobby_06")
	L._server_set_room_settings(41, "", "ctf")
	L._server_request_start(42, "speedball")
	var m: Dictionary = L.rooms["lobby_06"]["match"]
	_check(m["mode"] == "ctf" and m["phase"] == "live" and int(m["round"]) == 1, "round 1 live")
	# Round 1: red captures (41 runs to the blue base and back).
	_state(41, Vector3(0, 0, -45.5))
	_check(L.rooms["lobby_06"]["match"]["flags"]["BRAVO"]["state"] == "carried", "41 picked up the blue flag")
	_state(41, Vector3(0, 0, 0))
	_state(41, Vector3(1, 0, 44.0))
	var re := _events("round_ended", "lobby_06")
	_check(re.size() == 1 and re[0]["data"]["winner"] == "ALPHA" and re[0]["data"]["reason"] == "capture" and re[0]["data"]["score"] == {"red": 1, "blue": 0}, "round 1: red capture (%s)" % [re])
	var fs := _events("flag_state_changed", "lobby_06").map(func(e): return e["data"]["action"])
	_check(fs == ["picked_up", "captured"], "flag_state_changed picked_up -> captured (%s)" % [fs])
	var sb0: Array = re[0]["data"].get("scoreboard", [])
	var r41 := sb0.filter(func(r): return int(r["peer"]) == 41)
	_check(sb0.size() == 4 and r41.size() == 1 and int(r41[0]["captures"]) == 1 and String(sb0[0]["color"]) == "red", "round_ended carries the scoreboard (41: 1 capture)")
	_check(int(re[0]["data"]["next_round_in_ms"]) == L.ROUND_INTERMISSION_MS and not bool(re[0]["data"]["match_point"]), "round_ended: next round in %d ms" % L.ROUND_INTERMISSION_MS)
	_advance(1000)
	_check(L.rooms["lobby_06"]["match"]["phase"] == "intermission", "intermission between rounds")
	_advance(L.ROUND_INTERMISSION_MS - 900)
	_check(int(L.rooms["lobby_06"]["match"]["round"]) == 2 and _events("round_started", "lobby_06").size() == 2, "round 2 started after the intermission")
	# Late joiner sits out the current round.
	_reg(45, "lobby_06")
	_check(_team(45) == "ALPHA" and not _alive(45), "late joiner (red, tie) is dead until the next round")
	# Round 2: blue eliminates all of red; no respawn in CTF.
	_kill(42, 41)
	_advance(2500)
	_check(not _alive(41), "no respawn mid-round")
	_kill(44, 43)
	re = _events("round_ended", "lobby_06")
	_check(re.size() == 2 and re[1]["data"]["winner"] == "BRAVO" and re[1]["data"]["reason"] == "elimination" and re[1]["data"]["score"] == {"red": 1, "blue": 1}, "round 2: blue by elimination")
	_advance(L.ROUND_INTERMISSION_MS + 100)
	_check(_alive(41) and _alive(45) and int(L.rooms["lobby_06"]["match"]["round"]) == 3, "round 3: everyone alive again")
	# Round 3: blue grabs the red flag, gets shot -> drop; red touches it -> returned; red then captures.
	_state(42, Vector3(0, 0, 45.5))
	_check(L.rooms["lobby_06"]["match"]["flags"]["ALPHA"]["state"] == "carried", "42 carries the red flag")
	_kill(41, 42, Vector3(10, 0, 0))
	var fl: Dictionary = L.rooms["lobby_06"]["match"]["flags"]["ALPHA"]
	_check(fl["state"] == "dropped" and Vector3(fl["pos"]).distance_to(Vector3(10, 0, 0)) < 0.1, "red flag dropped where the carrier was eliminated")
	_state(43, Vector3(10.5, 0, 0.5))
	_check(L.rooms["lobby_06"]["match"]["flags"]["ALPHA"]["state"] == "home", "own-team touch returns the flag")
	_state(43, Vector3(0, 0, -45.5))
	_state(43, Vector3(0, 0, 45.5))
	re = _events("round_ended", "lobby_06")
	_check(re.size() == 3 and re[2]["data"]["winner"] == "ALPHA" and re[2]["data"]["score"] == {"red": 2, "blue": 1}, "round 3: red capture -> 2-1")
	_advance(L.ROUND_INTERMISSION_MS + 100)
	# Round 4: dropped flag auto-returns after 30s, then red captures the match.
	_state(44, Vector3(0, 0, 45.5))
	_kill(45, 44, Vector3(-12, 0, 10))
	_check(L.rooms["lobby_06"]["match"]["flags"]["ALPHA"]["state"] == "dropped", "dropped again")
	_advance(30100)
	_check(L.rooms["lobby_06"]["match"]["flags"]["ALPHA"]["state"] == "home" and _events("flag_state_changed", "lobby_06").filter(func(e): return e["data"]["action"] == "auto_returned").size() == 1, "dropped flag auto-returns after 30s")
	_check(_events("match_ended", "lobby_06").is_empty(), "no match_ended before 3 round wins")
	_state(41, Vector3(0, 0, -45.5))
	_state(41, Vector3(0, 0, 45.5))
	var me := _events("match_ended", "lobby_06")
	_check(me.size() == 1 and me[0]["data"]["winner"] == "ALPHA" and me[0]["data"]["score"] == {"red": 3, "blue": 1} and int(me[0]["data"]["rounds"]) == 4, "match_ended: red wins 3-1 in 4 rounds (%s)" % [me])
	_check(not bool(L.rooms["lobby_06"]["match"]["active"]), "room back to waiting after the match")
	_check(int(me[0]["data"]["return_to_lobby_in_ms"]) == L.MATCH_RESULTS_MS and (me[0]["data"]["scoreboard"] as Array).size() == 5 and (me[0]["data"]["winner_names"] as Array).size() == 3, "match_ended: scoreboard recap + winners + return timer")
	_check(bool(re[2]["data"].get("match_point", true)) == false and bool(_events("round_ended", "lobby_06")[3]["data"]["match_point"]), "deciding round_ended flagged match_point")
	_advance(5000)
	_check(_events("round_started", "lobby_06").size() == 4, "no extra round after the match ended")
	_check(_events("returned_to_lobby", "lobby_06").is_empty(), "still on the match recap")
	_advance(L.MATCH_RESULTS_MS)
	_check(_events("returned_to_lobby", "lobby_06").size() == 1, "returned_to_lobby after the recap")

func _test_ctf_round_timer() -> void:
	_begin("ctf: round timer, captures in roster, respawn delay")
	for pid in [71, 72, 73, 74]:
		_reg(pid, "lobby_08")
	L._server_set_room_settings(71, "", "ctf")
	L._server_request_start(71, "speedball")
	var rs := _events("round_started", "lobby_08")
	_check(rs.size() == 1 and int(rs[0]["data"]["round_time_ms"]) == L.CTF_ROUND_TIME_MS and int(rs[0]["data"]["respawn_ms"]) == 0, "round_started: round_time_ms + respawn_ms 0 in CTF")
	var pub: Dictionary = L._public_match_state(L.rooms["lobby_08"])
	_check(int(pub["round_ms_left"]) == L.CTF_ROUND_TIME_MS and int(pub["respawn_ms"]) == 0, "snapshot: round_ms_left (%s)" % pub["round_ms_left"])
	var blue_pid := 72 if _team(72) == "BRAVO" else (73 if _team(73) == "BRAVO" else 74)
	var red_pid := 71 if _team(71) == "ALPHA" else 73
	_kill(red_pid, blue_pid)
	_advance(L.CTF_ROUND_TIME_MS - 1000)
	_check(_events("round_ended", "lobby_08").is_empty(), "round still live before the time limit")
	_advance(1100)
	var re := _events("round_ended", "lobby_08")
	_check(re.size() == 1 and re[0]["data"]["reason"] == "time" and re[0]["data"]["winner"] == "ALPHA", "time-out: more players alive (red) wins the round (%s)" % [re])
	_advance(L.ROUND_INTERMISSION_MS + 100)
	_state(red_pid, Vector3(0, 0, -45.5))
	_state(red_pid, Vector3(0, 0, 45.5))
	var row: Array = L._room_roster(L.rooms["lobby_08"]).filter(func(r): return int(r["peer"]) == red_pid)
	_check(row.size() == 1 and int(row[0]["captures"]) == 1, "room_roster shows live captures")
	var pe := _events("player_eliminated", "lobby_08")
	_check(pe.size() == 1 and int(pe[0]["data"]["respawn_in_ms"]) == 0, "player_eliminated carries respawn_in_ms")
	L._server_set_room_settings(71, "", "deathmatch")

func _test_break_and_callouts() -> void:
	_begin("v0.6 break (3-2-1 + horn) and team-only callout pings")
	L.break_countdown_ms = L.BREAK_COUNTDOWN_MS
	for pid in [81, 82, 83, 84]:
		_reg(pid, "lobby_10")
	L._server_set_room_settings(81, "", "ctf")
	L._server_request_start(81, "speedball")
	var m: Dictionary = L.rooms["lobby_10"]["match"]
	_check(m["phase"] == "break" and _events("break_countdown", "lobby_10").size() == 1 and int(_events("break_countdown", "lobby_10")[0]["data"]["seconds_left"]) == 3, "round opens in the break: 3")
	var red := 81 if _team(81) == "ALPHA" else 82
	var blue := 82 if red == 81 else 81
	_state(red, Vector3(0, 0, 44))
	_state(blue, Vector3(0, 0, -44))
	_shoot(red, Vector3(0, 1.4, 44), Vector3(0, 1.2, -44))
	_check(int(L.rejected_shots.get("before_horn", 0)) == 1, "shot before the horn rejected")
	L._server_on_hit_report(red, blue, Vector3(0, 1.2, -44))
	_check(_alive(blue) and _events("player_eliminated", "lobby_10").is_empty(), "hit before the horn rejected")
	(L.outbound_capture as Array).clear()
	_state(red, Vector3(0, 0, 30))
	var rs := _sent(red, "cl_room_event").filter(func(x): return x["args"][0] == "break_line_reset")
	_check(rs.size() == 1 and int(L.players[red]["break_false_starts"]) == 1, "false start past the line -> break_line_reset")
	_advance(1100)
	_advance(1000)
	var cd := _events("break_countdown", "lobby_10").map(func(e): return int(e["data"]["seconds_left"]))
	_check(cd == [3, 2, 1], "countdown 3, 2, 1 (%s)" % [cd])
	_check(_events("break_horn", "lobby_10").is_empty(), "no horn yet")
	_advance(1000)
	_check(_events("break_horn", "lobby_10").size() == 1 and L.rooms["lobby_10"]["match"]["phase"] == "live", "horn -> live")
	_check(int(L._public_match_state(L.rooms["lobby_10"])["round_ms_left"]) == L.CTF_ROUND_TIME_MS - 100, "round clock starts at the horn")
	# Callouts: same team only, rate-limited.
	(L.outbound_capture as Array).clear()
	L._server_ping_callout(red, "Snake 2", Vector3(10, 0, -5), 1)
	var mates: Array = []
	var others: Array = []
	for pid in [81, 82, 83, 84]:
		var got := _sent(pid, "cl_room_event").filter(func(x): return x["args"][0] == "callout_pinged")
		if _team(pid) == _team(red):
			mates.append(got.size())
		else:
			others.append(got.size())
	_check(mates == [1, 1] and others == [0, 0], "callout reaches only the pinger's team (%s / %s)" % [mates, others])
	L._server_ping_callout(red, "Snake 2", Vector3(10, 0, -5), 1)
	_check(int(L.callouts_sent) == 1, "second ping inside the cooldown dropped")
	# Round recap (intermission): no shots or hits count.
	L.rooms["lobby_10"]["match"]["phase"] = "intermission"
	var before := int(L.rejected_shots.get("round_over", 0))
	_shoot(red, Vector3(0, 1.4, 44), Vector3(0, 1.2, -44))
	L._server_on_hit_report(red, blue, Vector3(0, 1.2, -44))
	_check(int(L.rejected_shots.get("round_over", 0)) == before + 1 and _alive(blue), "shots and hits during the round recap rejected (round_over)")
	L.break_countdown_ms = 0

func _test_bots_test_mode() -> void:
	_begin("bots_test: bots on, no win condition")
	_reg(51, "lobby_07", "", "", "", "bots_test")
	_reg(52, "lobby_07")
	L._server_request_start(51, "speedball")
	var n := _sent(51, "notify_match_start")
	_check(n.size() == 1 and n[0]["args"][2] == true, "notify_match_start fill_bots=true")
	for k in 12:
		_kill(51, 52)
		_advance(1100)
	_check(_events("match_ended", "lobby_07").is_empty() and bool(L.rooms["lobby_07"]["match"]["active"]), "12 kills, still no win")
	_check(L.get_public_lobby_list()[6]["bots"] == true and L.get_public_lobby_list()[6]["status"] == "in_match", "/api row: bots=true, in_match")

func _test_hit_validation() -> void:
	_begin("PB-13 hit validation")
	_check(L.ensure_collision_worlds() == 2, "collision worlds for both maps")
	_reg(61, "lobby_01") # red
	_reg(62, "lobby_01") # blue
	var rej := func(reason: String) -> int: return int(L.rejected_hits.get(reason, 0))
	# Clear lane at x=5 (between the centre bunker and the mini-window).
	var vpos := Vector3(5, 0, -4)
	var spos := Vector3(5, 0, 8)
	_state(62, vpos)
	_state(61, spos)
	var los: String = L.line_of_sight_status("speedball", spos + Vector3(0, 1.4, 0), (vpos + Vector3(0, 1.2, 0) - spos - Vector3(0, 1.4, 0)).normalized(), 290.0, vpos + Vector3(0, 1.2, 0))
	_check(los == "clear", "open lane LOS clear (%s)" % los)
	var blocked: String = L.line_of_sight_status("speedball", Vector3(0, 1.2, 8), Vector3(0, 0, -1), 290.0, Vector3(0, 1.2, -4))
	_check(blocked == "blocked", "LOS through the centre bunker blocked (%s)" % blocked)
	# no shot fired
	L._server_on_hit_report(61, 62, vpos + Vector3(0, 1.2, 0))
	_check(_alive(62) and rej.call("no_matching_shot") == 1, "hit without a shot rejected")
	# aim mismatch
	_shoot(61, spos + Vector3(0, 1.4, 0), spos + Vector3(10, 1.4, 0))
	L._server_on_hit_report(61, 62, vpos + Vector3(0, 1.2, 0))
	_check(_alive(62) and rej.call("aim_mismatch") == 1, "hit 90 deg off the shot direction rejected")
	# outside hitbox (head-height over a crouching victim)
	_state(62, vpos, 1)
	_shoot(61, spos + Vector3(0, 1.4, 0), vpos + Vector3(0, 1.7, 0))
	L._server_on_hit_report(61, 62, vpos + Vector3(0, 1.7, 0))
	_check(_alive(62) and rej.call("outside_hitbox") == 1, "1.7 m hit on a crouched (1.30 m) victim rejected")
	# prone victim: wide but low box
	var ppos := Vector3(5, 0, 3) # in front of the WoodSpool at (5.7, 0, 0.4), which blocks low shots further down this lane
	_state(62, ppos, 2)
	_shoot(61, spos + Vector3(0, 1.4, 0), ppos + Vector3(1.1, 0.4, 0))
	L._server_on_hit_report(61, 62, ppos + Vector3(1.1, 0.4, 0))
	_check(not _alive(62), "prone victim hit 1.1 m out at 0.4 m height accepted (%s)" % [L.rejected_hits])
	_advance(1100)
	_state(62, vpos, 0)
	# behind cover: victim hides behind the centre bunker
	var hide := Vector3(0, 0, -2.0)
	_state(62, hide)
	_state(61, Vector3(0, 0, 8))
	_shoot(61, Vector3(0, 1.4, 8), hide + Vector3(0, 1.0, 0))
	L._server_on_hit_report(61, 62, hide + Vector3(0, 1.0, 0))
	_check(_alive(62) and rej.call("no_line_of_sight") == 1, "hit through the centre bunker rejected (%s)" % [L.rejected_hits])
	# out of range
	_state(62, Vector3(5, 0, -44))
	_state(61, Vector3(5, 0, 44))
	_shoot(61, Vector3(5, 1.4, 44), Vector3(5, 1.2, -44))
	L._server_on_hit_report(61, 62, Vector3(5, 1.2, -44))
	_check(_alive(62), "88 m+ cross-field hit beyond range/drop rejected (%s)" % [L.rejected_hits])
	# fire lock: sliding shooter's shot is never accepted or relayed
	_state(61, spos, 16)
	(L.outbound_capture as Array).clear()
	_shoot(61, spos + Vector3(0, 1.0, 0), vpos + Vector3(0, 1.0, 0))
	_check(int(L.rejected_shots.get("fire_lock", 0)) == 1 and _sent(62, "rpc_fire_paintball").is_empty(), "shot under the slide fire lock rejected and not relayed")
	_state(61, spos, 0)
	_shoot(61, spos + Vector3(0, 1.4, 0), vpos + Vector3(0, 1.2, 0))
	_check(int(L.rejected_shots.get("fire_lock", 0)) == 2, "shot inside the 0.10 s recovery rejected")
	OS.delay_msec(150)
	_state(62, vpos)
	_shoot(61, spos + Vector3(0, 1.4, 0), vpos + Vector3(0, 1.2, 0))
	_check(_sent(62, "rpc_fire_paintball").size() == 1, "shot after recovery relayed at full speed")
	_check(float(_sent(62, "rpc_fire_paintball")[0]["args"][2]) == 290.0, "relayed muzzle velocity is not clamped (290 fps)")
	L._server_on_hit_report(61, 62, vpos + Vector3(0, 1.2, 0))
	_check(not _alive(62), "valid hit eliminates")
	# origin spoof
	_shoot(61, Vector3(5, 1.4, -2), vpos + Vector3(0, 1.2, 0))
	_check(int(L.rejected_shots.get("origin_mismatch", 0)) == 1, "shot from 10 m away from the shooter's position rejected")
	# victim already dead / friendly fire
	L._server_on_hit_report(61, 62, vpos + Vector3(0, 1.2, 0))
	_check(rej.call("victim_dead") == 1, "dead victim rejected")
	_reg(63, "lobby_01") # red
	_state(63, Vector3(-5, 0, 8))
	_shoot(61, spos + Vector3(0, 1.4, 0), Vector3(-5, 1.2, 8))
	L._server_on_hit_report(61, 63, Vector3(-5, 1.2, 8))
	_check(_alive(63) and rej.call("friendly_fire") == 1, "friendly fire rejected")

func _test_ready_and_countdown() -> void:
	_begin("READY toggle + match_starting / match_countdown")
	_check(L.MATCH_COUNTDOWN_MS == 5000, "default pre-match countdown is 5 s")
	L.match_countdown_ms = L.MATCH_COUNTDOWN_MS
	# start_rejected: a lone player cannot start a real match (empty team)...
	L._server_register_peer(70, "P70", "", "speedball", false, "lobby_08")
	L._server_request_start(70, "speedball")
	var sr := _sent(70, "cl_room_event").filter(func(m): return m["args"][0] == "start_rejected")
	_check(sr.size() == 1 and sr[0]["args"][1]["reason"] == "team_empty" and _events("match_starting", "lobby_08").is_empty(), "start_rejected(team_empty) with an empty team")
	# ...unless bots fill is on.
	L._server_request_start(70, "speedball", true)
	_check(_events("match_starting", "lobby_08").size() == 1, "bots fill on: an empty team may start")
	L._server_cancel_start(70)
	L._server_remove_peer(70)
	L._server_register_peer(71, "P71", "", "speedball", false, "lobby_07")
	L._server_register_peer(72, "P72", "", "speedball", false, "lobby_07")
	var snap: Dictionary = L._room_snapshot("lobby_07")
	var roster: Array = snap["room_roster"]
	_check(roster.size() == 2 and int(roster[0]["peer"]) == 71 and roster[0]["ready"] == false and roster[0].has("color"), "room_roster rows in join order, not ready (%s)" % [roster])
	(L.outbound_capture as Array).clear()
	L._server_set_ready(71, true)
	var syncs := _sent(72, "sync_lobby_state")
	_check(not syncs.is_empty() and syncs[-1]["args"][0]["room_roster"][0]["ready"] == true and int(syncs[-1]["args"][0]["ready_count"]) == 1, "set_ready broadcast in room_roster to the room")
	_check(_events("player_ready_changed", "lobby_07").size() == 1, "player_ready_changed event")
	L._server_set_ready(71, true)
	_check(_events("player_ready_changed", "lobby_07").size() == 1, "no-op ready toggle is not re-broadcast")
	# Start Match does not require everyone ready (72 is not ready).
	L._server_request_start(72, "speedball")
	var ms := _events("match_starting", "lobby_07")
	_check(ms.size() == 1 and int(ms[0]["data"]["in_ms"]) == 5000 and int(ms[0]["data"]["seconds"]) == 5 and int(ms[0]["data"]["by"]) == 72, "match_starting {in_ms:5000, seconds:5, by} even though not all ready")
	_check(_events("match_countdown", "lobby_07").size() == 1 and int(_events("match_countdown", "lobby_07")[0]["data"]["seconds_left"]) == 5, "match_countdown 5")
	_check(not bool(L.rooms["lobby_07"]["match"]["active"]) and _events("round_started", "lobby_07").is_empty(), "match not live during the countdown")
	L._server_request_start(71, "speedball")
	_check(_events("match_starting", "lobby_07").size() == 1, "second Start Match during the countdown is ignored")
	L._server_set_room_settings(71, "woodsball_crash", "")
	_check(L.rooms["lobby_07"]["settings"]["map"] == "speedball", "settings locked during the countdown")
	# cancel_start(): any player in the room stops the countdown and unlocks the settings.
	_advance(1000)
	L._server_cancel_start(71)
	var mc := _events("match_start_cancelled", "lobby_07")
	_check(mc.size() == 1 and int(mc[0]["data"]["by"]) == 71, "match_start_cancelled {by:71}")
	_check(not L.rooms["lobby_07"].has("countdown_until_ms") and L.room_status_of(L.rooms["lobby_07"]) == "waiting", "room back to waiting")
	_advance(6000)
	_check(not bool(L.rooms["lobby_07"]["match"]["active"]) and _events("round_started", "lobby_07").is_empty(), "cancelled countdown never starts the match")
	L._server_set_room_settings(71, "woodsball_crash", "")
	_check(L.rooms["lobby_07"]["settings"]["map"] == "woodsball_crash", "settings unlocked after cancel")
	L._server_set_room_settings(71, "speedball", "")
	ev.clear()
	L._server_request_start(71, "speedball")
	for i in 4:
		_advance(1000)
	var cd := _events("match_countdown", "lobby_07").map(func(e): return int(e["data"]["seconds_left"]))
	_check(cd == [5, 4, 3, 2, 1], "countdown 5,4,3,2,1 (%s)" % [cd])
	_advance(1000)
	_check(bool(L.rooms["lobby_07"]["match"]["active"]) and _events("round_started", "lobby_07").size() == 1, "round_started after the countdown")
	_check(_sent(71, "notify_match_start").size() == 1 and _sent(72, "notify_match_start").size() == 1, "notify_match_start to every player")
	L._end_room_match(L.rooms["lobby_07"], "ALPHA", "test")
	var r2: Array = L._room_snapshot("lobby_07")["room_roster"]
	_check(r2.all(func(r): return r["ready"] == false), "READY resets after the match")
	# A countdown is dropped when the room empties.
	L._server_request_start(71, "speedball")
	L._server_remove_peer(71)
	L._server_remove_peer(72)
	_advance(4000)
	_check(not L.rooms["lobby_07"].has("countdown_until_ms") and not bool(L.rooms["lobby_07"]["match"]["active"]), "countdown cancelled when the room empties")
	L.match_countdown_ms = 0
