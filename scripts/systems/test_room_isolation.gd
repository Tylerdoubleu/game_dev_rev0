extends SceneTree
## v0.5 PB-12 room isolation E2E: one dedicated server (the NetworkLobby autoload) + 5 in-process WebSocket
## clients, each its own NetworkLobby under a separate SceneMultiplayer root. Two in lobby_01, two in lobby_02,
## one in the ad-hoc private room "friends". A lobby_01 shot / state packet / elimination must never reach
## lobby_02 or friends, and a raw client .rpc() broadcast must not be relayed (server_relay = false).
## Run: godot --headless --path . -s res://scripts/systems/test_room_isolation.gd
const PORT := 19191
var LobbyScript: Script # loaded at runtime (preload would compile before the autoloads exist)
const CLIENTS := [
	{"key": "A1", "room": "lobby_01", "team": "ALPHA"},
	{"key": "A2", "room": "lobby_01", "team": "BRAVO"},
	{"key": "B1", "room": "LOBBY_02", "team": "ALPHA"},
	{"key": "B2", "room": "lobby_02", "team": "BRAVO"},
	{"key": "F1", "room": "friends", "team": "red"},
]
var server: Node
var cl := {}
var f := 0
var t := 0.0
var stage := 0
var stage_t := 0.0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _spawn_client(c: Dictionary) -> Node:
	var holder := Node.new()
	holder.name = "Client" + String(c["key"])
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var lobby: Node = LobbyScript.new()
	lobby.name = "NetworkLobby"
	holder.add_child(lobby)
	lobby.local_callsign = "P_" + String(c["key"])
	lobby.active_room = server.sanitize_room_id(String(c["room"]))
	lobby.local_team = server.normalize_team(String(c["team"]))
	lobby.connect_to_lobby("ws://127.0.0.1:%d/ws" % PORT)
	return lobby

func _all_registered() -> bool:
	return server.peer_room.size() == CLIENTS.size()

func _id(k: String) -> int:
	return (cl[k] as Node).multiplayer.get_unique_id()

