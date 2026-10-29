extends Node
const ProPaintballRig3DScript = preload("res://scripts/player/pro_paintball_rig_3d.gd")

const ProRigScript := preload("res://scripts/player/pro_paintball_rig_3d.gd")

const GrittyArtTheme = preload("res://scripts/systems/gritty_art_theme.gd")

## WebSocket Click-to-Lobby & Authoritative Room Router (PB-05, v0.5 PB-12 multi-room isolation).
## Supports:
## - Dedicated headless server mode (--server or DEDICATED_SERVER=1) on port 9080 (or WS_PORT /
##   ARBITRIUM_PORT_WS_INTERNAL) behind server/server.js (HTTP + /ws proxy + /api/lobbies).
## - Browser auto-join via URL query parameters (?server=wss://...&room=lobby_01&map=speedball&mode=ctf&team=ALPHA)
## - v0.5 rooms: the server keeps rooms[room_id] = {players, settings:{map, mode}, match}. Ten permanent lobbies
##   (lobby_01..lobby_10, 5 per team) always exist; any other ?room= (e.g. room=friends) is an ad-hoc private room
##   that is created on first join, never listed, and deleted when empty.
## - Every client RPC goes to the server only (rpc_id(1, ...)); SceneMultiplayer.server_relay is OFF on the server,
##   so a client can never reach another client directly. The server relays shots / state / events only to peers
##   in the sender's room. See docs/NETWORK_EVENTS.md.

signal lobby_state_changed(state_dict: Dictionary)
signal connection_status_changed(status_text: String, is_online: bool)
signal match_started_signal(room_id: String, bracket_id: String, fill_bots: bool)
signal map_changed(map_id: String)
signal remote_player_hit_local(shooter_name: String)
signal local_player_scored_kill(victim_name: String)
signal match_over_networked(loser_name: String, winner_name: String)
signal flag_event_received(event_type: String, player_name: String, team: String, world_pos: Vector3)
## v0.5: every documented server room event (see docs/NETWORK_EVENTS.md) is emitted here on clients.
signal room_event(event_name: String, data: Dictionary)
signal mode_changed(mode_id: String)

const DEFAULT_WS_PORT: int = 9080

## --- v0.5 room constants ---
const PERMANENT_LOBBY_COUNT: int = 10
const MAX_PER_TEAM: int = 5
const DEFAULT_ROOM: String = "alpha"
const MAPS: Array[String] = ["speedball", "woodsball_crash"]
const MODES: Array[String] = ["deathmatch", "ctf", "bots_test"]
const TEAMS: Array[String] = ["ALPHA", "BRAVO"] # ALPHA = "red" (south gate, +Z), BRAVO = "blue" (north gate, -Z)

var peer: WebSocketMultiplayerPeer = null
var is_dedicated_server: bool = false
var is_connected_to_server: bool = false
var is_connecting: bool = false

var current_ws_url: String = "ws://127.0.0.1:9080/ws"
var active_room: String = DEFAULT_ROOM
var local_callsign: String = "NPPL_Pro"
var local_team: String = "ALPHA"
var local_bracket: String = "speedball"
var local_ready: bool = true
var fill_bots_enabled: bool = false
var selected_map: String = "speedball"
var active_map: String = "speedball"
var selected_mode: String = "deathmatch"
var room_status: String = "waiting"
var match_active: bool = true
## True when the page / process was launched with an explicit ?room= (or --room=).
var room_from_url: bool = false

## Clients: the roster of the room we are in (peer_id -> {name, team, bracket, ready, room, kills, deaths, alive}).
## Server: every registered peer (same dictionaries as rooms[rid]["players"]).
var players: Dictionary = {}

## Server only: room_id -> {id, name, permanent, players: {peer_id: info}, settings: {map, mode}, match: Dictionary}
var rooms: Dictionary = {}
## Server only: peer_id -> room_id
var peer_room: Dictionary = {}
## Client: last public room state from the server (status, settings, match summary).
var room_state: Dictionary = {}

## Counters for diagnostics / headless tests.
var received_remote_shots: int = 0
var received_room_events: Array = []
var relayed_message_count: int = 0

## Spawned 3D remote player avatars in the current scene: peer_id (int) -> StaticBody3D
var remote_player_nodes: Dictionary = {}

func _ready() -> void:
	_generate_default_callsign()
	_connect_multiplayer_signals()
	_parse_runtime_environment_and_url()

	if is_dedicated_server:
		var port := _resolve_dedicated_ws_port()
		start_dedicated_server(port)
	else:
		# Auto-connect on Web or if LOBBY_WS_URL / ?server= was provided
		if OS.has_feature("web") or not OS.get_environment("LOBBY_WS_URL").is_empty():
			connect_to_lobby(current_ws_url)
		else:
			_refresh_offline_local_roster()
			connection_status_changed.emit("READY (Enter Edgegap/WS URL & Connect, or Drop In)", false)

func _resolve_dedicated_ws_port() -> int:
	var all_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in all_args:
		if arg.begins_with("--port=") and arg.trim_prefix("--port=").is_valid_int():
			return int(arg.trim_prefix("--port="))
	for env_key in ["WS_PORT", "ARBITRIUM_PORT_WS_INTERNAL"]:
		var val := OS.get_environment(env_key).strip_edges()
		if not val.is_empty() and val.is_valid_int():
			return int(val)
	return DEFAULT_WS_PORT

func _process(delta: float) -> void:
	if peer != null:
		var status := peer.get_connection_status()
		if not is_dedicated_server and is_connecting and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			is_connecting = false
			is_connected_to_server = false
			_refresh_offline_local_roster()
			connection_status_changed.emit("OFFLINE — Server unreachable, Solo + Bots Ready", false)
	if is_dedicated_server:
		_server_tick(delta)

func _generate_default_callsign() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	local_callsign = "Player_%03d" % rng.randi_range(100, 999)

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func normalize_ws_url(raw_input: String) -> String:
	var s := raw_input.strip_edges()
	if s.is_empty():
		return current_ws_url
	if s.begins_with("ws://") or s.begins_with("wss://"):
		return s
	if s.begins_with("https://"):
		var rest := s.trim_prefix("https://").trim_suffix("/")
		return "wss://" + rest + ("" if rest.ends_with("/ws") else "/ws")
	if s.begins_with("http://"):
		var rest := s.trim_prefix("http://").trim_suffix("/")
		return "ws://" + rest + ("" if rest.ends_with("/ws") else "/ws")
	# Plain host:port or Edgegap FQDN:port (e.g. abc.pr.edgegap.net:31234)
	var scheme := "ws://"
	if OS.has_feature("web"):
		var proto: Variant = JavaScriptBridge.eval("window.location.protocol || 'http:'")
		if typeof(proto) == TYPE_STRING and String(proto) == "https:" and not s.begins_with("127.0.0.1") and not s.begins_with("localhost"):
			scheme = "wss://"
	var clean_host := s.trim_suffix("/")
	if not clean_host.ends_with("/ws"):
		clean_host += "/ws"
	return scheme + clean_host

