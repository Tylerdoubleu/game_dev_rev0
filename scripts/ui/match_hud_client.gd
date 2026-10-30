extends Node
## v0.5 MATCH HUD CLIENT (Bluey) - client presentation ONLY for Tim's server-side match rules.
## Everything here is driven by NetworkLobby.room_event (docs/NETWORK_EVENTS.md) and the room_state.match snapshot
## that arrives with every sync_lobby_state. There is NO round / score / flag logic here: no win checks, no pickup or
## capture detection (the server does flag proximity from srv_player_state), nothing is ever sent to the server.
##
##  * Match HUD (Gritty 2000s Tournament panel): mode, team scores (DM kills -> 10, CTF rounds -> 3 of 5), round +
##    phase clock / intermission countdown, CTF alive counts per team, your auto-assigned team, short kill feed.
##  * Banners: round countdown ("ROUND 2 - 3...2...1 - GO"), round-end (winner + why), match-end (winner + final score),
##    DM respawn countdown, team assignment on join / auto-balance. Pre-match countdown: Tim's NetworkLobby signals
##    match_starting(data) / match_countdown(seconds_left, data) drive "MATCH STARTING - 3...2...1..." then round_started
##    shows GO. It is hidden again on leave_room(), or when a snapshot says the countdown stopped (countdown_ms_left=0
##    while still waiting = the server dropped it), or on match_start_cancelled (Tim's cancel_start(); signal hooked defensively).
##  * Spectate camera after a one-life CTF elimination: third person on living teammates, cycle with Q/E, LMB/RMB or
##    Left/Right (A/D), "SPECTATING: NAME"; returns control on round_started / match_ended. The player is locked via
##    PlayerController3D.set_spectating(true) (no movement, look or trigger pulls; no local respawn).
##  * CTF flags: one flag per base at NetworkLobby.team_base_position() (same on both maps), on the carrier's back
##    (remote avatar or local player), on the ground where dropped, back on the stand when returned/captured/reset.
##    HUD alerts ("YOU HAVE THE FLAG", "ENEMY HAS YOUR FLAG") + on-screen / off-screen edge markers to carriers.

const TEAM_COLORS := {"red": Color(0.96, 0.24, 0.18), "blue": Color(0.24, 0.56, 1.0)}
const GOLD := Color(0.98, 0.84, 0.15)
const KILL_FEED_MAX: int = 5
const KILL_FEED_TTL: float = 7.0
const ROUND_END_HOLD_MIN: float = 0.6 # the round-end banner shows until 3 s before the next round, at least this long
const COUNTDOWN_SECONDS: int = 3
const GO_BANNER_TIME: float = 1.6
const MATCH_END_BANNER_TIME: float = 9.0
const TEAM_BANNER_TIME: float = 3.5
const ROUND_SUMMARY_MIN: float = 2.5
const BREAK_LINE_Z_DEFAULT: float = 40.0
const BREAK_GO_TIME: float = 1.2
## v0.6 hook for the horn (Ren owns the sound): emitted once when the break horn releases the start line.
## NetworkLobby.break_horn(data) carries the same moment straight from the server.
signal break_horn_sounded(data: Dictionary)
const MODE_TITLES := {"deathmatch": "TEAM DEATHMATCH", "ctf": "CAPTURE THE FLAG", "bots_test": "BOTS TEST / PRACTICE"}

var builder: Node = null
var player: Node = null # PlayerController3D (CharacterBody3D)

## ---------------- presentation model (mirrors the server; replaced by every snapshot / event) ----------------
var mode: String = ""
var phase: String = "waiting" # waiting | live | intermission | ended (ended = client-only after match_ended)
var round_num: int = 0
var best_of: int = 1
var target: int = 0
var score := {"red": 0, "blue": 0}
var kills := {"red": 0, "blue": 0}
var flags := {}
var phase_clock: float = 0.0 # seconds since the current phase began on this client (display only)
var intermission_left: float = 0.0
var next_round_num: int = 0
var last_round_end_text: String = ""
var kill_feed: Array = [] # [{text, shooter_color, victim_color, age}]
var respawn_left: float = 0.0
## v0.5 (Tim 1a2b7d0): CTF round clock from match.round_ms_left / round_started.round_time_ms; ticks locally between syncs
var round_left: float = 0.0
var round_time_s: float = 0.0
var match_respawn_ms: int = -1 # match.respawn_ms / round_started.respawn_ms (-1 = not seen yet)
var round_timer_label: Label
## v0.6 break (server-run 3-2-1 + horn at the start line)
var break_active: bool = false
var break_left: float = 0.0
var break_line_z: float = BREAK_LINE_Z_DEFAULT
var break_go_left: float = 0.0
var break_line_resets: int = 0 # quiet snap-backs accepted (no UI)
var break_horns_heard: int = 0
var break_label: Label
var stats_label: Label
var last_team_shown: String = ""
var local_peer_override: int = 0 # tests
var events_seen: Array[String] = []
var _last_match_snapshot: Dictionary = {}

## countdown banner (round intermission or Tim's pre-match match_countdown)
var countdown_active: bool = false
var countdown_left: float = 0.0
var countdown_title: String = ""
var countdown_source: String = "" # "round" | "match"
## generic timed banner
var banner_text: String = ""
var banner_kind: String = "" # go | round_end | match_end | team | info
var banner_left: float = 0.0
var banner_color: Color = GOLD

## spectate
var spectating: bool = false
var spectate_target_pid: int = 0
var spectate_camera: Camera3D = null

## ---------------- nodes ----------------
var canvas: CanvasLayer
var panel: PanelContainer
var mode_label: Label
var red_score_label: Label
var blue_score_label: Label
var info_label: Label
var alive_label: Label
var team_label: Label
var kill_feed_box: VBoxContainer
var banner_label: Label
var sub_banner_label: Label
var flag_alert_label: Label
var spectate_label: Label
var flag_markers := {} # color -> Label
var flags_root: Node3D
## round-end / match-end scoreboard overlay
var summary_panel: PanelContainer
var summary_title: Label
var summary_sub: Label
var summary_grid: GridContainer
var summary_footer: Label
var summary_kind: String = "" # "" | round | match
var summary_left: float = 0.0
var summary_rows: Array = [] # the server's scoreboard rows {peer, name, team, color, kills, deaths, captures}, frozen
var has_server_match: bool = false # any server round/match event or match snapshot seen
var awaiting_return_to_lobby: bool = false # match recap up; the server's returned_to_lobby ends it (we never navigate)
var round_results_seen: int = 0
var match_results_seen: int = 0
var flag_stands := {} # color -> Node3D (base plate + stand, always at the base)
var flag_nodes := {} # color -> Node3D (pole + cloth, moves home / carrier back / dropped)

func setup(p_builder: Node, p_player: Node) -> void:
	builder = p_builder
	player = p_player
	for c in ["red", "blue"]:
		var t := "ALPHA" if c == "red" else "BRAVO"
		flags[c] = {"team": t, "state": "home", "carrier": 0, "pos": _base_pos(t)}
	_build_hud()
	_build_flags()
	if player != null and player.has_signal("player_eliminated"):
		player.player_eliminated.connect(_on_local_player_eliminated_signal)
	NetworkLobby.room_event.connect(apply_room_event)
	if NetworkLobby.has_signal("match_starting"):
		NetworkLobby.connect("match_starting", on_match_starting)
	if NetworkLobby.has_signal("match_countdown"):
		NetworkLobby.connect("match_countdown", on_match_countdown)
	if NetworkLobby.has_signal("match_start_cancelled"):
		NetworkLobby.connect("match_start_cancelled", on_match_start_cancelled)
	# Tim's recap signals (round_ended / match_ended data incl. "scoreboard"); the room-event fallback covers older builds
	if NetworkLobby.has_signal("round_results"):
		NetworkLobby.connect("round_results", on_round_results)
	if NetworkLobby.has_signal("match_results"):
		NetworkLobby.connect("match_results", on_match_results)
	if NetworkLobby.has_signal("returned_to_lobby"):
		NetworkLobby.connect("returned_to_lobby", on_returned_to_lobby)
	if NetworkLobby.has_signal("left_room"):
		NetworkLobby.connect("left_room", _on_left_room)
	for sig in [["break_countdown", on_break_countdown], ["break_horn", on_break_horn], ["break_line_reset", on_break_line_reset]]:
		if NetworkLobby.has_signal(sig[0]):
			NetworkLobby.connect(sig[0], sig[1])
	NetworkLobby.lobby_state_changed.connect(_on_lobby_state_changed)
	if NetworkLobby.has_signal("mode_changed"):
		NetworkLobby.mode_changed.connect(_on_mode_changed)
	# adopt whatever the lobby already knows (e.g. when the scene is rebuilt mid-match)
	_on_lobby_state_changed({})
	_refresh_all()

