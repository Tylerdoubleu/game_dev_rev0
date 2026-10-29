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
	_test_ipc_document()
	for t in ["_test_team_balance", "_test_lobby_settings", "_test_deathmatch", "_test_ctf_best_of_5", "_test_bots_test_mode", "_test_hit_validation"]:
		if has_method(t):
			L.start_dedicated_server(PORT + 1 + f)
			L.outbound_capture = []
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
