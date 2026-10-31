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
## v0.5 pre-match countdown (stable names; Bluey's HUD banner hooks these). Also delivered as room_event.
signal match_starting(data: Dictionary)
signal match_countdown(seconds_left: int, data: Dictionary)
signal match_start_cancelled(data: Dictionary)
signal start_rejected(reason: String, data: Dictionary)
## v0.5: emitted on clients after leave_room() (LobbyEntryFlow reopens the lobby browser).
signal left_room(room_id: String)
## v0.5: room_roster from the latest sync_lobby_state (Array of {peer,name,team,color,ready,alive,kills,deaths,bracket}).
signal room_roster_changed(roster: Array)
## v0.5 end-of-round / end-of-match recaps (data includes "scoreboard": Array of per-player rows) and the return to
## the waiting room once the match recap is over (see docs/NETWORK_EVENTS.md).
signal round_results(data: Dictionary)
signal match_results(data: Dictionary)
signal returned_to_lobby(room_id: String)
## v0.6 break + callouts: break_countdown(seconds_left) 3,2,1 -> break_horn (round goes live); callout_pinged(data)
## arrives only for your own team. break_line_reset(data) = you crossed your start line before the horn.
signal break_countdown(seconds_left: int, data: Dictionary)
signal break_horn(data: Dictionary)
signal break_line_reset(data: Dictionary)
signal callout_pinged(data: Dictionary)
## v0.6.4 team colors (Ren's waiting room / respawn screen): server-confirmed {"ALPHA": name, "BRAVO": name},
## and the reason your own request_team_color() was refused: round_active | taken | invalid | rate_limited.
signal team_colors_changed(team_colors: Dictionary)
signal team_color_rejected(reason: String)

const DEFAULT_WS_PORT: int = 9080

## --- v0.5 room constants ---
const PERMANENT_LOBBY_COUNT: int = 10
## v0.7: how many permanent lobbies this server runs (LOBBY_COUNT env or --lobbies=N, 1..10). The test server runs 2.
static var permanent_lobby_count: int = PERMANENT_LOBBY_COUNT
const BuildInfo = preload("res://scripts/systems/build_info.gd")
const TeamColorsScript = preload("res://scripts/systems/team_colors.gd") # v0.6.4 shared palette (not an autoload)
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
var local_ready: bool = false
var fill_bots_enabled: bool = false
var selected_map: String = "speedball"
var active_map: String = "speedball"
var selected_mode: String = "deathmatch"
var room_status: String = "waiting"
var match_active: bool = true
## True when the page / process was launched with an explicit ?room= (or --room=).
var room_from_url: bool = false
## v0.5: true when ?server= / --ws= / LOBBY_WS_URL chose the server explicitly.
var server_from_url: bool = false
## v0.5: the web build opened without ?room= shows Ren's LobbyBrowser (LobbyEntryFlow) instead of auto-joining.
var show_lobby_browser_on_start: bool = false
## Always-on DigitalOcean server (deploy/digitalocean) used when the page host does not serve /ws itself (GitHub Pages).
const DEFAULT_PUBLIC_WS_URL := "wss://play.jeetball.com/ws"
## The server a bare link connects to: the build's stamped SERVER_URL (test builds), else the page's own host /ws when
## served by our server (test.jeetball.com), else DEFAULT_PUBLIC_WS_URL. ?server= / --ws= still override it.
var default_ws_url: String = DEFAULT_PUBLIC_WS_URL

## SERVER_URL stamped into this build by tools/export_web.sh, else the live server.
static func build_default_ws_url() -> String:
	var stamped := String(BuildInfo.SERVER_URL).strip_edges()
	return stamped if not stamped.is_empty() else DEFAULT_PUBLIC_WS_URL

static func parse_lobby_count(raw: String) -> int:
	var t := raw.strip_edges()
	if t.is_empty() or not t.is_valid_int():
		return PERMANENT_LOBBY_COUNT
	return clampi(int(t), 1, PERMANENT_LOBBY_COUNT)

## Clients: the roster of the room we are in (peer_id -> {name, team, bracket, ready, room, kills, deaths, alive}).
## Server: every registered peer (same dictionaries as rooms[rid]["players"]).
var players: Dictionary = {}

## Server only: room_id -> {id, name, permanent, players: {peer_id: info}, settings: {map, mode}, match: Dictionary}
var rooms: Dictionary = {}
## Server only: peer_id -> room_id
var peer_room: Dictionary = {}
## Client: last public room state from the server (status, settings, match summary).
var room_state: Dictionary = {}
## v0.6.4: client view of the room's team colors (server-confirmed).
var team_colors: Dictionary = TeamColorsScript.DEFAULTS.duplicate()

## v0.7 profiles: the client's private profile token (user://profile.cfg, written by ProfileApi). It is sent to the
## server ONLY with srv_set_profile_token and kept server-side in _peer_profile_tokens (peer_id -> token), never in
## rooms[...]["players"], rosters, snapshots, room events or the lobby state file.
const PROFILE_CFG_PATH := "user://profile.cfg"
var profile_token: String = ""
var _peer_profile_tokens: Dictionary = {}
## Server: where to POST match results (PROFILE_API_URL + INTERNAL_KEY, both set by server.js when it spawns us).
var profile_api_url: String = ""
var profile_internal_key: String = ""
var last_match_result_payload: Dictionary = {}
var match_result_posts: int = 0

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

	if not is_dedicated_server and profile_token.is_empty():
		profile_token = load_saved_profile_token()
	if is_dedicated_server:
		var port := _resolve_dedicated_ws_port()
		start_dedicated_server(port)
		call_deferred("_build_server_collision_worlds")
	else:
		# Auto-connect when the link names a room (?room=, from a LobbyBrowser join_url) or LOBBY_WS_URL is set.
		# A bare web link shows the LobbyBrowser instead (LobbyEntryFlow); JOIN reloads the page with ?room=.
		if (OS.has_feature("web") and room_from_url) or not OS.get_environment("LOBBY_WS_URL").is_empty():
			connect_to_lobby(current_ws_url)
		elif show_lobby_browser_on_start:
			_refresh_offline_local_roster()
			connection_status_changed.emit("PICK A LOBBY (or SOLO TEST VS BOTS)", false)
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
	default_ws_url = build_default_ws_url()
	permanent_lobby_count = parse_lobby_count(OS.get_environment("LOBBY_COUNT"))

	for arg in all_args:
		if arg.begins_with("--lobbies="):
			permanent_lobby_count = parse_lobby_count(arg.trim_prefix("--lobbies="))
		elif arg.begins_with("--room="):
			active_room = sanitize_room_id(arg.trim_prefix("--room="))
			room_from_url = true
		elif arg.begins_with("--name="):
			local_callsign = _sanitize_token(arg.trim_prefix("--name="), local_callsign)
		elif arg.begins_with("--ws=") or arg.begins_with("--server="):
			var raw_arg := arg.split("=", true, 1)[1]
			current_ws_url = normalize_ws_url(raw_arg)
			server_from_url = true

	var env_ws := OS.get_environment("LOBBY_WS_URL")
	if not env_ws.is_empty():
		current_ws_url = normalize_ws_url(env_ws)
		server_from_url = true

	if OS.has_feature("web"):
		var host_v: Variant = JavaScriptBridge.eval("window.location.host || ''")
		var host := String(host_v) if typeof(host_v) == TYPE_STRING else ""
		if host.is_empty() or host.ends_with("github.io") or host.ends_with("itch.zone") or host.ends_with("itch.io"):
			# Static hosts (GitHub Pages) have no /ws: default to the build's server (live unless stamped otherwise).
			if not server_from_url:
				current_ws_url = default_ws_url
		else:
			var auto_ws: Variant = JavaScriptBridge.eval("(window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/ws'")
			if typeof(auto_ws) == TYPE_STRING and not String(auto_ws).is_empty():
				default_ws_url = String(auto_ws)
				if not server_from_url:
					current_ws_url = default_ws_url
		var search_str: Variant = JavaScriptBridge.eval("window.location.search || ''")
		if typeof(search_str) == TYPE_STRING and not String(search_str).is_empty():
			_parse_query_string(String(search_str))
		show_lobby_browser_on_start = not room_from_url

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
				server_from_url = true

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