## =========================================== queries used by the builder / player ===========================================

func my_peer_id() -> int:
	if local_peer_override != 0:
		return local_peer_override
	return int(NetworkLobby._my_peer_id())

func my_color() -> String:
	return NetworkLobby.team_label(NetworkLobby.local_team)

func enemy_color() -> String:
	return "blue" if my_color() == "red" else "red"

func is_one_life_round_live() -> bool:
	return mode == "ctf" and phase == "live"

## The legacy single Center-50 flag must not show (or run its local pickup) in CTF or on any online client.
func legacy_center_flag_enabled() -> bool:
	return mode != "ctf" and NetworkLobby.selected_mode != "ctf" and not NetworkLobby.is_online_client()

func base_flags_active() -> bool:
	return mode == "ctf" or (mode.is_empty() and NetworkLobby.selected_mode == "ctf")

func alive_counts() -> Dictionary:
	var out := {"red": 0, "blue": 0}
	for pid in NetworkLobby.players.keys():
		var info: Dictionary = NetworkLobby.players[pid]
		if bool(info.get("alive", true)):
			var c := NetworkLobby.team_label(String(info.get("team", "ALPHA")))
			out[c] = int(out[c]) + 1
	return out

## =========================================== event intake ===========================================

func apply_room_event(event_name: String, data: Dictionary) -> void:
	events_seen.append(event_name)
	if event_name in ["round_started", "round_ended", "match_ended"]:
		has_server_match = true
	match event_name:
		"round_started":
			_on_round_started(data)
		"round_ended":
			_on_round_ended(data)
			if not NetworkLobby.has_signal("round_results"):
				on_round_results(data)
		"match_ended":
			_on_match_ended(data)
			if not NetworkLobby.has_signal("match_results"):
				on_match_results(data)
		"returned_to_lobby":
			if not NetworkLobby.has_signal("returned_to_lobby"):
				on_returned_to_lobby(String(data.get("room", "")))
		"player_eliminated":
			_on_player_eliminated(data)
		"break_countdown":
			if not NetworkLobby.has_signal("break_countdown"):
				on_break_countdown(int(data.get("seconds_left", 0)), data)
		"break_horn":
			if not NetworkLobby.has_signal("break_horn"):
				on_break_horn(data)
		"break_line_reset":
			if not NetworkLobby.has_signal("break_line_reset"):
				on_break_line_reset(data)
		"flag_state_changed":
			_on_flag_state_changed(data)
		"teams_rebalanced":
			_on_teams_rebalanced(data)
		"room_settings_changed":
			if data.has("mode"):
				_set_mode(NetworkLobby.normalize_mode(String(data["mode"]), mode))
		# Pre-match countdown: NetworkLobby re-emits these as its match_starting / match_countdown signals (hooked in
		# setup); only fall back to the raw room events if a build has no such signals.
		"match_countdown":
			if not NetworkLobby.has_signal("match_countdown"):
				on_match_countdown(int(data.get("seconds_left", 0)), data)
		"match_starting":
			if summary_kind == "match":
				awaiting_return_to_lobby = false
				hide_summary()
			if not NetworkLobby.has_signal("match_starting"):
				on_match_starting(data)
		"match_start_cancelled", "match_start_canceled", "match_countdown_cancelled", "match_countdown_canceled":
			if not NetworkLobby.has_signal("match_start_cancelled"):
				on_match_start_cancelled(data)
	_refresh_all()

## Tim's upcoming cancel_start() -> match_start_cancelled: hide the countdown banner (signal hooked defensively).
func on_match_start_cancelled(_data: Variant = {}) -> void:
	cancel_countdown("match")
	_refresh_all()

## NetworkLobby.match_starting(data): {in_ms (3000), seconds (3), by, by_name, mode, map}.
func on_match_starting(data: Dictionary) -> void:
	if _is_cancel_payload(data):
		cancel_countdown("match")
		return
	if phase == "ended":
		phase = "waiting"
	start_countdown(_seconds_from(data, 0.0), "MATCH STARTING", "match")
	_refresh_all()

## NetworkLobby.match_countdown(seconds_left, data): sent at 3, 2, 1 (data: seconds_left, ms_left). round_started follows.
func on_match_countdown(seconds_left: int, data: Dictionary) -> void:
	if _is_cancel_payload(data):
		cancel_countdown("match")
		return
	var secs := float(data["ms_left"]) / 1000.0 if data.has("ms_left") else float(seconds_left)
	if secs <= 0.0:
		return # round_started (GO) is next
	if countdown_active and countdown_source == "match":
		countdown_left = secs # re-sync the local tick to the server's second
		_refresh_banner()
	else:
		start_countdown(secs, "MATCH STARTING", "match")
	_refresh_all()

func _on_left_room(_room_id: String = "") -> void:
	_end_break_hold()
	awaiting_return_to_lobby = false
	hide_summary()
	if countdown_active and countdown_source == "match":
		cancel_countdown("match", false)
	exit_spectate()
	_refresh_all()

func _on_lobby_state_changed(_state: Dictionary) -> void:
	var m: Variant = NetworkLobby.room_state.get("match", {})
	if typeof(m) == TYPE_DICTIONARY and not (m as Dictionary).is_empty() and m != _last_match_snapshot:
		_last_match_snapshot = (m as Dictionary).duplicate(true)
		has_server_match = true
		apply_match_snapshot(m)
	elif mode.is_empty() and NetworkLobby.is_online_client():
		_set_mode(NetworkLobby.selected_mode)
	# The server has no cancel event: a snapshot that shows no countdown while we are still waiting (and not about to
	# hit 0) means it was dropped (room emptied / a future cancel) - hide the banner.
	if countdown_active and countdown_source == "match" and NetworkLobby.room_state.has("countdown_ms_left") \
			and int(NetworkLobby.room_state.get("countdown_ms_left", 0)) <= 0 and phase != "live" and countdown_left > 0.75:
		cancel_countdown("match")
	_check_team_banner()
	_sync_spectate_with_roster()
	_refresh_all()

## Adopt the authoritative room_state.match (phase, mode, round, best_of, target, score, kills, flags).
func apply_match_snapshot(m: Dictionary) -> void:
	if m.has("mode") and not String(m["mode"]).is_empty():
		_set_mode(String(m["mode"]))
	var new_phase := String(m.get("phase", phase))
	if new_phase == "break" and not break_active and phase != "ended":
		_enter_break(0.0, float(m.get("break_line_z", break_line_z)))
	elif new_phase == "live" and break_active:
		on_break_horn({"round": int(m.get("round", round_num)), "mode": String(m.get("mode", mode)), "from_snapshot": true})
	if new_phase != phase and not (phase == "ended" and new_phase != "live"):
		if new_phase == "live" and phase != "live":
			phase_clock = 0.0
		phase = new_phase
	round_num = int(m.get("round", round_num))
	best_of = int(m.get("best_of", best_of))
	target = int(m.get("target", target))
	_copy_colors(m.get("score", {}), score)
	_copy_colors(m.get("kills", {}), kills)
	if m.has("round_time_ms"):
		round_time_s = float(m["round_time_ms"]) / 1000.0
	if m.has("round_ms_left"):
		round_left = float(m["round_ms_left"]) / 1000.0 # 0 outside a live CTF round
	if m.has("respawn_ms"):
		match_respawn_ms = int(m["respawn_ms"])
	var fl: Variant = m.get("flags", {})
	if typeof(fl) == TYPE_DICTIONARY:
		for c in ["red", "blue"]:
			if (fl as Dictionary).has(c):
				var f: Dictionary = fl[c]
				flags[c]["state"] = String(f.get("state", "home"))
				flags[c]["carrier"] = int(f.get("carrier", 0))
				flags[c]["pos"] = _to_vec3(f.get("pos", flags[c]["pos"]))
	_refresh_flags()

func _on_round_started(data: Dictionary) -> void:
	_set_mode(String(data.get("mode", mode)))
	round_num = int(data.get("round", round_num + 1))
	target = int(data.get("target", target))
	best_of = 5 if mode == "ctf" else 1
	_copy_colors(data.get("score", {}), score)
	_copy_colors(data.get("kills", {}), kills)
	phase = "live"
	phase_clock = 0.0
	intermission_left = 0.0
	respawn_left = 0.0
	countdown_active = false
	round_time_s = float(data.get("round_time_ms", 0)) / 1000.0
	var brk_ms := int(data.get("break_ms", 0))
	# v0.6: with a break the CTF clock starts at the horn (round_ms_left stays 0 until then)
	round_left = round_time_s if mode == "ctf" and brk_ms <= 0 else 0.0
	if data.has("respawn_ms"):
		match_respawn_ms = int(data["respawn_ms"])
	hide_summary()
	awaiting_return_to_lobby = false
	if mode == "ctf":
		for c in ["red", "blue"]: # the server resets both flags with every round_started (reset_positions)
			flags[c]["state"] = "home"
			flags[c]["carrier"] = 0
			flags[c]["pos"] = _base_pos(String(flags[c]["team"]))
	_refresh_flags()
	exit_spectate()
	_clear_player_input_blocks("round_started")
	if brk_ms > 0:
		_enter_break(float(brk_ms) / 1000.0, float(data.get("break_line_z", BREAK_LINE_Z_DEFAULT)))
		return
	_end_break_hold()
	_show_go_banner()

