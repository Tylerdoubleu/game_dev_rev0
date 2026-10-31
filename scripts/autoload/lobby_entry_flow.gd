extends Node
## v0.5 entry flow (Tim): shows Ren's LobbyBrowser when the web build is opened without ?room= (the always-on
## lobby link), and from a "BROWSE ONLINE LOBBIES" button added to the arena's lobby menu.
##   JOIN  -> LobbyBrowser navigates to the lobby's join_url (web) / connects directly (desktop).
##   SOLO  -> the existing offline flow: NPC presence ON + DROP IN (5 OpFor bots).
## A link with ?room= skips the browser: NetworkLobby auto-joins that room and the waiting room opens for it.
## v0.6.4: with no deep link (web or desktop) Ren's TitleScreen shows first (run_entry / entry_action).
## Kept out of speedball_arena_builder.gd (Bluey): it only calls the arena's existing public-ish methods.

const LobbyBrowserScript := preload("res://scripts/ui/lobby_browser.gd")
const WaitingRoomScript := preload("res://scripts/ui/lobby_waiting_room.gd")
const LAYER := 60

var browser: Control = null
var waiting_room: Control = null  # Ren v0.5: in-place JOIN -> waiting room -> START MATCH
var _layer: CanvasLayer = null
var _menu_button: Button = null
var solo_starts: int = 0

func _ready() -> void:
	if NetworkLobby.is_dedicated_server:
		return
	call_deferred("_attach_to_scene")

func _attach_to_scene() -> void:
	# Wait for the main scene (the arena builds its lobby overlay in _ready).
	for _i in 10:
		if get_tree().current_scene != null:
			break
		await get_tree().process_frame
	_add_menu_button()
	NetworkLobby.match_started_signal.connect(_on_match_started)
	NetworkLobby.left_room.connect(_on_left_room)
	NetworkLobby.returned_to_lobby.connect(_on_returned_to_lobby)
	var cmdline: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not OS.get_environment("LOBBY_WS_URL").is_empty():
		cmdline.append("--ws=" + OS.get_environment("LOBBY_WS_URL"))
	# Headless runs (CI / test runners driving the arena) never get the title screen on top of them.
	run_entry(_page_query(), cmdline, DisplayServer.get_name() != "headless")

## v0.6.4 title screen entry. Returns what happened: "title", "browser", "room_link" or "none".
func run_entry(query: String, cmdline: Array, allow_title: bool = true) -> String:
	var title_ok := allow_title and ResourceLoader.exists(title_screen_path)
	var action := entry_action(query, cmdline, NetworkLobby.is_dedicated_server, title_ok,
		NetworkLobby.show_lobby_browser_on_start, NetworkLobby.room_from_url and OS.has_feature("web"))
	match action:
		"title":
			if show_title_screen() == null:
				action = "browser" if NetworkLobby.show_lobby_browser_on_start else "none"
				if action == "browser":
					open_browser()
		"browser":
			open_browser()
		"room_link":
			# A shared ?room= link lands in that lobby's waiting room (NetworkLobby already auto-connects), never
			# straight into the arena; the match starts from START MATCH like an in-place JOIN.
			open_room_link_waiting_room()
	last_entry_action = action
	return action

## Pure decision (tests). Order:
##   dedicated server -> "none";
##   deep link (is_deep_link) -> today's behavior: "browser" if the page asked for it, "room_link" for a web
##     ?room= link, else "none" (?solo=ffa is started by the arena itself);
##   no deep link -> "title" (web and desktop) when Ren's title_screen.gd exists; else today's fallback:
##     "browser" for a bare web link (browser_on_start), "none" on desktop (the arena menu).
static func entry_action(query: String, cmdline: Array, dedicated: bool, title_available: bool,
		browser_on_start: bool = false, web_room_link: bool = false) -> String:
	if dedicated:
		return "none"
	if is_deep_link(query, cmdline):
		if browser_on_start:
			return "browser"
		if web_room_link:
			return "room_link"
		return "none"
	if title_available:
		return "title"
	return "browser" if browser_on_start else "none"

## A deep link already picks a destination: ?room= / ?server= (ws, edgegap) / quickjoin / ?solo= (tier=) /
## ?lobby= / ?team=, or the command-line flags --room= / --ws= / --server= (LOBBY_WS_URL counts as --ws=).
const DEEP_LINK_KEYS := ["room", "server", "ws", "edgegap", "quickjoin", "quick_join", "quick", "solo", "tier", "lobby", "team"]
const DEEP_LINK_FLAGS := ["--room=", "--ws=", "--server=", "--solo", "--quickjoin"]