func _build_server_collision_worlds() -> void:
	var n := ensure_collision_worlds()
	print("[NetworkLobby] PB-13 hit validation: %d map collision world(s) ready for line-of-sight checks" % n)

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
	_peer_profile_tokens.clear()
	profile_api_url = OS.get_environment("PROFILE_API_URL").strip_edges().trim_suffix("/")
	profile_internal_key = OS.get_environment("INTERNAL_KEY").strip_edges()
	rejected_shots.clear()
	rejected_hits.clear()
	rejected_team_colors.clear()
	_ensure_permanent_rooms()
	lobby_state_file = _resolve_lobby_state_file()
	if not lobby_state_file.is_empty():
		write_lobby_state_file()
		print("[NetworkLobby] Writing lobby state for /api/lobbies to %s" % lobby_state_file)
	var edgegap_ip := OS.get_environment("ARBITRIUM_PUBLIC_IP")
	var edgegap_tag := (" [Edgegap Public IP: %s]" % edgegap_ip) if not edgegap_ip.is_empty() else ""
	print("[NetworkLobby] Dedicated WebSocket Server listening on 0.0.0.0:%d (%d permanent lobbies, %d per team)%s" % [port, permanent_lobby_count, MAX_PER_TEAM, edgegap_tag])
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

## v0.5 READY toggle (informational only: Start Match never waits for it). Reset by the server after each match.
func set_ready(is_ready: bool) -> void:
	local_ready = is_ready
	if is_online_client():
		srv_set_ready.rpc_id(1, is_ready)
	else:
		_refresh_offline_local_roster()

## v0.6.4: ask the server for a team color for YOUR team (waiting room only). The answer is team_colors_changed
## (also in the lobby state) or team_color_rejected(reason). Offline there is no room to confirm it, so nothing is
## sent or emitted (the waiting room keeps its optimistic pick).
func request_team_color(color_name: String) -> void:
	if is_online_client():
		srv_request_team_color.rpc_id(1, color_name)

## Shared rule (server side): "" if team may take color_name given the room's current colors.
static func team_color_reject_reason(colors: Dictionary, team: String, color_name: String, locked: bool) -> String:
	if locked:
		return "round_active"
	if not TeamColorsScript.is_valid(color_name):
		return "invalid"
	var other := "BRAVO" if team == "ALPHA" else "ALPHA"
	if String(colors.get(other, TeamColorsScript.DEFAULTS[other])) == color_name:
		return "taken"
	return ""

func _client_set_team_colors(colors: Dictionary) -> void:
	var next := {}
	for t in TEAMS:
		next[t] = TeamColorsScript.name_for_team(t, colors)
	if next == team_colors:
		return
	team_colors = next
	_retint_nametags()
	team_colors_changed.emit(team_colors.duplicate())

## v0.6.4: remote callsign tags take the room's team color (TeamColors.for_team), lightened a bit to stay readable.
func nametag_color(team: String) -> Color:
	return TeamColorsScript.for_team(team, team_colors).lightened(0.3)

func _retint_nametags() -> void:
	for pid in remote_player_nodes:
		var node: Node = remote_player_nodes[pid]
		if not is_instance_valid(node):
			continue
		var tag := node.get_node_or_null("CallsignTag3D") as Label3D
		if tag != null and tag.has_meta("team"):
			tag.modulate = nametag_color(String(tag.get_meta("team")))

## v0.5: leave the current room cleanly and go back to the lobby list. Disconnects (the server drops the peer from
## its room on disconnect), clears room state, strips ?room= from the page URL and emits left_room.
func leave_room() -> void:
	var old_room := active_room
	if is_online_client() or peer != null:
		disconnect_from_lobby()
	active_room = DEFAULT_ROOM
	room_from_url = false
	match_active = false
	room_state = {}
	local_ready = false
	_client_set_team_colors(TeamColorsScript.DEFAULTS)
	if GameManager:
		GameManager.match_ended = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){var u=new URL(window.location.href);['room','team','map','mode'].forEach(function(k){u.searchParams.delete(k)});window.history.replaceState(null,'',u.toString());})()", true)
	show_lobby_browser_on_start = true
	_refresh_offline_local_roster()
	connection_status_changed.emit("LEFT ROOM [%s] — PICK A LOBBY" % old_room.to_upper(), false)
	left_room.emit(old_room)

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
		"players": players.duplicate(true),
		"room_roster": room_state.get("room_roster", []),
		"ready_count": int(room_state.get("ready_count", 0)),
		"countdown_ms_left": int(room_state.get("countdown_ms_left", 0)),
		"local_ready": local_ready,
		"team_colors": team_colors.duplicate(),
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
	_send_profile_token()

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

## v0.7: hand the server our private profile token so it can award clout at match end. Client -> server only.
static func is_valid_profile_token(t: String) -> bool:
	if t.length() != 64:
		return false
	for ch in t:
		if "0123456789abcdef".find(ch) == -1:
			return false
	return true

static func load_saved_profile_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_CFG_PATH) != OK:
		return ""
	var t := String(cfg.get_value("profile", "token", "")).strip_edges().to_lower()
	return t if is_valid_profile_token(t) else ""

func set_profile_token(token: String) -> void:
	var t := token.strip_edges().to_lower()
	profile_token = t if is_valid_profile_token(t) else ""
	if is_online_client():
		_send_profile_token()

func _send_profile_token() -> void:
	if not profile_token.is_empty():
		srv_set_profile_token.rpc_id(1, profile_token)

@rpc("any_peer", "call_remote", "reliable")
func srv_set_profile_token(token: String) -> void:
	if not is_dedicated_server:
		return
	_server_set_profile_token(multiplayer.get_remote_sender_id(), token)

func _server_set_profile_token(pid: int, token: String) -> void:
	if pid <= 1:
		return
	var t := token.strip_edges().to_lower()
	if is_valid_profile_token(t):
		_peer_profile_tokens[pid] = t
	else:
		_peer_profile_tokens.erase(pid)

## v0.6 bunker callout ping ("1 in Snake 2"): goes to your own team only. callout = bunker name, count = 0..5 enemies.
func ping_callout(callout: String, world_pos: Vector3, count: int = 1) -> void:
	if is_online_client():
		srv_ping_callout.rpc_id(1, callout, world_pos, count)

@rpc("any_peer", "call_remote", "reliable")
func srv_ping_callout(callout: String, world_pos: Vector3, count: int) -> void:
	if not is_dedicated_server:
		return
	_server_ping_callout(multiplayer.get_remote_sender_id(), callout, world_pos, count)

@rpc("any_peer", "call_remote", "reliable")
func srv_set_ready(is_ready: bool) -> void:
	if not is_dedicated_server:
		return
	_server_set_ready(multiplayer.get_remote_sender_id(), is_ready)

@rpc("any_peer", "call_remote", "reliable")
func srv_request_team_color(color_name: String) -> void:
	if not is_dedicated_server:
		return
	_server_request_team_color(multiplayer.get_remote_sender_id(), color_name)

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
			_server_request_start(sid, clean_bracket, fill_bots)
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
		# Online: the server answers with match_starting -> countdown -> notify_match_start (which sets match_active
		# and emits match_started_signal), or start_rejected.
		match_active = false
		return
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
			local_ready = bool(players[my_id].get("ready", local_ready))
	if state_dict.get("team_colors") is Dictionary:
		_client_set_team_colors(state_dict["team_colors"])
	if state_dict.has("room_roster"):
		room_roster_changed.emit(state_dict["room_roster"])
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
	if event_name == "match_starting":
		match_starting.emit(data)
	elif event_name == "match_countdown":
		match_countdown.emit(int(data.get("seconds_left", 0)), data)
	elif event_name == "match_start_cancelled":
		match_active = false
		match_start_cancelled.emit(data)
	elif event_name == "start_rejected":
		match_active = false
		start_rejected.emit(String(data.get("reason", "")), data)
	elif event_name == "team_colors_changed":
		if data.get("team_colors") is Dictionary:
			_client_set_team_colors(data["team_colors"])
	elif event_name == "team_color_rejected":
		if data.get("team_colors") is Dictionary:
			_client_set_team_colors(data["team_colors"])
		team_color_rejected.emit(String(data.get("reason", "invalid")))

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
		"round_ended":
			round_results.emit(data)
		"break_countdown":
			break_countdown.emit(int(data.get("seconds_left", 0)), data)
		"break_horn":
			break_horn.emit(data)
		"break_line_reset":
			break_line_reset.emit(data)
			_clamp_local_player_behind_line(float(data.get("line_z", 0.0)), String(data.get("team", local_team)))
		"callout_pinged":
			callout_pinged.emit(data)
		"returned_to_lobby":
			match_active = false
			room_status = "waiting"
			returned_to_lobby.emit(String(data.get("room", active_room)))
		"match_ended":
			match_results.emit(data)
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
		"round_started":
			match_active = true
			room_status = "in_match"
			GameManager.match_ended = false
			for pid in players.keys():
				players[pid]["alive"] = true
			if bool(data.get("reset_positions", false)):
				_respawn_local_player_at_gate()
		"teams_rebalanced":
			for mv in data.get("moves", []):
				if int(mv.get("peer", 0)) == my_id and String(mv.get("to", "")) in TEAMS:
					local_team = String(mv["to"])
					IntelBus.intel_feed_updated.emit("AUTO-BALANCE: YOU NOW PLAY FOR TEAM %s" % team_label(local_team).to_upper())
		"join_rejected":
			connection_status_changed.emit("ROOM [%s] REJECTED: %s" % [String(data.get("room", active_room)).to_upper(), String(data.get("reason", "?"))], true)


