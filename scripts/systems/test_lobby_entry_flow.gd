extends SceneTree
## v0.5 entry flow: LobbyBrowser wiring (LobbyEntryFlow autoload) on top of the arena scene.
## Run: godot --headless --path . -s res://scripts/systems/test_lobby_entry_flow.gd
var f := 0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _initialize() -> void:
	var arena := (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	var flow := root.get_node("LobbyEntryFlow")
	var L := root.get_node("NetworkLobby")
	print("--- LobbyEntryFlow ---")
	_check(not L.show_lobby_browser_on_start and not flow.is_open(), "desktop/headless start does not force the browser")
	# URL parsing: bare link vs ?room= link.
	L.room_from_url = false
	L.server_from_url = false
	L._parse_query_string("?map=speedball")
	_check(not L.room_from_url and not L.server_from_url, "bare link: no room, default server")
	L._parse_query_string("?server=wss://play.jeetball.com/ws&room=lobby_03&map=woodsball_crash")
	_check(L.room_from_url and L.active_room == "lobby_03" and L.server_from_url and L.current_ws_url == "wss://play.jeetball.com/ws", "join_url link: room + server parsed (%s %s)" % [L.active_room, L.current_ws_url])
	# v0.7 test/play split: lobby count setting + per-build default server.
	_check(L.parse_lobby_count("") == 10 and L.parse_lobby_count("2") == 2 and L.parse_lobby_count("0") == 1 and L.parse_lobby_count("99") == 10 and L.parse_lobby_count("x") == 10, "LOBBY_COUNT parsing (default 10, clamped 1..10)")
	var old_count: int = L.permanent_lobby_count
	L.permanent_lobby_count = 2
	_check(L.is_permanent_room_id("lobby_02") and not L.is_permanent_room_id("lobby_03"), "LOBBY_COUNT=2: only lobby_01..02 are permanent")
	L.permanent_lobby_count = old_count
	_check(L.build_default_ws_url() == "wss://play.jeetball.com/ws" and L.default_ws_url == "wss://play.jeetball.com/ws", "unstamped build defaults to the live server")
	_check(flow._explicit_server_url() == L.default_ws_url, "bare link uses the build's default server")
	L.room_from_url = false
	L.server_from_url = false
	L.active_room = "alpha"
	L.selected_map = "speedball"
	_check(flow._query_value("https://x/?server=wss%3A%2F%2Fh%2Fws&room=lobby_02", "server") == "wss://h/ws", "join_url query helper decodes server")
	var lc: Variant = current_scene.get("lobby_canvas")
	var btn: Node = (lc as Node).find_child("BrowseOnlineLobbiesButton", true, false) if lc is Node else null
	_check(btn is Button, "BROWSE ONLINE LOBBIES button added to the arena lobby menu")
	if btn is Button:
		(btn as Button).pressed.emit()
	_check(flow.is_open() and flow.browser is LobbyBrowser, "menu button opens Ren's LobbyBrowser")
	_check(flow.browser.api_base == "https://play.jeetball.com", "browser defaults to the always-on server API (%s)" % flow.browser.api_base)
	_check(flow.browser.lobby_join_requested.is_connected(flow._on_lobby_join_requested) and flow.browser.solo_requested.is_connected(flow._on_solo_requested), "join/solo signals connected")
	L.match_active = false
	flow.browser.solo_requested.emit()
	_check(flow.solo_starts == 1 and not flow.is_open(), "SOLO closes the browser")
	_check(L.fill_bots_enabled and L.match_active and not L.is_online_client(), "SOLO starts the offline bots match")
	var lc_vis: bool = (lc as CanvasLayer).visible if lc is CanvasLayer else true
	_check(not lc_vis, "arena lobby overlay dropped in")
	# ?room= link: opens that room's waiting room instead of dropping into the arena.
	L.active_room = "lobby_04"
	L.selected_map = "woodsball_crash"
	var wr: Control = flow.open_room_link_waiting_room()
	_check(wr != null and wr.visible and flow._layer.visible and not flow.browser.visible, "?room= link opens the waiting room (not the arena)")
	_check(String(wr.get("lobby_name")) == "LOBBY 04", "room-link waiting room titled for its lobby (%s)" % wr.get("lobby_name"))
	# leave_room(): clean leave back to the lobby list.
	var left: Array = []
	L.left_room.connect(func(r): left.append(r))
	L.active_room = "lobby_03"
	L.room_from_url = true
	L.room_state = {"room": "lobby_03"}
	L.local_ready = true
	L.leave_room()
	_check(left == ["lobby_03"] and flow.left_room_count == 1, "leave_room emits left_room(lobby_03)")
	_check(not L.room_from_url and L.active_room == L.DEFAULT_ROOM and not L.match_active and L.room_state.is_empty() and not L.local_ready and L.peer == null, "leave_room clears room/match/ready state and the peer")
	_check(flow.is_open(), "leave_room returns to the lobby list")
	L.set_ready(true)
	_check(L.local_ready and bool(L.players[1]["ready"]), "set_ready offline updates the local roster")
	print("=== [PASS] lobby entry flow ===" if fails.is_empty() else "=== [FAIL] lobby entry flow: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true