static func is_deep_link(query: String, cmdline: Array) -> bool:
	var clean := query.strip_edges().trim_prefix("?")
	if not clean.is_empty():
		for pair in clean.split("&"):
			var kv := pair.split("=", true, 1)
			var key := kv[0].uri_decode().strip_edges().to_lower()
			var val := kv[1].uri_decode().strip_edges() if kv.size() == 2 else ""
			if key in DEEP_LINK_KEYS and (val != "" or key.begins_with("quick")):
				return true
	for a in cmdline:
		var arg := String(a)
		for flag in DEEP_LINK_FLAGS:
			if arg.begins_with(flag):
				return true
	return false

## Ren's TitleScreen (scripts/ui/title_screen.gd, script-built). Loaded by path (no class_name / preload) so this
## works before it lands; its MULTIPLAYER button calls open_browser() itself.
const TITLE_SCREEN_PATH := "res://scripts/ui/title_screen.gd"
const TITLE_LAYER := 60
var title_screen_path: String = TITLE_SCREEN_PATH  # tests point this at a stub
var title_screen: Node = null
var title_layer: CanvasLayer = null
var last_entry_action: String = ""

func show_title_screen() -> Node:
	if not ResourceLoader.exists(title_screen_path):
		return null
	var scr := load(title_screen_path) as Script
	if scr == null or not scr.can_instantiate():
		return null
	var node: Variant = scr.new()
	if not (node is Node):
		return null
	if title_layer == null or not is_instance_valid(title_layer):
		title_layer = CanvasLayer.new()
		title_layer.name = "TitleScreenLayer"
		title_layer.layer = TITLE_LAYER
		add_child(title_layer)
	title_screen = node
	title_screen.name = "TitleScreen"
	title_layer.add_child(title_screen)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return title_screen

static func _page_query() -> String:
	if not OS.has_feature("web"):
		return ""
	var q: Variant = JavaScriptBridge.eval("window.location.search || ''", true)
	return String(q) if typeof(q) == TYPE_STRING else ""

## Waiting room for the room named by the page link (?room=&map=), e.g. an old join_url or a friend's invite.
func open_room_link_waiting_room() -> Control:
	var rid := NetworkLobby.active_room
	var entry := {"id": rid, "name": rid.replace("_", " ").capitalize(), "map": NetworkLobby.selected_map}
	return open_waiting_room(entry)

func is_open() -> bool:
	return browser != null and is_instance_valid(browser) and _layer != null and _layer.visible

func open_browser() -> Control:
	if browser == null or not is_instance_valid(browser):
		_layer = CanvasLayer.new()
		_layer.name = "LobbyBrowserLayer"
		_layer.layer = LAYER
		add_child(_layer)
		browser = LobbyBrowserScript.new()
		browser.name = "LobbyBrowser"
		browser.api_base = LobbyBrowserScript.derive_api_base(_explicit_server_url())
		browser.navigate_on_join = false
		browser.lobby_join_requested.connect(_on_lobby_join_requested)
		browser.solo_requested.connect(_on_solo_requested)
		_layer.add_child(browser)
		var close := Button.new()
		close.name = "CloseLobbyBrowser"
		close.text = "X  BACK TO MENU"
		close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		close.position = Vector2(-200, 16)
		close.custom_minimum_size = Vector2(180, 40)
		close.pressed.connect(close_browser)
		_layer.add_child(close)
	_layer.visible = true
	browser.visible = true
	if waiting_room != null and is_instance_valid(waiting_room):
		waiting_room.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if browser.has_method("refresh") and browser.is_inside_tree():
		browser.call("refresh")
	return browser

func close_browser() -> void:
	if _layer != null:
		_layer.visible = false

## ?server= from the page URL (or a manual URL), else this build's default server (NetworkLobby.default_ws_url: live,
## or test.jeetball.com for a test build / a page served from the test server).
func _explicit_server_url() -> String:
	return NetworkLobby.current_ws_url if NetworkLobby.server_from_url else NetworkLobby.default_ws_url