## v0.6 break: hard hold. Push the local player back onto their start line (no teleport, no penalty) and kill
## any velocity carrying them over it.
func _clamp_local_player_behind_line(line_z: float, team: String) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p: Variant = tree.current_scene.get("player")
	if not (p is Node3D and is_instance_valid(p)):
		return
	var n := p as Node3D
	var pos := n.global_position
	if team == "ALPHA":
		pos.z = max(pos.z, line_z)
	else:
		pos.z = min(pos.z, line_z)
	n.global_position = pos
	if n is CharacterBody3D:
		var b := n as CharacterBody3D
		if (team == "ALPHA" and b.velocity.z < 0.0) or (team != "ALPHA" and b.velocity.z > 0.0):
			b.velocity.z = 0.0

## Server round_started (CTF rounds / match start): put the local player back on their breakout gate.
func _respawn_local_player_at_gate() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p: Variant = tree.current_scene.get("player")
	if p is Node and is_instance_valid(p) and (p as Node).has_method("respawn_at_team_gate"):
		(p as Node).call("respawn_at_team_gate", local_team)

## =============================================================================================================
## SERVER: ROOM ROUTER (v0.5 PB-12). Everything below only runs on the dedicated server.
## =============================================================================================================

## Tests can set this to an Array to capture every outbound server message instead of (in addition to) sending.
var outbound_capture: Variant = null

static func is_permanent_room_id(rid: String) -> bool:
	if not rid.begins_with("lobby_") or rid.length() != 8:
		return false
	var n := rid.substr(6, 2)
	return n.is_valid_int() and int(n) >= 1 and int(n) <= permanent_lobby_count

static func default_map_for_lobby(index: int) -> String:
	return MAPS[(index - 1) % MAPS.size()]

func _ensure_permanent_rooms() -> void:
	for i in range(1, permanent_lobby_count + 1):
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
		"settings": {"map": map_id, "mode": mode_id, "team_colors": TeamColorsScript.DEFAULTS.duplicate()},
		"match": _new_match_state(),
	}

func _reset_room(room: Dictionary) -> void:
	var idx := int(String(room["id"]).substr(6, 2)) if bool(room["permanent"]) else 1
	room["settings"] = {"map": default_map_for_lobby(idx), "mode": "deathmatch", "team_colors": TeamColorsScript.DEFAULTS.duplicate()}
	room["match"] = _new_match_state()
	room["join_order"] = []
	room.erase("countdown_until_ms")
	room.erase("countdown_last_s")

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
			"ready": info.get("ready", false), "room": rid, "kills": info.get("kills", 0), "deaths": info.get("deaths", 0),
			"captures": info.get("captures", 0),
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
		"room_roster": _room_roster(room),
		"ready_count": _room_roster(room).filter(func(r): return bool(r["ready"])).size(),
		"countdown_ms_left": maxi(0, int(room.get("countdown_until_ms", 0)) - _rules_now()) if room.has("countdown_until_ms") else 0,
		"team_colors": _room_team_colors(room),
	}

## v0.5 room_roster: join order, one row per player (READY is informational only).
func _room_roster(room: Dictionary) -> Array:
	var out: Array = []
	var order: Array = room.get("join_order", []).duplicate()
	for pid in room.get("players", {}).keys():
		if not order.has(pid):
			order.append(pid)
	for pid in order:
		if not room.get("players", {}).has(pid):
			continue
		var info: Dictionary = room["players"][pid]
		out.append({
			"peer": int(pid), "name": info.get("name", ""), "team": info.get("team", "ALPHA"),
			"color": team_label(String(info.get("team", "ALPHA"))), "ready": bool(info.get("ready", false)),
			"alive": bool(info.get("alive", true)), "kills": int(info.get("kills", 0)), "deaths": int(info.get("deaths", 0)),
			"captures": int(info.get("captures", 0)),
			"bracket": info.get("bracket", "speedball"),
		})
	return out

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
	info["peer_id"] = pid
	info["team"] = _server_choose_team(room, pid, normalize_team(team), is_new, String(info.get("team", "")))
	room["players"][pid] = info
	players[pid] = info
	peer_room[pid] = rid
	if is_new:
		room["join_order"].append(pid)
		_on_player_joined_room(room, pid)
	print("[NetworkLobby] Registered peer %d: %s (Team %s, Bracket %s, Room %s, %d/%d)" % [pid, info["name"], info["team"], info["bracket"], rid, room["players"].size(), MAX_PER_TEAM * 2])
	_broadcast_room_state(rid)

## v0.5 auto team balance. A joining player goes to the smaller team (ties -> ALPHA/red). A requested team= is
## honoured only when it would not unbalance the room (the requested side is not already bigger) and has room.
## No switching while a match is running. Pure function of the room so tests can call it directly.
func _server_choose_team(room: Dictionary, pid: int, requested: String, is_new: bool, current: String) -> String:
	var c := room_team_counts(room, pid)
	var smaller := "ALPHA" if int(c["ALPHA"]) <= int(c["BRAVO"]) else "BRAVO"
	if int(c[smaller]) >= MAX_PER_TEAM:
		smaller = other_team(smaller)
	if not is_new and current in TEAMS:
		if bool(room["match"].get("active", false)):
			return current
		if requested.is_empty() or requested == current:
			return current
		if int(c[requested]) <= int(c[other_team(requested)]) and int(c[requested]) < MAX_PER_TEAM:
			return requested
		return current
	if requested in TEAMS and int(c[requested]) <= int(c[other_team(requested)]) and int(c[requested]) < MAX_PER_TEAM:
		return requested
	return smaller

## Between rounds / matches: if the teams differ by 2+, move the most recent joiners from the bigger team until
## the difference is <= 1. Returns [{peer, from, to}] and emits teams_rebalanced to the room when anything moved.
func _rebalance_room_teams(room: Dictionary) -> Array:
	var moves: Array = []
	var c := room_team_counts(room)
	var order: Array = room.get("join_order", []).duplicate()
	order.reverse()
	while absi(int(c["ALPHA"]) - int(c["BRAVO"])) >= 2:
		var big := "ALPHA" if int(c["ALPHA"]) > int(c["BRAVO"]) else "BRAVO"
		var moved := false
		for pid in order:
			var info: Dictionary = room["players"].get(pid, {})
			if not info.is_empty() and String(info.get("team", "")) == big:
				info["team"] = other_team(big)
				c[big] = int(c[big]) - 1
				c[other_team(big)] = int(c[other_team(big)]) + 1
				moves.append({"peer": int(pid), "name": info.get("name", ""), "from": big, "to": other_team(big)})
				order.erase(pid)
				moved = true
				break
		if not moved:
			break
	if not moves.is_empty():
		_send_room_event(String(room["id"]), "teams_rebalanced", {"moves": moves, "red": c["ALPHA"], "blue": c["BRAVO"]})
	return moves

func _server_remove_peer(pid: int) -> void:
	var rid := String(peer_room.get(pid, ""))
	peer_room.erase(pid)
	players.erase(pid)
	_peer_profile_tokens.erase(pid)
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
	_send_room(rid, &"rpc_fire_paintball", [origin, dir.normalized(), clampf(speed, MIN_MUZZLE_FPS, MAX_MUZZLE_FPS), pid], pid)

func _server_on_hit_report(shooter: int, victim: int, hit_pos: Vector3) -> void:
	var rid := String(peer_room.get(shooter, ""))
	if rid.is_empty() or shooter == victim or String(peer_room.get(victim, "")) != rid:
		return
	var verdict := {"ok": false, "reason": "before_horn"} if _in_break(rid) else ({"ok": false, "reason": "round_over"} if _in_intermission(rid) else _server_validate_hit(shooter, victim, hit_pos))
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
	v["dead_since_ms"] = _rules_now()
	_send_room_event(String(room["id"]), "player_eliminated", {
		"victim": victim, "victim_name": v.get("name", ""), "victim_team": v.get("team", ""),
		"shooter": shooter, "shooter_name": s.get("name", "Enemy"), "shooter_team": s.get("team", ""),
		"victim_kills": v.get("kills", 0), "victim_deaths": v.get("deaths", 0),
		"shooter_kills": s.get("kills", 0), "shooter_deaths": s.get("deaths", 0),
		"reason": reason, "scored": scored, "respawn_in_ms": _respawn_ms(room),
	})
	_on_player_eliminated(room, shooter, victim)
	_broadcast_room_state(String(room["id"]))