func _show_go_banner() -> void:
	if mode == "ctf":
		_show_banner("ROUND %d - GO!" % round_num, "go", GO_BANNER_TIME, Color(0.32, 1.0, 0.5))
	elif mode == "deathmatch":
		_show_banner("TEAM DEATHMATCH - FIRST TO %d - GO!" % maxi(target, 1), "go", GO_BANNER_TIME, Color(0.32, 1.0, 0.5))
	else:
		_show_banner("BOTS TEST - PRACTICE LIVE", "go", GO_BANNER_TIME, Color(0.32, 1.0, 0.5))

## =========================================== v0.6 break ===========================================

## Signed start line for my team: red holds z >= +line, blue z <= -line.
func my_break_line() -> float:
	return absf(break_line_z) * (1.0 if NetworkLobby.local_team == "ALPHA" else -1.0)

func _enter_break(seconds: float, line_z: float) -> void:
	break_active = true
	phase = "break"
	phase_clock = 0.0
	break_line_z = absf(line_z) if not is_zero_approx(line_z) else BREAK_LINE_Z_DEFAULT
	if seconds > 0.0:
		break_left = seconds
	elif break_left <= 0.0:
		break_left = float(COUNTDOWN_SECONDS)
	break_go_left = 0.0
	round_left = 0.0
	if banner_kind == "go":
		banner_left = 0.0
	_show_banner("ROUND %d - HOLD THE LINE" % round_num if mode == "ctf" else "HOLD THE LINE", "info", break_left, GOLD)
	if player != null and player.has_method("set_break_hold"):
		player.call("set_break_hold", true, my_break_line())

func _end_break_hold() -> void:
	break_active = false
	break_left = 0.0
	if player != null and player.has_method("set_break_hold"):
		player.call("set_break_hold", false, 0.0)

## NetworkLobby.break_countdown(seconds_left, data): 3, 2, 1 (data.ms_left re-syncs the local tick).
func on_break_countdown(seconds_left: int, data: Dictionary = {}) -> void:
	var secs := float(data["ms_left"]) / 1000.0 if data.has("ms_left") else float(seconds_left)
	if not break_active:
		_enter_break(secs, float(data.get("break_line_z", break_line_z)))
	break_left = maxf(0.0, secs)
	_refresh_all()

## NetworkLobby.break_horn(data): GO!, release the start line, start the CTF clock.
func on_break_horn(data: Dictionary = {}) -> void:
	var was_holding := break_active
	if not was_holding and phase == "live" and break_go_left > 0.0:
		return # already released (a snapshot beat the horn event here)
	_end_break_hold()
	phase = "live"
	phase_clock = 0.0
	if mode == "ctf" and round_left <= 0.0:
		round_left = round_time_s if round_time_s > 0.0 else float(NetworkLobby.CTF_ROUND_TIME_MS) / 1000.0
	break_go_left = BREAK_GO_TIME
	if banner_kind == "info":
		banner_left = 0.0
	_show_go_banner()
	if was_holding or not bool(data.get("from_snapshot", false)):
		break_horns_heard += 1
		break_horn_sounded.emit(data)
	_refresh_all()

## NetworkLobby.break_line_reset(data): the server snapped us back (NetworkLobby moves us to the gate). Accepted
## quietly - no message, flash or penalty; the start line is a physical wall client-side so this should not happen.
func on_break_line_reset(data: Dictionary = {}) -> void:
	break_line_resets += 1
	if data.has("line_z"):
		break_line_z = absf(float(data["line_z"]))
	if break_active and player != null and player.has_method("set_break_hold"):
		player.call("set_break_hold", true, my_break_line())
	_refresh_all()

## Big centre text: 3 / 2 / 1 > GO!
func break_text() -> String:
	if break_active:
		return str(maxi(1, int(ceil(break_left))))
	if break_go_left > 0.0:
		return "GO!"
	return ""

func _on_round_ended(data: Dictionary) -> void:
	_end_break_hold()
	_copy_colors(data.get("score", {}), score)
	phase = "intermission"
	phase_clock = 0.0
	round_left = 0.0
	var finished := int(data.get("round", round_num))
	round_num = finished
	next_round_num = finished + 1
	intermission_left = float(data.get("next_round_in_ms", NetworkLobby.ROUND_INTERMISSION_MS)) / 1000.0
	var winner_color := String(data.get("winner_color", ""))
	var why := round_why(data)
	if winner_color.is_empty():
		last_round_end_text = "ROUND %d - DRAW: %s" % [finished, why]
	else:
		last_round_end_text = "ROUND %d - %s WINS: %s" % [finished, winner_color.to_upper(), why]
	last_round_end_text += "   [RED %d - %d BLUE]" % [int(score["red"]), int(score["blue"])]
	banner_color = TEAM_COLORS.get(winner_color, GOLD)
	if intermission_left > 0.0: # 0 = this round decided the match; match_ended follows
		start_countdown(intermission_left, "ROUND %d" % next_round_num, "round")
	_show_banner(last_round_end_text, "round_end", maxf(ROUND_END_HOLD_MIN, intermission_left - COUNTDOWN_SECONDS), banner_color)

## "FLAG CAPTURED BY X" / "RED TEAM ELIMINATED" ... from round_ended data (by_name from the server, roster fallback).
func round_why(data: Dictionary) -> String:
	var winner_color := String(data.get("winner_color", ""))
	var reason := String(data.get("reason", ""))
	var why := ""
	match reason:
		"capture":
			var by_name := String(data.get("by_name", ""))
			if by_name.is_empty():
				by_name = _player_name(int(data.get("by", 0)))
			why = "FLAG CAPTURED" + (" BY %s" % by_name.to_upper() if not by_name.is_empty() else "")
		"elimination":
			why = "%s TEAM ELIMINATED" % ("BLUE" if winner_color == "red" else "RED")
		"double_elimination":
			why = "DOUBLE ELIMINATION - NO POINT"
		"time":
			if winner_color.is_empty():
				why = "TIME UP - EQUAL PLAYERS ALIVE, NO POINT"
			else:
				why = "TIME UP - %s HAD MORE PLAYERS ALIVE" % winner_color.to_upper()
		_:
			why = reason.to_upper().replace("_", " ")
	return why

func _on_match_ended(data: Dictionary) -> void:
	_end_break_hold()
	phase = "ended"
	round_left = 0.0
	intermission_left = 0.0
	respawn_left = 0.0
	countdown_active = false
	_copy_colors(data.get("score", {}), score)
	_copy_colors(data.get("kills", {}), kills)
	var m := String(data.get("mode", mode))
	var wc := String(data.get("winner_color", ""))
	var fs: Dictionary = score if m == "ctf" else kills
	var final_line := "FINAL: RED %d - %d BLUE" % [int(fs["red"]), int(fs["blue"])]
	var why := "FIRST TO %d KILLS" % NetworkLobby.DM_KILLS_TO_WIN if String(data.get("reason", "")) == "kills" else "BEST OF %d ROUNDS" % NetworkLobby.CTF_BEST_OF
	var head := "MATCH OVER - %s WINS" % wc.to_upper() if not wc.is_empty() else "MATCH OVER - DRAW"
	exit_spectate()
	_show_banner("%s\n%s (%s)" % [head, final_line, why], "match_end", maxf(MATCH_END_BANNER_TIME, float(data.get("return_to_lobby_in_ms", 0)) / 1000.0), TEAM_COLORS.get(wc, GOLD))

func _on_player_eliminated(data: Dictionary) -> void:
	var sc := NetworkLobby.team_label(String(data.get("shooter_team", "ALPHA")))
	var vc := NetworkLobby.team_label(String(data.get("victim_team", "BRAVO")))
	var sname := String(data.get("shooter_name", "Enemy"))
	var vname := String(data.get("victim_name", "Player"))
	kill_feed.push_front({"text": "%s  >>  %s" % [sname.to_upper(), vname.to_upper()], "shooter_color": sc, "victim_color": vc, "age": 0.0})
	while kill_feed.size() > KILL_FEED_MAX:
		kill_feed.pop_back()
	if int(data.get("victim", 0)) == my_peer_id():
		if is_one_life_round_live():
			enter_spectate() # idempotent; the PlayerController already locked itself via _handle_local_elimination
		elif mode in ["deathmatch", "bots_test"]:
			respawn_left = float(respawn_ms_for(data)) / 1000.0
	elif spectating and int(data.get("victim", 0)) == spectate_target_pid:
		cycle_spectate(1)

