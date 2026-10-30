extends SceneTree
## v0.5 client match presentation (MatchHudClient) driven by synthetic server events shaped exactly like
## docs/NETWORK_EVENTS.md, fed through the real client path (NetworkLobby.sync_lobby_state / cl_room_event).
## Checks: HUD scores/rounds/alive/team, kill feed, round/match/respawn/countdown banners (+ the match_countdown hook),
## CTF one-life elimination -> NO local respawn + spectate enter/cycle/exit + input lock, one flag per base driven by
## flag_state_changed (home / carrier back / dropped / returned) and the legacy center flag hidden in CTF.
## Run: godot --headless --path . -s scripts/systems/test_match_hud_client.gd

var arena: Node
var player: CharacterBody3D
var mc: Node
var failures: Array[String] = []
var fakes: Array[Node] = []
var started := false

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
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
		await physics_frame

func _lobby() -> Node:
	return root.get_node("NetworkLobby")

func _gm() -> Node:
	return root.get_node("GameManager")

func _players(alive_me: bool = true, alive := {}) -> Dictionary:
	var base := {
		1: {"name": "Bluey", "team": "ALPHA"}, 2: {"name": "Mate", "team": "ALPHA"}, 3: {"name": "Pal", "team": "ALPHA"},
		10: {"name": "Rival", "team": "BRAVO"}, 11: {"name": "Foe", "team": "BRAVO"},
	}
	var out := {}
	for pid in base.keys():
		var info: Dictionary = base[pid].duplicate()
		info["bracket"] = "speedball"
		info["ready"] = true
		info["room"] = "hudtest"
		info["kills"] = 0
		info["deaths"] = 0
		info["alive"] = alive_me if pid == 1 else bool(alive.get(pid, true))
		out[pid] = info
	return out

func _flags_home() -> Dictionary:
	var nl := _lobby()
	return {
		"red": {"team": "ALPHA", "state": "home", "carrier": 0, "pos": nl.team_base_position("ALPHA")},
		"blue": {"team": "BRAVO", "state": "home", "carrier": 0, "pos": nl.team_base_position("BRAVO")},
	}

func _sync(mode: String, phase: String, round_num: int, score: Dictionary, kills: Dictionary, pl: Dictionary) -> void:
	var nl := _lobby()
	nl.sync_lobby_state({
		"room": "hudtest", "name": "hudtest", "permanent": false, "map": nl.selected_map, "selected_map": nl.selected_map,
		"mode": mode, "fill_bots": false, "status": "in_match", "match_active": true, "max_per_team": 5,
		"match": {"phase": phase, "mode": mode, "round": round_num, "score": score, "kills": kills,
			"target": 3 if mode == "ctf" else 10, "best_of": 5 if mode == "ctf" else 1, "flags": _flags_home()},
		"players": pl,
	})

func _ev(name: String, data: Dictionary) -> void:
	data["room"] = "hudtest"
	_lobby().cl_room_event(name, data)

func _elim(victim: int, shooter: int) -> void:
	var pl: Dictionary = _lobby().players
	_ev("player_eliminated", {
		"victim": victim, "victim_name": pl[victim]["name"], "victim_team": pl[victim]["team"],
		"shooter": shooter, "shooter_name": pl[shooter]["name"], "shooter_team": pl[shooter]["team"],
		# like the server: running per-player totals after this elimination
		"victim_kills": int(pl[victim].get("kills", 0)), "victim_deaths": int(pl[victim].get("deaths", 0)) + 1,
		"shooter_kills": int(pl[shooter].get("kills", 0)) + 1, "shooter_deaths": int(pl[shooter].get("deaths", 0)), "reason": "paint", "scored": true,
	})

func _flag_ev(flag: String, state: String, action: String, carrier: int, pos: Vector3, by: int = 0) -> void:
	var pl: Dictionary = _lobby().players
	_ev("flag_state_changed", {
		"flag_team": "ALPHA" if flag == "red" else "BRAVO", "flag": flag, "state": state, "action": action,
		"carrier": carrier, "carrier_name": String(pl.get(carrier, {}).get("name", "")),
		"by": by, "by_name": String(pl.get(by, {}).get("name", "")), "pos": pos,
	})

func _banner() -> String:
	return String(mc.call("current_banner_text"))

func _lbl(n: String) -> String:
	var l := mc.find_child(n, true, false) as Label
	return l.text if l != null else "<missing %s>" % n