func _server_set_ready(pid: int, is_ready: bool) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty() or not players.has(pid):
		return
	if bool(players[pid].get("ready", false)) == is_ready:
		return
	players[pid]["ready"] = is_ready
	if is_ready and rooms.has(rid):
		_assign_team_on_ready(rooms[rid], pid)
	var t := String(players[pid].get("team", "ALPHA"))
	_send_room_event(rid, "player_ready_changed", {"peer": pid, "name": players[pid].get("name", ""), "ready": is_ready, "team": t, "color": team_label(t)})
	_broadcast_room_state(rid)

## v0.5 (Tyler): pressing READY takes a team spot: the side with fewer READY players (keep your side on a tie).
## Skipped mid-match / during the countdown so a running match never reshuffles. Start still runs a full balance.
func _assign_team_on_ready(room: Dictionary, pid: int) -> void:
	if bool(room["match"].get("active", false)) or room.has("countdown_until_ms"):
		return
	var info: Dictionary = room["players"].get(pid, {})
	if info.is_empty():
		return
	var rc := {"ALPHA": 0, "BRAVO": 0}
	for other in room["players"].keys():
		var o: Dictionary = room["players"][other]
		if int(other) != pid and bool(o.get("ready", false)):
			var ot := String(o.get("team", "ALPHA"))
			if rc.has(ot):
				rc[ot] = int(rc[ot]) + 1
	var cur := String(info.get("team", "ALPHA"))
	var target := cur
	if int(rc["ALPHA"]) < int(rc["BRAVO"]):
		target = "ALPHA"
	elif int(rc["BRAVO"]) < int(rc["ALPHA"]):
		target = "BRAVO"
	if target == cur or int(room_team_counts(room)[target]) >= MAX_PER_TEAM:
		return
	info["team"] = target
	var c := room_team_counts(room)
	_send_room_event(String(room["id"]), "teams_rebalanced", {"moves": [{"peer": pid, "name": info.get("name", ""), "from": cur, "to": target}], "red": c["ALPHA"], "blue": c["BRAVO"], "reason": "ready"})

func _server_set_room_settings(pid: int, map_id: String, mode_id: String) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty():
		return
	var room: Dictionary = rooms[rid]
	if bool(room["match"].get("active", false)) or room.has("countdown_until_ms"):
		_send_peer_event(pid, "settings_rejected", {"reason": "match_in_progress" if bool(room["match"].get("active", false)) else "match_starting", "map": room["settings"]["map"], "mode": room["settings"]["mode"]})
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

## v0.6.4 team colors: any room member picks the color of their own team while the room is waiting (not during
## the countdown or a match). Exact TeamColors.NAMES only, never the other team's color, at most one pick per
## TEAM_COLOR_MIN_INTERVAL_MS per player. Accepted: room event team_colors_changed + room state; refused: the
## requester gets team_color_rejected {reason, color, team_colors}.
const TEAM_COLOR_MIN_INTERVAL_MS: int = 300

func _room_team_colors(room: Dictionary) -> Dictionary:
	var cur: Dictionary = room.get("settings", {}).get("team_colors", {})
	var out := {}
	for t in TEAMS:
		out[t] = TeamColorsScript.name_for_team(t, cur)
	return out

func _server_request_team_color(pid: int, color_name: String) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty() or not rooms.has(rid) or not players.has(pid):
		return
	var room: Dictionary = rooms[rid]
	var info: Dictionary = players[pid]
	var team := String(TeamColorsScript.team_key(String(info.get("team", "ALPHA"))))
	var colors := _room_team_colors(room)
	var now := _rules_now()
	var locked := bool(room["match"].get("active", false)) or room.has("countdown_until_ms")
	var reason := team_color_reject_reason(colors, team, color_name, locked)
	if reason.is_empty() and info.has("team_color_ms") and now - int(info["team_color_ms"]) < TEAM_COLOR_MIN_INTERVAL_MS:
		reason = "rate_limited"
	if not reason.is_empty():
		_count_reject(rejected_team_colors, reason)
		_send_peer_event(pid, "team_color_rejected", {"reason": reason, "color": color_name.left(32), "team": team, "team_colors": colors})
		return
	info["team_color_ms"] = now
	if String(colors[team]) == color_name:
		_broadcast_room_state(rid)
		return
	colors[team] = color_name
	room["settings"]["team_colors"] = colors
	_send_room_event(rid, "team_colors_changed", {"team_colors": colors.duplicate(), "team": team, "color": color_name, "by": pid, "by_name": info.get("name", "")})
	_broadcast_room_state(rid)

## v0.5: any player in the room may cancel a running pre-match countdown.
func cancel_start() -> void:
	if is_online_client():
		srv_cancel_start.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func srv_cancel_start() -> void:
	if not is_dedicated_server:
		return
	_server_cancel_start(multiplayer.get_remote_sender_id())

func _server_cancel_start(pid: int) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty() or not rooms.has(rid):
		return
	var room: Dictionary = rooms[rid]
	if not room.has("countdown_until_ms"):
		return
	room.erase("countdown_until_ms")
	room.erase("countdown_last_s")
	_send_room_event(rid, "match_start_cancelled", {"by": pid, "by_name": players.get(pid, {}).get("name", "")})
	_broadcast_room_state(rid)

func _server_request_start(pid: int, bracket_id: String, fill_bots: bool = false) -> void:
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
	if room.has("countdown_until_ms"):
		_broadcast_room_state(rid) # countdown already running
		return
	if String(room["settings"]["mode"]) != "bots_test" and not fill_bots:
		_rebalance_room_teams(room) # a 2v0 room becomes 1v1 first; only a truly empty side is rejected
		var c: Dictionary = room_team_counts(room)
		if int(c["ALPHA"]) == 0 or int(c["BRAVO"]) == 0:
			_send_peer_event(pid, "start_rejected", {"room": rid, "reason": "team_empty", "red": int(c["ALPHA"]), "blue": int(c["BRAVO"])})
			return
	var ms := maxi(0, match_countdown_ms)
	var secs := int(ceil(ms / 1000.0))
	_send_room_event(rid, "match_starting", {
		"in_ms": ms, "seconds": secs, "by": pid, "by_name": players[pid].get("name", ""),
		"mode": room["settings"]["mode"], "map": room["settings"]["map"],
	})
	if ms <= 0:
		_start_room_match(room)
		return
	room["countdown_until_ms"] = _rules_now() + ms
	room["countdown_last_s"] = secs
	_send_room_event(rid, "match_countdown", {"seconds_left": secs, "ms_left": ms})
	_broadcast_room_state(rid)

## v0.5 pre-match countdown (match_starting -> match_countdown 5,4,3,2,1 -> round_started; cancel_start() aborts). Tests set match_countdown_ms.
const MATCH_COUNTDOWN_MS: int = 5000
var match_countdown_ms: int = MATCH_COUNTDOWN_MS

func _tick_room_countdown(room: Dictionary) -> void:
	if not room.has("countdown_until_ms"):
		return
	var rid := String(room["id"])
	if room["players"].is_empty():
		room.erase("countdown_until_ms")
		room.erase("countdown_last_s")
		return
	var left := int(room["countdown_until_ms"]) - _rules_now()
	if left <= 0:
		room.erase("countdown_until_ms")
		room.erase("countdown_last_s")
		_start_room_match(room)
		return
	var secs := int(ceil(left / 1000.0))
	if secs < int(room.get("countdown_last_s", secs + 1)):
		room["countdown_last_s"] = secs
		_send_room_event(rid, "match_countdown", {"seconds_left": secs, "ms_left": left})

func _server_tick(delta: float) -> void:
	for rid in rooms.keys():
		var room: Dictionary = rooms[rid]
		if room.has("countdown_until_ms"):
			_tick_room_countdown(room)
		if room["players"].is_empty():
			continue
		_tick_room_match(room, delta)
	_tick_lobby_state_file(delta)