func _on_flag_state_changed(data: Dictionary) -> void:
	var c := String(data.get("flag", ""))
	if not flags.has(c):
		c = NetworkLobby.team_label(String(data.get("flag_team", "ALPHA")))
	var f: Dictionary = flags[c]
	var action := String(data.get("action", ""))
	f["state"] = String(data.get("state", f["state"]))
	f["carrier"] = int(data.get("carrier", 0)) if f["state"] == "carried" else 0
	f["pos"] = _to_vec3(data.get("pos", f["pos"]))
	if f["state"] == "home":
		f["pos"] = _base_pos(String(f["team"]))
	_refresh_flags()
	var me := my_peer_id()
	var mine := c == my_color()
	var who := String(data.get("carrier_name", "")) if action == "picked_up" else String(data.get("by_name", ""))
	match action:
		"picked_up":
			if int(f["carrier"]) == me:
				_show_banner("YOU HAVE THE %s FLAG - RUN IT HOME!" % c.to_upper(), "info", 2.4, TEAM_COLORS[c])
			elif mine:
				_show_banner("%s HAS YOUR FLAG!" % who.to_upper(), "info", 2.4, TEAM_COLORS[enemy_color()])
			else:
				_show_banner("%s PULLED THE %s FLAG!" % [who.to_upper(), c.to_upper()], "info", 2.0, TEAM_COLORS[my_color()])
		"dropped", "carrier_eliminated", "carrier_left":
			_show_banner("%s FLAG DROPPED!" % c.to_upper(), "info", 2.0, TEAM_COLORS[c])
		"returned", "auto_returned":
			_show_banner("%s FLAG RETURNED TO BASE" % c.to_upper(), "info", 2.0, TEAM_COLORS[c])
		"captured":
			pass # round_ended / round_results carry who captured it

func _on_teams_rebalanced(data: Dictionary) -> void:
	for mv in data.get("moves", []):
		if typeof(mv) == TYPE_DICTIONARY and int(mv.get("peer", 0)) == my_peer_id():
			last_team_shown = ""
	_check_team_banner(true)

func _on_mode_changed(m: String) -> void:
	if phase not in ["live", "break"]:
		_set_mode(m)
	_refresh_all()

func _on_local_player_eliminated_signal(_killer: String) -> void:
	if player != null and bool(player.get("spectating")):
		enter_spectate()

## =========================================== countdown / banners ===========================================

## Generic countdown banner. Round intermission (round_ended.next_round_in_ms) and Tim's upcoming pre-match
## match_countdown both use this; cancel_countdown() hides it.
func start_countdown(seconds: float, title: String, source: String) -> void:
	countdown_active = seconds > 0.0
	countdown_left = maxf(0.0, seconds)
	countdown_title = title
	countdown_source = source
	if source == "match" and countdown_active and banner_kind in ["go", "info", "team"]:
		banner_left = 0.0 # a fresh pre-match countdown replaces stale toasts / GO
	if source == "match" and not countdown_active:
		_show_banner("%s - GO!" % title, "go", GO_BANNER_TIME, Color(0.32, 1.0, 0.5))
	_refresh_banner()

func cancel_countdown(source: String = "", toast: bool = true) -> void:
	if source.is_empty() or source == countdown_source:
		countdown_active = false
		countdown_left = 0.0
		if banner_kind in ["countdown", "go", "info", "team"]:
			banner_left = 0.0
		if toast:
			_show_banner("COUNTDOWN CANCELLED", "info", 1.5, Color(1.0, 0.55, 0.3))

## "ROUND 2 - 3...", "ROUND 2 - 3...2...", "ROUND 2 - 3...2...1..." (then round_started shows "ROUND 2 - GO!").
func countdown_text() -> String:
	var secs := int(ceil(countdown_left))
	var parts := ""
	var top := maxi(COUNTDOWN_SECONDS, secs) if countdown_source == "match" else COUNTDOWN_SECONDS
	for n in range(top, maxi(secs, 1) - 1, -1):
		parts += "%d..." % n
	return "%s - %s" % [countdown_title, parts]

func _show_banner(text: String, kind: String, seconds: float, color: Color) -> void:
	# never let an info toast hide the match-end result
	if banner_kind == "match_end" and banner_left > 0.0 and kind == "info":
		return
	banner_text = text
	banner_kind = kind
	banner_left = seconds
	banner_color = color
	_refresh_banner()

func current_banner_text() -> String:
	if banner_left > 0.0 and (banner_kind in ["match_end", "round_end", "go"] or not countdown_active):
		return banner_text
	if countdown_active and countdown_left <= float(COUNTDOWN_SECONDS) + 0.001:
		return countdown_text()
	if countdown_active and countdown_source == "match":
		return countdown_text()
	if banner_left > 0.0:
		return banner_text
	return ""

## Server respawn delay: player_eliminated.respawn_in_ms, else match.respawn_ms, else the lobby constants.
func respawn_ms_for(data: Dictionary) -> int:
	if data.has("respawn_in_ms"):
		return maxi(0, int(data["respawn_in_ms"]))
	if match_respawn_ms >= 0:
		return match_respawn_ms
	return NetworkLobby.DM_RESPAWN_MS if mode == "deathmatch" else NetworkLobby.PRACTICE_RESPAWN_MS

## "2:31" while a CTF round is live with time left; "" otherwise (the label hides).
func round_timer_text() -> String:
	if mode != "ctf" or phase != "live" or round_left <= 0.0:
		return ""
	var secs := int(ceil(round_left))
	return "%d:%02d" % [secs / 60, secs % 60]

## Live per-player rows (room_roster, which carries live captures; players as fallback).
func live_rows() -> Array:
	var out: Array = []
	var roster: Variant = NetworkLobby.room_state.get("room_roster", [])
	if typeof(roster) == TYPE_ARRAY and not (roster as Array).is_empty():
		for r in roster:
			if typeof(r) == TYPE_DICTIONARY:
				out.append({"peer": int(r.get("peer", 0)), "name": String(r.get("name", "")), "team": String(r.get("team", "ALPHA")),
					"color": NetworkLobby.team_label(String(r.get("team", "ALPHA"))), "kills": int(r.get("kills", 0)),
					"deaths": int(r.get("deaths", 0)), "captures": int(r.get("captures", 0))})
	else:
		for pid in NetworkLobby.players.keys():
			var info: Dictionary = NetworkLobby.players[pid]
			out.append({"peer": int(pid), "name": String(info.get("name", "")), "team": String(info.get("team", "ALPHA")),
				"color": NetworkLobby.team_label(String(info.get("team", "ALPHA"))), "kills": int(info.get("kills", 0)),
				"deaths": int(info.get("deaths", 0)), "captures": int(info.get("captures", 0))})
	return out

func team_captures() -> Dictionary:
	var out := {"red": 0, "blue": 0}
	for r in live_rows():
		out[String(r["color"])] = int(out.get(String(r["color"]), 0)) + int(r["captures"])
	return out

func stats_text() -> String:
	var me := my_peer_id()
	var mine: Dictionary = {}
	for r in live_rows():
		if int(r["peer"]) == me:
			mine = r
	var t := ""
	if not mine.is_empty():
		t = "YOU  K %d  D %d" % [int(mine["kills"]), int(mine["deaths"])]
		if mode == "ctf":
			t += "  CAPS %d" % int(mine["captures"])
	if mode == "ctf":
		var tc := team_captures()
		t += ("   |   " if not t.is_empty() else "") + "CAPTURES  RED %d - %d BLUE" % [int(tc["red"]), int(tc["blue"])]
	return t

func respawn_text() -> String:
	if respawn_left <= 0.0:
		return ""
	return "RESPAWNING IN %.1fs" % respawn_left

func _check_team_banner(force: bool = false) -> void:
	if not NetworkLobby.is_online_client() and local_peer_override == 0:
		return
	var c := my_color()
	if c != last_team_shown or force:
		var first := last_team_shown.is_empty()
		last_team_shown = c
		_show_banner("%s: YOU ARE ON TEAM %s (%s)" % ["AUTO-ASSIGNED" if first else "TEAMS BALANCED", c.to_upper(), NetworkLobby.local_team], "team", TEAM_BANNER_TIME, TEAM_COLORS[c])

## =========================================== spectate ===========================================

func spectate_candidates() -> Array:
	var out: Array = []
	var me := my_peer_id()
	var ids := NetworkLobby.players.keys()
	ids.sort()
	for pid in ids:
		if int(pid) == me:
			continue
		var info: Dictionary = NetworkLobby.players[pid]
		if String(info.get("team", "")) != NetworkLobby.local_team or not bool(info.get("alive", true)):
			continue
		var node: Variant = NetworkLobby.remote_player_nodes.get(pid, null)
		if node is Node3D and is_instance_valid(node):
			out.append(int(pid))
	return out