func _run() -> void:
	await _frames(3)
	var nl := _lobby()
	player = arena.get("player")
	mc = arena.get("match_client")
	_check(player != null and mc != null, "arena built the player and the MatchHudClient")
	if player == null or mc == null:
		_finish()
		return
	if arena.has_method("_set_lobby_overlay_visible"):
		arena.call("_set_lobby_overlay_visible", false)
	player.call("set_lobby_open_state", false)
	mc.set("local_peer_override", 1)
	nl.local_team = "ALPHA"
	# fake remote avatars (what NetworkLobby spawns as RemotePlayer_<pid>)
	var spots := {2: Vector3(-6, 0, 20), 3: Vector3(8, 0, 12), 10: Vector3(0, 0, -20), 11: Vector3(10, 0, -30)}
	for pid in spots.keys():
		var n := Node3D.new()
		n.name = "FakeRemote_%d" % pid
		arena.add_child(n)
		n.global_position = spots[pid]
		nl.remote_player_nodes[pid] = n
		fakes.append(n)

	print("[1] DEATHMATCH HUD / kill feed / respawn countdown / match end")
	_sync("deathmatch", "live", 1, {"red": 0, "blue": 0}, {"red": 3, "blue": 5}, _players())
	_check(mc.call("hud_visible"), "match HUD visible once the server match state arrives")
	_check(_lbl("ModeLabel").contains("DEATHMATCH") and _lbl("ModeLabel").contains("FIRST TO 10"), "mode label: %s" % _lbl("ModeLabel"))
	_check(_lbl("RedScore") == "RED 3/10" and _lbl("BlueScore") == "5/10 BLUE", "DM team kills toward 10: %s : %s" % [_lbl("RedScore"), _lbl("BlueScore")])
	_check(_lbl("TeamBadge").contains("TEAM RED (ALPHA)"), "team badge: %s" % _lbl("TeamBadge"))
	_check(_banner().contains("AUTO-ASSIGNED: YOU ARE ON TEAM RED"), "join banner shows the auto-assigned team: %s" % _banner())
	_ev("round_started", {"round": 1, "mode": "deathmatch", "score": {"red": 0, "blue": 0}, "kills": {"red": 3, "blue": 5}, "target": 10, "reset_positions": true})
	_check(_banner() == "TEAM DEATHMATCH - FIRST TO 10 - GO!", "DM GO banner: %s" % _banner())
	_elim(10, 1)
	var feed: Array = mc.call("kill_feed_texts")
	_check(feed.size() == 1 and String(feed[0]) == "BLUEY  >>  RIVAL", "kill feed row: %s" % [feed])
	_elim(1, 11)
	await _frames(1)
	_check(not bool(player.get("spectating")), "DM death does not spectate")
	_check(String(mc.call("respawn_text")).begins_with("RESPAWNING IN"), "DM respawn countdown shown: %s" % mc.call("respawn_text"))
	_check(_lbl("RespawnCountdown").begins_with("RESPAWNING IN") and (mc.find_child("RespawnCountdown", true, false) as Label).visible, "respawn countdown label visible")
	mc.set("respawn_left", 0.01)
	await _frames(3)
	_check(String(mc.call("respawn_text")).is_empty(), "DM respawn countdown clears")
	feed = mc.call("kill_feed_texts")
	_check(feed.size() == 2 and String(feed[0]) == "FOE  >>  BLUEY", "newest kill on top: %s" % [feed])
	for i in range(6):
		_elim(11, 2)
	_check((mc.call("kill_feed_texts") as Array).size() == 5, "kill feed capped at 5")
	_sync("deathmatch", "live", 1, {"red": 0, "blue": 0}, {"red": 9, "blue": 6}, _players())
	_check(_lbl("RedScore") == "RED 9/10", "snapshot updates DM score: %s" % _lbl("RedScore"))
	_ev("match_ended", {"winner": "ALPHA", "winner_color": "red", "reason": "kills", "mode": "deathmatch", "score": {"red": 0, "blue": 0}, "kills": {"red": 10, "blue": 6}, "rounds": 1})
	_check(_banner().contains("MATCH OVER - RED WINS") and _banner().contains("FINAL: RED 10 - 6 BLUE") and _banner().contains("FIRST TO 10 KILLS"), "DM match-end banner: %s" % _banner().replace("\n", " / "))
	_check(_lbl("RoundInfo") == "MATCH OVER", "phase shows MATCH OVER")

	print("[2] CTF round start / scores / alive / flags at both bases / legacy center flag hidden")
	_sync("ctf", "waiting", 0, {"red": 0, "blue": 0}, {"red": 0, "blue": 0}, _players())
	_ev("round_started", {"round": 1, "mode": "ctf", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 3, "reset_positions": true})
	await _frames(2)
	_check(not bool(_gm().get("match_ended")), "round_started clears match_ended")
	_check(_banner() == "ROUND 1 - GO!", "CTF GO banner: %s" % _banner())
	_check(_lbl("RedScore") == "RED 0/3" and _lbl("BlueScore") == "0/3 BLUE", "CTF rounds toward 3: %s : %s" % [_lbl("RedScore"), _lbl("BlueScore")])
	_check(_lbl("ModeLabel").contains("CAPTURE THE FLAG") and _lbl("ModeLabel").contains("BEST OF 5"), "CTF mode label: %s" % _lbl("ModeLabel"))
	_check(_lbl("RoundInfo").begins_with("ROUND 1 / 5  -  LIVE"), "round + phase clock: %s" % _lbl("RoundInfo"))
	_check(_lbl("AliveCounts") == "ALIVE   RED 3  |  BLUE 2", "alive counts: %s" % _lbl("AliveCounts"))
	var cfn: Node3D = arena.get("center_flag_node")
	_check(cfn != null and not cfn.visible and bool(arena.get("legacy_center_flag_hidden")), "legacy single Center-50 flag hidden + inert in CTF")
	var flags_root := arena.find_child("CTFBaseFlags", true, false) as Node3D
	_check(flags_root != null and flags_root.visible, "CTF base flags shown")
	var fred := arena.find_child("CTFFlag_red", true, false) as Node3D
	var fblue := arena.find_child("CTFFlag_blue", true, false) as Node3D
	_check(fred != null and fred.global_position.distance_to(nl.team_base_position("ALPHA")) < 0.3, "red flag at the red (ALPHA) base z=+45.5")
	_check(fblue != null and fblue.global_position.distance_to(nl.team_base_position("BRAVO")) < 0.3, "blue flag at the blue (BRAVO) base z=-45.5")
	player.global_position = Vector3(3, 0.1, -10)
	_check(cfn != null and not cfn.visible, "legacy flag stays hidden")
	var flags_before_legacy := int(_gm().get("alpha_flag_hangs"))
	player.global_position = Vector3(0, 0.1, 1.35) # standing on the old center flag must not pick anything up
	await _frames(3)
	_check(not bool(player.get("carrying_center_flag")) and int(_gm().get("alpha_flag_hangs")) == flags_before_legacy, "no legacy local center-flag pickup in CTF")

	print("[3] flag_state_changed: carrier back (local + remote), alerts, dropped, returned")
	player.global_position = Vector3(2, 0.1, -40)
	_flag_ev("blue", "carried", "picked_up", 1, Vector3(2, 0, -40))
	await _frames(1)
	_check(mc.call("flag_attached_to", "blue") == player, "blue flag attached to the local carrier")
	var back_expected: Vector3 = player.global_position + player.global_transform.basis.orthonormalized() * Vector3(0, 0.85, 0.32)
	_check(fblue.global_position.distance_to(back_expected) < 0.05, "flag sits on the local carrier's back")
	_check(bool(player.get("carrying_ctf_flag")), "first-person carried-flag viewmodel on")
	_check(_lbl("FlagAlert").contains("YOU HAVE THE FLAG"), "alert: %s" % _lbl("FlagAlert"))
	var remote10: Node3D = nl.remote_player_nodes[10]
	_flag_ev("red", "carried", "picked_up", 10, remote10.global_position)
	await _frames(1)
	_check(mc.call("flag_attached_to", "red") == remote10, "red flag attached to remote carrier Rival")
	_check(fred.global_position.distance_to(remote10.global_position + Vector3(0, 0.85, 0.32)) < 0.05, "flag on the remote avatar's back")
	remote10.global_position = Vector3(-15, 0, 30)
	remote10.rotation.y = PI
	await _frames(2)
	_check(fred.global_position.distance_to(remote10.global_position + remote10.global_transform.basis.orthonormalized() * Vector3(0, 0.85, 0.32)) < 0.05, "carried flag follows the moving/turning carrier")
	_check(_lbl("FlagAlert").contains("ENEMY HAS YOUR FLAG (RIVAL)"), "alert: %s" % _lbl("FlagAlert"))
	var mk := mc.find_child("FlagMarker_red", true, false) as Label
	_check(mk != null and mk.visible and mk.text.contains("RIVAL [RED FLAG]") and mk.text.contains("m"), "carrier direction marker: %s" % (mk.text if mk else "?"))
	player.rotation.y = 0.0
	player.set("yaw", 0.0)
	player.global_position = Vector3(0, 0.1, 0) # looking -Z, Rival is behind (+Z)
	await _frames(2)
	_check(mk.visible and not bool(mk.get_meta("on_screen", true)) and mk.text.substr(0, 1) in ["<", ">", "^", "v"], "off-screen edge indicator: %s" % mk.text)
	_check(not (mc.find_child("FlagMarker_blue", true, false) as Label).visible, "no marker for the flag I carry")
	_flag_ev("red", "dropped", "carrier_eliminated", 0, Vector3(5, 0, 10), 10)
	await _frames(1)
	_check(fred.global_position.distance_to(Vector3(5, 0.15, 10)) < 0.05 and absf(fred.rotation.z) > 0.5, "dropped flag lies on the ground at pos")
	_check(_lbl("FlagAlert").contains("YOUR FLAG IS DOWN"), "dropped alert: %s" % _lbl("FlagAlert"))
	_flag_ev("red", "home", "returned", 0, nl.team_base_position("ALPHA"), 2)
	await _frames(1)
	_check(fred.global_position.distance_to(nl.team_base_position("ALPHA") + Vector3(0, 0.18, 0)) < 0.05 and fred.rotation.z == 0.0, "returned flag back on the red stand")

	print("[4] CTF one-life elimination: no local respawn, spectate enter / cycle / input lock")
	var death_pos := Vector3(12, 0.1, -3)
	player.global_position = death_pos
	player.velocity = Vector3.ZERO
	await _frames(2)
	death_pos = player.global_position
	_elim(1, 10)
	_flag_ev("blue", "dropped", "carrier_eliminated", 0, death_pos, 1)
	await _frames(2)
	_check(bool(player.get("spectating")) and bool(mc.get("spectating")), "elimination event enters spectate")
	_check(player.global_position.distance_to(death_pos) < 0.3, "NO local respawn in one-life CTF (stayed at %s)" % player.global_position)
	_check(not bool(player.get("awaiting_respawn_choice")), "no respawn-zone map in CTF")
	_check(not bool(player.get("carrying_ctf_flag")), "carried-flag viewmodel cleared")
	_check(fblue.global_position.distance_to(Vector3(death_pos.x, 0.15, death_pos.z)) < 0.1, "flag dropped where I fell")
	var cam := mc.get("spectate_camera") as Camera3D
	_check(cam != null and cam.current, "spectate camera is current")
	_check(int(mc.get("spectate_target_pid")) == 2 and _lbl("SpectateLabel").contains("SPECTATING: MATE"), "watching first living teammate: %s" % _lbl("SpectateLabel").replace("\n", " / "))
	var mate: Node3D = nl.remote_player_nodes[2]
	_check(cam.global_position.distance_to(mate.global_position) < 6.0 and cam.global_position.y > mate.global_position.y + 1.0, "third-person framing behind/above the teammate")
	_check(_lbl("AliveCounts") == "ALIVE   RED 2  |  BLUE 2", "alive counts after my death: %s" % _lbl("AliveCounts"))
	# input lock: trigger pulls, mouse clicks and movement keys do nothing to the player
	var shots0 := int(player.get("_shot_counter"))
	var pos0 := player.global_position
	player.call("_handle_trigger_press", false)
	player.call("_handle_trigger_press", true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	player.call("_unhandled_input", click)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(12)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check(int(player.get("_shot_counter")) == shots0 and int(player.get("spectate_blocked_trigger_pulls")) >= 2, "no shots while spectating (blocked pulls=%d)" % int(player.get("spectate_blocked_trigger_pulls")))
	_check(player.global_position.distance_to(pos0) < 0.05, "no movement while spectating")
	# cycling: LMB / Right -> next, RMB / Left -> previous
	mc.call("_unhandled_input", click)
	_check(int(mc.get("spectate_target_pid")) == 3 and _lbl("SpectateLabel").contains("PAL"), "LMB cycles to Pal")
	var left := InputEventKey.new()
	left.physical_keycode = KEY_LEFT
	left.pressed = true
	mc.call("_unhandled_input", left)
	_check(int(mc.get("spectate_target_pid")) == 2, "Left arrow cycles back to Mate")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	mc.call("_unhandled_input", rmb)
	_check(int(mc.get("spectate_target_pid")) == 3, "RMB cycles (wraps) to Pal")
	_elim(3, 11)
	await _frames(1)
	_check(int(mc.get("spectate_target_pid")) == 2, "watched teammate eliminated -> auto-switch to Mate")
	_elim(2, 11)
	await _frames(1)
	_check(int(mc.get("spectate_target_pid")) == 0 and _lbl("SpectateLabel").contains("NO TEAMMATES ALIVE"), "no teammates left -> overview")

	print("[5] round end / countdown banner / round reset returns control")
	_ev("round_ended", {"round": 1, "winner": "BRAVO", "winner_color": "blue", "reason": "elimination", "by": 11, "score": {"red": 0, "blue": 1}, "next_round_in_ms": 4000})
	_check(_banner().begins_with("ROUND 1 - BLUE WINS: RED TEAM ELIMINATED"), "round-end banner: %s" % _banner())
	_check(_lbl("BlueScore") == "1/3 BLUE" and _lbl("RoundInfo").begins_with("ROUND 1 OVER  -  NEXT ROUND IN"), "intermission HUD: %s / %s" % [_lbl("BlueScore"), _lbl("RoundInfo")])
	_check(bool(player.get("spectating")), "still spectating during the intermission")
	mc.set("banner_left", 0.0)
	mc.set("countdown_left", 2.6)
	_check(_banner() == "ROUND 2 - 3...", "countdown 3: %s" % _banner())
	mc.set("countdown_left", 1.6)
	_check(_banner() == "ROUND 2 - 3...2...", "countdown 2: %s" % _banner())
	mc.set("countdown_left", 0.4)
	_check(_banner() == "ROUND 2 - 3...2...1...", "countdown 1: %s" % _banner())
	_ev("round_ended", {"round": 2, "winner": "ALPHA", "winner_color": "red", "reason": "capture", "by": 2, "score": {"red": 1, "blue": 1}, "next_round_in_ms": 4000})
	_check(_banner().begins_with("ROUND 2 - RED WINS: FLAG CAPTURED BY MATE"), "capture banner names the capper: %s" % _banner())
	_ev("round_ended", {"round": 3, "winner": "", "winner_color": "", "reason": "double_elimination", "by": 0, "score": {"red": 1, "blue": 1}, "next_round_in_ms": 4000})
	_check(_banner().contains("DOUBLE ELIMINATION"), "double elimination banner: %s" % _banner())
	_ev("round_started", {"round": 4, "mode": "ctf", "score": {"red": 1, "blue": 1}, "kills": {"red": 0, "blue": 0}, "target": 3, "reset_positions": true})
	await _frames(2)
	_check(not bool(player.get("spectating")) and not bool(mc.get("spectating")), "round_started exits spectate")
	_check(player.camera.current and not cam.current, "first-person camera restored")
	_check(player.global_position.distance_to(Vector3(0, 0.1, 45.5)) < 1.0, "server round reset put me on the red gate")
	_check(_banner() == "ROUND 4 - GO!" and not bool(mc.get("countdown_active")), "GO banner after the countdown")
	_check(fblue.global_position.distance_to(nl.team_base_position("BRAVO") + Vector3(0, 0.18, 0)) < 0.05, "flags reset to their bases")
	var shots1 := int(player.get("_shot_counter"))
	player.call("_handle_trigger_press", false)
	_check(int(player.get("_shot_counter")) > shots1 or bool(player.get("is_reloading_pod")) or int(player.get("hopper_paint")) <= 0, "firing works again after the reset")

	print("[6] late joiner (server alive=false in a live CTF round) spectates; pre-match countdown hook; CTF match end; rebalance")
	_sync("ctf", "live", 4, {"red": 1, "blue": 1}, {"red": 0, "blue": 0}, _players(false))
	await _frames(1)
	_check(bool(player.get("spectating")), "server alive=false -> spectate")
	# pre-match countdown, exactly as Tim's server sends it (NetworkLobby re-emits match_starting / match_countdown signals)
	_ev("match_starting", {"in_ms": 3000, "seconds": 3, "by": 2, "by_name": "Mate", "mode": "ctf", "map": nl.selected_map})
	_ev("match_countdown", {"seconds_left": 3, "ms_left": 3000})
	_check(bool(mc.get("countdown_active")) and _banner() == "MATCH STARTING - 3...", "match_starting/match_countdown banner: %s" % _banner())
	_ev("match_countdown", {"seconds_left": 2, "ms_left": 2000})
	_check(_banner() == "MATCH STARTING - 3...2...", "countdown re-synced to 2: %s" % _banner())
	_check(mc.events_seen.count("match_countdown") == 2, "room_event path saw both ticks")
	_ev("match_start_cancelled", {"by": 2, "by_name": "Mate"})
	_check(not bool(mc.get("countdown_active")) and not _banner().begins_with("MATCH STARTING"), "match_start_cancelled hides the countdown: %s" % _banner())
	_ev("match_starting", {"in_ms": 5000, "seconds": 5, "by": 2, "by_name": "Mate", "mode": "ctf", "map": nl.selected_map})
	_check(_banner() == "MATCH STARTING - 5...", "5 s countdown supported: %s" % _banner())
	mc.call("on_match_start_cancelled")
	_check(not bool(mc.get("countdown_active")), "signal-style cancel handler (connected when NetworkLobby has match_start_cancelled)")
	_sync("ctf", "waiting", 0, {"red": 0, "blue": 0}, {"red": 0, "blue": 0}, _players())
	_ev("match_starting", {"in_ms": 3000, "seconds": 3, "by": 2, "by_name": "Mate", "mode": "ctf", "map": nl.selected_map})
	nl.room_state["countdown_ms_left"] = 2500
	nl.lobby_state_changed.emit(nl.room_state)
	_check(bool(mc.get("countdown_active")), "snapshot with a running countdown keeps the banner")
	nl.room_state["countdown_ms_left"] = 0
	nl.lobby_state_changed.emit(nl.room_state)
	_check(not bool(mc.get("countdown_active")), "snapshot with countdown_ms_left=0 while waiting hides a dropped countdown")
	_ev("match_starting", {"in_ms": 3000, "seconds": 3, "by": 2, "by_name": "Mate", "mode": "ctf", "map": nl.selected_map})
	mc.call("_on_left_room", "hudtest")
	_check(not bool(mc.get("countdown_active")) and not _banner().begins_with("MATCH STARTING"), "leave_room hides the countdown")
	_ev("match_starting", {"in_ms": 3000, "seconds": 3, "by": 2, "by_name": "Mate", "mode": "ctf", "map": nl.selected_map})
	_ev("match_countdown", {"seconds_left": 1, "ms_left": 1000})
	_check(_banner() == "MATCH STARTING - 3...2...1...", "countdown 1: %s" % _banner())
	_ev("round_started", {"round": 5, "mode": "ctf", "score": {"red": 2, "blue": 1}, "kills": {"red": 0, "blue": 0}, "target": 3, "reset_positions": true})
	await _frames(1)
	_check(_banner() == "ROUND 5 - GO!" and not bool(mc.get("countdown_active")), "round_started after the countdown -> GO: %s" % _banner())
	_ev("match_ended", {"winner": "ALPHA", "winner_color": "red", "reason": "rounds", "mode": "ctf", "score": {"red": 3, "blue": 1}, "kills": {"red": 9, "blue": 7}, "rounds": 4})
	await _frames(1)
	_check(_banner().contains("MATCH OVER - RED WINS") and _banner().contains("FINAL: RED 3 - 1 BLUE") and _banner().contains("BEST OF 5"), "CTF match-end banner: %s" % _banner().replace("\n", " / "))
	_check(not bool(player.get("spectating")), "match end releases spectate")
	_flag_ev("red", "home", "returned", 0, nl.team_base_position("ALPHA"))
	_check(_banner().contains("MATCH OVER"), "info toasts don't overwrite the match result")
	_ev("teams_rebalanced", {"moves": [{"peer": 1, "name": "Bluey", "from": "ALPHA", "to": "BRAVO"}], "red": 2, "blue": 3})
	_check(nl.local_team == "BRAVO" and _lbl("TeamBadge").contains("TEAM BLUE (BRAVO)"), "rebalance -> team badge: %s" % _lbl("TeamBadge"))

	await _ctf_round_and_match_end_flow()
	await _dm_match_end_flow()
	await _timer_captures_respawn_flow()
	await _break_flow()

	_finish()

func _summary_title() -> String:
	return _lbl("SummaryTitle")

func _row(pid: int, name: String, team: String, k: int, d: int, caps: int) -> Dictionary:
	return {"peer": pid, "name": name, "team": team, "color": "red" if team == "ALPHA" else "blue", "kills": k, "deaths": d, "captures": caps}

func _ctf_round_and_match_end_flow() -> void:
	print("[7] CTF round_results -> winner + server scoreboard (K/D/captures) + round score for next_round_in_ms; match_results -> congrats + recap; returned_to_lobby")
	var nl := _lobby()
	var flow := root.get_node_or_null("LobbyEntryFlow")
	_check(nl.has_signal("round_results") and nl.has_signal("match_results") and nl.has_signal("returned_to_lobby"), "Tim's recap signals exist")
	_sync("ctf", "waiting", 0, {"red": 0, "blue": 0}, {"red": 0, "blue": 0}, _players())
	_check(nl.local_team == "ALPHA", "back on red for the flow test")
	_ev("round_started", {"round": 1, "mode": "ctf", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 3, "reset_positions": true})
	await _frames(1)
	_check(not bool(mc.call("summary_visible")), "no overview while the round is live")
	var sb1 := [_row(2, "Mate", "ALPHA", 3, 0, 1), _row(1, "Bluey", "ALPHA", 1, 1, 0), _row(3, "Pal", "ALPHA", 0, 0, 0), _row(10, "Rival", "BRAVO", 1, 2, 0), _row(11, "Foe", "BRAVO", 0, 2, 0)]
	var rr0 := int(mc.get("round_results_seen"))
	_ev("round_ended", {"round": 1, "winner": "ALPHA", "winner_color": "red", "reason": "capture", "by": 2, "by_name": "Mate", "score": {"red": 1, "blue": 0},
		"target": 3, "best_of": 5, "next_round_in_ms": 8000, "match_point": false, "scoreboard": sb1})
	_check(int(mc.get("round_results_seen")) == rr0 + 1, "driven by NetworkLobby.round_results")
	_check(bool(mc.call("summary_visible")) and String(mc.get("summary_kind")) == "round", "round-end overview shown")
	_check(_summary_title() == "ROUND 1 - RED WINS", "overview title: %s" % _summary_title())
	_check(_lbl("SummarySub").contains("FLAG CAPTURED BY MATE") and _lbl("SummarySub").contains("ROUND SCORE:  RED 1  -  0 BLUE") and _lbl("SummarySub").contains("FIRST TO 3  -  BEST OF 5"), "overview reason + round score: %s" % _lbl("SummarySub").replace("\n", " / "))
	_check(absf(float(mc.get("summary_left")) - 8.0) < 0.2, "shown for the 8 s intermission: %.2f" % float(mc.get("summary_left")))
	var rows: Array = mc.call("summary_row_texts")
	_check(rows.size() == 5 and rows[0] == "Mate|red|3|0|1" and rows[4] == "Foe|blue|0|2|0", "server scoreboard rows in server order: %s" % [rows])
	var grid := mc.find_child("SummaryGrid", true, false) as GridContainer
	_check(grid != null and grid.columns == 5 and grid.get_child_count() == 30, "CTF table: PLAYER/TEAM/KILLS/DEATHS/CAPS + 5 rows")
	_check(_lbl("SummaryFooter").begins_with("NEXT ROUND IN"), "footer counts to the next round")
	_check(_banner().begins_with("ROUND 1 - RED WINS: FLAG CAPTURED BY MATE"), "round-winner banner: %s" % _banner())
	_ev("round_started", {"round": 2, "mode": "ctf", "score": {"red": 1, "blue": 0}, "kills": {"red": 3, "blue": 1}, "target": 3, "reset_positions": true})
	await _frames(1)
	_check(not bool(mc.call("summary_visible")), "next round_started hides the overview and play resumes")
	_ev("round_ended", {"round": 2, "winner": "BRAVO", "winner_color": "blue", "reason": "elimination", "by": 11, "by_name": "Foe", "score": {"red": 1, "blue": 1},
		"target": 3, "best_of": 5, "next_round_in_ms": 8000, "match_point": false, "scoreboard": sb1})
	_check(_summary_title() == "ROUND 2 - BLUE WINS" and _lbl("SummarySub").contains("RED TEAM ELIMINATED") and _lbl("SummarySub").contains("RED 1  -  1 BLUE"), "elimination overview: %s / %s" % [_summary_title(), _lbl("SummarySub").replace("\n", " / ")])
	mc.set("summary_left", 0.01)
	await _frames(2)
	_check(not bool(mc.call("summary_visible")), "overview times out on its own")
	_check(not (flow != null and bool(flow.call("is_open"))), "a round end never leaves the arena")
	_ev("round_started", {"round": 3, "mode": "ctf", "score": {"red": 1, "blue": 1}, "kills": {"red": 3, "blue": 3}, "target": 3, "reset_positions": true})
	_ev("round_ended", {"round": 3, "winner": "ALPHA", "winner_color": "red", "reason": "capture", "by": 2, "by_name": "Mate", "score": {"red": 3, "blue": 1},
		"target": 3, "best_of": 5, "next_round_in_ms": 0, "match_point": true, "scoreboard": sb1})
	_check(_lbl("SummarySub").contains("MATCH POINT - RED TAKES THE MATCH") and not bool(mc.get("countdown_active")), "deciding round: match point line, no next-round countdown")
	var scoreboard: CanvasLayer = arena.get("scoreboard_canvas")
	var sb_before := scoreboard != null and scoreboard.visible
	var mr0 := int(mc.get("match_results_seen"))
	var sbf := [_row(2, "Mate", "ALPHA", 6, 1, 2), _row(1, "Bluey", "ALPHA", 4, 2, 1), _row(3, "Pal", "ALPHA", 1, 3, 0), _row(10, "Rival", "BRAVO", 4, 4, 0), _row(11, "Foe", "BRAVO", 2, 5, 1)]
	_ev("match_ended", {"winner": "ALPHA", "winner_color": "red", "winner_names": ["Mate", "Bluey", "Pal"], "reason": "rounds", "mode": "ctf", "score": {"red": 3, "blue": 1},
		"kills": {"red": 11, "blue": 6}, "rounds": 4, "scoreboard": sbf, "return_to_lobby_in_ms": 12000})
	await _frames(1)
	_check(int(mc.get("match_results_seen")) == mr0 + 1, "driven by NetworkLobby.match_results")
	_check(String(mc.get("summary_kind")) == "match" and _summary_title() == "MATCH OVER - RED WINS!", "CTF match-end screen: %s" % _summary_title())
	var sub := _lbl("SummarySub")
	_check(sub.contains("CONGRATULATIONS TEAM RED!") and sub.contains("YOUR TEAM WON!") and sub.contains("WINNERS: MATE, BLUEY, PAL") and sub.contains("FINAL: RED 3 - 1 BLUE") and sub.contains("BEST OF 5 ROUNDS"), "congrats + final: %s" % sub.replace("\n", " / "))
	_check(sub.contains("MVP: MATE  -  6 KILLS  /  2 CAPS"), "MVP from the server scoreboard: %s" % sub.replace("\n", " / "))
	_check((mc.call("summary_row_texts") as Array)[0] == "Mate|red|6|1|2", "match recap uses match_results.scoreboard")
	_check(absf(float(mc.get("summary_left")) - 12.0) < 0.2 and _lbl("SummaryFooter").contains("WAITING ROOM"), "recap held for return_to_lobby_in_ms: %s" % _lbl("SummaryFooter"))
	_check(scoreboard == null or scoreboard.visible == sb_before, "legacy offline scoreboard stays down online")
	_check(not _arena_status().contains("Rematch"), "no 'Press [T] for Rematch' text online: %s" % _arena_status())
	await _frames(3)
	_check(not (flow != null and bool(flow.call("is_open"))) and not bool(player.get("lobby_open")), "the client never navigates on its own")
	mc.set("summary_left", 0.01)
	await _frames(2)
	_check(not (flow != null and bool(flow.call("is_open"))), "recap timing out still does not navigate - only returned_to_lobby does")
	mc.call("show_summary", "match", "X", "Y", "", Color.WHITE, 30.0, sbf, "ctf")
	mc.set("awaiting_return_to_lobby", true)
	_ev("returned_to_lobby", {"room": "hudtest"})
	await _frames(2)
	_check(not bool(mc.call("summary_visible")) and not bool(mc.get("awaiting_return_to_lobby")), "returned_to_lobby drops the recap")
	if flow != null:
		var wr: Control = flow.get("waiting_room")
		_check(wr != null and wr.visible and bool(flow.call("is_open")), "LobbyEntryFlow (Tim/Ren) opened the waiting room")
		flow.call("close_browser")
	arena.call("_set_lobby_overlay_visible", false)

func _dm_match_end_flow() -> void:
	print("[8] DM: 10 kills -> match_results congrats + recap for 12 s (no navigation)")
	_sync("deathmatch", "waiting", 0, {"red": 0, "blue": 0}, {"red": 0, "blue": 0}, _players())
	_ev("match_starting", {"in_ms": 5000, "seconds": 5, "by": 1, "by_name": "Bluey", "mode": "deathmatch", "map": _lobby().selected_map})
	_ev("round_started", {"round": 1, "mode": "deathmatch", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 10, "reset_positions": true})
	await _frames(1)
	var sb := [_row(1, "Bluey", "ALPHA", 6, 1, 0), _row(3, "Pal", "ALPHA", 4, 2, 0), _row(2, "Mate", "ALPHA", 0, 2, 0), _row(10, "Rival", "BRAVO", 2, 6, 0), _row(11, "Foe", "BRAVO", 0, 4, 0)]
	_ev("match_ended", {"winner": "BRAVO", "winner_color": "blue", "winner_names": ["Rival", "Foe"], "reason": "kills", "mode": "deathmatch", "score": {"red": 0, "blue": 0},
		"kills": {"red": 9, "blue": 10}, "rounds": 1, "scoreboard": sb, "return_to_lobby_in_ms": 12000})
	await _frames(1)
	_check(String(mc.get("summary_kind")) == "match" and _summary_title() == "MATCH OVER - BLUE WINS!", "DM match-end screen: %s" % _summary_title())
	var sub := _lbl("SummarySub")
	_check(sub.contains("CONGRATULATIONS TEAM BLUE!") and sub.contains("BETTER LUCK NEXT MATCH") and sub.contains("FINAL: RED 9 - 10 BLUE") and sub.contains("FIRST TO 10 KILLS"), "DM congrats (loser view) + final: %s" % sub.replace("\n", " / "))
	_check(sub.contains("MVP: BLUEY  -  6 KILLS") and not sub.contains("CAPS"), "DM MVP line, no caps: %s" % sub.replace("\n", " / "))
	var grid := mc.find_child("SummaryGrid", true, false) as GridContainer
	_check(grid.columns == 4 and grid.get_child_count() == 24, "DM recap: PLAYER/TEAM/KILLS/DEATHS for 5 players")
	_check((mc.call("summary_row_texts") as Array)[0] == "Bluey|red|6|1|0", "recap rows from match_results.scoreboard")
	_lobby().players[1]["kills"] = 0 # the server's post-match reset must not change the recap
	_sync("deathmatch", "waiting", 0, {"red": 0, "blue": 0}, {"red": 0, "blue": 0}, _players())
	_check((mc.call("summary_row_texts") as Array)[0] == "Bluey|red|6|1|0" and bool(mc.call("summary_visible")), "recap stays frozen through the post-match sync")
	_ev("returned_to_lobby", {"room": "hudtest"})
	await _frames(2)
	_check(not bool(mc.call("summary_visible")), "returned_to_lobby ends the DM recap")
	var flow := root.get_node_or_null("LobbyEntryFlow")
	if flow != null:
		_check(bool(flow.call("is_open")), "waiting room open after DM")
		flow.call("close_browser")
	arena.call("_set_lobby_overlay_visible", false)

func _arena_status() -> String:
	var l: Variant = arena.get("status_label")
	return (l as Label).text if l is Label else ""

func _sync_x(mode: String, phase: String, round_num: int, score: Dictionary, extra_match: Dictionary, roster: Array) -> void:
	var nl := _lobby()
	var m := {"phase": phase, "mode": mode, "round": round_num, "score": score, "kills": {"red": 0, "blue": 0},
		"target": 3 if mode == "ctf" else 10, "best_of": 5 if mode == "ctf" else 1, "flags": _flags_home()}
	m.merge(extra_match, true)
	var pl := _players()
	for r in roster:
		pl[int(r["peer"])]["kills"] = int(r["kills"])
		pl[int(r["peer"])]["deaths"] = int(r["deaths"])
		pl[int(r["peer"])]["captures"] = int(r["captures"])
	nl.sync_lobby_state({
		"room": "hudtest", "name": "hudtest", "permanent": false, "map": nl.selected_map, "selected_map": nl.selected_map,
		"mode": mode, "fill_bots": false, "status": "in_match", "match_active": true, "max_per_team": 5,
		"match": m, "players": pl, "room_roster": roster,
	})

func _timer_captures_respawn_flow() -> void:
	print("[9] Tim 1a2b7d0: CTF round timer (round_ms_left / round_time_ms), time-out + draw reasons, live captures, respawn_in_ms")
	var nl := _lobby()
	_sync_x("ctf", "waiting", 0, {"red": 0, "blue": 0}, {"round_time_ms": 180000, "round_ms_left": 0, "respawn_ms": 1000}, [])
	_check(String(mc.call("round_timer_text")) == "" and not mc.find_child("RoundTimer", true, false).visible, "no round clock outside a live CTF round")
	_ev("round_started", {"round": 1, "mode": "ctf", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 3,
		"reset_positions": true, "round_time_ms": 180000, "respawn_ms": 0})
	await _frames(1)
	_check(String(mc.call("round_timer_text")) == "3:00" and _lbl("RoundTimer") == "3:00" and mc.find_child("RoundTimer", true, false).visible, "round_started.round_time_ms -> 3:00: %s" % _lbl("RoundTimer"))
	_check(_lbl("RoundInfo").contains("3:00 LEFT"), "info line shows time left: %s" % _lbl("RoundInfo"))
	var roster := [_row(1, "Bluey", "ALPHA", 2, 1, 1), _row(2, "Mate", "ALPHA", 1, 0, 1), _row(3, "Pal", "ALPHA", 0, 1, 0), _row(10, "Rival", "BRAVO", 1, 1, 1), _row(11, "Foe", "BRAVO", 0, 2, 0)]
	_sync_x("ctf", "live", 1, {"red": 0, "blue": 0}, {"round_time_ms": 180000, "round_ms_left": 151200, "respawn_ms": 0}, roster)
	await _frames(1)
	_check(String(mc.call("round_timer_text")) == "2:32", "snapshot round_ms_left resyncs the clock: %s" % mc.call("round_timer_text"))
	mc.set("round_left", 0.6)
	await _frames(1)
	mc.call("_process", 0.7)
	_check(String(mc.call("round_timer_text")) == "" and not mc.find_child("RoundTimer", true, false).visible, "clock ticks locally and hides at 0")
	_check(_lbl("LiveStats").contains("YOU  K 2  D 1  CAPS 1") and _lbl("LiveStats").contains("CAPTURES  RED 2 - 1 BLUE"), "live captures from room_roster: %s" % _lbl("LiveStats"))
	var tc: Dictionary = mc.call("team_captures")
	_check(int(tc["red"]) == 2 and int(tc["blue"]) == 1, "team capture totals from roster rows")
	_ev("round_ended", {"round": 1, "winner": "ALPHA", "winner_color": "red", "reason": "time", "by": 0, "by_name": "", "score": {"red": 1, "blue": 0},
		"target": 3, "best_of": 5, "next_round_in_ms": 8000, "match_point": false, "scoreboard": roster})
	_check(_banner().begins_with("ROUND 1 - RED WINS: TIME UP - RED HAD MORE PLAYERS ALIVE"), "time-out banner: %s" % _banner())
	_check(_summary_title() == "ROUND 1 - RED WINS" and _lbl("SummarySub").contains("TIME UP - RED HAD MORE PLAYERS ALIVE"), "time-out overview: %s" % _lbl("SummarySub").replace("\n", " / "))
	_check(String(mc.call("round_timer_text")) == "" and float(mc.get("round_left")) == 0.0, "no clock in the intermission")
	_ev("round_started", {"round": 2, "mode": "ctf", "score": {"red": 1, "blue": 0}, "kills": {"red": 3, "blue": 1}, "target": 3, "reset_positions": true, "round_time_ms": 180000, "respawn_ms": 0})
	_ev("round_ended", {"round": 2, "winner": "", "winner_color": "", "reason": "time", "by": 0, "by_name": "", "score": {"red": 1, "blue": 0},
		"target": 3, "best_of": 5, "next_round_in_ms": 8000, "match_point": false, "scoreboard": roster})
	_check(_banner().begins_with("ROUND 2 - DRAW: TIME UP - EQUAL PLAYERS ALIVE, NO POINT") and _banner().contains("[RED 1 - 0 BLUE]"), "draw banner: %s" % _banner())
	_check(_summary_title() == "ROUND 2 - DRAW" and _lbl("SummarySub").contains("RED 1  -  0 BLUE") and not _lbl("SummarySub").contains("MATCH POINT"), "draw overview, score unchanged: %s / %s" % [_summary_title(), _lbl("SummarySub").replace("\n", " / ")])
	_check(bool(mc.get("countdown_active")), "draw still counts down to the next round")
	mc.call("show_summary", "round", "T", "S", "", Color.WHITE, 3.0, [], "ctf")
	_check((mc.call("summary_row_texts") as Array).has("Bluey|red|2|1|1"), "scoreboard without server rows falls back to live room_roster captures")
	mc.call("hide_summary")
	print("  -- respawn_in_ms")
	_sync_x("deathmatch", "live", 1, {"red": 0, "blue": 0}, {"round_time_ms": 0, "round_ms_left": 0, "respawn_ms": 1000}, [])
	_ev("round_started", {"round": 1, "mode": "deathmatch", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 10, "reset_positions": true, "round_time_ms": 0, "respawn_ms": 1000})
	_check(String(mc.call("round_timer_text")) == "" and not mc.find_child("RoundTimer", true, false).visible, "no round clock in deathmatch")
	var pl: Dictionary = nl.players
	_ev("player_eliminated", {"victim": 1, "victim_name": "Bluey", "victim_team": "ALPHA", "shooter": 10, "shooter_name": "Rival", "shooter_team": "BRAVO",
		"victim_kills": 0, "victim_deaths": 1, "shooter_kills": 1, "shooter_deaths": 0, "reason": "paint", "scored": true, "respawn_in_ms": 2500})
	_check(absf(float(mc.get("respawn_left")) - 2.5) < 0.01 and String(mc.call("respawn_text")) == "RESPAWNING IN 2.5s", "respawn timer from respawn_in_ms: %s" % mc.call("respawn_text"))
	mc.set("respawn_left", 0.0)
	mc.set("match_respawn_ms", 1750)
	_ev("player_eliminated", {"victim": 1, "victim_name": "Bluey", "victim_team": "ALPHA", "shooter": 10, "shooter_name": "Rival", "shooter_team": "BRAVO",
		"victim_kills": 0, "victim_deaths": 2, "shooter_kills": 2, "shooter_deaths": 0, "reason": "paint", "scored": true})
	_check(absf(float(mc.get("respawn_left")) - 1.75) < 0.01, "falls back to match.respawn_ms: %.2f" % float(mc.get("respawn_left")))
	_sync_x("deathmatch", "live", 1, {"red": 0, "blue": 0}, {"round_time_ms": 0, "round_ms_left": 0, "respawn_ms": 1200}, [])
	_check(int(mc.get("match_respawn_ms")) == 1200 and pl.size() >= 5, "snapshot respawn_ms adopted")

func _walk(actions: Array, frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	await _frames(frames)
	for a in actions:
		Input.action_release(a)
	await _frames(2)

## Drive moves at the start line and record z every physics frame.
func _line_attempt(hold: Array, tap: String, frames: int, start_z: float) -> Dictionary:
	player.global_position = Vector3(6.0, player.global_position.y, start_z)
	player.set("velocity", Vector3.ZERO)
	player.set("ground_speed", 0.0)
	player.set("slide_timer", 0.0)
	player.set("dive_timer", 0.0)
	player.set("yaw", 0.0)
	await _frames(2)
	var zs: Array[float] = []
	for a in hold:
		Input.action_press(a)
	for i in range(frames):
		if not tap.is_empty() and i == 6:
			Input.action_press(tap)
		if not tap.is_empty() and i == 9:
			Input.action_release(tap)
		await physics_frame
		zs.append(float(player.global_position.z))
	for a in hold:
		Input.action_release(a)
	await _frames(2)
	var mn := 1e9
	for z in zs:
		mn = minf(mn, z)
	return {"min_z": mn, "tail": zs.slice(zs.size() - 12)}

func _break_flow() -> void:
	print("[10] v0.6 break: round_started.break_ms/break_line_z hold (invisible wall), 3-2-1, no false-start UI, horn -> GO! + release + clock")
	var nl := _lobby()
	nl.local_team = "ALPHA"
	player.set("awaiting_respawn_choice", false)
	player.set("spectating", false)
	player.call("set_lobby_open_state", false)
	_gm().set("breakout_horn_sounded", true) # the legacy offline breakout slow-walk from scene load is not part of this
	var horns := [0]
	mc.connect("break_horn_sounded", func(_d: Dictionary) -> void: horns[0] += 1)
	_check(nl.has_signal("break_horn") and mc.has_signal("break_horn_sounded"), "horn hooks for Ren's sound: NetworkLobby.break_horn + MatchHudClient.break_horn_sounded")
	_sync_x("ctf", "waiting", 0, {"red": 0, "blue": 0}, {"round_time_ms": 180000, "round_ms_left": 0, "respawn_ms": 0}, [])
	_ev("round_started", {"round": 1, "mode": "ctf", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 3,
		"reset_positions": true, "round_time_ms": 180000, "respawn_ms": 0, "break_ms": 3000, "break_line_z": 40.0})
	await _frames(1)
	_check(String(mc.get("phase")) == "break" and bool(mc.get("break_active")), "round_started with break_ms -> break phase")
	_check(String(mc.call("break_text")) == "3" and _lbl("BreakCountdown") == "3" and mc.find_child("BreakCountdown", true, false).visible, "big 3 on the HUD: %s" % _lbl("BreakCountdown"))
	_check(bool(player.get("break_hold_active")) and is_equal_approx(float(player.get("break_hold_line_z")), 40.0), "red held at z >= 40")
	_check(String(mc.call("round_timer_text")) == "" and float(mc.get("round_left")) == 0.0, "no CTF clock during the break")
	_check(_lbl("RoundInfo").contains("BREAK IN 3"), "info line: %s" % _lbl("RoundInfo"))
	mc.call("_process", 0.4)
	_check(float(mc.get("round_left")) == 0.0, "the clock does not tick during the break")
	_ev("break_countdown", {"round": 1, "seconds_left": 2, "ms_left": 2000})
	_check(String(mc.call("break_text")) == "2", "break_countdown(2) -> 2: %s" % mc.call("break_text"))
	_ev("break_countdown", {"round": 1, "seconds_left": 1, "ms_left": 1000})
	await _frames(1)
	_check(_lbl("BreakCountdown") == "1", "break_countdown(1) -> 1")
	# hold: the start line is an invisible wall - walk / sprint / slide / dive into it just stop, no jitter
	for att in [["walk", ["move_forward"], "", 70], ["sprint", ["move_forward", "sprint"], "", 70], ["slide", ["move_forward", "sprint"], "crouch_slide", 70], ["dive", ["move_forward", "sprint"], "prone_dive", 80]]:
		var r: Dictionary = await _line_attempt(att[1], att[2], att[3], 43.0)
		var tail: Array = r["tail"]
		var jitter := 0.0
		for i in range(1, tail.size()):
			jitter = maxf(jitter, absf(float(tail[i]) - float(tail[i - 1])))
		_check(float(r["min_z"]) >= 40.0 - 0.001, "%s into the line from z=43: never past it (min z=%.3f)" % [att[0], float(r["min_z"])])
		_check(float(r["min_z"]) <= 40.05, "%s actually reached the line (min z=%.3f)" % [att[0], float(r["min_z"])])
		_check(jitter < 0.005, "%s: no jitter pinned at the line (max step %.4f)" % [att[0], jitter])
	player.global_position = Vector3(6.0, player.global_position.y, 39.0)
	await _frames(2)
	_check(float(player.global_position.z) >= 39.999, "a red player past the line is clamped back to it: %.2f" % float(player.global_position.z))
	_check(int(mc.get("break_line_resets")) == 0 and String(mc.call("break_text")) == "1", "no message / flash from hitting the wall")
	player.global_position = Vector3(6.0, player.global_position.y, 44.0)
	await _walk(["move_back"], 20)
	_check(float(player.global_position.z) > 44.2, "moving away from the line still works: %.2f" % float(player.global_position.z))
	player.global_position = Vector3(6.0, player.global_position.y, 40.0)
	await _walk(["move_right"], 20)
	_check(absf(float(player.global_position.x) - 6.0) > 0.3 and float(player.global_position.z) >= 39.999, "strafing along the line works: x=%.2f z=%.3f" % [float(player.global_position.x), float(player.global_position.z)])
	var shots0 := int(player.get("_shot_counter"))
	var blocked0 := int(player.get("break_blocked_trigger_pulls"))
	player.call("_handle_trigger_press", false)
	_check(int(player.get("_shot_counter")) == shots0 and int(player.get("break_blocked_trigger_pulls")) == blocked0 + 1, "trigger blocked before the horn")
	_check(not bool(player.get("awaiting_respawn_choice")) and not bool(player.get("spectating")) and not bool(player.get("lobby_open")), "look is not locked (only crossing + firing are)")
	_ev("break_line_reset", {"team": "ALPHA", "gate": nl.team_base_position("ALPHA") if nl.has_method("team_base_position") else Vector3.ZERO, "line_z": 40.0})
	await _frames(1)
	_check(int(mc.get("break_line_resets")) == 1 and String(mc.call("break_text")) == "1" and _lbl("BreakCountdown") == "1", "break_line_reset accepted quietly (countdown unchanged, no flash): %s" % _lbl("BreakCountdown"))
	_check(not _banner().to_upper().contains("FALSE"), "no FALSE START banner: %s" % _banner())
	_check(bool(player.get("break_hold_active")), "still held after a snap-back")
	_ev("break_horn", {"round": 1, "mode": "ctf"})
	await _frames(1)
	_check(horns[0] == 1, "break_horn_sounded hook fired once")
	_check(String(mc.call("break_text")) == "GO!" and _lbl("BreakCountdown") == "GO!", "horn -> GO!")
	_check(_banner().contains("GO!"), "GO banner: %s" % _banner())
	_check(String(mc.get("phase")) == "live" and not bool(player.get("break_hold_active")), "horn releases the start line")
	_check(String(mc.call("round_timer_text")) == "3:00", "CTF clock starts at the horn: %s" % mc.call("round_timer_text"))
	mc.call("_process", 1.0)
	_check(String(mc.call("round_timer_text")) == "2:59", "and ticks after it: %s" % mc.call("round_timer_text"))
	mc.call("_process", 0.5)
	_check(String(mc.call("break_text")) == "", "GO! clears")
	for att in [["walk", ["move_forward"], "", 50], ["sprint", ["move_forward", "sprint"], "", 50], ["slide", ["move_forward", "sprint"], "crouch_slide", 50], ["dive", ["move_forward", "sprint"], "prone_dive", 60]]:
		var r: Dictionary = await _line_attempt(att[1], att[2], att[3], 41.0)
		_check(float(r["min_z"]) < 39.5, "after the horn %s crosses the line freely: min z=%.2f" % [att[0], float(r["min_z"])])
		await _frames(40)
	print("  -- break from a snapshot (late join) + duplicate horn")
	_sync_x("ctf", "break", 2, {"red": 1, "blue": 0}, {"round_time_ms": 180000, "round_ms_left": 0, "respawn_ms": 0}, [])
	_check(bool(mc.get("break_active")) and bool(player.get("break_hold_active")) and String(mc.call("round_timer_text")) == "", "snapshot phase=break -> hold, no clock")
	_sync_x("ctf", "live", 2, {"red": 1, "blue": 0}, {"round_time_ms": 180000, "round_ms_left": 178500, "respawn_ms": 0}, [])
	_check(not bool(mc.get("break_active")) and not bool(player.get("break_hold_active")) and String(mc.call("round_timer_text")) == "2:59", "snapshot live -> released, clock from round_ms_left: %s" % mc.call("round_timer_text"))
	_check(horns[0] == 2, "hook fired for the snapshot release")
	_ev("break_horn", {"round": 2, "mode": "ctf"})
	_check(horns[0] == 2, "a late break_horn after the snapshot does not double-fire: %d" % horns[0])
	print("  -- blue side")
	nl.local_team = "BRAVO"
	_ev("round_started", {"round": 3, "mode": "ctf", "score": {"red": 1, "blue": 1}, "kills": {"red": 0, "blue": 0}, "target": 3,
		"reset_positions": true, "round_time_ms": 180000, "respawn_ms": 0, "break_ms": 3000, "break_line_z": 40.0})
	_check(is_equal_approx(float(player.get("break_hold_line_z")), -40.0), "blue held at z <= -40")
	player.global_position = Vector3(0.0, player.global_position.y, -39.0)
	await _frames(2)
	_check(float(player.global_position.z) <= -39.99, "blue past the line clamped to -40: %.2f" % float(player.global_position.z))
	_ev("round_ended", {"round": 3, "winner": "", "winner_color": "", "reason": "time", "by": 0, "by_name": "", "score": {"red": 1, "blue": 1},
		"target": 3, "best_of": 5, "next_round_in_ms": 8000, "match_point": false, "scoreboard": []})
	_check(not bool(player.get("break_hold_active")), "round_ended drops any hold")
	nl.local_team = "ALPHA"
	print("  -- no break (bots_test break_ms 0)")
	_ev("round_started", {"round": 1, "mode": "ctf", "score": {"red": 0, "blue": 0}, "kills": {"red": 0, "blue": 0}, "target": 3,
		"reset_positions": true, "round_time_ms": 180000, "respawn_ms": 0, "break_ms": 0, "break_line_z": 40.0})
	_check(String(mc.get("phase")) == "live" and not bool(player.get("break_hold_active")) and String(mc.call("round_timer_text")) == "3:00", "break_ms 0 -> live at once, clock running")

func _finish() -> void:
	var nl := _lobby()
	for n in fakes:
		for pid in nl.remote_player_nodes.keys():
			if nl.remote_player_nodes[pid] == n:
				nl.remote_player_nodes.erase(pid)
	if failures.is_empty():
		print("MATCH HUD CLIENT TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("MATCH HUD CLIENT TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
