extends Node

## Manages round loop, target elimination counts, K/D scoreboard, First-to-10-Deaths rule, and runtime InputMap bindings.

signal round_updated(round_num: int, remaining_enemies: int, round_time_left: float)
signal round_won(round_num: int)
signal scoreboard_updated(stats: Dictionary)
signal match_over(loser_name: String, winner_label: String)
signal breakout_countdown_updated(seconds_left: float, horn_sounded: bool)
signal center_flag_state_changed(state_text: String, carrier_name: String, carrier_team: String, flag_world_pos: Vector3)

const BREAKOUT_COUNTDOWN_DURATION: float = 3.0
var breakout_countdown_left: float = 0.0
var breakout_horn_sounded: bool = true
var flag_state: String = "CENTER_50" # "CENTER_50", "CARRIED", "DROPPED"
var flag_carrier_name: String = ""
var flag_carrier_team: String = ""
var flag_world_pos: Vector3 = Vector3(0.0, 0.0, 1.35)
var alpha_flag_hangs: int = 0
var bravo_flag_hangs: int = 0

const MAX_DEATHS_TO_LOSE: int = 10

var current_round: int = 1
var remaining_enemies: int = 0
var round_time_left: float = 240.0
var round_active: bool = false

var local_kills: int = 0
var local_deaths: int = 0
var npc_deaths: int = 0
var match_ended: bool = false

func _ready() -> void:
	_setup_input_map()
	_setup_browser_close_and_hotkey_guard()

## v0.5 (Ren): the "Leave site?" warning is armed only during a match (so lobby menus / JOIN never trigger it).
func set_unload_guard(armed: bool) -> void:
	unload_guard_armed = armed
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__pb_unload_guard_armed = %s;" % ("true" if armed else "false"), true)

var unload_guard_armed: bool = false

func _wire_unload_guard() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl == null:
		return
	nl.match_started_signal.connect(func(_r, _b, _f): set_unload_guard(true))
	if nl.has_signal("left_room"):
		nl.left_room.connect(func(_r): set_unload_guard(false))
	if nl.has_signal("room_event"):
		nl.room_event.connect(func(ev, _d): if ev == "match_ended": set_unload_guard(false))