## =============================================================================================================
## SERVER-AUTHORITATIVE MATCH RULES (v0.5). One state machine per room. See docs/NETWORK_EVENTS.md.
##   deathmatch : first team to DM_KILLS_TO_WIN kills, respawn ~1s after an elimination.
##   ctf        : one life per round, best of 5 (first to CTF_ROUNDS_TO_WIN). A round ends on a flag capture or when a
##                whole team is eliminated. One flag per base; the server owns pickup / drop / return / capture.
##   bots_test  : bots on (fill_bots), kills tracked, no win condition.
## phase: "waiting" (lobby, practice hits are not scored) -> "live" -> ("intermission" -> "live")* -> "waiting".
## =============================================================================================================
const DM_KILLS_TO_WIN: int = 10
const CTF_ROUNDS_TO_WIN: int = 3
const CTF_BEST_OF: int = 5
const DM_RESPAWN_MS: int = 1000
const BREAK_COUNTDOWN_MS: int = 3000 # v0.6: 3-2-1 at the start line, then the horn; no scored shots before it
const BREAK_LINE_Z: float = 40.0 # start line: ALPHA must stay at z >= +40, BRAVO at z <= -40 until the horn
const CALLOUT_COOLDOWN_MS: int = 1200
## Tests set this to 0 so rounds go live instantly.
var break_countdown_ms: int = BREAK_COUNTDOWN_MS
const CTF_ROUND_TIME_MS: int = 180000 # 3 min; on time-out the team with more players alive wins the round, else a draw
const PRACTICE_RESPAWN_MS: int = 1000
const ROUND_INTERMISSION_MS: int = 8000 # round winner + scoreboard recap before the next round
const MATCH_RESULTS_MS: int = 12000 # match winner + scoreboard recap before everyone returns to the waiting room
const FLAG_PICKUP_RADIUS: float = 2.35
const FLAG_CAPTURE_RADIUS: float = 4.2
const FLAG_AUTO_RETURN_MS: int = 30000
const TEAM_BASE_Z: float = 45.5 # ALPHA/red base +Z, BRAVO/blue base -Z (the breakout gates)
## Test hook: when >= 0 it replaces Time.get_ticks_msec() for the rules clock.
var rules_clock_override_ms: int = -1

func _rules_now() -> int:
	return rules_clock_override_ms if rules_clock_override_ms >= 0 else Time.get_ticks_msec()

static func team_base_position(team: String) -> Vector3:
	return Vector3(0.0, 0.0, TEAM_BASE_Z if team == "ALPHA" else -TEAM_BASE_Z)

func _new_match_state() -> Dictionary:
	return {
		"active": false, "phase": "waiting", "mode": "", "round": 0,
		"score": {"ALPHA": 0, "BRAVO": 0}, "kills": {"ALPHA": 0, "BRAVO": 0},
		"flags": _new_flags(), "phase_until_ms": 0, "winner": "",
	}

func _new_flags() -> Dictionary:
	var f := {}
	for t in TEAMS:
		f[t] = {"state": "home", "carrier": 0, "pos": team_base_position(t), "dropped_ms": 0}
	return f

static func _team_dict_to_colors(d: Dictionary) -> Dictionary:
	return {"red": int(d.get("ALPHA", 0)), "blue": int(d.get("BRAVO", 0))}

func _public_match_state(room: Dictionary) -> Dictionary:
	var m: Dictionary = room.get("match", {})
	if m.is_empty():
		return {}
	var flags := {}
	for t in TEAMS:
		var fl: Dictionary = m["flags"][t]
		flags[team_label(t)] = {"team": t, "state": fl["state"], "carrier": fl["carrier"], "pos": fl["pos"]}
	var mode := String(m.get("mode", "")) if bool(m.get("active", false)) else String(room["settings"]["mode"])
	return {
		"phase": m.get("phase", "waiting"), "mode": mode, "round": m.get("round", 0),
		"score": _team_dict_to_colors(m.get("score", {})), "kills": _team_dict_to_colors(m.get("kills", {})),
		"target": CTF_ROUNDS_TO_WIN if mode == "ctf" else (DM_KILLS_TO_WIN if mode == "deathmatch" else 0),
		"best_of": CTF_BEST_OF if mode == "ctf" else 1, "flags": flags,
		"round_time_ms": CTF_ROUND_TIME_MS if mode == "ctf" else 0,
		"round_ms_left": maxi(0, int(m.get("round_ends_ms", 0)) - _rules_now()) if String(m.get("phase", "")) == "live" and int(m.get("round_ends_ms", 0)) > 0 else 0,
		"respawn_ms": _respawn_ms(room),
	}

## Respawn delay for this room right now: DM 1 s, practice (waiting) 1 s, CTF 0 = no respawn until the next round.
func _respawn_ms(room: Dictionary) -> int:
	var m: Dictionary = room.get("match", {})
	if not bool(m.get("active", false)):
		return PRACTICE_RESPAWN_MS
	return 0 if String(m.get("mode", "")) == "ctf" else DM_RESPAWN_MS

func _room_mode(room: Dictionary) -> String:
	var m: Dictionary = room["match"]
	return String(m["mode"]) if bool(m.get("active", false)) else String(room["settings"]["mode"])

## v0.6 break: hard hold. Anyone past their own start line before the horn is pushed back onto the line (no
## false-start penalty, no teleport to the gate). Rate-limited to every 150 ms so a held W can't outrun it.
func _check_break_line(room: Dictionary, pid: int, pos: Vector3) -> void:
	var info: Dictionary = room["players"].get(pid, {})
	if info.is_empty():
		return
	var team := String(info.get("team", "ALPHA"))
	var crossed := pos.z < BREAK_LINE_Z if team == "ALPHA" else pos.z > -BREAK_LINE_Z
	if not crossed:
		return
	var now := _rules_now()
	if now - int(info.get("break_reset_ms", -100000)) < 150:
		return
	info["break_reset_ms"] = now
	info["break_false_starts"] = int(info.get("break_false_starts", 0)) + 1
	_send_peer_event(pid, "break_line_reset", {"room": String(room["id"]), "team": team, "gate": team_base_position(team), "line_z": BREAK_LINE_Z if team == "ALPHA" else -BREAK_LINE_Z})

func _in_break(rid: String) -> bool:
	if not rooms.has(rid):
		return false
	var m: Dictionary = rooms[rid]["match"]
	return bool(m.get("active", false)) and String(m.get("phase", "")) == "break"

## v0.6.1: the round recap (intermission) is dead time too - no shots or hits until the next break's horn.
func _in_intermission(rid: String) -> bool:
	if not rooms.has(rid):
		return false
	var m: Dictionary = rooms[rid]["match"]
	return bool(m.get("active", false)) and String(m.get("phase", "")) == "intermission"

## v0.6 callouts: relayed to the pinger's own team only (pinger included), rate-limited, alive players only.
func _server_ping_callout(pid: int, callout: String, world_pos: Vector3, count: int) -> void:
	var rid := String(peer_room.get(pid, ""))
	if rid.is_empty() or not rooms.has(rid) or not players.has(pid):
		return
	var info: Dictionary = players[pid]
	if not bool(info.get("alive", true)):
		return
	var now := _rules_now()
	if now - int(info.get("callout_ms", -100000)) < CALLOUT_COOLDOWN_MS:
		return
	info["callout_ms"] = now
	var clean := callout.strip_edges().substr(0, 24)
	if clean.is_empty():
		return
	var team := String(info.get("team", "ALPHA"))
	var data := {"room": rid, "peer": pid, "name": String(info.get("name", "")), "team": team, "color": team_label(team),
		"callout": clean, "count": clampi(count, 0, 5),
		"pos": Vector3(clampf(world_pos.x, -60.0, 60.0), clampf(world_pos.y, -5.0, 20.0), clampf(world_pos.z, -60.0, 60.0))}
	for other in rooms[rid]["players"].keys():
		if String(rooms[rid]["players"][other].get("team", "")) == team:
			_send_peer_event(int(other), "callout_pinged", data)
	callouts_sent += 1

var callouts_sent: int = 0

func _is_live(room: Dictionary) -> bool:
	return bool(room["match"].get("active", false)) and String(room["match"].get("phase", "")) == "live"

func _on_player_joined_room(room: Dictionary, pid: int) -> void:
	var info: Dictionary = room["players"][pid]
	info["alive"] = true
	# One life per CTF round: a late joiner sits out until the next round starts.
	if bool(room["match"].get("active", false)) and String(room["match"]["mode"]) == "ctf":
		info["alive"] = false
		info["dead_since_ms"] = _rules_now()
		info["late_join"] = true

func _on_player_left_room(room: Dictionary, pid: int) -> void:
	_drop_flags_carried_by(room, pid, "carrier_left")
	if _is_live(room) and String(room["match"]["mode"]) == "ctf":
		_check_ctf_elimination(room)

