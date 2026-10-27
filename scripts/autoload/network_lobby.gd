extends Node

const GrittyArtTheme = preload("res://scripts/systems/gritty_art_theme.gd")

## WebSocket Click-to-Lobby & Authoritative Match Synchronizer (PB-05).
## Supports:
## - Dedicated headless server mode (--server or DEDICATED_SERVER=1) on port 9080 (or WS_PORT /
##   ARBITRIUM_PORT_WS_INTERNAL) alongside the unified HTTP+WS proxy on ARBITRIUM_PORT_GAMEPORT_INTERNAL /
##   ARBITRIUM_PORT_HTTP_INTERNAL / PORT (8080).
## - Browser auto-join via URL query parameters (?room=alpha&name=Player&team=ALPHA&bracket=speedball&server=wss://...)
##   connecting over WebSocket to either an explicit Edgegap Arbitrium endpoint (?server= / ?ws=) or same-origin /ws.
## - Live lobby state sync, bracket/team selection, OpFor bot co-op/fill toggle,
##   20Hz remote player 3D avatar synchronization, and networked paintball shots & eliminations.

signal lobby_state_changed(state_dict: Dictionary)
signal connection_status_changed(status_text: String, is_online: bool)
signal match_started_signal(room_id: String, bracket_id: String, fill_bots: bool)
signal remote_player_hit_local(shooter_name: String)
signal local_player_scored_kill(victim_name: String)
signal match_over_networked(loser_name: String, winner_name: String)

const DEFAULT_WS_PORT: int = 9080

var peer: WebSocketMultiplayerPeer = null
var is_dedicated_server: bool = false
var is_connected_to_server: bool = false
var is_connecting: bool = false

var current_ws_url: String = "ws://127.0.0.1:9080/ws"
var active_room: String = "alpha"
var local_callsign: String = "NPPL_Pro"
var local_team: String = "ALPHA"
var local_bracket: String = "speedball"
var local_ready: bool = true
var fill_bots_enabled: bool = false
var match_active: bool = true

## Connected human players: peer_id (int) -> Dictionary { name, team, bracket, ready, room }
var players: Dictionary = {}

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
	for env_key in ["WS_PORT", "ARBITRIUM_PORT_WS_INTERNAL"]:
		var val := OS.get_environment(env_key).strip_edges()
		if not val.is_empty() and val.is_valid_int():
			return int(val)
	return DEFAULT_WS_PORT

func _process(_delta: float) -> void:
	if peer != null:
		var status := peer.get_connection_status()
		if not is_dedicated_server and is_connecting and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			is_connecting = false
			is_connected_to_server = false
			_refresh_offline_local_roster()
			connection_status_changed.emit("OFFLINE — Server unreachable, Solo + Bots Ready", false)

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
			active_room = _sanitize_token(arg.trim_prefix("--room="), "alpha")
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
				active_room = _sanitize_token(val, "alpha")
			elif (key == "name" or key == "callsign") and not val.is_empty():
				local_callsign = _sanitize_token(val, local_callsign)
			elif key == "team" and val.to_upper() in ["ALPHA", "BRAVO"]:
				local_team = val.to_upper()
			elif key == "bracket" and val.to_lower() in ["speedball", "woodsball", "pump"]:
				local_bracket = val.to_lower()
				GearRuleEnforcer.set_active_bracket(local_bracket)
			elif key in ["bots", "npc", "npcs"] and not val.is_empty():
				fill_bots_enabled = val.to_lower() in ["1", "true", "on", "yes"]
			elif key in ["server", "ws", "edgegap"] and not val.is_empty():
				current_ws_url = normalize_ws_url(val)
			elif key in ["bots", "npcs", "npc"] and not val.is_empty():
				fill_bots_enabled = val.to_lower() in ["1", "true", "on", "yes"]

func _sanitize_token(raw: String, fallback: String) -> String:
	var cleaned := raw.strip_edges().substr(0, 20)
	return cleaned if not cleaned.is_empty() else fallback