func _setup_browser_close_and_hotkey_guard() -> void:
	call_deferred("_wire_unload_guard")
	# Prevent accidental window/tab closure or OS/browser hotkey interruptions during Ctrl/Alt + WASD diving/sliding
	get_tree().set_auto_accept_quit(false)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
		(function() {
			if (window.__pb_hotkey_guard_installed) return;
			window.__pb_hotkey_guard_installed = true;
			window.addEventListener('beforeunload', function(e) {
				// v0.5 (Ren): only warn while you're actually in a match, never from the lobby menus.
				if (!window.__pb_unload_guard_armed) return;
				e.preventDefault();
				e.returnValue = '';
				return '';
			});
			window.addEventListener('keydown', function(e) {
				var k = (e.key || '').toLowerCase();
				if ((e.ctrlKey || e.altKey || e.metaKey) && (k === 'w' || k === 'q' || k === 'r' || k === 's' || k === 'a' || k === 'd' || k === 'c' || k === 'f4')) {
					e.preventDefault();
				}
			}, { capture: true, passive: false });
		})();
		""")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Ignore accidental Alt+F4 / Ctrl+W close requests while actively holding movement/dive keys in-match
		if Input.is_action_pressed("move_forward") or Input.is_action_pressed("prone_dive") or Input.is_action_pressed("crouch_slide") or Input.is_action_pressed("sprint"):
			return
		get_tree().quit()

func _process(delta: float) -> void:
	if not breakout_horn_sounded and round_active and not match_ended:
		breakout_countdown_left = maxf(0.0, breakout_countdown_left - delta)
		if breakout_countdown_left <= 0.0:
			breakout_horn_sounded = true
			breakout_countdown_updated.emit(0.0, true)
		else:
			breakout_countdown_updated.emit(breakout_countdown_left, false)
	if round_active and not match_ended:
		round_time_left = max(0.0, round_time_left - delta)
		round_updated.emit(current_round, remaining_enemies, round_time_left)

func register_round_start(enemy_count: int) -> void:
	remaining_enemies = enemy_count
	round_time_left = 240.0
	round_active = true
	match_ended = false
	breakout_countdown_left = BREAKOUT_COUNTDOWN_DURATION
	breakout_horn_sounded = false
	reset_center_flag_to_50()
	breakout_countdown_updated.emit(breakout_countdown_left, false)
	round_updated.emit(current_round, remaining_enemies, round_time_left)
	_emit_scoreboard()

func reset_center_flag_to_50() -> void:
	flag_state = "CENTER_50"
	flag_carrier_name = ""
	flag_carrier_team = ""
	flag_world_pos = Vector3(0.0, 0.0, 1.35)
	center_flag_state_changed.emit("AT CENTER 50", "", "", flag_world_pos)

func notify_flag_picked_up(carrier_name: String, carrier_team: String, pos: Vector3) -> void:
	flag_state = "CARRIED"
	flag_carrier_name = carrier_name
	flag_carrier_team = carrier_team
	flag_world_pos = pos
	center_flag_state_changed.emit("CARRIED BY %s (%s)" % [carrier_name, carrier_team], carrier_name, carrier_team, flag_world_pos)
	_emit_scoreboard()

func notify_flag_dropped(drop_pos: Vector3, former_carrier: String = "") -> void:
	flag_state = "DROPPED"
	flag_carrier_name = ""
	flag_carrier_team = ""
	flag_world_pos = Vector3(drop_pos.x, 0.0, drop_pos.z)
	center_flag_state_changed.emit("DROPPED @ (%.0fm, %.0fm)" % [drop_pos.x, drop_pos.z], former_carrier, "", flag_world_pos)
	_emit_scoreboard()

func notify_flag_hung(scorer_name: String, scorer_team: String) -> void:
	if scorer_team == "ALPHA":
		alpha_flag_hangs += 1
	else:
		bravo_flag_hangs += 1
	if scorer_name == (NetworkLobby.local_callsign if NetworkLobby else ""):
		local_deaths = max(0, local_deaths - 3)
	reset_center_flag_to_50()
	round_won.emit(current_round)
	_emit_scoreboard()

func reset_match_stats() -> void:
	local_kills = 0
	local_deaths = 0
	npc_deaths = 0
	match_ended = false
	_emit_scoreboard()

func record_local_kill(_victim_label: String = "Enemy") -> void:
	if match_ended:
		return
	local_kills += 1
	_emit_scoreboard()

func record_local_death(killer_label: String = "Enemy") -> void:
	if match_ended:
		return
	local_deaths += 1
	_emit_scoreboard()
	if local_deaths >= MAX_DEATHS_TO_LOSE:
		match_ended = true
		round_active = false
		match_over.emit(NetworkLobby.local_callsign, killer_label)

func notify_enemy_eliminated() -> void:
	if match_ended:
		return
	npc_deaths += 1
	remaining_enemies = max(0, remaining_enemies - 1)
	round_updated.emit(current_round, remaining_enemies, round_time_left)
	_emit_scoreboard()
	if npc_deaths >= MAX_DEATHS_TO_LOSE and round_active:
		match_ended = true
		round_active = false
		round_won.emit(current_round)
		match_over.emit("OpFor NPC Squad (10 Deaths)", NetworkLobby.local_callsign)

func get_scoreboard_snapshot() -> Dictionary:
	return {
		"local_name": NetworkLobby.local_callsign if NetworkLobby else "Player",
		"local_team": NetworkLobby.local_team if NetworkLobby else "ALPHA",
		"local_kills": local_kills,
		"local_deaths": local_deaths,
		"npc_deaths": npc_deaths,
		"alpha_flag_hangs": alpha_flag_hangs,
		"bravo_flag_hangs": bravo_flag_hangs,
		"flag_state": flag_state,
		"flag_carrier_name": flag_carrier_name,
		"max_deaths": MAX_DEATHS_TO_LOSE,
		"match_ended": match_ended
	}

func _emit_scoreboard() -> void:
	scoreboard_updated.emit(get_scoreboard_snapshot())

func reset_round() -> void:
	current_round += 1
	reset_match_stats()
	PaintBallistics.clear_all()
	get_tree().reload_current_scene()

func _setup_input_map() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("crouch_slide", KEY_Q)
	_bind_key("prone_dive", KEY_C)
	_bind_key("prone_dive", KEY_CTRL)
	_bind_key("prone_dive", KEY_ALT)
	_bind_key("prone_dive", KEY_Z)
	_bind_key("lean_peek", KEY_E)
	_bind_key("lean_right", KEY_E)
	_bind_key("swap_shoulder", KEY_X)
	_bind_key("reload_pod", KEY_R)
	_bind_key("bracket_speedball", KEY_1)
	_bind_key("bracket_woodsball", KEY_2)
	_bind_key("bracket_pump", KEY_3)
	_bind_key("reset_round", KEY_T)
	_bind_key("toggle_lobby", KEY_TAB)
	_bind_key("toggle_scoreboard", KEY_M)
	_bind_mouse("fire_primary", MOUSE_BUTTON_LEFT)
	_bind_mouse("fire_secondary_walk", MOUSE_BUTTON_RIGHT)
	_bind_mouse("swap_shoulder", MOUSE_BUTTON_MIDDLE)
	# v0.6 bunker callout ("1 in Red Snake 2"): Z (prone_dive) and MMB (swap_shoulder) are taken -> F (replaces the old
	# "ping_intel" F ping, folded into the callout) + mouse thumb button
	_bind_key("callout_bunker", KEY_F)
	_bind_mouse("callout_bunker", MOUSE_BUTTON_XBUTTON1)

func _bind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