func enter_spectate() -> void:
	if player != null and player.has_method("set_spectating"):
		player.call("set_spectating", true)
	if spectating:
		return
	spectating = true
	if spectate_camera == null:
		spectate_camera = Camera3D.new()
		spectate_camera.name = "SpectateCamera3D"
		spectate_camera.fov = 70.0
		var host: Node = builder if builder != null else self
		host.add_child(spectate_camera)
	var cands := spectate_candidates()
	spectate_target_pid = int(cands[0]) if not cands.is_empty() else 0
	spectate_camera.current = true
	_update_spectate_camera(1.0)
	_refresh_spectate_label()

func exit_spectate() -> void:
	if player != null and player.has_method("set_spectating"):
		player.call("set_spectating", false)
	if not spectating:
		return
	spectating = false
	spectate_target_pid = 0
	if spectate_camera != null:
		spectate_camera.current = false
	if player != null:
		var cam: Variant = player.get("camera")
		if cam is Camera3D:
			(cam as Camera3D).current = true
	_refresh_spectate_label()

var spectate_cycles: int = 0 # v0.6.2: counts cycle_spectate calls (tests: the CLICK TO RESUME click must not cycle)
func cycle_spectate(direction: int) -> void:
	if not spectating:
		return
	spectate_cycles += 1
	var cands := spectate_candidates()
	if cands.is_empty():
		spectate_target_pid = 0
	else:
		var idx := cands.find(spectate_target_pid)
		if idx < 0:
			idx = 0 if direction > 0 else cands.size() - 1
			# the previous target died/left: the "next" one is whoever now sits at its slot
			spectate_target_pid = int(cands[idx])
		else:
			spectate_target_pid = int(cands[posmod(idx + direction, cands.size())])
	_update_spectate_camera(1.0)
	_refresh_spectate_label()

func spectate_target_name() -> String:
	return _player_name(spectate_target_pid) if spectate_target_pid != 0 else ""

## Late CTF joiner (server alive=false) -> spectate; spectating while the server says we're alive in a live round -> leave.
func _sync_spectate_with_roster() -> void:
	var me := my_peer_id()
	if not NetworkLobby.players.has(me):
		return
	var alive := bool(NetworkLobby.players[me].get("alive", true))
	if is_one_life_round_live() and not alive and not spectating:
		enter_spectate()
	elif spectating and alive and phase == "live":
		exit_spectate()
	elif spectating and not spectate_candidates().has(spectate_target_pid):
		cycle_spectate(1)

func _unhandled_input(event: InputEvent) -> void:
	if not spectating:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			cycle_spectate(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cycle_spectate(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_RIGHT, KEY_D, KEY_E]:
			cycle_spectate(1)
		elif event.physical_keycode in [KEY_LEFT, KEY_A, KEY_Q]:
			cycle_spectate(-1)

func _update_spectate_camera(blend: float) -> void:
	if spectate_camera == null or not spectating:
		return
	var node: Variant = NetworkLobby.remote_player_nodes.get(spectate_target_pid, null)
	var look_at_pos: Vector3
	var want: Vector3
	if node is Node3D and is_instance_valid(node):
		var t := node as Node3D
		var back := t.global_transform.basis.z
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3(0, 0, 1)
		look_at_pos = t.global_position + Vector3(0, 1.45, 0)
		want = t.global_position + back * 3.8 + Vector3(0, 2.3, 0)
	else:
		# nobody left to follow: high overview of the field
		var side := 1.0 if NetworkLobby.local_team == "ALPHA" else -1.0
		look_at_pos = Vector3(0, 0, 0)
		want = Vector3(0, 34.0, 52.0 * side)
	spectate_camera.global_position = spectate_camera.global_position.lerp(want, clampf(blend, 0.0, 1.0)) if blend < 1.0 else want
	if spectate_camera.global_position.distance_to(look_at_pos) > 0.05:
		spectate_camera.look_at(look_at_pos, Vector3.UP)

## =========================================== per-frame ===========================================

func _process(delta: float) -> void:
	phase_clock += delta
	if intermission_left > 0.0:
		intermission_left = maxf(0.0, intermission_left - delta)
	if countdown_active:
		countdown_left = maxf(0.0, countdown_left - delta)
		if countdown_left <= 0.0:
			countdown_active = false
			if countdown_source == "round":
				_show_banner("%s - GET READY" % countdown_title, "info", 1.0, GOLD) # GO! comes with round_started
	if banner_left > 0.0:
		banner_left = maxf(0.0, banner_left - delta)
	if summary_left > 0.0:
		summary_left = maxf(0.0, summary_left - delta)
		_refresh_summary_footer()
		if summary_left <= 0.0:
			hide_summary()
	if respawn_left > 0.0:
		respawn_left = maxf(0.0, respawn_left - delta)
	if round_left > 0.0 and phase == "live":
		round_left = maxf(0.0, round_left - delta)
	if break_active and break_left > 0.0:
		break_left = maxf(0.0, break_left - delta)
	if break_go_left > 0.0:
		break_go_left = maxf(0.0, break_go_left - delta)
	for e in kill_feed:
		e["age"] = float(e["age"]) + delta
	while not kill_feed.is_empty() and float(kill_feed[-1]["age"]) > KILL_FEED_TTL:
		kill_feed.pop_back()
	_update_spectate_camera(minf(1.0, delta * 6.0))
	_update_flag_followers(delta)
	_refresh_all()

## =========================================== HUD build / refresh ===========================================

func _build_hud() -> void:
	canvas = CanvasLayer.new()
	canvas.name = "MatchHUD"
	canvas.layer = 6
	add_child(canvas)

	panel = PanelContainer.new()
	panel.name = "MatchScorePanel"
	panel.position = Vector2(590, 96)
	panel.custom_minimum_size = Vector2(420, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.86)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.92, 0.76, 0.14, 0.95)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	mode_label = _mk_label("ModeLabel", 15, GOLD, true)
	vb.add_child(mode_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	red_score_label = _mk_label("RedScore", 26, TEAM_COLORS["red"], true)
	red_score_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(red_score_label)
	var vs := _mk_label("Vs", 22, Color(0.85, 0.85, 0.85), true)
	vs.text = ":"
	row.add_child(vs)
	blue_score_label = _mk_label("BlueScore", 26, TEAM_COLORS["blue"], true)
	blue_score_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(blue_score_label)
	info_label = _mk_label("RoundInfo", 15, Color(0.92, 0.92, 0.88), true)
	vb.add_child(info_label)
	round_timer_label = _mk_label("RoundTimer", 24, Color(1, 1, 1), true)
	vb.add_child(round_timer_label)
	alive_label = _mk_label("AliveCounts", 14, Color(0.75, 0.95, 0.75), true)
	vb.add_child(alive_label)
	stats_label = _mk_label("LiveStats", 14, Color(0.95, 0.9, 0.7), true)
	vb.add_child(stats_label)
	team_label = _mk_label("TeamBadge", 14, Color(1, 1, 1), true)
	vb.add_child(team_label)

	kill_feed_box = VBoxContainer.new()
	kill_feed_box.name = "KillFeed"
	kill_feed_box.position = Vector2(1180, 120)
	kill_feed_box.custom_minimum_size = Vector2(400, 0)
	kill_feed_box.add_theme_constant_override("separation", 2)
	canvas.add_child(kill_feed_box)

	banner_label = _mk_label("MatchBanner", 38, GOLD, true)
	banner_label.position = Vector2(0, 250)
	banner_label.size = Vector2(1600, 100)
	canvas.add_child(banner_label)
	break_label = _mk_label("BreakCountdown", 120, GOLD, true)
	break_label.position = Vector2(0, 400)
	break_label.size = Vector2(1600, 170)
	break_label.add_theme_constant_override("outline_size", 10)
	break_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	break_label.visible = false
	canvas.add_child(break_label)
	sub_banner_label = _mk_label("RespawnCountdown", 26, Color(1.0, 0.45, 0.45), true)
	sub_banner_label.position = Vector2(0, 360)
	sub_banner_label.size = Vector2(1600, 40)
	canvas.add_child(sub_banner_label)
	flag_alert_label = _mk_label("FlagAlert", 22, Color(1, 1, 1), true)
	flag_alert_label.position = Vector2(0, 212)
	flag_alert_label.size = Vector2(1600, 34)
	canvas.add_child(flag_alert_label)
	spectate_label = _mk_label("SpectateLabel", 22, Color(0.95, 0.95, 0.95), true)
	spectate_label.position = Vector2(0, 700)
	spectate_label.size = Vector2(1600, 60)
	canvas.add_child(spectate_label)
	for c in ["red", "blue"]:
		var mk := _mk_label("FlagMarker_%s" % c, 16, TEAM_COLORS[c], true)
		mk.size = Vector2(190, 24)
		mk.visible = false
		canvas.add_child(mk)
		flag_markers[c] = mk

func _mk_label(n: String, font_size: int, color: Color, centered: bool) -> Label:
	var l := Label.new()
	l.name = n
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func hud_visible() -> bool:
	return not mode.is_empty() and (NetworkLobby.is_online_client() or local_peer_override != 0)

func _refresh_all() -> void:
	if canvas == null:
		return
	panel.visible = hud_visible()
	kill_feed_box.visible = panel.visible
	var unit := "ROUNDS" if mode == "ctf" else ("KILLS" if mode == "deathmatch" else "KILLS")
	var tgt := target if target > 0 else (NetworkLobby.CTF_ROUNDS_TO_WIN if mode == "ctf" else (NetworkLobby.DM_KILLS_TO_WIN if mode == "deathmatch" else 0))
	var src: Dictionary = score if mode == "ctf" else kills
	mode_label.text = String(MODE_TITLES.get(mode, mode.to_upper())) + ("  -  BEST OF %d" % maxi(best_of, NetworkLobby.CTF_BEST_OF) if mode == "ctf" else ("  -  FIRST TO %d" % tgt if mode == "deathmatch" else "  -  NO WIN CONDITION"))
	if tgt > 0:
		red_score_label.text = "RED %d/%d" % [int(src["red"]), tgt]
		blue_score_label.text = "%d/%d BLUE" % [int(src["blue"]), tgt]
	else:
		red_score_label.text = "RED %d" % int(src["red"])
		blue_score_label.text = "%d BLUE" % int(src["blue"])
	red_score_label.tooltip_text = unit
	info_label.text = phase_text()
	var ac := alive_counts()
	alive_label.visible = mode == "ctf"
	alive_label.text = "ALIVE   RED %d  |  BLUE %d" % [int(ac["red"]), int(ac["blue"])]
	var rt := round_timer_text()
	round_timer_label.text = rt
	round_timer_label.visible = not rt.is_empty()
	round_timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if round_left <= 30.0 else Color(1, 1, 1))
	stats_label.text = stats_text()
	stats_label.visible = not stats_label.text.is_empty()
	var mc := my_color()
	team_label.text = "YOU: TEAM %s (%s)" % [mc.to_upper(), NetworkLobby.local_team]
	team_label.add_theme_color_override("font_color", TEAM_COLORS[mc])
	_refresh_kill_feed()
	_refresh_banner()
	if break_label != null:
		var bt := break_text()
		break_label.text = bt
		break_label.visible = not bt.is_empty()
		break_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.5) if bt == "GO!" else GOLD)
	_refresh_flag_hud()
	_refresh_spectate_label()