func _on_player_moved(room: Dictionary, pid: int, pos: Vector3) -> void:
	if bool(room["match"].get("active", false)) and String(room["match"].get("phase", "")) == "break":
		_check_break_line(room, pid, pos)
		return
	if not _is_live(room) or String(room["match"]["mode"]) != "ctf":
		return
	var info: Dictionary = room["players"].get(pid, {})
	if info.is_empty() or not bool(info.get("alive", true)):
		return
	var team := String(info.get("team", "ALPHA"))
	var enemy := other_team(team)
	var flags: Dictionary = room["match"]["flags"]
	var own: Dictionary = flags[team]
	var theirs: Dictionary = flags[enemy]
	var flat := Vector2(pos.x, pos.z)
	# Own flag lying in the field: touching it sends it home.
	if String(own["state"]) == "dropped" and flat.distance_to(Vector2(own["pos"].x, own["pos"].z)) <= FLAG_PICKUP_RADIUS:
		_set_flag(room, team, "home", 0, team_base_position(team), "returned", pid)
	# Enemy flag at their base or dropped: pick it up.
	if String(theirs["state"]) in ["home", "dropped"] and flat.distance_to(Vector2(theirs["pos"].x, theirs["pos"].z)) <= FLAG_PICKUP_RADIUS:
		_set_flag(room, enemy, "carried", pid, pos, "picked_up", pid)
	# Carrying the enemy flag back to your own base: capture (your own flag does not need to be home).
	if String(theirs["state"]) == "carried" and int(theirs["carrier"]) == pid:
		theirs["pos"] = pos
		var base := team_base_position(team)
		if flat.distance_to(Vector2(base.x, base.z)) <= FLAG_CAPTURE_RADIUS:
			_set_flag(room, enemy, "home", 0, team_base_position(enemy), "captured", pid)
			var cap_info: Dictionary = room["players"].get(pid, {})
			if not cap_info.is_empty():
				cap_info["captures"] = int(cap_info.get("captures", 0)) + 1
			_end_ctf_round(room, team, "capture", pid)

func _set_flag(room: Dictionary, flag_team: String, state: String, carrier: int, pos: Vector3, action: String, by_pid: int) -> void:
	var fl: Dictionary = room["match"]["flags"][flag_team]
	fl["state"] = state
	fl["carrier"] = carrier
	fl["pos"] = pos
	fl["dropped_ms"] = _rules_now() if state == "dropped" else 0
	var by_info: Dictionary = room["players"].get(by_pid, {})
	_send_room_event(String(room["id"]), "flag_state_changed", {
		"flag_team": flag_team, "flag": team_label(flag_team), "state": state, "action": action,
		"carrier": carrier, "carrier_name": String(room["players"].get(carrier, {}).get("name", "")),
		"by": by_pid, "by_name": String(by_info.get("name", "")), "pos": pos,
	})

func _drop_flags_carried_by(room: Dictionary, pid: int, action: String) -> void:
	if not bool(room["match"].get("active", false)):
		return
	for t in TEAMS:
		var fl: Dictionary = room["match"]["flags"][t]
		if String(fl["state"]) == "carried" and int(fl["carrier"]) == pid:
			var p: Vector3 = fl["pos"]
			var info: Dictionary = room["players"].get(pid, players.get(pid, {}))
			if info.has("state"):
				p = info["state"]["pos"]
			_set_flag(room, t, "dropped", 0, Vector3(clampf(p.x, -48.0, 48.0), 0.0, clampf(p.z, -46.0, 46.0)), action, pid)

func _on_player_eliminated(room: Dictionary, shooter: int, victim: int) -> void:
	if not _is_live(room):
		return
	var mode := String(room["match"]["mode"])
	var s: Dictionary = room["players"].get(shooter, {})
	var v: Dictionary = room["players"].get(victim, {})
	if mode == "ctf":
		_drop_flags_carried_by(room, victim, "carrier_eliminated")
		_check_ctf_elimination(room)
		return
	if s.is_empty() or v.is_empty() or String(s.get("team", "")) == String(v.get("team", "")):
		return
	var st := String(s["team"])
	room["match"]["kills"][st] = int(room["match"]["kills"][st]) + 1
	if mode == "deathmatch" and int(room["match"]["kills"][st]) >= DM_KILLS_TO_WIN:
		_end_room_match(room, st, "kills")

func _match_counts_kill(room: Dictionary) -> bool:
	return _is_live(room)

func _alive_counts(room: Dictionary) -> Dictionary:
	var c := {"ALPHA": 0, "BRAVO": 0}
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		if bool(info.get("alive", true)):
			c[String(info.get("team", "ALPHA"))] = int(c[String(info.get("team", "ALPHA"))]) + 1
	return c

func _check_ctf_elimination(room: Dictionary) -> void:
	if not _is_live(room):
		return
	var tc := room_team_counts(room)
	if int(tc["ALPHA"]) == 0 or int(tc["BRAVO"]) == 0:
		return # needs both teams present; a one-sided room can still win by capture
	var ac := _alive_counts(room)
	if int(ac["ALPHA"]) == 0 and int(ac["BRAVO"]) == 0:
		_end_ctf_round(room, "", "double_elimination", 0)
	elif int(ac["ALPHA"]) == 0:
		_end_ctf_round(room, "BRAVO", "elimination", 0)
	elif int(ac["BRAVO"]) == 0:
		_end_ctf_round(room, "ALPHA", "elimination", 0)

func _end_ctf_round(room: Dictionary, winner: String, reason: String, by_pid: int) -> void:
	var m: Dictionary = room["match"]
	if String(m["phase"]) != "live":
		return
	if winner in TEAMS:
		m["score"][winner] = int(m["score"][winner]) + 1
	m["phase"] = "intermission"
	m["phase_until_ms"] = _rules_now() + ROUND_INTERMISSION_MS
	var rid := String(room["id"])
	_send_room_event(rid, "round_ended", {
		"round": m["round"], "winner": winner, "winner_color": team_label(winner) if winner in TEAMS else "",
		"reason": reason, "by": by_pid, "by_name": String(room["players"].get(by_pid, {}).get("name", "")),
		"score": _team_dict_to_colors(m["score"]), "target": CTF_ROUNDS_TO_WIN, "best_of": CTF_BEST_OF,
		"next_round_in_ms": ROUND_INTERMISSION_MS if not (winner in TEAMS and int(m["score"][winner]) >= CTF_ROUNDS_TO_WIN) else 0,
		"match_point": winner in TEAMS and int(m["score"][winner]) >= CTF_ROUNDS_TO_WIN,
		"scoreboard": _room_scoreboard(room),
	})
	if winner in TEAMS and int(m["score"][winner]) >= CTF_ROUNDS_TO_WIN:
		_end_room_match(room, winner, "rounds")
		return
	_broadcast_room_state(rid)

## v0.5 recap rows: red then blue, each sorted by kills (then captures, then fewest deaths).
func _room_scoreboard(room: Dictionary) -> Array:
	var rows: Array = []
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		var t := String(info.get("team", "ALPHA"))
		rows.append({"peer": int(pid), "name": String(info.get("name", "")), "team": t, "color": team_label(t),
			"kills": int(info.get("kills", 0)), "deaths": int(info.get("deaths", 0)), "captures": int(info.get("captures", 0))})
	rows.sort_custom(func(a, b):
		if a["team"] != b["team"]:
			return String(a["team"]) == "ALPHA"
		if a["kills"] != b["kills"]:
			return int(a["kills"]) > int(b["kills"])
		if a["captures"] != b["captures"]:
			return int(a["captures"]) > int(b["captures"])
		return int(a["deaths"]) < int(b["deaths"]))
	return rows

func _start_room_match(room: Dictionary) -> void:
	var rid := String(room["id"])
	var mode := String(room["settings"]["mode"])
	var m := _new_match_state()
	m["active"] = true
	m["mode"] = mode
	room["match"] = m
	_rebalance_room_teams(room)
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		info["kills"] = 0
		info["deaths"] = 0
		info["captures"] = 0
		info["alive"] = true
		info.erase("late_join")
	room.erase("results_until_ms")
	_broadcast_room_state(rid)
	for pid in room["players"].keys():
		_send(int(pid), &"notify_match_start", [rid, String(room["players"][pid].get("bracket", "speedball")), mode == "bots_test"])
	_start_round(room, false)

func _start_round(room: Dictionary, rebalance: bool) -> void:
	var m: Dictionary = room["match"]
	var rid := String(room["id"])
	if rebalance:
		_rebalance_room_teams(room)
	m["round"] = int(m["round"]) + 1
	var brk := maxi(0, break_countdown_ms) if String(m["mode"]) != "bots_test" else 0
	m["phase"] = "break" if brk > 0 else "live"
	m["phase_until_ms"] = _rules_now() + brk if brk > 0 else 0
	m["break_last_s"] = int(ceil(brk / 1000.0))
	m["flags"] = _new_flags()
	m["round_ends_ms"] = _rules_now() + brk + CTF_ROUND_TIME_MS if String(m["mode"]) == "ctf" else 0
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		info["alive"] = true
		info.erase("late_join")
	_send_room_event(rid, "round_started", {
		"round_time_ms": CTF_ROUND_TIME_MS if String(m["mode"]) == "ctf" else 0, "respawn_ms": _respawn_ms(room),
		"break_ms": brk, "break_line_z": BREAK_LINE_Z,
		"round": m["round"], "mode": m["mode"], "score": _team_dict_to_colors(m["score"]),
		"kills": _team_dict_to_colors(m["kills"]), "reset_positions": true,
		"target": CTF_ROUNDS_TO_WIN if String(m["mode"]) == "ctf" else (DM_KILLS_TO_WIN if String(m["mode"]) == "deathmatch" else 0),
	})
	if brk > 0:
		_send_room_event(rid, "break_countdown", {"round": m["round"], "seconds_left": int(m["break_last_s"]), "ms_left": brk})
	_broadcast_room_state(rid)

