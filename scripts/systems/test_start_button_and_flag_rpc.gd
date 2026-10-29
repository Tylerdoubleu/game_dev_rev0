extends SceneTree
## v0.5: (1) the in-arena lobby menu start button (">> DROP IN TO ARENA <<", SpeedballArenaBuilder._on_drop_in_pressed)
## goes through the room start when online - request_start_match + waiting room, menu stays up (no practice-mode
## limbo during the 5 s countdown) until notify_match_start - and is still a direct drop-in offline (solo / bots).
## (2) client flag sends only use NetworkLobby.broadcast_flag_event(...) with the server's 4-arg srv_flag_event
## signature (event_type, player_name, team, world_pos); nothing calls srv_flag_event directly.
## Online is real: a local WebSocket server peer on 127.0.0.1 that NetworkLobby connects to as a client.
## Run: godot --headless --path . -s scripts/systems/test_start_button_and_flag_rpc.gd

const PORT := 19187
var arena: Node
var server_peer: WebSocketMultiplayerPeer
var failures: Array[String] = []
var started := false
var match_started_count := 0

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	if server_peer != null:
		server_peer.poll()
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _on_match_started(_r: String, _b: String, _f: bool) -> void:
	match_started_count += 1

func _run() -> void:
	await _frames(3)
	var nl := root.get_node("NetworkLobby")
	nl.match_started_signal.connect(_on_match_started)
	var flow := root.get_node_or_null("LobbyEntryFlow")

	print("[1] flag RPC signature")
	_flag_signature_checks(nl)

	print("[2] online start button -> room start + waiting room, menu stays up")
	server_peer = WebSocketMultiplayerPeer.new()
	_check(server_peer.create_server(PORT) == OK, "local test ws server on %d" % PORT)
	nl.active_room = "btntest"
	nl.connect_to_lobby("ws://127.0.0.1:%d/ws" % PORT)
	for i in range(240):
		await _frames(1)
		if nl.is_online_client():
			break
	_check(nl.is_online_client(), "NetworkLobby connected as an online client")
	arena.call("_set_lobby_overlay_visible", true)
	var room_input: LineEdit = arena.get("room_input")
	if room_input != null:
		room_input.text = "btntest"
	var lobby_canvas: CanvasLayer = arena.get("lobby_canvas")
	var player: Node = arena.get("player")
	await _frames(2)
	while server_peer.get_available_packet_count() > 0:
		server_peer.get_packet()
	var starts_before := match_started_count
	arena.call("_on_drop_in_pressed")
	await _frames(4)
	_check(lobby_canvas != null and lobby_canvas.visible, "online: lobby menu NOT hidden on press")
	_check(bool(player.get("lobby_open")), "online: player still locked in the menu (no practice limbo)")
	_check(bool(arena.get("awaiting_online_start")) and int(arena.get("online_start_requests")) == 1, "online: start routed through request_start_match")
	_check(not bool(nl.match_active) and match_started_count == starts_before, "online: no local drop-in before the server says go")
	var got := 0
	while server_peer.get_available_packet_count() > 0:
		server_peer.get_packet()
		got += 1
	_check(got > 0, "online: request_start_match RPC reached the server (%d packet(s))" % got)
	if flow != null:
		var wr: Control = flow.get("waiting_room")
		_check(wr != null and wr.visible and flow.call("is_open"), "online: Ren's waiting room is shown")
	nl.notify_match_start("btntest", "speedball", false)
	await _frames(2)
	_check(not lobby_canvas.visible and not bool(arena.get("awaiting_online_start")), "notify_match_start drops everyone in: menu hidden")
	_check(flow == null or not bool(flow.call("is_open")), "waiting room closes on match start")

	print("[3] offline start button = direct drop-in")
	nl.disconnect_from_lobby()
	server_peer.close()
	server_peer = null
	await _frames(2)
	_check(not nl.is_online_client(), "offline now")
	arena.call("_set_lobby_overlay_visible", true)
	var before := match_started_count
	var req_before := int(arena.get("online_start_requests"))
	arena.call("_on_drop_in_pressed")
	await _frames(2)
	_check(not lobby_canvas.visible and not bool(player.get("lobby_open")), "offline: menu hides, straight into the arena")
	_check(match_started_count == before + 1 and int(arena.get("online_start_requests")) == req_before, "offline: local match start, no room start")
	_finish()

func _flag_signature_checks(nl: Node) -> void:
	var srv_args := -1
	var wrap_args := -1
	for m in nl.get_method_list():
		if String(m["name"]) == "srv_flag_event":
			srv_args = (m["args"] as Array).size()
		elif String(m["name"]) == "broadcast_flag_event":
			wrap_args = (m["args"] as Array).size()
	_check(srv_args == 4, "server srv_flag_event takes 4 args (event_type, player_name, team, world_pos): %d" % srv_args)
	_check(wrap_args == 4, "client wrapper broadcast_flag_event takes the same 4 args: %d" % wrap_args)
	var files: Array[String] = []
	_collect("res://scripts", files)
	var direct := 0
	var calls := 0
	var bad: Array[String] = []
	for path in files:
		if path.ends_with("network_lobby.gd") or path.get_file().begins_with("test_"):
			continue
		var src := FileAccess.get_file_as_string(path)
		if src.contains("srv_flag_event"):
			direct += 1
			bad.append(path)
		var idx := src.find("broadcast_flag_event(")
		while idx != -1:
			var args := _top_level_arg_count(src, idx + "broadcast_flag_event(".length())
			calls += 1
			if args != 4:
				bad.append("%s:%d args" % [path, args])
			idx = src.find("broadcast_flag_event(", idx + 1)
	_check(direct == 0, "no client script calls srv_flag_event directly %s" % [bad])
	_check(calls >= 1 and bad.is_empty(), "every client flag send uses broadcast_flag_event with 4 args (%d call sites)" % calls)
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/match_hud_client.gd")
	_check(not hud_src.contains("flag_event(") and not hud_src.contains(".rpc"), "MatchHudClient sends nothing (CTF pickup/capture is server proximity)")

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_collect(dir_path.path_join(sub), out)

## counts comma-separated args at depth 0 starting right after "("
func _top_level_arg_count(src: String, start: int) -> int:
	var depth := 0
	var count := 1
	var i := start
	var any := false
	while i < src.length():
		var ch := src[i]
		if ch in ["(", "[", "{"]:
			depth += 1
		elif ch in [")", "]", "}"]:
			if depth == 0:
				return count if any else 0
			depth -= 1
		elif ch == "," and depth == 0:
			count += 1
		elif ch != " ":
			any = true
		i += 1
	return -1

func _finish() -> void:
	if failures.is_empty():
		print("START BUTTON + FLAG RPC TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("START BUTTON + FLAG RPC TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