func phase_text() -> String:
	var clock := "%02d:%02d" % [int(phase_clock) / 60, int(phase_clock) % 60]
	match phase:
		"live":
			if mode == "ctf":
				var rtt := round_timer_text()
				if not rtt.is_empty():
					return "ROUND %d / %d  -  %s LEFT" % [round_num, maxi(best_of, 1), rtt]
				return "ROUND %d / %d  -  LIVE %s" % [round_num, maxi(best_of, 1), clock]
			return "LIVE %s" % clock
		"break":
			return "ROUND %d / %d  -  BREAK IN %d" % [round_num, maxi(best_of, 1), maxi(1, int(ceil(break_left)))] if mode == "ctf" else "BREAK IN %d" % maxi(1, int(ceil(break_left)))
		"intermission":
			return "ROUND %d OVER  -  NEXT ROUND IN %d" % [round_num, int(ceil(intermission_left))]
		"ended":
			return "MATCH OVER"
	if countdown_active and countdown_source == "match":
		return "MATCH STARTS IN %d" % int(ceil(countdown_left))
	return "WAITING FOR PLAYERS"

func _refresh_kill_feed() -> void:
	while kill_feed_box.get_child_count() > kill_feed.size():
		var ch := kill_feed_box.get_child(kill_feed_box.get_child_count() - 1)
		kill_feed_box.remove_child(ch)
		ch.queue_free()
	while kill_feed_box.get_child_count() < kill_feed.size():
		var l := _mk_label("KillFeedRow", 16, Color(1, 1, 1), false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(400, 0)
		kill_feed_box.add_child(l)
	for i in range(kill_feed.size()):
		var e: Dictionary = kill_feed[i]
		var l := kill_feed_box.get_child(i) as Label
		l.text = String(e["text"])
		l.add_theme_color_override("font_color", TEAM_COLORS.get(String(e["shooter_color"]), Color(1, 1, 1)))
		l.modulate.a = clampf((KILL_FEED_TTL - float(e["age"])) / 1.5, 0.15, 1.0)

func kill_feed_texts() -> Array:
	var out: Array = []
	for e in kill_feed:
		out.append(String(e["text"]))
	return out

func _refresh_banner() -> void:
	if banner_label == null:
		return
	var t := current_banner_text()
	banner_label.text = t
	banner_label.visible = not t.is_empty()
	if countdown_active and t == countdown_text():
		banner_label.add_theme_color_override("font_color", GOLD)
	else:
		banner_label.add_theme_color_override("font_color", banner_color)
	sub_banner_label.text = respawn_text()
	sub_banner_label.visible = not sub_banner_label.text.is_empty()

func flag_alert_text() -> String:
	if mode != "ctf":
		return ""
	var lines: Array[String] = []
	var me := my_peer_id()
	var ec := enemy_color()
	var mc := my_color()
	if flags[ec]["state"] == "carried" and int(flags[ec]["carrier"]) == me:
		lines.append("YOU HAVE THE FLAG - GET IT TO YOUR BASE")
	if flags[mc]["state"] == "carried":
		lines.append("ENEMY HAS YOUR FLAG (%s)" % _player_name(int(flags[mc]["carrier"])).to_upper())
	elif flags[mc]["state"] == "dropped":
		lines.append("YOUR FLAG IS DOWN - TOUCH IT TO RETURN")
	if flags[ec]["state"] == "carried" and int(flags[ec]["carrier"]) != me:
		lines.append("%s HAS THE ENEMY FLAG - ESCORT" % _player_name(int(flags[ec]["carrier"])).to_upper())
	return "   |   ".join(lines)

func _refresh_flag_hud() -> void:
	var t := flag_alert_text()
	flag_alert_label.text = t
	flag_alert_label.visible = not t.is_empty()
	if not t.is_empty():
		flag_alert_label.add_theme_color_override("font_color", TEAM_COLORS[enemy_color()] if t.begins_with("ENEMY") else GOLD)
	var cam := _active_camera()
	var vp_size := Vector2(1600, 900)
	for c in ["red", "blue"]:
		var mk: Label = flag_markers[c]
		var f: Dictionary = flags[c]
		var want_show: bool = mode == "ctf" and f["state"] != "home" and not (f["state"] == "carried" and int(f["carrier"]) == my_peer_id())
		mk.visible = want_show and cam != null
		if not mk.visible:
			continue
		var wp := flag_world_position(c) + Vector3(0, 2.3, 0)
		var dist := cam.global_position.distance_to(wp)
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		var on_screen := not behind and sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= vp_size.x and sp.y <= vp_size.y
		var lbl := ("%s FLAG" % c.to_upper()) if f["state"] == "dropped" else "%s [%s FLAG]" % [_player_name(int(f["carrier"])).to_upper(), c.to_upper()]
		if on_screen:
			mk.text = "v %s %dm" % [lbl, int(dist)]
			mk.position = sp - Vector2(mk.size.x * 0.5, 26)
		else:
			# off-screen: pin to the screen edge in the carrier's direction with an arrow glyph
			var dir := sp - vp_size * 0.5
			if behind:
				dir = -dir
			if dir.length() < 1.0:
				dir = Vector2(0, 1)
			var half := vp_size * 0.5 - Vector2(110, 40)
			var k := minf(absf(half.x / dir.x) if absf(dir.x) > 0.001 else 1e9, absf(half.y / dir.y) if absf(dir.y) > 0.001 else 1e9)
			var edge := vp_size * 0.5 + dir * k
			var arrow := "<" if absf(dir.x) >= absf(dir.y) and dir.x < 0 else (">" if absf(dir.x) >= absf(dir.y) else ("^" if dir.y < 0 else "v"))
			mk.text = "%s %s %dm" % [arrow, lbl, int(dist)]
			mk.position = edge - mk.size * 0.5
		mk.set_meta("on_screen", on_screen)

func _refresh_spectate_label() -> void:
	if spectate_label == null:
		return
	spectate_label.visible = spectating
	if not spectating:
		return
	var cands := spectate_candidates()
	if spectate_target_pid == 0:
		spectate_label.text = "ELIMINATED - NO TEAMMATES ALIVE - OVERVIEW\nBack in at the next round"
	else:
		spectate_label.text = "SPECTATING: %s  (%d/%d)\n[Q/E, LEFT/RIGHT or LMB/RMB] cycle teammates  -  back in at the next round" % [spectate_target_name().to_upper(), cands.find(spectate_target_pid) + 1, cands.size()]

func _active_camera() -> Camera3D:
	if spectating and spectate_camera != null:
		return spectate_camera
	if player != null:
		var cam: Variant = player.get("camera")
		if cam is Camera3D and (cam as Camera3D).is_inside_tree():
			return cam
	return get_viewport().get_camera_3d() if is_inside_tree() else null

## =========================================== 3D flags ===========================================

func _build_flags() -> void:
	flags_root = Node3D.new()
	flags_root.name = "CTFBaseFlags"
	var host: Node = builder if builder != null else self
	host.add_child(flags_root)
	for c in ["red", "blue"]:
		var team := "ALPHA" if c == "red" else "BRAVO"
		var col: Color = TEAM_COLORS[c]
		var stand := Node3D.new()
		stand.name = "FlagStand_%s" % c
		flags_root.add_child(stand)
		stand.position = _base_pos(team)
		var plate := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = NetworkLobby.FLAG_PICKUP_RADIUS
		cyl.bottom_radius = NetworkLobby.FLAG_PICKUP_RADIUS
		cyl.height = 0.04
		plate.mesh = cyl
		plate.position = Vector3(0, 0.02, 0)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(col.r, col.g, col.b, 0.35)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plate.material_override = pm
		stand.add_child(plate)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.18, 0.7)
		base.mesh = bm
		base.position = Vector3(0, 0.09, 0)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.2, 0.2, 0.22)
		base.material_override = bmat
		stand.add_child(base)
		flag_stands[c] = stand

		var flag := Node3D.new()
		flag.name = "CTFFlag_%s" % c
		flags_root.add_child(flag)
		var pole := MeshInstance3D.new()
		pole.name = "Pole"
		var pc := CylinderMesh.new()
		pc.top_radius = 0.03
		pc.bottom_radius = 0.035
		pc.height = 2.4
		pole.mesh = pc
		pole.position = Vector3(0, 1.2, 0)
		var polem := StandardMaterial3D.new()
		polem.albedo_color = Color(0.78, 0.78, 0.8)
		polem.metallic = 0.6
		pole.material_override = polem
		flag.add_child(pole)
		var cloth := MeshInstance3D.new()
		cloth.name = "Cloth"
		var cb := BoxMesh.new()
		cb.size = Vector3(0.9, 0.6, 0.03)
		cloth.mesh = cb
		cloth.position = Vector3(0.48, 2.05, 0)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = col
		cm.emission_enabled = true
		cm.emission = col
		cm.emission_energy_multiplier = 0.45
		cloth.material_override = cm
		flag.add_child(cloth)
		var tag := Label3D.new()
		tag.name = "FlagTag"
		tag.text = "%s FLAG" % c.to_upper()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.75, 0)
		tag.font_size = 48
		tag.modulate = col
		tag.outline_size = 10
		flag.add_child(tag)
		flag_nodes[c] = flag
	_refresh_flags()

