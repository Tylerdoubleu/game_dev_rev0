extends Node
## v0.5 entry flow (Tim): shows Ren's LobbyBrowser when the web build is opened without ?room= (the always-on
## lobby link), and from a "BROWSE ONLINE LOBBIES" button added to the arena's lobby menu.
##   JOIN  -> LobbyBrowser navigates to the lobby's join_url (web) / connects directly (desktop).
##   SOLO  -> the existing offline flow: NPC presence ON + DROP IN (5 OpFor bots).
## A link with ?room= skips the browser and NetworkLobby auto-joins that room as before.
## Kept out of speedball_arena_builder.gd (Bluey): it only calls the arena's existing public-ish methods.

const LobbyBrowserScript := preload("res://scripts/ui/lobby_browser.gd")
const LAYER := 60

var browser: Control = null
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
	if NetworkLobby.show_lobby_browser_on_start:
		open_browser()

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if browser.has_method("refresh") and browser.is_inside_tree():
		browser.call("refresh")
	return browser

func close_browser() -> void:
	if _layer != null:
		_layer.visible = false

## ?server= from the page URL (or a manual URL), else the always-on server (NetworkLobby.DEFAULT_PUBLIC_WS_URL).
func _explicit_server_url() -> String:
	return NetworkLobby.current_ws_url if NetworkLobby.server_from_url else NetworkLobby.DEFAULT_PUBLIC_WS_URL

func _on_lobby_join_requested(entry: Dictionary) -> void:
	if OS.has_feature("web"):
		return # LobbyBrowser.join() already navigates to entry.join_url (page reload with ?room=).
	# Desktop / editor: connect in-process to the lobby's server and room.
	var url := String(entry.get("join_url", ""))
	var server := _query_value(url, "server")
	NetworkLobby.active_room = NetworkLobby.sanitize_room_id(String(entry.get("id", "lobby_01")))
	NetworkLobby.room_from_url = true
	var m := String(entry.get("map", ""))
	if m != "":
		NetworkLobby.selected_map = NetworkLobby.normalize_map(m)
	close_browser()
	NetworkLobby.connect_to_lobby(server if server != "" else NetworkLobby.DEFAULT_PUBLIC_WS_URL)

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