func _process(delta: float) -> bool:
	f += 1
	t += delta
	stage_t += delta
	if f == 1:
		var scene := Node3D.new()
		scene.name = "IsoScene"
		root.add_child(scene)
		current_scene = scene
		server = root.get_node("NetworkLobby")
		LobbyScript = server.get_script()
		_check(server.start_dedicated_server(PORT) == OK, "dedicated server starts")
		_check((server.multiplayer as SceneMultiplayer).server_relay == false, "server_relay disabled on the room router")
		_check(server.rooms.size() == 10 and server.rooms.has("lobby_01") and server.rooms.has("lobby_10"), "10 permanent lobbies exist")
		for c in CLIENTS:
			cl[c["key"]] = _spawn_client(c)
		return false
	if t > 15.0:
		_check(false, "timed out at stage %d" % stage)
		return _finish()
	match stage:
		0:
			if _all_registered() and stage_t > 0.3:
				_check(server.peer_room[_id("A1")] == "lobby_01" and server.peer_room[_id("B1")] == "lobby_02", "peers routed into their rooms (LOBBY_02 normalised)")
				_check(server.rooms.has("friends") and not bool(server.rooms["friends"]["permanent"]), "ad-hoc private room 'friends' created on demand")
				_check(cl["A1"].players.size() == 2 and cl["B1"].players.size() == 2 and cl["F1"].players.size() == 1, "each client's roster only contains its room (A1=%d B1=%d F1=%d)" % [cl["A1"].players.size(), cl["B1"].players.size(), cl["F1"].players.size()])
				_check(not cl["B1"].players.has(_id("A1")) and not cl["F1"].players.has(_id("A2")), "lobby_02 / friends rosters never see lobby_01 peers")
				_check(cl["F1"].local_team == "ALPHA", "team=red maps to ALPHA")
				for k in cl.keys():
					cl[k].received_remote_shots = 0
				# A1 fires a sanctioned shot (rpc_id(1) -> server -> room relay) and sends state packets.
				cl["A1"].broadcast_paintball_shot(Vector3(0, 1.4, 40), Vector3(0, 0, -1), 59.0)
				for i in 3:
					cl["A1"].send_local_player_state(Vector3(1, 0, 40), 0.0, 0.0, 0.0, 0, false)
				# A spoofing client tries a raw broadcast to every peer; authority-only + server_relay=false must drop it.
				cl["A2"].rpc("rpc_fire_paintball", Vector3.ZERO, Vector3.FORWARD, 50.0, _id("A2"))
				cl["A2"].rpc("cl_room_event", "match_ended", {"winner": "BRAVO"})
				stage = 1
				stage_t = 0.0
		1:
			if stage_t > 0.6:
				_check(cl["A2"].received_remote_shots == 1, "lobby_01 room-mate A2 received A1's shot (%d)" % cl["A2"].received_remote_shots)
				_check(cl["B1"].received_remote_shots == 0 and cl["B2"].received_remote_shots == 0, "lobby_02 never receives the lobby_01 shot")
				_check(cl["F1"].received_remote_shots == 0, "friends room never receives the lobby_01 shot")
				_check(cl["A1"].received_remote_shots == 0, "spoofed raw .rpc() broadcast from A2 was not relayed to A1")
				_check(cl["A2"].remote_player_nodes.has(_id("A1")), "A2 sees A1's avatar from relayed state")
				_check(cl["B1"].remote_player_nodes.is_empty() and cl["F1"].remote_player_nodes.is_empty(), "no lobby_01 avatars spawn in lobby_02 / friends")
				var spoof_ok := true
				for k in cl.keys():
					for e in cl[k].received_room_events:
						if e["event"] == "match_ended":
							spoof_ok = false
				_check(spoof_ok, "spoofed client cl_room_event broadcast rejected everywhere")
				# Server-authoritative elimination inside lobby_01 (A2 on BRAVO hit by A1 on ALPHA).
				cl["A1"].notify_remote_player_hit(_id("A2"), Vector3(1, 1.0, 40))
				stage = 2
				stage_t = 0.0
		2:
			if stage_t > 0.5:
				var a2_elim: Array = (cl["A2"].received_room_events as Array).filter(func(e): return e["event"] == "player_eliminated")
				_check(a2_elim.size() == 1 and int(a2_elim[0]["data"]["victim"]) == _id("A2"), "lobby_01 victim A2 receives exactly one server player_eliminated")
				for k in ["B1", "B2", "F1"]:
					var leaked := (cl[k].received_room_events as Array).filter(func(e): return e["event"] == "player_eliminated")
					_check(leaked.is_empty(), "%s (other room) never receives lobby_01 player_eliminated" % k)
				# Settings change in lobby_02 stays in lobby_02.
				cl["B1"].select_mode("ctf")
				cl["B1"].select_map("woodsball_crash")
				stage = 3
				stage_t = 0.0
		3:
			if stage_t > 0.5:
				_check(cl["B2"].selected_mode == "ctf", "lobby_02 mode change synced to B2")
				_check(cl["A1"].selected_mode == "deathmatch" and String(server.rooms["lobby_01"]["settings"]["mode"]) == "deathmatch", "lobby_01 settings untouched by lobby_02")
				# Switching rooms moves the player; ad-hoc room is deleted when empty.
				cl["F1"].active_room = "lobby_01"
				cl["F1"]._send_registration()
				stage = 4
				stage_t = 0.0
		4:
			if stage_t > 0.5:
				_check(server.peer_room[_id("F1")] == "lobby_01", "re-registering with a new room moves the player")
				_check(not server.rooms.has("friends"), "empty ad-hoc room deleted")
				_check(cl["A1"].players.size() == 3, "lobby_01 roster now 3")
				(cl["A2"] as Node).disconnect_from_lobby()
				stage = 5
				stage_t = 0.0
		5:
			if stage_t > 0.6:
				_check(server.rooms["lobby_01"]["players"].size() == 2, "disconnect removes the peer from its room")
				return _finish()
	return false

func _finish() -> bool:
	print("=== [PASS] v0.5 room isolation ===" if fails.is_empty() else "=== [FAIL] room isolation: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true