## Where the flag is drawn right now (carrier body when carried, the dropped spot, or the base).
func flag_world_position(c: String) -> Vector3:
	var f: Dictionary = flags[c]
	if f["state"] == "carried":
		var n := carrier_node(int(f["carrier"]))
		if n != null:
			return n.global_position
	return f["pos"]

func carrier_node(pid: int) -> Node3D:
	if pid == 0:
		return null
	if pid == my_peer_id() and player is Node3D:
		return player as Node3D
	var n: Variant = NetworkLobby.remote_player_nodes.get(pid, null)
	if n is Node3D and is_instance_valid(n):
		return n
	return null

func _refresh_flags() -> void:
	if flags_root == null:
		return
	var active := base_flags_active()
	flags_root.visible = active
	var me := my_peer_id()
	var local_carry := false
	var local_carry_color := Color(1, 1, 1)
	for c in ["red", "blue"]:
		var f: Dictionary = flags[c]
		var flag: Node3D = flag_nodes[c]
		var tag := flag.get_node("FlagTag") as Label3D
		match String(f["state"]):
			"carried":
				flag.scale = Vector3(0.55, 0.55, 0.55)
				tag.text = "%s FLAG - %s" % [c.to_upper(), _player_name(int(f["carrier"])).to_upper()]
				if int(f["carrier"]) == me:
					local_carry = true
					local_carry_color = TEAM_COLORS[c]
			"dropped":
				flag.scale = Vector3.ONE
				flag.rotation = Vector3(0, 0, deg_to_rad(68.0))
				flag.position = _ground(f["pos"])
				tag.text = "%s FLAG - DROPPED" % c.to_upper()
			_:
				flag.scale = Vector3.ONE
				flag.rotation = Vector3.ZERO
				flag.position = _base_pos(String(f["team"])) + Vector3(0, 0.18, 0)
				tag.text = "%s FLAG" % c.to_upper()
	_update_flag_followers(0.0)
	if player != null and player.has_method("set_carrying_ctf_flag") and bool(player.get("carrying_ctf_flag")) != (local_carry and active):
		player.call("set_carrying_ctf_flag", local_carry and active, local_carry_color)

## Carried flags ride on the carrier's back (local player or remote avatar), re-placed every frame.
func _update_flag_followers(_delta: float) -> void:
	for c in flag_nodes.keys():
		var f: Dictionary = flags[c]
		if f["state"] != "carried":
			continue
		var flag: Node3D = flag_nodes[c]
		var n := carrier_node(int(f["carrier"]))
		if n == null:
			flag.position = f["pos"]
			flag.rotation = Vector3.ZERO
			continue
		var basis := n.global_transform.basis.orthonormalized()
		flag.global_position = n.global_position + basis * Vector3(0.0, 0.85, 0.32)
		flag.global_rotation = Vector3(0.0, n.global_rotation.y, deg_to_rad(-12.0))

func flag_attached_to(c: String) -> Node3D:
	var f: Dictionary = flags[c]
	return carrier_node(int(f["carrier"])) if f["state"] == "carried" else null

## =========================================== helpers ===========================================

func _set_mode(m: String) -> void:
	var nm := NetworkLobby.normalize_mode(m, mode)
	if nm.is_empty() or nm == mode:
		return
	mode = nm
	_refresh_flags()

func _player_name(pid: int) -> String:
	if pid == 0:
		return ""
	if NetworkLobby.players.has(pid):
		return String(NetworkLobby.players[pid].get("name", "Peer %d" % pid))
	return "Peer %d" % pid

static func _base_pos(team: String) -> Vector3:
	return NetworkLobby.team_base_position(team)

static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, 0.0) + 0.15, p.z)

static func _to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Dictionary:
		return Vector3(float(v.get("x", 0.0)), float(v.get("y", 0.0)), float(v.get("z", 0.0)))
	return Vector3.ZERO

static func _copy_colors(src: Variant, dst: Dictionary) -> void:
	if typeof(src) != TYPE_DICTIONARY:
		return
	for c in ["red", "blue"]:
		if (src as Dictionary).has(c):
			dst[c] = int(src[c])
	# tolerate ALPHA/BRAVO keyed dicts too
	if (src as Dictionary).has("ALPHA"):
		dst["red"] = int(src["ALPHA"])
	if (src as Dictionary).has("BRAVO"):
		dst["blue"] = int(src["BRAVO"])

static func _is_cancel_payload(data: Dictionary) -> bool:
	return bool(data.get("cancelled", data.get("canceled", false))) or String(data.get("state", data.get("action", ""))) in ["cancelled", "canceled", "cancel"]

static func _seconds_from(data: Dictionary, fallback: float) -> float:
	for k in ["in_ms", "ms_left"]:
		if data.has(k):
			return float(data[k]) / 1000.0
	for k in ["seconds", "seconds_left"]:
		if data.has(k):
			return float(data[k])
	return fallback


## =========================================== round / match scoreboard overlay ===========================================

