extends SceneTree
## v0.7 profile/clout hook (no sockets): tokens stay server-side, match-end payload rows are right.
## Run: godot --headless --path . -s res://scripts/systems/test_profile_hook.gd
const PORT := 19390
const STATE_PATH := "/tmp/pb_profile_hook_state.json"
var L: Node
var f := 0
var fails: Array[String] = []
const TOK_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const TOK_B := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	L = root.get_node("NetworkLobby")
	L.start_dedicated_server(PORT)
	L.outbound_capture = []
	L.match_countdown_ms = 0
	L.break_countdown_ms = 0
	for pid in [11, 12, 13, 14]:
		L._server_register_peer(pid, "P%d" % pid, "", "speedball", true, "lobby_03", "", "ctf")
	L._server_set_profile_token(11, TOK_A)
	L._server_set_profile_token(12, TOK_B.to_upper())
	L._server_set_profile_token(13, "not-a-token")
	_check(L._peer_profile_tokens.size() == 2, "only valid 64-hex tokens kept (%d)" % L._peer_profile_tokens.size())
	var room: Dictionary = L.rooms["lobby_03"]
	room["settings"]["mode"] = "ctf"
	L._start_room_match(room)
	var team11 := String(room["players"][11]["team"])
	var team12 := String(room["players"][12]["team"])
	room["players"][11]["kills"] = 3
	room["players"][11]["captures"] = 1
	room["players"][12]["kills"] = 1
	room["match"]["score"][team11] = 3
	room["match"]["score"][L.other_team(team11)] = 1
	L._end_room_match(room, team11, "rounds")
	var p: Dictionary = L.last_match_result_payload
	_check(p.get("room", "") == "lobby_03" and p.get("mode", "") == "ctf" and String(p.get("match_id", "")) != "", "payload header %s" % [p.keys()])
	var rows: Array = p.get("results", [])
	_check(rows.size() == 2, "one row per tokened human (%d)" % rows.size())
	var by_tok := {}
	for r in rows:
		by_tok[r["token"]] = r
	var a: Dictionary = by_tok.get(TOK_A, {})
	_check(a.get("won") == true and int(a.get("eliminations", -1)) == 3 and int(a.get("flags", -1)) == 1 and int(a.get("rounds_won", -1)) == 3, "winner row %s" % [a])
	var b: Dictionary = by_tok.get(TOK_B, {})
	var b_rounds := 3 if team12 == team11 else 1
	_check(b.get("won") == (team12 == team11) and int(b.get("eliminations", -1)) == 1 and int(b.get("rounds_won", -1)) == b_rounds, "second row %s" % [b])
	# tokens never leave the server
	var leaked := false
	for m in (L.outbound_capture as Array):
		var txt := var_to_str(m)
		if txt.contains(TOK_A) or txt.contains(TOK_B):
			leaked = true
	_check(not leaked, "no outbound RPC / room event carries a token (%d messages)" % (L.outbound_capture as Array).size())
	L.write_lobby_state_file(STATE_PATH)
	var doc := FileAccess.get_file_as_string(STATE_PATH)
	_check(not doc.contains(TOK_A) and not doc.contains(TOK_B), "lobby state file has no tokens")
	var snap := var_to_str(L._room_snapshot("lobby_03"))
	_check(not snap.contains(TOK_A) and not snap.contains(TOK_B), "room snapshot / roster has no tokens")
	room["settings"]["mode"] = "bots_test"
	_check(L.build_match_result_payload(room, team11, "bots_test").is_empty(), "bots_test earns no clout")
	L._server_remove_peer(11)
	_check(not L._peer_profile_tokens.has(11), "token dropped on disconnect")
	_check(L.is_valid_profile_token(TOK_B) and not L.is_valid_profile_token(TOK_B.substr(1)), "token validator")
	print("=== [PASS] v0.7 profile hook ===" if fails.is_empty() else "=== [FAIL] profile hook: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true