func _end_room_match(room: Dictionary, winner: String, reason: String) -> void:
	var m: Dictionary = room["match"]
	var rid := String(room["id"])
	var mode := String(m["mode"])
	var score: Dictionary = m["score"] if mode == "ctf" else m["kills"]
	_report_match_result(room, winner, mode)
	_send_room_event(rid, "match_ended", {
		"winner": winner, "winner_color": team_label(winner) if winner in TEAMS else "", "reason": reason,
		"mode": mode, "score": _team_dict_to_colors(score), "kills": _team_dict_to_colors(m["kills"]),
		"rounds": m["round"], "scoreboard": _room_scoreboard(room),
		"winner_names": _room_scoreboard(room).filter(func(r): return String(r["team"]) == winner).map(func(r): return r["name"]),
		"return_to_lobby_in_ms": MATCH_RESULTS_MS,
	})
	room["results_until_ms"] = _rules_now() + MATCH_RESULTS_MS
	var fresh := _new_match_state()
	fresh["winner"] = winner
	room["match"] = fresh
	for pid in room["players"].keys():
		room["players"][pid]["alive"] = true
		room["players"][pid]["ready"] = false # READY resets after each match
	_rebalance_room_teams(room)
	_broadcast_room_state(rid)

## v0.7 clout hook: one row per human in the room who sent a profile token. bots_test matches earn nothing.
## server.js (POST /internal/match_result) resolves tokens, clamps values and applies the CLOUT table.
func build_match_result_payload(room: Dictionary, winner: String, mode: String) -> Dictionary:
	if mode == "bots_test" or not (mode in ["deathmatch", "ctf"]):
		return {}
	var m: Dictionary = room.get("match", {})
	var rows: Array = []
	for pid in room["players"].keys():
		var tok := String(_peer_profile_tokens.get(int(pid), ""))
		if tok.is_empty():
			continue
		var info: Dictionary = room["players"][pid]
		var team := String(info.get("team", "ALPHA"))
		rows.append({
			"token": tok, "won": winner in TEAMS and team == winner,
			"eliminations": int(info.get("kills", 0)), "flags": int(info.get("captures", 0)),
			"rounds_won": int(m.get("score", {}).get(team, 0)) if mode == "ctf" else 0,
		})
	if rows.is_empty():
		return {}
	return {"room": String(room["id"]), "mode": mode, "match_id": "%s_%d_%d" % [String(room["id"]), int(Time.get_unix_time_from_system() * 1000.0), randi()], "results": rows}

