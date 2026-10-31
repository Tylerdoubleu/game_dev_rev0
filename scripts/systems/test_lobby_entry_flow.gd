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

## v0.6.4 title screen entry: deep links skip it, a bare start shows it (stub script), missing script -> fallback.
func _test_title_entry(flow: Node, L: Node) -> void:
	print("--- title screen entry ---")
	var E: Script = flow.get_script()
	var deep := ["?room=lobby_03", "?server=wss://test.jeetball.com/ws", "?ws=wss://h/ws", "?quickjoin=1", "?quickjoin",
		"?solo=ffa", "?solo=ffa&tier=rookie", "?tier=amateur", "?lobby=lobby_02", "?team=bravo", "?map=woodsball&room=x"]
	for q in deep:
		_check(E.is_deep_link(q, []) and E.entry_action(q, [], false, true) != "title", "deep link %s skips the title" % q)
	for flag in ["--room=lobby_02", "--ws=ws://127.0.0.1:8910/ws", "--server=wss://h/ws"]:
		_check(E.entry_action("", [flag], false, true) != "title", "flag %s skips the title" % flag)
	_check(not E.is_deep_link("?map=woodsball&name=Tyler&bots=1", ["--name=Tyler"]) and not E.is_deep_link("?room=", []), "map/name/bots or an empty ?room= are not deep links")
	_check(E.entry_action("", [], false, true) == "title" and E.entry_action("?map=speedball", [], false, true, true) == "title", "no deep link -> title (desktop and web)")
	_check(E.entry_action("", [], false, false, true) == "browser" and E.entry_action("", [], false, false, false) == "none", "no title script -> today's fallback (web browser / desktop menu)")
	_check(E.entry_action("?room=lobby_01", [], false, true, false, true) == "room_link" and E.entry_action("?solo=ffa", [], false, true, true) == "browser" and E.entry_action("?solo=ffa", [], false, true) == "none", "deep links keep today's behavior")
	_check(E.entry_action("", [], true, true) == "none" and E.entry_action("?room=x", [], true, true, true) == "none", "dedicated server shows nothing")
	# run_entry with a stub TitleScreen script (Ren's file isn't on test yet).
	var stub := GDScript.new()
	stub.source_code = "extends Control\nvar made := true\n"
	stub.reload()
	ResourceSaver.save(stub, "user://title_screen_stub.gd")
	flow.title_screen_path = "user://title_screen_stub.gd"
	var opened_before: bool = flow.is_open()
	_check(flow.run_entry("?room=lobby_05", [], true) != "title" and flow.title_screen == null, "run_entry: deep link never instances the title")
	var act: String = flow.run_entry("", [], true)
	_check(act == "title" and flow.title_screen is Control and bool(flow.title_screen.get("made")), "run_entry: no link instances the TitleScreen script (%s)" % act)
	_check(flow.title_layer is CanvasLayer and flow.title_layer.layer >= 60 and flow.title_screen.get_parent() == flow.title_layer, "title on a CanvasLayer at layer >= 60")
	_check(flow.is_open() == opened_before, "title path does not also open the browser")
	_check(flow.run_entry("", [], false) != "title", "allow_title=false (headless) skips it")
	flow.title_layer.queue_free()
	flow.title_screen = null
	flow.title_layer = null
	flow.title_screen_path = "res://scripts/ui/__missing_title_screen.gd"
	var old_bos: bool = L.show_lobby_browser_on_start
	L.show_lobby_browser_on_start = true
	_check(flow.run_entry("", [], true) == "browser" and flow.is_open() and flow.title_screen == null, "missing title script -> falls back to open_browser()")
	flow.close_browser()
	L.show_lobby_browser_on_start = old_bos
	var was_ded: bool = L.is_dedicated_server
	L.is_dedicated_server = true
	flow.title_screen_path = "user://title_screen_stub.gd"
	_check(flow.run_entry("", [], true) == "none" and flow.title_screen == null and not flow.is_open(), "dedicated server: run_entry shows nothing")
	L.is_dedicated_server = was_ded
	flow.title_screen_path = flow.TITLE_SCREEN_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title_screen_stub.gd"))

func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	var flow := root.get_node("LobbyEntryFlow")
	var L := root.get_node("NetworkLobby")
	print("--- LobbyEntryFlow ---")
	_check(not L.show_lobby_browser_on_start and not flow.is_open(), "desktop/headless start does not force the browser")
	_check(flow.last_entry_action == "none" and flow.title_screen == null, "headless start: no title screen, no browser (%s)" % flow.last_entry_action)
	_test_title_entry(flow, L)
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