func _parse_runtime_environment_and_url() -> void:
	var all_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--server" in all_args or OS.get_environment("DEDICATED_SERVER") == "1":
		is_dedicated_server = true

	for arg in all_args:
		if arg.begins_with("--room="):
			active_room = sanitize_room_id(arg.trim_prefix("--room="))
			room_from_url = true
		elif arg.begins_with("--name="):
			local_callsign = _sanitize_token(arg.trim_prefix("--name="), local_callsign)
		elif arg.begins_with("--ws=") or arg.begins_with("--server="):
			var raw_arg := arg.split("=", true, 1)[1]
			current_ws_url = normalize_ws_url(raw_arg)

	var env_ws := OS.get_environment("LOBBY_WS_URL")
	if not env_ws.is_empty():
		current_ws_url = normalize_ws_url(env_ws)

	if OS.has_feature("web"):
		var auto_ws: Variant = JavaScriptBridge.eval("(window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/ws'")
		if typeof(auto_ws) == TYPE_STRING and not String(auto_ws).is_empty():
			current_ws_url = String(auto_ws)
		var search_str: Variant = JavaScriptBridge.eval("window.location.search || ''")
		if typeof(search_str) == TYPE_STRING and not String(search_str).is_empty():
			_parse_query_string(String(search_str))

func _parse_query_string(query: String) -> void:
	var clean := query.trim_prefix("?")
	if clean.is_empty():
		return
	for pair in clean.split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2:
			var key := kv[0].uri_decode().to_lower()
			var val := kv[1].uri_decode().strip_edges()
			if key == "room" and not val.is_empty():
				active_room = sanitize_room_id(val)
				room_from_url = true
			elif (key == "name" or key == "callsign") and not val.is_empty():
				local_callsign = _sanitize_token(val, local_callsign)
			elif key == "team" and not normalize_team(val).is_empty():
				local_team = normalize_team(val)
			elif key == "bracket" and val.to_lower() in ["speedball", "woodsball", "pump"]:
				local_bracket = val.to_lower()
				GearRuleEnforcer.set_active_bracket(local_bracket)
			elif key in ["bots", "npc", "npcs"] and not val.is_empty():
				fill_bots_enabled = val.to_lower() in ["1", "true", "on", "yes"]
			elif key in ["map", "arena"] and not val.is_empty():
				selected_map = normalize_map(val)
				active_map = selected_map
			elif key in ["mode", "game", "gametype"] and not val.is_empty():
				selected_mode = normalize_mode(val, selected_mode)
			elif key in ["server", "ws", "edgegap"] and not val.is_empty():
				current_ws_url = normalize_ws_url(val)

func _sanitize_token(raw: String, fallback: String) -> String:
	var cleaned := raw.strip_edges().substr(0, 20)
	return cleaned if not cleaned.is_empty() else fallback