func _on_lobby_join_requested(entry: Dictionary) -> void:
	# Ren v0.5: JOIN connects to the lobby in place (web and desktop) and shows the waiting room; the match only
	# starts when someone presses START MATCH there.
	var url := String(entry.get("join_url", ""))
	var server := _query_value(url, "server")
	NetworkLobby.active_room = NetworkLobby.sanitize_room_id(String(entry.get("id", "lobby_01")))
	NetworkLobby.room_from_url = true
	var m := String(entry.get("map", ""))
	if m != "":
		NetworkLobby.selected_map = NetworkLobby.normalize_map(m)
	open_waiting_room(entry)
	if NetworkLobby.is_online_client():
		NetworkLobby.disconnect_from_lobby()
	NetworkLobby.connect_to_lobby(server if server != "" else _explicit_server_url())

func open_waiting_room(entry: Dictionary) -> Control:
	if _layer == null:
		open_browser()
	if waiting_room == null or not is_instance_valid(waiting_room):
		waiting_room = WaitingRoomScript.new()
		waiting_room.name = "LobbyWaitingRoom"
		waiting_room.leave_requested.connect(_on_leave_waiting_room)
		_layer.add_child(waiting_room)
	waiting_room.call("set_lobby", entry)
	waiting_room.visible = true
	if browser != null and is_instance_valid(browser):
		browser.visible = false
	var close := _layer.get_node_or_null("CloseLobbyBrowser")
	if close != null:
		close.visible = false
	_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return waiting_room

func _on_leave_waiting_room() -> void:
	var close := _layer.get_node_or_null("CloseLobbyBrowser")
	if close != null:
		close.visible = true
	open_browser()

func _on_match_started(_room: String, _bracket: String, _fill_bots: bool) -> void:
	if not is_open():
		return
	close_browser()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("_set_lobby_overlay_visible"):
		scene.call("_set_lobby_overlay_visible", false)

func _on_solo_requested() -> void:
	solo_starts += 1
	close_browser()
	if NetworkLobby.is_online_client() and NetworkLobby.has_method("disconnect_from_lobby"):
		NetworkLobby.call("disconnect_from_lobby")
	NetworkLobby.fill_bots_enabled = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("_select_npc_presence") and scene.has_method("_on_drop_in_pressed"):
		scene.call("_select_npc_presence", true)
		scene.call("_on_drop_in_pressed")
	else:
		NetworkLobby.request_start_match(NetworkLobby.active_room, NetworkLobby.local_bracket, true)

## Adds a "BROWSE ONLINE LOBBIES" button to the arena's lobby overlay (CanvasLayer lobby_canvas) at runtime.
func _add_menu_button() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var canvas: Variant = scene.get("lobby_canvas")
	if not (canvas is CanvasLayer) or not is_instance_valid(canvas):
		return
	_menu_button = Button.new()
	_menu_button.name = "BrowseOnlineLobbiesButton"
	_menu_button.text = "BROWSE ONLINE LOBBIES"
	_menu_button.custom_minimum_size = Vector2(260, 46)
	_menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_menu_button.position = Vector2(16, 16)
	_menu_button.pressed.connect(func() -> void: open_browser())
	(canvas as CanvasLayer).add_child(_menu_button)

static func _query_value(url: String, key: String) -> String:
	var q := url.split("?", true, 1)
	if q.size() < 2:
		return ""
	for pair in q[1].split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and kv[0].uri_decode().to_lower() == key:
			return kv[1].uri_decode()
	return ""

## v0.5: NetworkLobby.leave_room() -> back to the lobby list.
var left_room_count: int = 0
func _on_left_room(_room_id: String) -> void:
	left_room_count += 1
	if _layer != null:
		var close := _layer.get_node_or_null("CloseLobbyBrowser")
		if close != null:
			close.visible = true
	open_browser()

## v0.5: after the match recap (MATCH_RESULTS_MS) the server sends everyone back to the room's waiting room.
var returned_count: int = 0
func _on_returned_to_lobby(room_id: String) -> void:
	returned_count += 1
	var rid := room_id if room_id != "" else NetworkLobby.active_room
	var entry := {"id": rid, "name": rid.replace("_", " ").capitalize(), "map": NetworkLobby.selected_map}
	open_waiting_room(entry)
	var scene := get_tree().current_scene
	if scene != null:
		var sb: Variant = scene.get("scoreboard_canvas")
		if sb is CanvasLayer and is_instance_valid(sb):
			(sb as CanvasLayer).visible = false