func _report_match_result(room: Dictionary, winner: String, mode: String) -> void:
	var payload := build_match_result_payload(room, winner, mode)
	last_match_result_payload = payload
	if payload.is_empty() or profile_api_url.is_empty() or profile_internal_key.is_empty() or not is_inside_tree():
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		if code != 200:
			push_warning("[NetworkLobby] match_result POST failed (HTTP %d) for room %s" % [code, payload["room"]])
		http.queue_free())
	var err := http.request(profile_api_url + "/internal/match_result",
		["Content-Type: application/json", "X-Internal-Key: " + profile_internal_key], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return
	match_result_posts += 1

func _tick_room_match(room: Dictionary, _delta: float) -> void:
	var now := _rules_now()
	if room.has("results_until_ms") and now >= int(room["results_until_ms"]):
		room.erase("results_until_ms")
		_send_room_event(String(room["id"]), "returned_to_lobby", {"room": String(room["id"])})
		_broadcast_room_state(String(room["id"]))
	var m: Dictionary = room["match"]
	var active := bool(m.get("active", false))
	var mode := String(m.get("mode", ""))
	if active and String(m["phase"]) == "intermission" and now >= int(m["phase_until_ms"]):
		_start_round(room, true)
		return
	if active and String(m["phase"]) == "break":
		var left_ms := int(m["phase_until_ms"]) - now
		if left_ms <= 0:
			m["phase"] = "live"
			m["phase_until_ms"] = 0
			_send_room_event(String(room["id"]), "break_horn", {"round": m["round"], "mode": mode})
			_broadcast_room_state(String(room["id"]))
			return
		var secs := int(ceil(left_ms / 1000.0))
		if secs < int(m.get("break_last_s", 0)):
			m["break_last_s"] = secs
			_send_room_event(String(room["id"]), "break_countdown", {"round": m["round"], "seconds_left": secs, "ms_left": left_ms})
		return
	var revived := false
	for pid in room["players"].keys():
		var info: Dictionary = room["players"][pid]
		if bool(info.get("alive", true)):
			continue
		var wait_ms := DM_RESPAWN_MS if active else PRACTICE_RESPAWN_MS
		if active and mode == "ctf":
			continue # one life per round
		if now - int(info.get("dead_since_ms", 0)) >= wait_ms:
			info["alive"] = true
			revived = true
	if active and mode == "ctf" and String(m["phase"]) == "live" and int(m.get("round_ends_ms", 0)) > 0 and now >= int(m["round_ends_ms"]):
		var ac := _alive_counts(room)
		var tw := "" if int(ac["ALPHA"]) == int(ac["BRAVO"]) else ("ALPHA" if int(ac["ALPHA"]) > int(ac["BRAVO"]) else "BRAVO")
		_end_ctf_round(room, tw, "time", 0)
		return
	if active and mode == "ctf" and String(m["phase"]) == "live":
		for t in TEAMS:
			var fl: Dictionary = m["flags"][t]
			if String(fl["state"]) == "dropped" and now - int(fl["dropped_ms"]) >= FLAG_AUTO_RETURN_MS:
				_set_flag(room, t, "home", 0, team_base_position(t), "auto_returned", 0)
	if revived:
		_broadcast_room_state(String(room["id"]))

## =============================================================================================================
## PB-13 SERVER HIT VALIDATION. Clients only *report* hits; the server checks them and owns eliminations.
##   shot  : shooter alive, not under the knee-slide / dive fire lock (packed_stance bits 16/32 + 0.10s recovery),
##           muzzle within SHOT_ORIGIN_TOLERANCE of the shooter's last reported position, sane muzzle velocity.
##   hit   : same room, different teams, both alive, a matching accepted shot from the last HIT_SHOT_WINDOW_MS
##           (range <= HIT_MAX_RANGE, aim within HIT_AIM_TOLERANCE_DEG after gravity drop), hit point inside the
##           victim's stance-sized hitbox at some point in their recent movement history (lag tolerant), and clear
##           line of sight against the room map's static geometry (arc or straight chord).
## =============================================================================================================
const BALL_GRAVITY: float = 9.81 # mirrors PaintBallistics.GRAVITY
const BALL_AIR_DRAG: float = 0.26 # mirrors PaintBallistics.AIR_DRAG
const MIN_MUZZLE_FPS: float = 150.0
const MAX_MUZZLE_FPS: float = 300.0
const SHOT_ORIGIN_TOLERANCE: float = 2.0
const HIT_SHOT_WINDOW_MS: int = 3000
const HIT_MAX_RANGE: float = 90.0
const HIT_AIM_TOLERANCE_DEG: float = 12.0
const HIT_HISTORY_SLACK_MS: int = 250
const HIT_BOX_TOP := [1.95, 1.30, 0.80, 0.80] # standing, crouching, prone, (spare) - feet-relative metres
const HIT_BOX_TOP_SLIDE: float = 1.0
const HIT_BOX_TOP_DIVE: float = 0.80
const HIT_BOX_BOTTOM: float = -0.35
const HIT_BOX_RADIUS: float = 0.9
const HIT_BOX_RADIUS_PRONE: float = 1.3
const LOS_END_SLACK: float = 0.45
var rejected_shots: Dictionary = {} # reason -> count
var rejected_hits: Dictionary = {} # reason -> count
var rejected_team_colors: Dictionary = {} # v0.6.4 reason -> count
## map_id -> World3D holding a private, collision-only copy of that arena (server only, see ensure_collision_worlds).
var collision_worlds: Dictionary = {}

static func muzzle_fps_to_mps(fps: float) -> float:
	return fps * 0.3048 * 0.68 # same conversion as PaintBallistics.spawn_paintball

func _count_reject(bucket: Dictionary, reason: String) -> void:
	bucket[reason] = int(bucket.get(reason, 0)) + 1

func _server_accept_shot(pid: int, origin: Vector3, dir: Vector3, speed: float) -> bool:
	var info: Dictionary = players.get(pid, {})
	if info.is_empty():
		return false
	var reason := ""
	if _in_break(String(peer_room.get(pid, ""))):
		reason = "before_horn"
	elif _in_intermission(String(peer_room.get(pid, ""))):
		reason = "round_over"
	elif not bool(info.get("alive", true)):
		reason = "shooter_dead"
	elif not is_remote_fire_allowed(pid):
		reason = "fire_lock"
		rejected_movement_lock_shots += 1
	elif info.has("state") and Vector3(info["state"]["pos"]).distance_to(origin - Vector3(0.0, 1.0, 0.0)) > SHOT_ORIGIN_TOLERANCE + 1.0:
		reason = "origin_mismatch"
	if not reason.is_empty():
		_count_reject(rejected_shots, reason)
		return false
	var now := _rules_now()
	var shots: Array = info.get("shots", [])
	shots.append({"ms": now, "origin": origin, "dir": dir, "speed": clampf(speed, MIN_MUZZLE_FPS, MAX_MUZZLE_FPS)})
	while shots.size() > 0 and (now - int(shots[0]["ms"]) > HIT_SHOT_WINDOW_MS or shots.size() > 48):
		shots.pop_front()
	info["shots"] = shots
	return true

static func stance_hitbox_top(stance_idx: int) -> float:
	if (stance_idx & STANCE_BIT_DIVING) != 0:
		return HIT_BOX_TOP_DIVE
	if (stance_idx & STANCE_BIT_SLIDING) != 0:
		return HIT_BOX_TOP_SLIDE
	return float(HIT_BOX_TOP[stance_idx & 3])

static func point_in_stance_box(hit_pos: Vector3, feet: Vector3, stance_idx: int) -> bool:
	var prone := (stance_idx & 3) == 2 or (stance_idx & STANCE_BIT_DIVING) != 0
	var r := HIT_BOX_RADIUS_PRONE if prone else HIT_BOX_RADIUS
	if Vector2(hit_pos.x - feet.x, hit_pos.z - feet.z).length() > r:
		return false
	var dy := hit_pos.y - feet.y
	return dy >= HIT_BOX_BOTTOM and dy <= stance_hitbox_top(stance_idx)

func _server_validate_hit(shooter: int, victim: int, hit_pos: Vector3) -> Dictionary:
	var s: Dictionary = players.get(shooter, {})
	var v: Dictionary = players.get(victim, {})
	var verdict := _validate_hit_inner(s, v, hit_pos)
	if not bool(verdict.get("ok", false)):
		_count_reject(rejected_hits, String(verdict.get("reason", "invalid")))
	return verdict

func _validate_hit_inner(s: Dictionary, v: Dictionary, hit_pos: Vector3) -> Dictionary:
	if s.is_empty() or v.is_empty():
		return {"ok": false, "reason": "unknown_player"}
	if not hit_pos.is_finite():
		return {"ok": false, "reason": "no_hit_position"}
	if String(s.get("team", "")) == String(v.get("team", "")):
		return {"ok": false, "reason": "friendly_fire"}
	if not bool(v.get("alive", true)):
		return {"ok": false, "reason": "victim_dead"}
	var now := _rules_now()
	var dead_since := int(s.get("dead_since_ms", -1)) if not bool(s.get("alive", true)) else -1
	# 1) a matching accepted shot (fired while alive; a ball in flight when the shooter dies still counts)
	var shot: Dictionary = {}
	var best_angle := 999.0
	for sh in s.get("shots", []):
		var age := now - int(sh["ms"])
		if age > HIT_SHOT_WINDOW_MS or age < -50:
			continue
		if dead_since >= 0 and int(sh["ms"]) > dead_since:
			continue
		var o: Vector3 = sh["origin"]
		var dist := o.distance_to(hit_pos)
		if dist > HIT_MAX_RANGE:
			continue
		var t := dist / maxf(muzzle_fps_to_mps(float(sh["speed"])), 1.0)
		var aim := hit_pos + Vector3(0.0, 0.5 * BALL_GRAVITY * t * t, 0.0) - o
		var ang := 0.0 if aim.length() < 0.5 else rad_to_deg(Vector3(sh["dir"]).angle_to(aim))
		if ang < best_angle:
			best_angle = ang
			shot = sh
	if dead_since >= 0 and shot.is_empty():
		return {"ok": false, "reason": "shooter_dead"}
	if shot.is_empty():
		return {"ok": false, "reason": "no_matching_shot"}
	if best_angle > HIT_AIM_TOLERANCE_DEG:
		return {"ok": false, "reason": "aim_mismatch", "angle": best_angle}
	# 2) stance-sized hitbox somewhere in the victim's recent history (shot time - slack .. now)
	var in_box := false
	var samples: Array = v.get("history", [])
	if samples.is_empty() and v.has("state"):
		samples = [[now, v["state"]["pos"], int(v["state"]["stance"])]]
	if samples.is_empty():
		return {"ok": false, "reason": "no_victim_state"}
	for smp in samples:
		if int(smp[0]) < int(shot["ms"]) - HIT_HISTORY_SLACK_MS and smp != samples[samples.size() - 1]:
			continue
		if point_in_stance_box(hit_pos, smp[1], int(smp[2])):
			in_box = true
			break
	if not in_box:
		return {"ok": false, "reason": "outside_hitbox"}
	# 3) line of sight against the room map's static geometry
	var room: Dictionary = rooms.get(String(s.get("room", "")), {})
	var map_id := String(room.get("settings", {}).get("map", "speedball")) if not room.is_empty() else "speedball"
	var los := line_of_sight_status(map_id, shot["origin"], shot["dir"], float(shot["speed"]), hit_pos)
	if los == "blocked":
		return {"ok": false, "reason": "no_line_of_sight"}
	return {"ok": true, "angle": best_angle, "los": los}

## Builds one private World3D per map containing a collision copy of the arena (bunkers, trees, wreck, walls).
## Called on the real dedicated server; tests call it explicitly. Returns the number of worlds available.
func ensure_collision_worlds() -> int:
	for map_id in MAPS:
		if collision_worlds.has(map_id):
			continue
		var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
		if packed == null:
			break
		var vp := SubViewport.new()
		vp.name = "CollisionWorld_%s" % map_id
		vp.own_world_3d = true
		vp.disable_3d = false
		vp.size = Vector2i(2, 2)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var arena := packed.instantiate()
		vp.add_child(arena)
		if map_id != "speedball" and arena.has_method("switch_arena_map"):
			arena.call("switch_arena_map", map_id)
		collision_worlds[map_id] = vp.find_world_3d()
	return collision_worlds.size()

func _ray_blocked(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	if a.distance_to(b) < 0.01:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()

## "clear", "blocked" or "unchecked" (no collision world for this map). Accepts if either the straight chord or the
## gravity+drag arc reaches the hit point (stopping LOS_END_SLACK short of it so the victim's cover lip still counts).
func line_of_sight_status(map_id: String, origin: Vector3, dir: Vector3, speed_fps: float, hit_pos: Vector3) -> String:
	var world: World3D = collision_worlds.get(normalize_map(map_id), null)
	if world == null:
		return "unchecked"
	var space := world.direct_space_state
	if space == null:
		return "unchecked"
	var total := origin.distance_to(hit_pos)
	if total <= LOS_END_SLACK:
		return "clear"
	var end := hit_pos.move_toward(origin, LOS_END_SLACK)
	if not _ray_blocked(space, origin, end):
		return "clear"
	# Arc: integrate the same gravity + drag as PaintBallistics until we pass the hit point.
	var p := origin
	var vel := dir.normalized() * muzzle_fps_to_mps(speed_fps)
	var dt := 1.0 / 60.0
	for _i in range(0, 400):
		vel.y -= BALL_GRAVITY * dt
		vel *= maxf(0.0, 1.0 - BALL_AIR_DRAG * dt)
		var nxt := p + vel * dt
		if nxt.distance_to(origin) >= total - LOS_END_SLACK:
			nxt = end if nxt.distance_to(end) < 3.0 else nxt
			return "blocked" if _ray_blocked(space, p, nxt) else "clear"
		if _ray_blocked(space, p, nxt):
			return "blocked"
		p = nxt
	return "blocked"

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
	for i in range(1, permanent_lobby_count + 1):
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
		tag.set_meta("team", team)
		tag.modulate = nametag_color(team)

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
	tag.set_meta("team", team)
	tag.modulate = nametag_color(team)
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