## Room ids are lower-case [a-z0-9_-], max 24 chars ("LOBBY_01" == "lobby_01"). Empty -> "alpha".
static func sanitize_room_id(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	out = out.substr(0, 24)
	return out if not out.is_empty() else DEFAULT_ROOM

static func normalize_map(raw: String) -> String:
	var m := raw.strip_edges().to_lower()
	return "woodsball_crash" if m in ["woodsball_crash", "woodsball", "woods", "crash", "crash_site", "heli"] else "speedball"

## Returns "" for an unknown mode when fallback is "".
static func normalize_mode(raw: String, fallback: String = "") -> String:
	var m := raw.strip_edges().to_lower()
	if m in ["deathmatch", "dm", "deathmatch_10", "tdm"]:
		return "deathmatch"
	if m in ["ctf", "ctf_bo5", "capture_the_flag"]:
		return "ctf"
	if m in ["bots_test", "bot_test", "test", "bots", "practice"]:
		return "bots_test"
	return fallback

## ALPHA/BRAVO (or red/blue) -> "ALPHA"/"BRAVO"; "" if invalid.
static func normalize_team(raw: String) -> String:
	var t := raw.strip_edges().to_upper()
	if t in ["ALPHA", "RED", "SOUTH"]:
		return "ALPHA"
	if t in ["BRAVO", "BLUE", "NORTH"]:
		return "BRAVO"
	return ""

static func other_team(team: String) -> String:
	return "BRAVO" if team == "ALPHA" else "ALPHA"

func start_dedicated_server(port: int = DEFAULT_WS_PORT) -> int:
	is_dedicated_server = true
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("[NetworkLobby] Failed to start WebSocket server on port %d (err=%d)" % [port, err])
		return err
	# PB-12: never let SceneMultiplayer relay client -> client packets; the room router does all relaying.
	var smp := multiplayer as SceneMultiplayer
	if smp != null:
		smp.server_relay = false
	multiplayer.multiplayer_peer = peer
	players.clear()
	peer_room.clear()
	rooms.clear()
	_ensure_permanent_rooms()
	lobby_state_file = _resolve_lobby_state_file()
	if not lobby_state_file.is_empty():
		write_lobby_state_file()
		print("[NetworkLobby] Writing lobby state for /api/lobbies to %s" % lobby_state_file)
	var edgegap_ip := OS.get_environment("ARBITRIUM_PUBLIC_IP")
	var edgegap_tag := (" [Edgegap Public IP: %s]" % edgegap_ip) if not edgegap_ip.is_empty() else ""
	print("[NetworkLobby] Dedicated WebSocket Server listening on 0.0.0.0:%d (%d permanent lobbies, %d per team)%s" % [port, PERMANENT_LOBBY_COUNT, MAX_PER_TEAM, edgegap_tag])
	connection_status_changed.emit("DEDICATED SERVER LIVE ON PORT %d%s" % [port, edgegap_tag], true)
	return OK

func connect_to_lobby(ws_url: String = "") -> int:
	if is_dedicated_server:
		return ERR_ALREADY_IN_USE
	if not ws_url.strip_edges().is_empty():
		current_ws_url = normalize_ws_url(ws_url)

	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null

	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(current_ws_url)
	if err != OK:
		is_connecting = false
		is_connected_to_server = false
		_refresh_offline_local_roster()
		connection_status_changed.emit("CONNECT FAILED (%s) — Solo Bot Mode Ready" % current_ws_url, false)
		return err

	multiplayer.multiplayer_peer = peer
	is_connecting = true
	is_connected_to_server = false
	connection_status_changed.emit("CONNECTING TO %s (ROOM: %s)..." % [current_ws_url, active_room.to_upper()], false)
	return OK

func disconnect_from_lobby() -> void:
	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null
	is_connecting = false
	is_connected_to_server = false
	_clear_all_remote_player_nodes()
	_refresh_offline_local_roster()
	connection_status_changed.emit("DISCONNECTED — Solo Bot Practice Mode", false)

func is_online_client() -> bool:
	return not is_dedicated_server and is_connected_to_server and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _my_peer_id() -> int:
	return multiplayer.get_unique_id() if peer != null else 1

func _refresh_offline_local_roster() -> void:
	players.clear()
	players[1] = {
		"name": local_callsign,
		"team": local_team,
		"bracket": local_bracket,
		"ready": local_ready,
		"room": active_room,
		"alive": true,
		"kills": GameManager.local_kills if GameManager else 0,
		"deaths": GameManager.local_deaths if GameManager else 0
	}
	lobby_state_changed.emit(get_lobby_state_snapshot())

func get_lobby_state_snapshot() -> Dictionary:
	return {
		"room": active_room,
		"bracket": local_bracket,
		"map": selected_map,
		"selected_map": selected_map,
		"mode": selected_mode,
		"status": room_status,
		"fill_bots": fill_bots_enabled,
		"match_active": match_active,
		"ws_url": current_ws_url,
		"match": room_state.get("match", {}),
		"players": players.duplicate(true)
	}

## Lobby menu map picker. Online: asks the server to change the room's map (validated, synced to the whole room,
## rejected once a match is running). Offline: switches locally.
func select_map(map_id: String) -> void:
	var norm := normalize_map(map_id)
	if is_online_client():
		srv_set_room_settings.rpc_id(1, norm, "")
		return
	selected_map = norm
	active_map = norm
	lobby_state_changed.emit(get_lobby_state_snapshot())
	map_changed.emit(selected_map)

## Lobby menu game-type picker ("deathmatch" | "ctf" | "bots_test").
func select_mode(mode_id: String) -> void:
	var norm := normalize_mode(mode_id, "")
	if norm.is_empty():
		return
	if is_online_client():
		srv_set_room_settings.rpc_id(1, "", norm)
		return
	selected_mode = norm
	fill_bots_enabled = fill_bots_enabled or norm == "bots_test"
	lobby_state_changed.emit(get_lobby_state_snapshot())
	mode_changed.emit(selected_mode)

func _on_connected_to_server() -> void:
	is_connecting = false
	is_connected_to_server = true
	var my_id := multiplayer.get_unique_id()
	print("[NetworkLobby] Connected to lobby server as peer %d, joining room '%s'" % [my_id, active_room])
	connection_status_changed.emit("LIVE IN LOBBY ROOM [%s] (Peer #%d)" % [active_room.to_upper(), my_id], true)
	_send_registration()

func _send_registration() -> void:
	register_player_info.rpc_id(1, local_callsign, local_team, local_bracket, local_ready, active_room, selected_map, selected_mode)

func _on_connection_failed() -> void:
	is_connecting = false
	is_connected_to_server = false
	_clear_all_remote_player_nodes()
	_refresh_offline_local_roster()
	connection_status_changed.emit("OFFLINE — Could not reach %s (Solo Bots Active)" % current_ws_url, false)

func _on_server_disconnected() -> void:
	is_connecting = false
	is_connected_to_server = false
	_clear_all_remote_player_nodes()
	_refresh_offline_local_roster()
	connection_status_changed.emit("DISCONNECTED FROM SERVER — Reconnect or Play Solo", false)

func _on_peer_connected(id: int) -> void:
	if is_dedicated_server:
		# The peer is not in any room (and receives nothing) until it sends register_player_info.
		print("[NetworkLobby] Peer connected: %d (awaiting room registration)" % id)

func _on_peer_disconnected(id: int) -> void:
	if is_dedicated_server:
		print("[NetworkLobby] Peer disconnected: %d" % id)
		_server_remove_peer(id)
	else:
		players.erase(id)
		_remove_remote_player_node(id)
		lobby_state_changed.emit(get_lobby_state_snapshot())

func update_local_player_choices(callsign: String, team: String, bracket_id: String, fill_bots: bool = false) -> void:
	local_callsign = _sanitize_token(callsign, local_callsign)
	local_team = normalize_team(team) if not normalize_team(team).is_empty() else "ALPHA"
	if bracket_id in ["speedball", "woodsball", "pump"]:
		local_bracket = bracket_id
		GearRuleEnforcer.set_active_bracket(local_bracket)
	fill_bots_enabled = fill_bots

	if is_online_client():
		_send_registration()
	else:
		_refresh_offline_local_roster()

## =============================================================================================================
## CLIENT -> SERVER RPCs (always sent with rpc_id(1, ...); the server ignores them on clients)
## =============================================================================================================

@rpc("any_peer", "call_remote", "reliable")
func register_player_info(callsign: String, team: String, bracket_id: String, is_ready: bool, room_id: String = DEFAULT_ROOM, map_id: String = "", mode_id: String = "") -> void:
	if not is_dedicated_server:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return
	_server_register_peer(sender_id, callsign, team, bracket_id, is_ready, room_id, map_id, mode_id)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_player_state(pos: Vector3, body_yaw: float, head_pitch: float, lean: float, stance_idx: int, eliminated: bool) -> void:
	if not is_dedicated_server:
		return
	_server_on_player_state(multiplayer.get_remote_sender_id(), pos, body_yaw, head_pitch, lean, stance_idx, eliminated)

@rpc("any_peer", "call_remote", "reliable")
func srv_fire(origin: Vector3, dir: Vector3, speed: float) -> void:
	if not is_dedicated_server:
		return
	_server_on_fire(multiplayer.get_remote_sender_id(), origin, dir, speed)

@rpc("any_peer", "call_remote", "reliable")
func srv_report_hit(victim_peer_id: int, hit_pos: Vector3) -> void:
	if not is_dedicated_server:
		return
	_server_on_hit_report(multiplayer.get_remote_sender_id(), victim_peer_id, hit_pos)

@rpc("any_peer", "call_remote", "reliable")
func srv_bot_eliminated(bot_node_name: String) -> void:
	if not is_dedicated_server:
		return
	var sid := multiplayer.get_remote_sender_id()
	var rid := String(peer_room.get(sid, ""))
	if rid.is_empty():
		return
	_send_room(rid, &"rpc_notify_bot_eliminated", [bot_node_name.substr(0, 40)], sid)

@rpc("any_peer", "call_remote", "reliable")
func srv_flag_event(event_type: String, player_name: String, team: String, world_pos: Vector3) -> void:
	if not is_dedicated_server:
		return
	var sid := multiplayer.get_remote_sender_id()
	var rid := String(peer_room.get(sid, ""))
	if rid.is_empty():
		return
	_send_room(rid, &"rpc_broadcast_flag_event", [event_type.substr(0, 12), player_name.substr(0, 20), team, world_pos, rid], sid)

@rpc("any_peer", "call_remote", "reliable")
func srv_set_room_settings(map_id: String, mode_id: String) -> void:
	if not is_dedicated_server:
		return
	_server_set_room_settings(multiplayer.get_remote_sender_id(), map_id, mode_id)

## Kept as the lobby "DROP IN / PLAY" entry point. Locally (sender 0) it starts the client flow; on the server it
## starts the sender's room match.
@rpc("any_peer", "call_remote", "reliable")
func request_start_match(room_id: String, bracket_id: String, fill_bots: bool) -> void:
	var clean_bracket := bracket_id if bracket_id in ["speedball", "woodsball", "pump"] else local_bracket
	if is_dedicated_server:
		var sid := multiplayer.get_remote_sender_id()
		if sid > 1:
			_server_request_start(sid, clean_bracket)
		return
	var clean_room := sanitize_room_id(room_id) if not room_id.strip_edges().is_empty() else active_room
	local_bracket = clean_bracket
	fill_bots_enabled = fill_bots
	match_active = true
	GearRuleEnforcer.set_active_bracket(clean_bracket)
	if is_online_client():
		if clean_room != active_room:
			active_room = clean_room
			_send_registration()
		request_start_match.rpc_id(1, clean_room, clean_bracket, fill_bots)
	match_started_signal.emit(clean_room, clean_bracket, fill_bots)

## =============================================================================================================
## SERVER -> CLIENT RPCs (authority only; sent per peer with rpc_id to the members of one room)
## =============================================================================================================

@rpc("authority", "call_remote", "reliable")
func sync_lobby_state(state_dict: Dictionary) -> void:
	if is_dedicated_server:
		return
	room_state = state_dict.duplicate(true)
	if state_dict.has("room"):
		active_room = String(state_dict["room"])
	if state_dict.has("players") and typeof(state_dict["players"]) == TYPE_DICTIONARY:
		players = state_dict["players"].duplicate(true)
		var my_id := _my_peer_id()
		if players.has(my_id):
			var srv_team := String(players[my_id].get("team", local_team)).to_upper()
			if srv_team in TEAMS and srv_team != local_team:
				local_team = srv_team
	if state_dict.has("status"):
		room_status = String(state_dict["status"])
	# Keep local fill_bots_enabled choice (default OFF); only menu selection or match start changes it.
	if state_dict.has("match_active"):
		match_active = bool(state_dict["match_active"])
	if state_dict.has("mode"):
		var srv_mode := normalize_mode(String(state_dict["mode"]), selected_mode)
		if srv_mode != selected_mode:
			selected_mode = srv_mode
			mode_changed.emit(selected_mode)
	if state_dict.has("selected_map"):
		var srv_map := String(state_dict["selected_map"])
		if srv_map != selected_map:
			selected_map = srv_map
			active_map = srv_map
			map_changed.emit(selected_map)
	var existing_ids := remote_player_nodes.keys()
	for pid in existing_ids:
		if not players.has(pid):
			_remove_remote_player_node(int(pid))
	lobby_state_changed.emit(get_lobby_state_snapshot())

@rpc("authority", "call_remote", "reliable")
func notify_match_start(room_id: String, bracket_id: String, fill_bots: bool) -> void:
	if is_dedicated_server:
		return
	fill_bots_enabled = fill_bots
	match_active = true
	if bracket_id in ["speedball", "woodsball", "pump"]:
		local_bracket = bracket_id
		GearRuleEnforcer.set_active_bracket(bracket_id)
	match_started_signal.emit(room_id, bracket_id, fill_bots)

## Generic documented room event (round_started, round_ended, match_ended, player_eliminated, flag_state_changed,
## room_settings_changed, teams_rebalanced, join_rejected, settings_rejected, ...). See docs/NETWORK_EVENTS.md.
@rpc("authority", "call_remote", "reliable")
func cl_room_event(event_name: String, data: Dictionary) -> void:
	if is_dedicated_server:
		return
	received_room_events.append({"event": event_name, "data": data})
	if received_room_events.size() > 256:
		received_room_events.pop_front()
	_client_apply_room_event(event_name, data)
	room_event.emit(event_name, data)

func copy_invite_link() -> String:
	var invite_url := "http://127.0.0.1:8080/?room=%s&bracket=%s&map=%s" % [active_room.uri_encode(), local_bracket.uri_encode(), selected_map.uri_encode()]
	if OS.has_feature("web"):
		var js_code := """
		(function() {
			var u = new URL(window.location.href);
			u.searchParams.set('room', '%s');
			u.searchParams.set('bracket', '%s');
			u.searchParams.set('map', '%s');
			var ws = '%s';
			var pageWs = (window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/ws';
			if (ws && ws !== pageWs) { u.searchParams.set('server', ws); }
			var link = u.toString();
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(link).catch(function(){});
			}
			return link;
		})()
		""" % [active_room.replace("'", ""), local_bracket.replace("'", ""), selected_map.replace("'", ""), current_ws_url.replace("'", "").replace("\\", "")]
		var res: Variant = JavaScriptBridge.eval(js_code)
		if typeof(res) == TYPE_STRING and not String(res).is_empty():
			invite_url = String(res)
	else:
		if not current_ws_url.begins_with("ws://127.0.0.1"):
			invite_url += "&server=" + current_ws_url.uri_encode()
		DisplayServer.clipboard_set(invite_url)
	return invite_url

## --- IN-MATCH 20Hz PLAYER & PAINTBALL SYNCHRONIZATION ---

func send_local_player_state(pos: Vector3, body_yaw: float, head_pitch: float, lean: float, stance_idx: int, eliminated: bool) -> void:
	if not is_online_client():
		return
	srv_player_state.rpc_id(1, pos, body_yaw, head_pitch, lean, stance_idx, eliminated)

## Server -> client relay of one room-mate's state packet.
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_sync_player_state(peer_id: int, pos: Vector3, body_yaw: float, head_pitch: float, lean: float, stance_idx: int, team: String, callsign: String, eliminated: bool) -> void:
	if is_dedicated_server:
		return
	if peer_id <= 1 or peer_id == _my_peer_id():
		return
	_update_or_spawn_remote_player(peer_id, pos, body_yaw, head_pitch, lean, stance_idx, team, callsign, eliminated)

# v0.4.5: knee-slide / Superman-dive fire lock for other peers. v0.5: the server enforces it first (shots fired
# under the lock are never relayed); every receiving client still validates against the shooter's latest
# packed_stance: reject while bit 16 (knee-slide) or bit 32 (dive) is set, and for a short recovery after it clears.
const STANCE_BIT_SLIDING: int = 16
const STANCE_BIT_DIVING: int = 32
const STANCE_FIRE_LOCK_BITS: int = STANCE_BIT_SLIDING | STANCE_BIT_DIVING
## Slightly shorter than the local 0.15s lock to absorb the 0.05s state-tick + jitter (no false rejects).
const REMOTE_SLIDE_FIRE_RECOVERY_SEC: float = 0.10
var remote_move_lock_state: Dictionary = {} # peer_id -> {"locked": bool, "cleared_ms": int}
var rejected_movement_lock_shots: int = 0

func _note_remote_stance_bits(peer_id: int, stance_idx: int) -> void:
	var st: Dictionary = remote_move_lock_state.get(peer_id, {"locked": false, "cleared_ms": -100000})
	var locked := (stance_idx & STANCE_FIRE_LOCK_BITS) != 0
	if bool(st["locked"]) and not locked:
		st["cleared_ms"] = Time.get_ticks_msec()
	st["locked"] = locked
	remote_move_lock_state[peer_id] = st

func is_remote_fire_allowed(peer_id: int) -> bool:
	if not remote_move_lock_state.has(peer_id):
		return true
	var st: Dictionary = remote_move_lock_state[peer_id]
	if bool(st["locked"]):
		return false
	return float(Time.get_ticks_msec() - int(st["cleared_ms"])) >= REMOTE_SLIDE_FIRE_RECOVERY_SEC * 1000.0

func broadcast_paintball_shot(origin: Vector3, dir: Vector3, speed: float) -> void:
	if not is_online_client():
		return
	srv_fire.rpc_id(1, origin, dir, speed)

## Server -> client relay of a room-mate's shot (also called directly by headless tests).
@rpc("authority", "call_remote", "reliable")
func rpc_fire_paintball(origin: Vector3, dir: Vector3, speed: float, shooter_peer_id: int) -> void:
	if is_dedicated_server:
		return
	var my_id := _my_peer_id()
	if shooter_peer_id == my_id:
		return
	received_remote_shots += 1
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	if not is_remote_fire_allowed(shooter_peer_id):
		rejected_movement_lock_shots += 1
		return
	var shooter_node: Node = remote_player_nodes.get(shooter_peer_id, null)
	var shooter_team: String = "BRAVO"
	if players.has(shooter_peer_id):
		shooter_team = players[shooter_peer_id].get("team", "BRAVO")
	var col := Color(0.98, 0.84, 0.10) if shooter_team == "ALPHA" else Color(0.96, 0.16, 0.58)
	GrittyArtTheme.spawn_muzzle_gas_puff(scene_root, origin, dir)
	PaintBallistics.spawn_paintball(origin, dir, speed, shooter_node, col)

func broadcast_bot_eliminated(bot_node_name: String) -> void:
	if not is_online_client():
		return
	srv_bot_eliminated.rpc_id(1, bot_node_name)

@rpc("authority", "call_remote", "reliable")
func rpc_notify_bot_eliminated(bot_node_name: String) -> void:
	if is_dedicated_server:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var bot := scene_root.get_node_or_null(bot_node_name)
	if bot != null and bot.has_method("eliminate_from_network"):
		bot.call("eliminate_from_network")

## Called by the shooter's client when its own paintball breaks on a remote avatar. v0.5: this is only a *report*;
## the server validates it (PB-13) and is the authority on the elimination (player_eliminated event).
func notify_remote_player_hit(victim_peer_id: int, hit_pos: Vector3 = Vector3.INF) -> void:
	if not is_online_client():
		return
	srv_report_hit.rpc_id(1, victim_peer_id, hit_pos)

func broadcast_flag_event(event_type: String, player_name: String, team: String, world_pos: Vector3) -> void:
	if not is_online_client():
		return
	srv_flag_event.rpc_id(1, event_type, player_name, team, world_pos)

@rpc("authority", "call_remote", "reliable")
func rpc_broadcast_flag_event(event_type: String, player_name: String, team: String, world_pos: Vector3, room_id: String) -> void:
	if is_dedicated_server:
		return
	if room_id != active_room:
		return
	flag_event_received.emit(event_type, player_name, team, world_pos)

## Client-side reaction to authoritative room events (keeps the v0.4 HUD/respawn flow working).
func _client_apply_room_event(event_name: String, data: Dictionary) -> void:
	var my_id := _my_peer_id()
	match event_name:
		"player_eliminated":
			var victim := int(data.get("victim", 0))
			var shooter := int(data.get("shooter", 0))
			for key in ["victim", "shooter"]:
				var pid := int(data.get(key, 0))
				if players.has(pid):
					players[pid]["kills"] = int(data.get(key + "_kills", players[pid].get("kills", 0)))
					players[pid]["deaths"] = int(data.get(key + "_deaths", players[pid].get("deaths", 0)))
			if players.has(victim):
				players[victim]["alive"] = false
			if victim == my_id:
				remote_player_hit_local.emit(String(data.get("shooter_name", "Enemy")))
				IntelBus.intel_feed_updated.emit("HIT BY %s!" % String(data.get("shooter_name", "Enemy")))
			elif shooter == my_id:
				var victim_name := String(data.get("victim_name", "Peer #%d" % victim))
				local_player_scored_kill.emit(victim_name)
				IntelBus.intel_feed_updated.emit("ELIMINATED %s! (+1 BONUS PAINT POD AWARDED!)" % victim_name)
			lobby_state_changed.emit(get_lobby_state_snapshot())
		"match_ended":
			match_active = false
			var winner := String(data.get("winner", ""))
			var loser := other_team(winner) if winner in TEAMS else "DRAW"
			match_over_networked.emit("TEAM %s" % loser, "TEAM %s" % winner)
			GameManager.match_ended = true
			GameManager.match_over.emit("TEAM %s" % loser, "TEAM %s" % winner)
		"room_settings_changed":
			var m := normalize_map(String(data.get("map", selected_map)))
			var md := normalize_mode(String(data.get("mode", selected_mode)), selected_mode)
			if md != selected_mode:
				selected_mode = md
				mode_changed.emit(selected_mode)
			if m != selected_map:
				selected_map = m
				active_map = m
				map_changed.emit(selected_map)
		"join_rejected":
			connection_status_changed.emit("ROOM [%s] REJECTED: %s" % [String(data.get("room", active_room)).to_upper(), String(data.get("reason", "?"))], true)


## =============================================================================================================
## SERVER: ROOM ROUTER (v0.5 PB-12). Everything below only runs on the dedicated server.
## =============================================================================================================

## Tests can set this to an Array to capture every outbound server message instead of (in addition to) sending.
var outbound_capture: Variant = null

static func is_permanent_room_id(rid: String) -> bool:
	if not rid.begins_with("lobby_") or rid.length() != 8:
		return false
	var n := rid.substr(6, 2)
	return n.is_valid_int() and int(n) >= 1 and int(n) <= PERMANENT_LOBBY_COUNT

static func default_map_for_lobby(index: int) -> String:
	return MAPS[(index - 1) % MAPS.size()]

func _ensure_permanent_rooms() -> void:
	for i in range(1, PERMANENT_LOBBY_COUNT + 1):
		var rid := "lobby_%02d" % i
		if not rooms.has(rid):
			rooms[rid] = _new_room(rid, "Lobby %02d" % i, true, default_map_for_lobby(i), "deathmatch")

func _new_room(rid: String, display_name: String, permanent: bool, map_id: String, mode_id: String) -> Dictionary:
	return {
		"id": rid,
		"name": display_name,
		"permanent": permanent,
		"players": {},
		"join_order": [],
		"settings": {"map": map_id, "mode": mode_id},
		"match": _new_match_state(),
	}

func _reset_room(room: Dictionary) -> void:
	var idx := int(String(room["id"]).substr(6, 2)) if bool(room["permanent"]) else 1
	room["settings"] = {"map": default_map_for_lobby(idx), "mode": "deathmatch"}
	room["match"] = _new_match_state()
	room["join_order"] = []

func get_room(rid: String) -> Dictionary:
	return rooms.get(rid, {})

func room_team_counts(room: Dictionary, exclude_peer: int = 0) -> Dictionary:
	var c := {"ALPHA": 0, "BRAVO": 0}
	for pid in room.get("players", {}).keys():
		if int(pid) == exclude_peer:
			continue
		var t := String(room["players"][pid].get("team", "ALPHA"))
		c[t] = int(c.get(t, 0)) + 1
	return c

func room_status_of(room: Dictionary) -> String:
	if room.get("players", {}).size() >= MAX_PER_TEAM * 2:
		return "full"
	if bool(room.get("match", {}).get("active", false)):
		return "in_match"
	return "waiting"

## --- outbound helpers ---

func _send(pid: int, method: StringName, args: Array) -> void:
	relayed_message_count += 1
	if outbound_capture is Array:
		(outbound_capture as Array).append({"peer": pid, "method": String(method), "args": args})
	if peer == null or pid <= 1:
		return
	if not multiplayer.get_peers().has(pid):
		return
	callv("rpc_id", [pid, method] + args)

func _send_room(rid: String, method: StringName, args: Array, exclude_peer: int = 0) -> void:
	var room: Dictionary = rooms.get(rid, {})
	if room.is_empty():
		return
	for pid in room["players"].keys():
		if int(pid) != exclude_peer:
			_send(int(pid), method, args)

## Emits a documented room event to every peer in the room (and locally as room_event for server-side tests).
func _send_room_event(rid: String, event_name: String, data: Dictionary) -> void:
	var payload := data.duplicate(true)
	payload["room"] = rid
	_send_room(rid, &"cl_room_event", [event_name, payload])
	room_event.emit(event_name, payload)

func _send_peer_event(pid: int, event_name: String, data: Dictionary) -> void:
	_send(pid, &"cl_room_event", [event_name, data])

func _room_snapshot(rid: String) -> Dictionary:
	var room: Dictionary = rooms.get(rid, {})
	var pl := {}
	for pid in room.get("players", {}).keys():
		var info: Dictionary = room["players"][pid]
		pl[pid] = {
			"name": info.get("name", ""), "team": info.get("team", "ALPHA"), "bracket": info.get("bracket", "speedball"),
			"ready": info.get("ready", true), "room": rid, "kills": info.get("kills", 0), "deaths": info.get("deaths", 0),
			"alive": info.get("alive", true),
		}
	var mode := String(room.get("settings", {}).get("mode", "deathmatch"))
	return {
		"room": rid,
		"name": room.get("name", rid),
		"permanent": room.get("permanent", false),
		"map": room.get("settings", {}).get("map", "speedball"),
		"selected_map": room.get("settings", {}).get("map", "speedball"),
		"mode": mode,
		"fill_bots": mode == "bots_test",
		"status": room_status_of(room),
		"match_active": bool(room.get("match", {}).get("active", false)),
		"max_per_team": MAX_PER_TEAM,
		"match": _public_match_state(room),
		"players": pl,
	}

func _broadcast_room_state(rid: String) -> void:
	if not rooms.has(rid):
		return
	var snap := _room_snapshot(rid)
	_send_room(rid, &"sync_lobby_state", [snap])
	_mark_lobby_state_dirty()

## --- registration / membership ---

func _server_register_peer(pid: int, callsign: String, team: String, bracket_id: String, is_ready: bool, room_id: String, map_id: String = "", mode_id: String = "") -> void:
	var rid := sanitize_room_id(room_id)
	var prev := String(peer_room.get(pid, ""))
	if not prev.is_empty() and prev != rid:
		_server_remove_peer(pid)
	if not rooms.has(rid):
		if rid.begins_with("lobby_") and not is_permanent_room_id(rid):
			_send_peer_event(pid, "join_rejected", {"room": rid, "reason": "unknown_lobby"})
			return
		var m0 := normalize_map(map_id) if not map_id.is_empty() else "speedball"
		rooms[rid] = _new_room(rid, rid, false, m0, normalize_mode(mode_id, "deathmatch"))
	var room: Dictionary = rooms[rid]
	var is_new: bool = not room["players"].has(pid)
	if is_new and room["players"].size() >= MAX_PER_TEAM * 2:
		print("[NetworkLobby] Peer %d rejected from full room '%s'" % [pid, rid])
		_send_peer_event(pid, "join_rejected", {"room": rid, "reason": "full"})
		if room["players"].is_empty() and not bool(room["permanent"]):
			rooms.erase(rid)
		return
	if is_new and room["players"].is_empty() and not bool(room["match"].get("active", false)):
		# First player into an empty room: their ?map= / ?mode= choose the room settings.
		if not map_id.is_empty():
			room["settings"]["map"] = normalize_map(map_id)
		if not normalize_mode(mode_id, "").is_empty():
			room["settings"]["mode"] = normalize_mode(mode_id, "")
	var info: Dictionary = room["players"].get(pid, {"kills": 0, "deaths": 0, "alive": true, "joined_ms": Time.get_ticks_msec()})
	info["name"] = _sanitize_token(callsign, "Player_%d" % (pid % 1000))
	info["bracket"] = bracket_id if bracket_id in ["speedball", "woodsball", "pump"] else "speedball"
	info["ready"] = is_ready
	info["room"] = rid
	info["team"] = _server_choose_team(room, pid, normalize_team(team), is_new, String(info.get("team", "")))
	room["players"][pid] = info
	players[pid] = info
	peer_room[pid] = rid
	if is_new:
		room["join_order"].append(pid)
		_on_player_joined_room(room, pid)
	print("[NetworkLobby] Registered peer %d: %s (Team %s, Bracket %s, Room %s, %d/%d)" % [pid, info["name"], info["team"], info["bracket"], rid, room["players"].size(), MAX_PER_TEAM * 2])
	_broadcast_room_state(rid)

## Phase-1 placeholder balance (replaced by auto team balance below).
func _server_choose_team(room: Dictionary, pid: int, requested: String, is_new: bool, current: String) -> String:
	var c := room_team_counts(room, pid)
	var want := requested if not requested.is_empty() else (current if not current.is_empty() else "ALPHA")
	if int(c[want]) >= MAX_PER_TEAM:
		want = other_team(want)
	return want

func _server_remove_peer(pid: int) -> void:
	var rid := String(peer_room.get(pid, ""))
	peer_room.erase(pid)
	players.erase(pid)
	remote_move_lock_state.erase(pid)
	if rid.is_empty() or not rooms.has(rid):
		return
	var room: Dictionary = rooms[rid]
	room["players"].erase(pid)
	room["join_order"].erase(pid)
	_on_player_left_room(room, pid)
	if room["players"].is_empty():
		if bool(room["permanent"]):
			_reset_room(room)
		else:
			rooms.erase(rid)
		_mark_lobby_state_dirty()
		return
	_broadcast_room_state(rid)

## --- relays ---

func _server_on_player_state(pid: int, pos: Vector3, body_yaw: float, head_pitch: float, lean: float, stance_idx: int, eliminated: bool) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty():
		return
	var info: Dictionary = players[pid]
	_note_remote_stance_bits(pid, stance_idx)
	var now := Time.get_ticks_msec()
	info["state"] = {"pos": pos, "yaw": body_yaw, "pitch": head_pitch, "lean": lean, "stance": stance_idx, "eliminated": eliminated, "t": now}
	var hist: Array = info.get("history", [])
	hist.append([now, pos, stance_idx])
	while hist.size() > 0 and now - int(hist[0][0]) > 1200:
		hist.pop_front()
	info["history"] = hist
	_on_player_moved(rooms[rid], pid, pos)
	_server_relay_player_state(rid, pid, info)

func _server_relay_player_state(rid: String, pid: int, info: Dictionary) -> void:
	var s: Dictionary = info["state"]
	_send_room(rid, &"rpc_sync_player_state", [pid, s["pos"], s["yaw"], s["pitch"], s["lean"], s["stance"], info.get("team", "ALPHA"), info.get("name", ""), s["eliminated"] or not bool(info.get("alive", true))], pid)

func _server_on_fire(pid: int, origin: Vector3, dir: Vector3, speed: float) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty() or dir.length_squared() < 0.0001:
		return
	if not _server_accept_shot(pid, origin, dir.normalized(), speed):
		return
	_send_room(rid, &"rpc_fire_paintball", [origin, dir.normalized(), clampf(speed, 1.0, 120.0), pid], pid)

func _server_on_hit_report(shooter: int, victim: int, hit_pos: Vector3) -> void:
	var rid := String(peer_room.get(shooter, ""))
	if rid.is_empty() or shooter == victim or String(peer_room.get(victim, "")) != rid:
		return
	var verdict := _server_validate_hit(shooter, victim, hit_pos)
	if not bool(verdict.get("ok", false)):
		var info: Dictionary = players.get(shooter, {})
		info["rejected_hits"] = int(info.get("rejected_hits", 0)) + 1
		_send_peer_event(shooter, "hit_rejected", {"victim": victim, "reason": verdict.get("reason", "invalid")})
		return
	_server_apply_elimination(rooms[rid], shooter, victim, "paint")

func _server_apply_elimination(room: Dictionary, shooter: int, victim: int, reason: String) -> void:
	var pl: Dictionary = room["players"]
	if not pl.has(victim):
		return
	var v: Dictionary = pl[victim]
	var s: Dictionary = pl.get(shooter, {})
	var scored := _match_counts_kill(room)
	if scored:
		v["deaths"] = int(v.get("deaths", 0)) + 1
		if not s.is_empty():
			s["kills"] = int(s.get("kills", 0)) + 1
	v["alive"] = false
	v["dead_since_ms"] = Time.get_ticks_msec()
	_send_room_event(String(room["id"]), "player_eliminated", {
		"victim": victim, "victim_name": v.get("name", ""), "victim_team": v.get("team", ""),
		"shooter": shooter, "shooter_name": s.get("name", "Enemy"), "shooter_team": s.get("team", ""),
		"victim_kills": v.get("kills", 0), "victim_deaths": v.get("deaths", 0),
		"shooter_kills": s.get("kills", 0), "shooter_deaths": s.get("deaths", 0),
		"reason": reason, "scored": scored,
	})
	_on_player_eliminated(room, shooter, victim)
	_broadcast_room_state(String(room["id"]))

func _server_set_room_settings(pid: int, map_id: String, mode_id: String) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty():
		return
	var room: Dictionary = rooms[rid]
	if bool(room["match"].get("active", false)):
		_send_peer_event(pid, "settings_rejected", {"reason": "match_in_progress", "map": room["settings"]["map"], "mode": room["settings"]["mode"]})
		return
	var m := normalize_map(map_id) if map_id.strip_edges().to_lower() in ["speedball", "woodsball_crash", "woodsball", "woods", "crash", "crash_site", "heli"] else String(room["settings"]["map"])
	var md := normalize_mode(mode_id, String(room["settings"]["mode"]))
	if m == String(room["settings"]["map"]) and md == String(room["settings"]["mode"]):
		_broadcast_room_state(rid)
		return
	room["settings"]["map"] = m
	room["settings"]["mode"] = md
	_send_room_event(rid, "room_settings_changed", {"map": m, "mode": md, "by": pid, "by_name": players[pid].get("name", "")})
	_broadcast_room_state(rid)

func _server_request_start(pid: int, bracket_id: String) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty():
		return
	players[pid]["bracket"] = bracket_id
	var room: Dictionary = rooms[rid]
	if bool(room["match"].get("active", false)):
		# Joining a running match: just tell this peer to drop in with its own bracket.
		_send(pid, &"notify_match_start", [rid, bracket_id, String(room["settings"]["mode"]) == "bots_test"])
		_broadcast_room_state(rid)
		return
	_start_room_match(room)

func _server_tick(delta: float) -> void:
	for rid in rooms.keys():
		var room: Dictionary = rooms[rid]
		if room["players"].is_empty():
			continue
		_tick_room_match(room, delta)
	_tick_lobby_state_file(delta)

## --- match rules hooks (phase 1: minimal; replaced by server-authoritative rules) ---

func _new_match_state() -> Dictionary:
	return {"active": false}

func _public_match_state(_room: Dictionary) -> Dictionary:
	return {}

func _on_player_joined_room(_room: Dictionary, _pid: int) -> void:
	pass

func _on_player_left_room(_room: Dictionary, _pid: int) -> void:
	pass

func _on_player_moved(_room: Dictionary, _pid: int, _pos: Vector3) -> void:
	pass

func _on_player_eliminated(_room: Dictionary, _shooter: int, _victim: int) -> void:
	pass

func _match_counts_kill(_room: Dictionary) -> bool:
	return true

func _start_room_match(room: Dictionary) -> void:
	room["match"]["active"] = true
	var rid := String(room["id"])
	for pid in room["players"].keys():
		_send(int(pid), &"notify_match_start", [rid, String(room["players"][pid].get("bracket", "speedball")), String(room["settings"]["mode"]) == "bots_test"])
	_broadcast_room_state(rid)

func _tick_room_match(room: Dictionary, _delta: float) -> void:
	var now := Time.get_ticks_msec()
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		if not bool(info.get("alive", true)) and now - int(info.get("dead_since_ms", 0)) > 1000:
			info["alive"] = true

func _server_accept_shot(_pid: int, _origin: Vector3, _dir: Vector3, _speed: float) -> bool:
	return true

func _server_validate_hit(_shooter: int, _victim: int, _hit_pos: Vector3) -> Dictionary:
	return {"ok": true}

## =============================================================================================================
## SERVER -> server.js IPC (v0.5 PB-12): the public lobby list is written as JSON to LOBBY_STATE_FILE (env) or
## --lobby-state-file=PATH about once a second and shortly after any room change. server.js serves it as
## GET /api/lobbies and GET /api/quickjoin. Written atomically (tmp + rename).
## =============================================================================================================
const LOBBY_STATE_WRITE_INTERVAL: float = 1.0
const LOBBY_STATE_MIN_INTERVAL: float = 0.2
var lobby_state_file: String = ""
var _lobby_state_dirty: bool = true
var _lobby_state_timer: float = 0.0
var _lobby_state_since_write: float = 99.0
var lobby_state_writes: int = 0

func _resolve_lobby_state_file() -> String:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--lobby-state-file="):
			return arg.trim_prefix("--lobby-state-file=")
	return OS.get_environment("LOBBY_STATE_FILE").strip_edges()

static func team_label(team: String) -> String:
	return "red" if team == "ALPHA" else "blue"

## The permanent lobbies in the exact /api/lobbies row shape (minus join_url, which server.js adds).
func get_public_lobby_list() -> Array:
	var out: Array = []
	for i in range(1, PERMANENT_LOBBY_COUNT + 1):
		var rid := "lobby_%02d" % i
		var room: Dictionary = rooms.get(rid, {})
		if room.is_empty():
			continue
		var c := room_team_counts(room)
		var mode := String(room["settings"]["mode"])
		out.append({
			"id": rid,
			"name": String(room["name"]),
			"map": String(room["settings"]["map"]),
			"mode": mode,
			"players": {"red": int(c["ALPHA"]), "blue": int(c["BRAVO"])},
			"max_per_team": MAX_PER_TEAM,
			"status": room_status_of(room),
			"bots": mode == "bots_test",
		})
	return out

func build_lobby_state_document() -> Dictionary:
	var adhoc := 0
	for rid in rooms.keys():
		if not bool(rooms[rid]["permanent"]):
			adhoc += 1
	return {
		"version": 1,
		"generated_at": Time.get_unix_time_from_system(),
		"max_per_team": MAX_PER_TEAM,
		"lobbies": get_public_lobby_list(),
		"private_rooms": adhoc,
		"connected_peers": peer_room.size(),
	}

func write_lobby_state_file(path: String = "") -> bool:
	var target := path if not path.is_empty() else lobby_state_file
	if target.is_empty():
		return false
	var tmp := target + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_string(JSON.stringify(build_lobby_state_document()))
	fa.close()
	var err := DirAccess.rename_absolute(tmp, target)
	if err == OK:
		lobby_state_writes += 1
	return err == OK

func _mark_lobby_state_dirty() -> void:
	_lobby_state_dirty = true

func _tick_lobby_state_file(delta: float) -> void:
	if lobby_state_file.is_empty():
		return
	_lobby_state_timer += delta
	_lobby_state_since_write += delta
	if (_lobby_state_dirty and _lobby_state_since_write >= LOBBY_STATE_MIN_INTERVAL) or _lobby_state_timer >= LOBBY_STATE_WRITE_INTERVAL:
		_lobby_state_dirty = false
		_lobby_state_timer = 0.0
		_lobby_state_since_write = 0.0
		write_lobby_state_file()

## --- REMOTE AVATARS ---
func _update_or_spawn_remote_player(peer_id: int, pos: Vector3, body_yaw: float, _head_pitch: float, lean: float, stance_idx: int, team: String, callsign: String, eliminated: bool) -> void:
	var scene_root := get_tree().current_scene as Node3D
	if scene_root == null:
		return

	_note_remote_stance_bits(peer_id, stance_idx)
	var avatar: StaticBody3D = remote_player_nodes.get(peer_id, null) as StaticBody3D
	if avatar == null or not is_instance_valid(avatar):
		avatar = _create_remote_player_avatar(peer_id, team, callsign)
		scene_root.add_child(avatar)
		remote_player_nodes[peer_id] = avatar

	var prev_pos := avatar.global_position
	avatar.global_position = avatar.global_position.lerp(pos, 0.45)
	var est_vel := (avatar.global_position - prev_pos) / 0.05
	avatar.rotation.y = body_yaw
	avatar.rotation.z = 0.0
	avatar.rotation.x = 0.0
	avatar.scale = Vector3.ONE

	var base_stance: int = stance_idx & 3
	var remote_left_handed: bool = (stance_idx & 4) != 0 if stance_idx >= 4 else (lean < -0.05)
	var remote_tucked: bool = (stance_idx & 8) != 0
	var remote_sliding: bool = (stance_idx & 16) != 0
	var remote_diving: bool = (stance_idx & 32) != 0
	var remote_reloading: bool = (stance_idx & 64) != 0
	var packed_b_idx: int = (stance_idx >> 7) & 3
	var p_bracket: String = "woodsball" if packed_b_idx == 1 else ("pump" if packed_b_idx == 2 else String(players.get(peer_id, {}).get("bracket", local_bracket)))

	var pro_rig := avatar.get_node_or_null("ProPaintballRig3D") as Node3D
	if pro_rig != null and pro_rig.has_method("apply_pose"):
		pro_rig.call("apply_pose", 0.05, {
			"velocity": est_vel,
			"stance": base_stance,
			"lean": lean,
			"is_left_handed": remote_left_handed,
			"bunker_tuck": 1.0 if remote_tucked else 0.0,
			"is_sliding": remote_sliding,
			"is_diving": remote_diving,
			"is_reloading": remote_reloading,
			"is_eliminated": eliminated,
			"team": team,
			"bracket": p_bracket,
		})
		var marker_piv := avatar.get_node_or_null("MarkerPivot3D") as Node3D
		var m_asm := pro_rig.get("marker_assembly_pivot") as Node3D
		var h_unit := pro_rig.get("hopper_unit_pivot") as Node3D
		if marker_piv != null and m_asm != null:
			marker_piv.global_transform = m_asm.global_transform
			var hopper_piv := marker_piv.get_node_or_null("HopperPivot3D") as Node3D
			if hopper_piv != null and h_unit != null:
				hopper_piv.global_transform = h_unit.global_transform

	var tag := avatar.get_node_or_null("CallsignTag3D") as Label3D
	if tag != null:
		tag.text = "[%s] %s" % [team, callsign]
		tag.modulate = Color(0.35, 0.85, 1.0) if team == "ALPHA" else Color(1.0, 0.42, 0.42)

func _create_remote_player_avatar(peer_id: int, team: String, callsign: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "RemotePlayer_%d" % peer_id
	body.set_meta("remote_peer_id", peer_id)

	var p_bracket: String = String(players.get(peer_id, {}).get("bracket", local_bracket))
	var pro_rig := ProRigScript.new()
	pro_rig.name = "ProPaintballRig3D"
	body.add_child(pro_rig)
	pro_rig.build_rig(team, p_bracket)
	pro_rig.build_sub_hitboxes_on(body)
	pro_rig.apply_pose(0.0, {
		"velocity": Vector3.ZERO,
		"stance": 0,
		"lean": 0.0,
		"is_left_handed": false,
		"bunker_tuck": 0.0,
		"is_eliminated": false,
		"team": team,
		"bracket": p_bracket,
	})

	var marker_piv := Node3D.new()
	marker_piv.name = "MarkerPivot3D"
	body.add_child(marker_piv)
	var hopper_piv := Node3D.new()
	hopper_piv.name = "HopperPivot3D"
	marker_piv.add_child(hopper_piv)

	var tag := Label3D.new()
	tag.name = "CallsignTag3D"
	tag.text = "[%s] %s" % [team, callsign]
	tag.font_size = 42
	tag.pixel_size = 0.0045
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.92, 0)
	tag.modulate = Color(0.35, 0.85, 1.0) if team == "ALPHA" else Color(1.0, 0.42, 0.42)
	body.add_child(tag)

	body.set_script(load("res://scripts/player/remote_player_avatar.gd"))

	return body

func _remove_remote_player_node(peer_id: int) -> void:
	remote_move_lock_state.erase(peer_id)
	if remote_player_nodes.has(peer_id):
		var node: Node = remote_player_nodes[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		remote_player_nodes.erase(peer_id)

func _clear_all_remote_player_nodes() -> void:
	for pid in remote_player_nodes.keys():
		var node: Node = remote_player_nodes[pid]
		if is_instance_valid(node):
			node.queue_free()
	remote_player_nodes.clear()