func start_dedicated_server(port: int = DEFAULT_WS_PORT) -> int:
	is_dedicated_server = true
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("[NetworkLobby] Failed to start WebSocket server on port %d (err=%d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	var edgegap_ip := OS.get_environment("ARBITRIUM_PUBLIC_IP")
	var edgegap_tag := (" [Edgegap Public IP: %s]" % edgegap_ip) if not edgegap_ip.is_empty() else ""
	print("[NetworkLobby] Dedicated WebSocket Server listening on 0.0.0.0:%d (default room: %s)%s" % [port, active_room, edgegap_tag])
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

func _refresh_offline_local_roster() -> void:
	players.clear()
	players[1] = {
		"name": local_callsign,
		"team": local_team,
		"bracket": local_bracket,
		"ready": local_ready,
		"room": active_room,
		"kills": GameManager.local_kills if GameManager else 0,
		"deaths": GameManager.local_deaths if GameManager else 0
	}
	lobby_state_changed.emit(get_lobby_state_snapshot())

func get_lobby_state_snapshot() -> Dictionary:
	return {
		"room": active_room,
		"bracket": local_bracket,
		"fill_bots": fill_bots_enabled,
		"match_active": match_active,
		"ws_url": current_ws_url,
		"players": players.duplicate(true)
	}

func _on_connected_to_server() -> void:
	is_connecting = false
	is_connected_to_server = true
	var my_id := multiplayer.get_unique_id()
	print("[NetworkLobby] Connected to lobby server as peer %d in room '%s'" % [my_id, active_room])
	connection_status_changed.emit("LIVE IN LOBBY ROOM [%s] (Peer #%d)" % [active_room.to_upper(), my_id], true)
	register_player_info.rpc_id(1, local_callsign, local_team, local_bracket, local_ready, active_room, fill_bots_enabled)

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
		print("[NetworkLobby] Peer connected: %d" % id)
		players[id] = {
			"name": "Player_%d" % (id % 1000),
			"team": "ALPHA" if (players.size() % 2 == 0) else "BRAVO",
			"bracket": local_bracket,
			"ready": true,
			"room": active_room,
			"kills": 0,
			"deaths": 0
		}
		_broadcast_lobby_state_from_server()

func _on_peer_disconnected(id: int) -> void:
	if is_dedicated_server:
		print("[NetworkLobby] Peer disconnected: %d" % id)
		players.erase(id)
		_broadcast_lobby_state_from_server()
	else:
		players.erase(id)
		_remove_remote_player_node(id)
		lobby_state_changed.emit(get_lobby_state_snapshot())

func _broadcast_lobby_state_from_server() -> void:
	if not is_dedicated_server:
		return
	var snapshot := get_lobby_state_snapshot()
	sync_lobby_state.rpc(snapshot)

func update_local_player_choices(callsign: String, team: String, bracket_id: String, fill_bots: bool = false) -> void:
	local_callsign = _sanitize_token(callsign, local_callsign)
	local_team = team.to_upper() if team.to_upper() in ["ALPHA", "BRAVO"] else "ALPHA"
	if bracket_id in ["speedball", "woodsball", "pump"]:
		local_bracket = bracket_id
		GearRuleEnforcer.set_active_bracket(local_bracket)
	fill_bots_enabled = fill_bots

	if is_online_client():
		register_player_info.rpc_id(1, local_callsign, local_team, local_bracket, true, active_room, fill_bots_enabled)
	else:
		_refresh_offline_local_roster()

@rpc("any_peer", "call_local", "reliable")
func register_player_info(callsign: String, team: String, bracket_id: String, is_ready: bool, room_id: String = "alpha", fill_bots: bool = false) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id() if peer != null else 1
	fill_bots_enabled = fill_bots
	players[sender_id] = {
		"name": _sanitize_token(callsign, "Player_%d" % (sender_id % 1000)),
		"team": team.to_upper() if team.to_upper() in ["ALPHA", "BRAVO"] else "ALPHA",
		"bracket": bracket_id if bracket_id in ["speedball", "woodsball", "pump"] else "speedball",
		"ready": is_ready,
		"room": _sanitize_token(room_id, "alpha"),
		"kills": int(players.get(sender_id, {}).get("kills", 0)),
		"deaths": int(players.get(sender_id, {}).get("deaths", 0))
	}
	if is_dedicated_server:
		print("[NetworkLobby] Registered peer %d: %s (Team %s, Bracket %s, Room %s, fill_bots=%s)" % [
			sender_id, players[sender_id]["name"], players[sender_id]["team"], players[sender_id]["bracket"], players[sender_id]["room"], str(fill_bots)
		])
		_broadcast_lobby_state_from_server()

@rpc("authority", "call_local", "reliable")
func sync_lobby_state(state_dict: Dictionary) -> void:
	if state_dict.has("players") and typeof(state_dict["players"]) == TYPE_DICTIONARY:
		players = state_dict["players"].duplicate(true)
	if state_dict.has("fill_bots"):
		fill_bots_enabled = bool(state_dict["fill_bots"])
	if state_dict.has("match_active"):
		match_active = bool(state_dict["match_active"])
	var existing_ids := remote_player_nodes.keys()
	for pid in existing_ids:
		if not players.has(pid):
			_remove_remote_player_node(int(pid))
	lobby_state_changed.emit(get_lobby_state_snapshot())

@rpc("any_peer", "call_local", "reliable")
func request_start_match(room_id: String, bracket_id: String, fill_bots: bool) -> void:
	var clean_room := _sanitize_token(room_id, active_room)
	var clean_bracket := bracket_id if bracket_id in ["speedball", "woodsball", "pump"] else local_bracket
	active_room = clean_room
	local_bracket = clean_bracket
	fill_bots_enabled = fill_bots
	match_active = true

	if is_dedicated_server:
		print("[NetworkLobby] Match start requested for room '%s' (bracket=%s, fill_bots=%s)" % [clean_room, clean_bracket, str(fill_bots)])
		_broadcast_lobby_state_from_server()
		notify_match_start.rpc(clean_room, clean_bracket, fill_bots)
	elif is_online_client() and multiplayer.get_remote_sender_id() == 0:
		request_start_match.rpc_id(1, clean_room, clean_bracket, fill_bots)
		GearRuleEnforcer.set_active_bracket(clean_bracket)
		match_started_signal.emit(clean_room, clean_bracket, fill_bots)
	else:
		GearRuleEnforcer.set_active_bracket(clean_bracket)
		match_started_signal.emit(clean_room, clean_bracket, fill_bots)

@rpc("authority", "call_local", "reliable")
func notify_match_start(room_id: String, bracket_id: String, fill_bots: bool) -> void:
	if is_dedicated_server:
		return
	fill_bots_enabled = fill_bots
	match_active = true
	if bracket_id in ["speedball", "woodsball", "pump"]:
		local_bracket = bracket_id
		GearRuleEnforcer.set_active_bracket(bracket_id)
	match_started_signal.emit(room_id, bracket_id, fill_bots)

func copy_invite_link() -> String:
	var invite_url := "http://127.0.0.1:8080/?room=%s&bracket=%s" % [active_room.uri_encode(), local_bracket.uri_encode()]
	if OS.has_feature("web"):
		var js_code := """
		(function() {
			var u = new URL(window.location.href);
			u.searchParams.set('room', '%s');
			u.searchParams.set('bracket', '%s');
			var link = u.toString();
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(link).catch(function(){});
			}
			return link;
		})()
		""" % [active_room.replace("'", ""), local_bracket.replace("'", "")]
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
	rpc_sync_player_state.rpc(pos, body_yaw, head_pitch, lean, stance_idx, local_team, local_callsign, eliminated)

@rpc("any_peer", "unreliable_ordered")
func rpc_sync_player_state(pos: Vector3, body_yaw: float, head_pitch: float, lean: float, stance_idx: int, team: String, callsign: String, eliminated: bool) -> void:
	if is_dedicated_server:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or sender_id == multiplayer.get_unique_id():
		return
	if players.has(sender_id):
		var p_room: String = players[sender_id].get("room", active_room)
		if p_room != active_room:
			return
	_update_or_spawn_remote_player(sender_id, pos, body_yaw, head_pitch, lean, stance_idx, team, callsign, eliminated)

func broadcast_paintball_shot(origin: Vector3, dir: Vector3, speed: float) -> void:
	if not is_online_client():
		return
	rpc_fire_paintball.rpc(origin, dir, speed, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func rpc_fire_paintball(origin: Vector3, dir: Vector3, speed: float, shooter_peer_id: int) -> void:
	if is_dedicated_server:
		return
	var my_id := multiplayer.get_unique_id() if peer != null else 1
	if shooter_peer_id == my_id:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
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
	rpc_notify_bot_eliminated.rpc(bot_node_name)

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_bot_eliminated(bot_node_name: String) -> void:
	if is_dedicated_server:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var bot := scene_root.get_node_or_null(bot_node_name)
	if bot != null and bot.has_method("eliminate_from_network"):
		bot.call("eliminate_from_network")

func notify_remote_player_hit(victim_peer_id: int) -> void:
	if not is_online_client():
		return
	rpc_notify_player_hit.rpc(victim_peer_id, multiplayer.get_unique_id(), local_callsign)

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_player_hit(victim_peer_id: int, shooter_peer_id: int, shooter_name: String) -> void:
	if players.has(victim_peer_id):
		players[victim_peer_id]["deaths"] = int(players[victim_peer_id].get("deaths", 0)) + 1
	if players.has(shooter_peer_id):
		players[shooter_peer_id]["kills"] = int(players[shooter_peer_id].get("kills", 0)) + 1

	if is_dedicated_server:
		_broadcast_lobby_state_from_server()
		var v_deaths: int = int(players.get(victim_peer_id, {}).get("deaths", 0))
		if v_deaths >= 10:
			var loser_n: String = str(players.get(victim_peer_id, {}).get("name", "Peer #%d" % victim_peer_id))
			rpc_announce_match_over.rpc(loser_n, shooter_name)
		return

	var my_id := multiplayer.get_unique_id() if peer != null else 1
	if victim_peer_id == my_id:
		remote_player_hit_local.emit(shooter_name)
		IntelBus.intel_feed_updated.emit("HIT BY %s! Respawning at Original Starting Gate..." % shooter_name)
	elif shooter_peer_id == my_id:
		var victim_name: String = players.get(victim_peer_id, {}).get("name", "Peer #%d" % victim_peer_id)
		local_player_scored_kill.emit(victim_name)
		IntelBus.intel_feed_updated.emit("ELIMINATED %s! (+1 BONUS PAINT POD AWARDED!)" % victim_name)
	lobby_state_changed.emit(get_lobby_state_snapshot())

@rpc("authority", "call_local", "reliable")
func rpc_announce_match_over(loser_name: String, winner_name: String) -> void:
	if is_dedicated_server:
		return
	match_active = false
	match_over_networked.emit(loser_name, winner_name)
	GameManager.match_ended = true
	GameManager.match_over.emit(loser_name, winner_name)

func _update_or_spawn_remote_player(peer_id: int, pos: Vector3, body_yaw: float, _head_pitch: float, lean: float, stance_idx: int, team: String, callsign: String, eliminated: bool) -> void:
	var scene_root := get_tree().current_scene as Node3D
	if scene_root == null:
		return

	var avatar: StaticBody3D = remote_player_nodes.get(peer_id, null) as StaticBody3D
	if avatar == null or not is_instance_valid(avatar):
		avatar = _create_remote_player_avatar(peer_id, team, callsign)
		scene_root.add_child(avatar)
		remote_player_nodes[peer_id] = avatar

	avatar.global_position = avatar.global_position.lerp(pos, 0.45)
	avatar.rotation.y = body_yaw
	avatar.rotation.z = deg_to_rad(-lean * 10.0)
	avatar.rotation.x = deg_to_rad(-70.0) if eliminated else 0.0

	var stance_scale_y: float = 1.0
	if stance_idx == 1:
		stance_scale_y = 0.65
	elif stance_idx == 2:
		stance_scale_y = 0.35
	avatar.scale.y = lerpf(avatar.scale.y, stance_scale_y, 0.35)

	var tag := avatar.get_node_or_null("CallsignTag3D") as Label3D
	if tag != null:
		tag.text = "[%s] %s" % [team, callsign]
		tag.modulate = Color(0.35, 0.85, 1.0) if team == "ALPHA" else Color(1.0, 0.42, 0.42)

func _create_remote_player_avatar(peer_id: int, team: String, callsign: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "RemotePlayer_%d" % peer_id
	body.set_meta("remote_peer_id", peer_id)

	var col_torso := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.45
	col_torso.shape = cap
	col_torso.position = Vector3(0, 0.72, 0)
	body.add_child(col_torso)

	var jersey := MeshInstance3D.new()
	jersey.name = "JerseyMesh"
	var cmesh := CapsuleMesh.new()
	cmesh.radius = 0.26
	cmesh.height = 1.35
	jersey.mesh = cmesh
	jersey.position = Vector3(0, 0.70, 0)
	var jmat := StandardMaterial3D.new()
	jmat.albedo_color = Color(0.18, 0.44, 0.86) if team == "ALPHA" else Color(0.82, 0.20, 0.22)
	jmat.roughness = 0.55
	jersey.material_override = jmat
	body.add_child(jersey)

	var head := MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = 0.17
	smesh.height = 0.34
	head.mesh = smesh
	head.position = Vector3(0, 1.48, 0.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.15, 0.16, 0.18)
	hmat.roughness = 0.40
	head.material_override = hmat
	body.add_child(head)

	var visor := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.30, 0.12, 0.18)
	visor.mesh = vbox
	visor.position = Vector3(0, 1.49, -0.12)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.90, 0.65, 0.15)
	vmat.metallic = 0.85
	vmat.roughness = 0.12
	visor.material_override = vmat
	body.add_child(visor)

	var marker := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(0.06, 0.12, 0.52)
	marker.mesh = mbox
	marker.position = Vector3(0.22, 1.20, -0.28)
	marker.material_override = hmat
	body.add_child(marker)

	var tag := Label3D.new()
	tag.name = "CallsignTag3D"
	tag.text = "[%s] %s" % [team, callsign]
	tag.font_size = 42
	tag.pixel_size = 0.0045
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.92, 0)
	tag.modulate = Color(0.35, 0.85, 1.0) if team == "ALPHA" else Color(1.0, 0.42, 0.42)
	body.add_child(tag)

	var hit_script := GDScript.new()
	hit_script.source_code = """extends StaticBody3D
func on_paintball_break(_hit_pos: Vector3, _shooter: Node) -> void:
	if has_meta("remote_peer_id"):
		NetworkLobby.notify_remote_player_hit(int(get_meta("remote_peer_id")))
"""
	hit_script.reload()
	body.set_script(hit_script)

	return body

func _remove_remote_player_node(peer_id: int) -> void:
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
