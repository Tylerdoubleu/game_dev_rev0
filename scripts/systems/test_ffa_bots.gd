extends SceneTree
## v0.7 Solo FFA deathmatch (Bluey, plan "Smarter bots"): ?solo=ffa query parsing, 4 bots with unique callsigns spawn
## through the arena entry point, the respawn map runs in deathmatch mode, ALL BOTS vs YOU (v0.7, Tyler): every bot shot
## is at the human player, never at another bot, there are NO bot-on-bot eliminations (a bot ball on a bot is ignored and
## never scored), the bots' eliminations of the player are credited in the standings, every snap shot had an independent
## raycast line of sight to its target, first-to-N ends the match (you at N, or any bot reaching N on you), and stopping
## restores the GameManager death limit. Respawn minimap: in a bot match every live bot is sent to set_players, also in
## deathmatch mode.
## Aim fix (Tyler: "do the bots look where they are aiming? bullets going behind them?"): EVERY shot is audited — the
## angle between the bot's body/aim forward and the ball direction is under SHOT_CONE_DEG, the spawn point is in front
## of the bot (dot > 0, also in front of the eye) and the visible marker barrel points along the shot; a bot whose
## target is behind it turns (at its tier rate) before the first ball. Kill feed: every line reads SHOOTER SPLATTED
## VICTIM and matches the standings deltas of that same elimination.
## Run: godot --headless --path . -s scripts/systems/test_ffa_bots.gd

var BotPlayerScript: GDScript # loaded in _initialize (after the autoloads exist)
var ArenaScript: GDScript

var arena: Node3D
var GM: Node
var failures: Array[String] = []
var started := false
var snap_checked := 0
var snap_no_los := 0
var bot_on_bot_kills := 0
var shots_at_bots := 0
var player_respawns := 0
const SHOT_CONE_DEG := 10.0 # body forward vs actual ball dir (FIRE_CONE_DEG 7 + MovementRules spread)
var shots_audited := 0
var shots_bad_angle := 0
var shots_behind := 0
var shots_marker_off := 0
var worst_shot_angle := 0.0
var worst_shot_msg := ""
var feed_lines: Array[String] = []
var feed_mismatch: Array[String] = []
var _standings_before := {}
var _done := {}