## v0.5 server recaps. Everything shown comes from Tim's round_results / match_results data (incl. its "scoreboard"
## rows); nothing is derived client-side, and the client never navigates: the server's returned_to_lobby does that.
func on_round_results(data: Dictionary) -> void:
	has_server_match = true
	round_results_seen += 1
	var finished := int(data.get("round", round_num))
	var wc := String(data.get("winner_color", ""))
	var sc: Dictionary = data.get("score", {}) if typeof(data.get("score")) == TYPE_DICTIONARY else {}
	var hold := float(data.get("next_round_in_ms", NetworkLobby.ROUND_INTERMISSION_MS)) / 1000.0
	var title := "ROUND %d - %s" % [finished, ("%s WINS" % wc.to_upper()) if not wc.is_empty() else "DRAW"]
	var why := round_why(data)
	var sub := "%s\nROUND SCORE:  RED %d  -  %d BLUE    (FIRST TO %d  -  BEST OF %d)" % [why, int(sc.get("red", 0)), int(sc.get("blue", 0)),
		int(data.get("target", NetworkLobby.CTF_ROUNDS_TO_WIN)), int(data.get("best_of", NetworkLobby.CTF_BEST_OF))]
	if bool(data.get("match_point", false)):
		sub += "\nMATCH POINT - %s TAKES THE MATCH" % wc.to_upper()
	# next_round_in_ms is 0 when this round decided the match: match_results replaces the panel straight away
	show_summary("round", title, sub, "NEXT ROUND IN %ds" % int(ceil(hold)) if hold > 0.0 else "", TEAM_COLORS.get(wc, GOLD),
		maxf(ROUND_SUMMARY_MIN, hold), data.get("scoreboard", []), "ctf")

func on_match_results(data: Dictionary) -> void:
	has_server_match = true
	match_results_seen += 1
	var m := String(data.get("mode", mode))
	var wc := String(data.get("winner_color", ""))
	var fs: Dictionary = data.get("score" if m == "ctf" else "kills", {})
	var final_line := "FINAL: RED %d - %d BLUE" % [int(fs.get("red", 0)), int(fs.get("blue", 0))]
	var why := "FIRST TO %d KILLS" % NetworkLobby.DM_KILLS_TO_WIN if String(data.get("reason", "")) == "kills" else "BEST OF %d ROUNDS" % NetworkLobby.CTF_BEST_OF
	var hold := float(data.get("return_to_lobby_in_ms", 12000)) / 1000.0
	var title := "MATCH OVER - %s WINS!" % wc.to_upper() if not wc.is_empty() else "MATCH OVER - DRAW"
	var sub := ""
	if not wc.is_empty():
		sub = "CONGRATULATIONS TEAM %s!   %s\n" % [wc.to_upper(), "YOUR TEAM WON!" if wc == my_color() else "BETTER LUCK NEXT MATCH."]
		var names: Array = data.get("winner_names", [])
		if not names.is_empty():
			sub += "WINNERS: %s\n" % ", ".join(names.map(func(n): return String(n).to_upper()))
	sub += "%s   (%s)" % [final_line, why]
	var mvp := mvp_row(data.get("scoreboard", []))
	if not mvp.is_empty():
		sub += "\nMVP: %s  -  %d KILLS%s" % [String(mvp["name"]).to_upper(), int(mvp.get("kills", 0)), ("  /  %d CAPS" % int(mvp.get("captures", 0))) if m == "ctf" else ""]
	awaiting_return_to_lobby = true
	exit_spectate()
	show_summary("match", title, sub, "BACK TO THE WAITING ROOM IN %ds" % int(ceil(hold)), TEAM_COLORS.get(wc, GOLD), hold, data.get("scoreboard", []), m)

## Server sent everyone back to the waiting room (LobbyEntryFlow opens it); just drop the recap.
func on_returned_to_lobby(_room_id: String = "") -> void:
	awaiting_return_to_lobby = false
	hide_summary()
	exit_spectate()
	_clear_player_input_blocks("returned_to_lobby")

## v0.6.2: round_started / returned_to_lobby drop the respawn map, spectate and any stale lobby_open (via the arena so the
## death canvas goes too); falls back to the player when the scene has no builder.
func _clear_player_input_blocks(reason: String) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene := tree.current_scene
	if scene.has_method("clear_gameplay_input_blocks"):
		scene.call("clear_gameplay_input_blocks", reason)
		return
	var p: Variant = scene.get("player")
	if p is Node and is_instance_valid(p) and (p as Node).has_method("clear_input_blocks"):
		(p as Node).call("clear_input_blocks", reason)

func mvp_row(rows: Array) -> Dictionary:
	var best: Dictionary = {}
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var key: int = int(r.get("kills", 0)) * 2 + int(r.get("captures", 0)) * 3 - int(r.get("deaths", 0)) / 4
		if best.is_empty() or key > int(best.get("kills", 0)) * 2 + int(best.get("captures", 0)) * 3 - int(best.get("deaths", 0)) / 4:
			best = r
	return best

func show_summary(kind: String, title: String, sub: String, footer: String, color: Color, seconds: float, rows: Array, for_mode: String) -> void:
	if summary_panel == null:
		_build_summary()
	summary_kind = kind
	summary_left = seconds
	summary_rows = []
	if rows.is_empty():
		rows = live_rows() # older server without a scoreboard: live room_roster (incl. captures)
	for r in rows:
		if typeof(r) == TYPE_DICTIONARY:
			summary_rows.append((r as Dictionary).duplicate())
	summary_title.text = title
	summary_title.add_theme_color_override("font_color", color)
	summary_sub.text = sub
	summary_footer.text = footer
	for ch in summary_grid.get_children():
		summary_grid.remove_child(ch)
		ch.queue_free()
	var ctf := for_mode == "ctf"
	summary_grid.columns = 5 if ctf else 4
	var heads := ["PLAYER", "TEAM", "KILLS", "DEATHS"]
	if ctf:
		heads.append("CAPS")
	for h in heads:
		summary_grid.add_child(_cell(h, GOLD, h == "PLAYER"))
	for r in summary_rows:
		var color_id := String(r.get("color", NetworkLobby.team_label(String(r.get("team", "ALPHA")))))
		var col: Color = TEAM_COLORS.get(color_id, Color.WHITE)
		var me := int(r.get("peer", 0)) == my_peer_id()
		summary_grid.add_child(_cell(String(r.get("name", "PLAYER")).to_upper() + ("  (YOU)" if me else ""), Color(1, 1, 1) if me else col.lightened(0.25), true))
		summary_grid.add_child(_cell(color_id.to_upper(), col, false))
		summary_grid.add_child(_cell(str(int(r.get("kills", 0))), Color(0.92, 0.92, 0.92), false))
		summary_grid.add_child(_cell(str(int(r.get("deaths", 0))), Color(0.92, 0.92, 0.92), false))
		if ctf:
			summary_grid.add_child(_cell(str(int(r.get("captures", 0))), Color(0.92, 0.92, 0.92), false))
	summary_panel.visible = true

func hide_summary() -> void:
	summary_kind = ""
	summary_left = 0.0
	if summary_panel != null:
		summary_panel.visible = false

func summary_visible() -> bool:
	return summary_panel != null and summary_panel.visible

## Rows as text (tests / debugging): "NAME|COLOR|K|D|CAPS".
func summary_row_texts() -> Array:
	var out: Array = []
	for r in summary_rows:
		out.append("%s|%s|%d|%d|%d" % [r.get("name", ""), r.get("color", ""), int(r.get("kills", 0)), int(r.get("deaths", 0)), int(r.get("captures", 0))])
	return out

## The builder's legacy offline "first to 10 deaths" scoreboard defers to this screen in server-driven matches.
func owns_match_end() -> bool:
	return has_server_match or NetworkLobby.is_online_client() or local_peer_override != 0

func _refresh_summary_footer() -> void:
	if summary_footer == null or summary_kind.is_empty():
		return
	var secs := int(ceil(summary_left))
	if summary_kind == "round":
		summary_footer.text = "NEXT ROUND IN %ds" % maxi(int(ceil(intermission_left)), 0)
	elif awaiting_return_to_lobby:
		summary_footer.text = "BACK TO THE WAITING ROOM IN %ds" % maxi(secs, 0)

func _cell(text: String, color: Color, left: bool) -> Label:
	var l := _mk_label("Cell", 19, color, not left)
	l.text = text
	l.custom_minimum_size = Vector2(260 if left else 96, 0)
	return l

func _build_summary() -> void:
	summary_panel = PanelContainer.new()
	summary_panel.name = "MatchSummary"
	summary_panel.position = Vector2(440, 318)
	summary_panel.custom_minimum_size = Vector2(720, 0)
	summary_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.08, 0.92)
	st.border_color = GOLD
	st.set_border_width_all(3)
	st.set_content_margin_all(16)
	summary_panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	summary_panel.add_child(vb)
	summary_title = _mk_label("SummaryTitle", 32, GOLD, true)
	summary_sub = _mk_label("SummarySub", 18, Color(0.95, 0.95, 0.9), true)
	summary_grid = GridContainer.new()
	summary_grid.name = "SummaryGrid"
	summary_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_grid.add_theme_constant_override("h_separation", 18)
	summary_footer = _mk_label("SummaryFooter", 17, Color(0.75, 0.78, 0.8), true)
	vb.add_child(summary_title)
	vb.add_child(summary_sub)
	vb.add_child(summary_grid)
	vb.add_child(summary_footer)
	summary_panel.visible = false
	canvas.add_child(summary_panel)