func _initialize() -> void:
	BotPlayerScript = load("res://scripts/bots/bot_player.gd")
	ArenaScript = load("res://scripts/systems/speedball_arena_builder.gd")
	arena = (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_d: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## `seconds` of game time (physics delta is already scaled by Engine.time_scale).
func _sim(seconds: float) -> void:
	await _frames(maxi(1, int(ceil(seconds * float(Engine.physics_ticks_per_second) / Engine.time_scale))))

func _run() -> void:
	GM = root.get_node("GameManager")
	await _frames(4)
	_test_query()
	Engine.time_scale = 4.0
	await _test_ffa_match()
	await _test_first_to_n()
	await _test_feed_order()
	await _test_turn_before_fire()
	_check(_done.has("feed") and _done.has("turn"), "feed-order and turn-before-fire tests ran to the end (no script error) %s" % str(_done.keys()))
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("FFA BOTS TEST: ALL PASSED")
		quit(0)
	else:
		print("FFA BOTS TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

func _test_query() -> void:
	var o: Dictionary = ArenaScript.parse_ffa_query("?solo=ffa")
	_check(int(o.get("bots", 0)) == 4 and String(o.get("tier", "")) == "amateur", "?solo=ffa -> 4 amateur bots (%s)" % str(o))
	o = ArenaScript.parse_ffa_query("?solo=ffa&tier=rookie&ffa_bots=12")
	_check(int(o.get("bots", 0)) == 7 and String(o.get("tier", "")) == "rookie", "tier=rookie, ffa_bots clamped to 7 (%s)" % str(o))
	o = ArenaScript.parse_ffa_query("?room=abc")
	_check(o.is_empty(), "no solo=ffa -> no auto start")

func _on_shot(bot: Node, origin: Vector3, _aim: Vector3, kind: String) -> void:
	_audit_shot(bot, origin, kind)
	var ct: Variant = bot.get("current_target")
	if ct != null and is_instance_valid(ct) and not BotPlayerScript.is_human(ct):
		shots_at_bots += 1
	if kind != "snap":
		return
	snap_checked += 1
	var tgt: Node3D = bot.get("current_target")
	if tgt == null:
		snap_no_los += 1
		return
	var eye: Vector3 = bot.call("eye_position")
	var space := (bot as Node3D).get_world_3d().direct_space_state
	var seen := false
	for ap in BotPlayerScript.aim_points_of(tgt):
		var q := PhysicsRayQueryParameters3D.create(eye, ap)
		q.exclude = [(bot as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			seen = true
		else:
			var col: Object = hit.get("collider")
			if col == tgt or (col is Node and tgt.is_ancestor_of(col)) or (hit["position"] as Vector3).distance_to(ap) < 0.35:
				seen = true
		if seen:
			break
	if not seen:
		snap_no_los += 1

## Every shot: body (yaw + pitch) forward within SHOT_CONE_DEG of the ball direction, spawn point in front of the bot,
## marker barrel along the shot.
func _audit_shot(bot: Node, origin: Vector3, kind: String) -> void:
	shots_audited += 1
	var dir: Vector3 = bot.get("last_shot_dir")
	var body_fwd: Vector3 = bot.call("aim_forward")
	var ang := rad_to_deg(body_fwd.angle_to(dir))
	var flat_fwd: Vector3 = bot.call("body_forward")
	var pos := (bot as Node3D).global_position
	var rel := origin - pos
	rel.y = 0.0
	var front_dot := rel.dot(flat_fwd)
	var eye_dot := (origin - (bot.call("eye_position") as Vector3)).dot(dir)
	var marker_ang := rad_to_deg((bot.call("marker_forward") as Vector3).angle_to(dir))
	if ang > worst_shot_angle:
		worst_shot_angle = ang
		worst_shot_msg = "%s %s state=%d ang=%.1f" % [bot.get("bot_name"), kind, int(bot.get("state")), ang]
	if ang >= SHOT_CONE_DEG:
		shots_bad_angle += 1
		print("    DBG bad shot %s %s ang %.1f: impact dist %.1f (dy %.2f), flight %.2f, dir pitch %.1f, aim pitch %.1f, yaw diff %.1f" % [bot.get("bot_name"), kind, ang, (bot.call("eye_position") as Vector3).distance_to(bot.get("last_shot_impact")), (bot.get("last_shot_impact") as Vector3).y - (bot.call("eye_position") as Vector3).y, float(bot.get("last_shot_flight_t")), rad_to_deg(asin(dir.y)), rad_to_deg(float(bot.get("aim_pitch"))), rad_to_deg(Vector2(dir.x, dir.z).angle_to(Vector2(body_fwd.x, body_fwd.z)))])
	if front_dot <= 0.0 or eye_dot <= 0.0:
		shots_behind += 1
	if marker_ang > 15.0:
		shots_marker_off += 1
		print("    marker off: %s %s state=%d marker=%.1f w=%.2f" % [bot.get("bot_name"), kind, int(bot.get("state")), marker_ang, float(bot.get("_aim_pose_w"))])

func _on_feed(msg: String) -> void:
	feed_lines.append(msg)

func _snap_standings(m: Node) -> Dictionary:
	var d := {}
	for row in m.call("standings"):
		d[String(row["name"])] = [int(row["kills"]), int(row["deaths"])]
	return d

## Called from the match's standings_changed: the newest kill_log entry's feed line must read SHOOTER SPLATTED VICTIM,
## the shooter's kills and the victim's deaths must each have gone up by one in this same update.
func _on_standings(_rows: Array, m: Node) -> void:
	var now := _snap_standings(m)
	var log: Array = m.get("kill_log")
	if log.is_empty():
		_standings_before = now
		return
	var k: Dictionary = log[log.size() - 1]
	var shooter := String(k["shooter"])
	var victim := String(k["victim"])
	var line := String(k["feed"])
	if not line.begins_with("%s SPLATTED %s" % [shooter.to_upper(), victim.to_upper()]):
		feed_mismatch.append("feed '%s' vs log %s->%s" % [line, shooter, victim])
	if feed_lines.is_empty() or feed_lines[feed_lines.size() - 1] != line:
		feed_mismatch.append("HUD feed signal didn't carry '%s'" % line)
	if _standings_before.has(shooter) and now.has(shooter) and shooter != victim and now[shooter][0] != _standings_before[shooter][0] + 1:
		feed_mismatch.append("'%s' but %s kills %s -> %s" % [line, shooter, _standings_before[shooter][0], now[shooter][0]])
	if _standings_before.has(victim) and now[victim][1] != _standings_before[victim][1] + 1:
		feed_mismatch.append("'%s' but %s deaths %s -> %s" % [line, victim, _standings_before[victim][1], now[victim][1]])
	_standings_before = now

func _on_bot_elim(_bot: Node, shooter: Node, _zone: String) -> void:
	if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("bot_players"):
		bot_on_bot_kills += 1

func _test_ffa_match() -> void:
	var player: Node3D = arena.get("player")
	var m: Node = arena.call("start_solo_ffa", {"bots": 4, "tier": "amateur", "seed": 7})
	_check(m != null and bool(arena.call("is_solo_ffa_active")), "start_solo_ffa creates the match")
	if m == null:
		return
	# the human stays on the field (the ALPHA gate): every bot comes for them.
	var bots: Array = m.get("bots")
	_check(bots.size() == 4, "default FFA has 4 bots (%d)" % bots.size())
	var names := {}
	for b in bots:
		names[String(b.get("bot_name")).to_lower()] = true
		b.connect("shot_fired", _on_shot)
		b.connect("bot_eliminated", _on_bot_elim)
		_check(b.get("difficulty") != null and float(b.get("difficulty").get("turn_rate_deg")) > 0.0, "%s has a tier turn rate (%s deg/s)" % [b.get("bot_name"), str(b.get("difficulty").get("turn_rate_deg")) if b.get("difficulty") != null else "?"])
		_check(bool(b.get("ffa")), "%s is FFA" % b.get("bot_name"))
		_check(bool(b.get("hunt_player_only")), "%s hunts only the player" % b.get("bot_name"))
		if player != null:
			_check(bool(b.call("_is_hostile", player)), "%s: the player is hostile" % b.get("bot_name"))
		for o in bots:
			if o != b:
				_check(not bool(b.call("_is_hostile", o)), "%s: %s is not a target" % [b.get("bot_name"), o.get("bot_name")])
	root.get_node("IntelBus").intel_feed_updated.connect(_on_feed)
	_standings_before = _snap_standings(m)
	m.connect("standings_changed", _on_standings.bind(m))
	_check(names.size() == 4 and not names.has(String(m.get("_player_name")).to_lower()), "callsigns unique (and not the player's): %s" % str(names.keys()))
	_check(int(m.get("kills_to_win")) == 10, "first to 10")
	_check(not bool(GM.get("death_limit_enabled")), "GameManager death limit off during FFA")
	_check(String(arena.call("respawn_map_mode")) == "deathmatch", "respawn map in deathmatch mode")
	# HUD: no CTF text during FFA - your eliminations, the leader and first-to-N instead.
	arena.call("_on_round_updated", 1, 0, 200.0)
	var rl: Label = arena.get("round_label")
	if rl != null:
		var hud := rl.text
		_check(not hud.contains("FLAG:") and not hud.contains("DEATHS:") and not hud.contains("Flag Pull"), "FFA HUD hides CTF flag / death-limit text")
		_check(hud.contains("YOUR ELIMS: 0") and hud.contains("LEADER:") and hud.contains("FIRST TO 10"), "FFA HUD shows your elims, leader, first to 10")
		arena.call("_on_status_banner", "BUZZER! CLEAN BREAKOUT! (+15% Sprint Burst for 1.5s — Go Get Center Flag!)", Color.WHITE)
		var sl: Label = arena.get("status_label")
		_check(sl == null or not sl.text.contains("Center Flag"), "FFA breakout banner drops 'Go Get Center Flag'")
	var ft: String = ArenaScript.ffa_round_text([{"name": "Viper", "kills": 4, "deaths": 1, "is_player": false}, {"name": "Me", "kills": 2, "deaths": 3, "is_player": true}], 10, 90.0)
	_check(ft.contains("YOUR ELIMS: 2") and ft.contains("LEADER: Viper (4)") and ft.contains("FIRST TO 10"), "ffa_round_text: elims 2, leader Viper (4), first to 10")
	var zones: Array = m.call("player_respawn_zones")
	_check(zones.size() >= 3, "player gets FFA respawn zones (%d)" % zones.size())
	var start_pos := {}
	for b in bots:
		start_pos[b] = (b as Node3D).global_position
	m.set("kills_to_win", 1000) # keep the soak going: a bot reaching 10 on a parked player would end it early
	var t := 0.0
	var pdeaths := 0
	while t < 150.0 and not (shots_audited >= 300 and pdeaths >= 2):
		await _sim(1.0)
		t += 1.0
		pdeaths = _player_deaths(m)
		if player != null and bool(player.get("awaiting_respawn_choice")):
			arena.call("_on_respawn_zone_selected", 0) # pick spawn 1 like the browser check
			player_respawns += 1
	var moved := 0
	for b in bots:
		if float(b.get("distance_moved")) > 5.0:
			moved += 1
	_check(moved >= 3, "bots move around (%d of 4 moved > 5 m)" % moved)
	_check(bot_on_bot_kills == 0, "no bot-on-bot eliminations (%d in %.0f s)" % [bot_on_bot_kills, t])
	_check(shots_at_bots == 0, "every bot shot was at the player (%d of %d at a bot)" % [shots_at_bots, shots_audited])
	var ignored := 0
	for b in bots:
		ignored += int(b.get("bot_friendly_hits_ignored"))
	print("    stray bot balls on bots ignored: %d" % ignored)
	pdeaths = _player_deaths(m)
	_check(pdeaths >= 1, "the bots splat the player (%d deaths in %.0f s, %d respawns)" % [pdeaths, t, player_respawns])
	var bot_kills_in_standings := 0
	var bot_deaths_in_standings := 0
	for row in m.call("standings"):
		if not bool(row["is_player"]):
			bot_kills_in_standings += int(row["kills"])
			bot_deaths_in_standings += int(row["deaths"])
	_check(bot_kills_in_standings == pdeaths, "standings: bot kills (%d) == player deaths (%d)" % [bot_kills_in_standings, pdeaths])
	_check(bot_deaths_in_standings == 0, "standings: no bot deaths with a parked player (%d)" % bot_deaths_in_standings)
	for k in (m.get("kill_log") as Array):
		_check(String(k["victim"]) == String(m.get("_player_name")) or String(k["shooter"]) == String(m.get("_player_name")), "kill log entry involves the player: %s" % String(k["feed"]))
	# respawn minimap in a bot match (Solo FFA = deathmatch mode): every live bot is sent, anywhere on the field.
	arena.call("_refresh_respawn_map_dots")
	var dots: Array = arena.get("respawn_map_dots")
	var live := 0
	for b in bots:
		if not bool(b.get("is_eliminated")) and (b as Node3D).visible:
			live += 1
	_check(bool(arena.call("is_bot_match")), "Solo FFA is a bot match")
	_check(dots.size() == live and live > 0, "FFA respawn minimap gets every live bot (%d dots, %d live) in deathmatch mode" % [dots.size(), live])
	_check(shots_audited > 50 and shots_bad_angle == 0, "every shot within %.0f deg of the bot's body/aim forward (%d shots, %d outside, worst %s)" % [SHOT_CONE_DEG, shots_audited, shots_bad_angle, worst_shot_msg])
	_check(shots_behind == 0, "every ball spawned in front of the bot (dot > 0) (%d shots, %d behind)" % [shots_audited, shots_behind])
	_check(shots_marker_off == 0, "visible marker barrel within 15 deg of every shot (%d off)" % shots_marker_off)
	var klog: Array = m.get("kill_log")
	_check(klog.size() == pdeaths and klog.size() > 0, "kill log records every elimination (%d)" % klog.size())
	_check(feed_mismatch.is_empty(), "every kill feed line reads SHOOTER SPLATTED VICTIM, matching the standings (%d kills; %s)" % [klog.size(), str(feed_mismatch.slice(0, 3))])
	_check(snap_checked > 0 and snap_no_los == 0, "every snap shot had raycast LOS to its target (%d shots, %d without)" % [snap_checked, snap_no_los])
	var respawned := 0
	for b in bots:
		if int(b.get("deaths")) > 0 and not bool(b.get("is_eliminated")):
			respawned += 1
	print("    standings: %s" % str(m.call("standings")))
	arena.call("stop_solo_ffa")
	await _frames(2)
	_check(not bool(arena.call("is_solo_ffa_active")), "stop_solo_ffa ends the match")
	_check(bool(GM.get("death_limit_enabled")), "death limit restored after stop")
	_check(get_nodes_in_group("bot_players").is_empty(), "FFA bots removed on stop")
	arena.call("_on_round_updated", 1, 5, 200.0)
	var rl2: Label = arena.get("round_label")
	_check(rl2 == null or rl2.text.contains("FLAG:"), "CTF HUD text back after FFA stops")

func _test_first_to_n() -> void:
	# you win at N
	var m: Node = arena.call("start_solo_ffa", {"bots": 2, "tier": "amateur", "kills_to_win": 2})
	var bots: Array = m.get("bots")
	var a: Node = bots[0]
	var b: Node = bots[1]
	var pl: Node = m.get("player")
	var me := String(m.get("_player_name"))
	var over := [""]
	m.connect("ffa_match_over", func(w): over[0] = w)
	m.call("on_bot_eliminated", b, a)
	_check(String(m.get("winner")) == "" and _row(m, String(a.get("bot_name"))).get("kills", -1) == 0 and _row(m, String(b.get("bot_name"))).get("deaths", -1) == 0, "a bot credited with a bot: ignored (no kill, no death)")
	m.call("on_bot_eliminated", b, pl)
	_check(String(m.get("winner")) == "" and not bool(GM.get("match_ended")), "1 kill: match continues")
	m.call("on_bot_eliminated", a, pl)
	_check(String(m.get("winner")) == me and over[0] == me, "you reach kills_to_win=2: you win (%s)" % String(m.get("winner")))
	_check(bool(GM.get("match_ended")), "GameManager match ended")
	arena.call("stop_solo_ffa")
	await _frames(2)
	GM.set("match_ended", false)
	# any bot reaching N on you ends it
	m = arena.call("start_solo_ffa", {"bots": 2, "tier": "amateur", "kills_to_win": 2})
	bots = m.get("bots")
	a = bots[0]
	pl = m.get("player")
	over = [""]
	m.connect("ffa_match_over", func(w): over[0] = w)
	if pl != null and pl.has_signal("player_eliminated"):
		for i in 2:
			pl.set("last_shooter_name", String(a.get("bot_name")))
			pl.emit_signal("player_eliminated", "%s [MASK / GOGGLES]" % a.get("bot_name"))
			if i == 0:
				_check(String(m.get("winner")) == "", "bot 1 kill on you: match continues")
		_check(String(m.get("winner")) == String(a.get("bot_name")) and over[0] == String(a.get("bot_name")) and bool(GM.get("match_ended")), "%s reaches 2 on you: match over, bot wins" % a.get("bot_name"))
	arena.call("stop_solo_ffa")
	await _frames(2)
	GM.set("match_ended", false)

func _row(m: Node, n: String) -> Dictionary:
	for r in m.call("standings"):
		if String(r["name"]) == n:
			return r
	return {}

func _player_deaths(m: Node) -> int:
	return int(_row(m, String(m.get("_player_name"))).get("deaths", 0))

## Deterministic feed check: Hammer's ball on Rook is ignored (all bots vs you); you paint Rook -> "<YOU> SPLATTED ROOK",
## you +1 kill, Rook +1 death (never the reverse); a bot painting the player names the bot first and the player second.
func _test_feed_order() -> void:
	var m: Node = arena.call("start_solo_ffa", {"bots": 2, "tier": "amateur", "kills_to_win": 10})
	var bots: Array = m.get("bots")
	var hammer: Node = bots[0]
	var rook: Node = bots[1]
	# rename the two bots to the playtest pair (scores rows are keyed by callsign)
	var sc: Dictionary = m.get("scores")
	var hr: Dictionary = sc[String(hammer.get("bot_name"))]
	var rr: Dictionary = sc[String(rook.get("bot_name"))]
	sc.erase(String(hammer.get("bot_name")))
	sc.erase(String(rook.get("bot_name")))
	hr["name"] = "Hammer"
	rr["name"] = "Rook"
	sc["Hammer"] = hr
	sc["Rook"] = rr
	hammer.set("bot_name", "Hammer")
	rook.set("bot_name", "Rook")
	feed_lines.clear()
	# all bots vs you: Hammer's ball on Rook is ignored - no elimination, no feed line, no score
	rook.call("on_paintball_break", (rook as Node3D).global_position + Vector3(0, 1.3, 0), hammer)
	await _frames(1)
	_check(not bool(rook.get("is_eliminated")) and feed_lines.is_empty() and int(_row(m, "Hammer").get("kills", -1)) == 0 and int(_row(m, "Rook").get("deaths", -1)) == 0, "Hammer's ball on Rook is ignored (no elim, no feed, no score; feed %s)" % str(feed_lines))
	var pl0: Node = m.get("player")
	var me := String(m.get("_player_name"))
	feed_lines.clear()
	rook.call("on_paintball_break", (rook as Node3D).global_position + Vector3(0, 1.3, 0), pl0)
	await _frames(1)
	var ham_row := _row(m, "Hammer")
	var rook_row := _row(m, "Rook")
	var me_row := _row(m, me)
	var line: String = feed_lines[feed_lines.size() - 1] if not feed_lines.is_empty() else ""
	_check(line.begins_with("%s SPLATTED ROOK" % me.to_upper()), "you paint Rook -> feed '%s'" % line)
	_check(feed_lines.size() == 1, "exactly one feed line per elimination (%d)" % feed_lines.size())
	_check(int(me_row.get("kills", -1)) == 1 and int(rook_row.get("deaths", -1)) == 1 and int(rook_row.get("kills", -1)) == 0 and int(ham_row.get("kills", -1)) == 0, "standings credit you (shooter), not Rook: %s / %s" % [str(me_row), str(rook_row)])
	var pl: Node = m.get("player")
	if pl != null and pl.has_signal("player_eliminated"):
		pl.set("last_shooter_name", "Hammer")
		feed_lines.clear()
		pl.emit_signal("player_eliminated", "Hammer [GOGGLE]")
		var pline: String = feed_lines[feed_lines.size() - 1] if not feed_lines.is_empty() else ""
		var pname := String(m.get("_player_name"))
		_check(pline == "HAMMER SPLATTED %s [GOGGLE]" % pname.to_upper(), "Hammer paints the player -> feed '%s' (standings name '%s')" % [pline, pname])
	arena.call("stop_solo_ffa")
	await _frames(2)
	_done["feed"] = true

## A target directly behind a bot: no ball leaves until the body has turned onto it, and the first ball goes out the
## front. Brains are paused (physics off) and the bot's fire / motor / pose ticks are stepped by hand.
func _test_turn_before_fire() -> void:
	Engine.time_scale = 1.0
	var m: Node = arena.call("start_solo_ffa", {"bots": 2, "tier": "rookie", "kills_to_win": 10})
	var bots: Array = m.get("bots")
	var a: Node3D = bots[0]
	var b: Node3D = bots[1]
	a.set_physics_process(false)
	b.set_physics_process(false)
	await _frames(2)
	# find a spot for b with clear LOS from a
	var placed := false
	for r in [6.0, 9.0, 4.0, 12.0]:
		for k in 16:
			var ang := TAU * float(k) / 16.0
			b.global_position = a.global_position + Vector3(sin(ang), 0.0, cos(ang)) * r
			await _frames(1)
			if bool(a.call("has_los", a.call("eye_position"), BotPlayerScript.aim_points_of(b)[0], b)):
				placed = true
				break
		if placed:
			break
	_check(placed, "turn test: found a clear line between the two bots")
	var shots := []
	a.connect("shot_fired", func(bot, o, _aim, _k): shots.append([o, bot.call("aim_forward"), bot.get("last_shot_dir"), bot.call("body_forward"), (bot as Node3D).global_position, bot.call("marker_forward")]))
	var to_b := b.global_position - a.global_position
	var away := atan2(to_b.x, to_b.z) # forward (-sin, -cos) of this yaw points straight away from b
	a.set("yaw", away)
	a.rotation.y = away
	a.set("aim_pitch", 0.0)
	a.set("current_target", b)
	a.set("burst_pause", 0.0)
	a.call("_start_burst", "snap")
	var dt := 1.0 / 60.0
	var waits0 := int(a.get("shots_waited_for_turn"))
	a.call("_tick_fire", dt)
	_check(shots.is_empty(), "target behind: no ball on the burst's first frame (%d)" % shots.size())
	var t := 0.0
	var first_shot_t := -1.0
	while t < 2.0:
		a.call("_tick_fire", dt)
		a.call("_motor", dt)
		a.call("_pose", dt)
		t += dt
		if first_shot_t < 0.0 and not shots.is_empty():
			first_shot_t = t
	var waited := int(a.get("shots_waited_for_turn")) - waits0
	var rate := float(a.get("difficulty").get("turn_rate_deg"))
	_check(not shots.is_empty() and waited > 0, "bot held fire while turning 180 deg, then fired (%d waits, first ball at %.2f s, rookie %.0f deg/s)" % [waited, first_shot_t, rate])
	_check(first_shot_t >= (180.0 - BotPlayerScript.FIRE_CONE_DEG) / rate * 0.9, "first ball not before the turn could finish (%.2f s)" % first_shot_t)
	var all_ok := true
	for s in shots:
		var rel: Vector3 = s[0] - s[4]
		rel.y = 0.0
		if rad_to_deg((s[1] as Vector3).angle_to(s[2])) >= SHOT_CONE_DEG or rel.dot(s[3]) <= 0.0 or rad_to_deg((s[5] as Vector3).angle_to(s[2])) > 15.0:
			all_ok = false
	_check(all_ok, "turned shots: on body forward, marker on the shot, spawned in front (%d)" % shots.size())
	arena.call("stop_solo_ffa")
	await _frames(2)
	_done["turn"] = true
