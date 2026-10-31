extends SceneTree
## v0.7 BotPlayer (Bluey, plan "Smarter bots"): movement constants unchanged (player aliases MovementRules), difficulty
## tiers applied, bots break to their assigned primary bunker (both sides, every role), no paint without a raycast line of
## sight (wall test + control), reaction time honoured, team-mode hostility, hits through the existing paint path (hit
## marker only for the local player's kills).
## Run: godot --headless --path . -s scripts/systems/test_bot_player.gd

var MovementRules: GDScript # loaded in _initialize (after the autoloads exist)
var BotPlayerScript: GDScript # loaded in _initialize (after the autoloads exist)
var BotDifficultyScript: GDScript # loaded in _initialize (after the autoloads exist)
var BunkerGraphScript: GDScript # loaded in _initialize (after the autoloads exist)

var arena: Node3D
var GM: Node
var IB: Node
var PB: Node
var failures: Array[String] = []
var started := false

func _initialize() -> void:
	MovementRules = load("res://scripts/player/movement_rules.gd")
	BotPlayerScript = load("res://scripts/bots/bot_player.gd")
	BotDifficultyScript = load("res://scripts/bots/bot_difficulty.gd")
	BunkerGraphScript = load("res://scripts/bots/bunker_graph.gd")
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

func _make_bot(opts: Dictionary) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.set_script(BotPlayerScript)
	b.call("configure", opts)
	arena.add_child(b)
	return b

func _run() -> void:
	GM = root.get_node("GameManager")
	IB = root.get_node("IntelBus")
	PB = root.get_node("PaintBallistics")
	await _frames(4)
	Engine.time_scale = 4.0
	var player: Node3D = arena.get("player")
	if player != null:
		player.global_position = Vector3(0, 0.1, 62.5) # behind the ALPHA gate, out of the bots' way
	await _test_movement_constants()
	_test_difficulty_tiers()
	var graph: RefCounted = BunkerGraphScript.build(arena, "speedball")
	await _test_reach_assigned_bunkers(graph, "ALPHA", "amateur", Vector3(0, 0, 45.5), 0.0)
	await _test_reach_assigned_bunkers(graph, "BRAVO", "rookie", Vector3(0, 0, -45.5), PI)
	await _test_no_fire_without_los()
	_test_team_hostility()
	await _test_hit_path(player)
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("BOT PLAYER TEST: ALL PASSED")
		quit(0)
	else:
		print("BOT PLAYER TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

# --- player movement stays identical: shared constants keep their v0.6 values and the player aliases them
func _test_movement_constants() -> void:
	print("movement constants")
	var expect := {
		"WALK_SPEED": 5.6, "SPRINT_SPEED": 8.4, "CROUCH_SPEED": 3.3, "PRONE_SPEED": 1.7, "BACKPEDAL_SPEED_MULT": 0.5,
		"GROUND_ACCEL": 28.0, "SPRINT_ACCEL": 9.0, "GROUND_DECEL": 60.0, "SLIDE_INITIAL_SPEED": 15.8, "SLIDE_DURATION": 0.85,
		"MOVEMENT_FIRE_RECOVERY": 0.15, "DIVE_INITIAL_SPEED": 17.6, "DIVE_DURATION": 0.95,
		"SPREAD_MULT_POCKET": 0.55, "SPREAD_MULT_PRONE": 0.6, "SPREAD_MULT_CROUCH": 0.7, "SPREAD_MULT_STANDING": 1.0,
		"SPREAD_MULT_WALK": 2.0, "SPREAD_MULT_SPRINT": 4.5, "SPREAD_MULT_AIRBORNE": 3.0,
	}
	var rules: Dictionary = MovementRules.get_script_constant_map()
	var pc: Dictionary = (load("res://scripts/player/player_controller_3d.gd") as GDScript).get_script_constant_map()
	var bad_rules: Array = []
	var bad_player: Array = []
	for k in expect.keys():
		if not rules.has(k) or not is_equal_approx(float(rules[k]), float(expect[k])):
			bad_rules.append(k)
		if not pc.has(k) or not is_equal_approx(float(pc[k]), float(rules.get(k, -1.0))):
			bad_player.append(k)
	_check(bad_rules.is_empty(), "MovementRules keeps the v0.6 player values %s" % str(bad_rules))
	_check(bad_player.is_empty(), "PlayerController3D constants alias MovementRules (identical) %s" % str(bad_player))
	_check(is_equal_approx(MovementRules.gait_target_speed(Vector2(0, -1), true, MovementRules.STANCE_STANDING), 8.4), "sprint forward = 8.4 m/s")
	_check(is_equal_approx(MovementRules.gait_target_speed(Vector2(0, -1), false, MovementRules.STANCE_CROUCHING), 3.3), "crouch walk = 3.3 m/s")
	var dist := 0.0
	var t: float = MovementRules.SLIDE_DURATION
	while t > 0.0:
		t -= 1.0 / 60.0
		dist += MovementRules.slide_speed(maxf(t, 0.0)) / 60.0
	_check(dist > 5.5 and dist < 8.5, "knee-slide covers ~7 m (%.2f m)" % dist)
	_check(MovementRules.is_fire_locked(0.2, 0.0, 0.0) and MovementRules.is_fire_locked(0.0, 0.0, 0.1) and not MovementRules.is_fire_locked(0.0, 0.0, 0.0), "slide / recovery fire lock shared")
	await _frames(1)

func _test_difficulty_tiers() -> void:
	print("difficulty tiers")
	var r: Resource = BotDifficultyScript.make("rookie")
	var a: Resource = BotDifficultyScript.make("amateur")
	var p: Resource = BotDifficultyScript.make("pro")
	var l: Resource = BotDifficultyScript.make("legend")
	_check(is_equal_approx(r.reaction_s, 0.65) and is_equal_approx(a.reaction_s, 0.45), "reaction 650 / 450 ms")
	_check(is_equal_approx(r.aim_error_at(20.0), 0.8) and is_equal_approx(a.aim_error_at(20.0), 0.7), "aim error at 20 m: 0.8 / 0.7 m (Rookie trimmed in v0.7: drop is compensated, the miss is a small cone)")
	_check(r.aim_error_at(40.0) > r.aim_error_at(20.0), "aim error grows with range")
	_check(is_equal_approx(r.shot_interval(10.5), 2.0 * a.shot_interval(10.5)), "Rookie bursts at half rate")
	_check(not r.suppresses and a.suppresses, "Amateur suppresses, Rookie does not")
	_check(not r.can_slide and a.can_slide and not a.can_dive and p.can_dive, "slide: Amateur yes / Rookie no; dive arrives with Pro")
	_check(not r.varies_peek_side and a.varies_peek_side, "peek side: Rookie same every time, Amateur varies")
	_check(r.move_chance < a.move_chance, "Rookie rarely moves, Amateur moves when safe")
	_check(p.reaction_s < a.reaction_s and l.reaction_s < p.reaction_s and p.flanks, "Pro / Legend exist as data")
	var b: Node = BotPlayerScript.new()
	b.call("configure", {"callsign": "Tier", "difficulty": "rookie"})
	_check(b.difficulty != null and is_equal_approx(b.difficulty.reaction_s, 0.65), "configure() applies the tier to the bot")
	b.free()

func _test_reach_assigned_bunkers(graph: RefCounted, team: String, tier: String, gate: Vector3, yaw: float) -> void:
	print("break to assigned bunkers: %s (%s)" % [team, tier])
	GM.reset_match_stats()
	GM.register_round_start(5)
	var bots: Array = []
	var roles := ["front", "mid", "back"]
	for i in roles.size():
		var role: String = roles[i]
		var node: int = graph.primary_for(role, team, 0)
		_check(node >= 0, "%s %s primary exists (%s)" % [team, role, graph.nodes[node]["callout"] if node >= 0 else "-"])
		bots.append(_make_bot({"callsign": "%s_%s" % [team, role], "team": team, "ffa": false, "role": role, "index": i,
			"difficulty": tier, "graph": graph, "assigned_node": node, "spawn": gate + Vector3((i - 1) * 2.2, 0, 0), "spawn_yaw": yaw, "seed": 11 + i}))
	var horn_waits := 0
	while not GM.breakout_horn_sounded:
		await physics_frame
		horn_waits += 1
	await _frames(1)
	var horn_clock: float = bots[0].clock
	for b in bots:
		_check(horn_waits > 30 and b.distance_moved < 0.3 and b.reached_assigned == false, "%s held the start box until the horn (moved %.2f m)" % [b.bot_name, b.distance_moved])
	var t := 0.0
	while t < 18.0:
		await _sim(0.5)
		t += 0.5
		var all := true
		for b in bots:
			all = all and b.reached_assigned
		if all:
			break
	for b in bots:
		var d: float = b.arrival_error
		_check(b.reached_assigned and d >= 0.0 and d < 1.0, "%s reached the %s pocket after the break (%.2f m off, %.1fs after the horn, slides %d)" % [b.bot_name, graph.nodes[b.assigned_node]["callout"], d, b.reached_assigned_at - horn_clock, b.slides_done])
	if tier == "rookie":
		var slides := 0
		for b in bots:
			slides += b.slides_done
		_check(slides == 0, "Rookie never slides")
	for b in bots:
		b.queue_free()
	await _frames(2)

func _test_no_fire_without_los() -> void:
	print("no fire without line of sight")
	GM.reset_match_stats()
	GM.register_round_start(5)
	var wall := StaticBody3D.new()
	wall.name = "TestLosWall"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 0.6)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = Vector3(-44.0, 2.0, 0.0)
	var a := _make_bot({"callsign": "LosA", "team": "ALPHA", "ffa": false, "role": "mid", "index": 0, "difficulty": "amateur", "spawn": Vector3(-44, 0, 5), "spawn_yaw": 0.0, "seed": 3})
	var b := _make_bot({"callsign": "LosB", "team": "BRAVO", "ffa": false, "role": "mid", "index": 1, "difficulty": "amateur", "spawn": Vector3(-44, 0, -5), "spawn_yaw": PI, "seed": 4})
	await _sim(12.0) # horn, then ~9 s of hold / peek behind the wall
	_check(a.perception_ticks > 30 and a.los_rays_cast > 30, "perception ran (~10 Hz: %d ticks, %d rays)" % [a.perception_ticks, a.los_rays_cast])
	_check(a.shots_fired == 0 and b.shots_fired == 0, "wall between them: zero shots (%d / %d)" % [a.shots_fired, b.shots_fired])
	_check(a.current_target == null and b.current_target == null, "no target through the wall")
	var first_shot := {}
	var on_shot := func(bot: Node, _o: Vector3, _p: Vector3, _k: String):
		if not first_shot.has(bot):
			first_shot[bot] = [bot.clock, bot.target_seen_since]
	a.shot_fired.connect(on_shot)
	b.shot_fired.connect(on_shot)
	wall.queue_free()
	await _sim(10.0)
	_check(a.shots_fired + b.shots_fired > 0, "control: wall removed -> they shoot (%d / %d)" % [a.shots_fired, b.shots_fired])
	_check(a.deaths + b.deaths > 0, "control: a bot's paint eliminates the other (deaths %d / %d)" % [a.deaths, b.deaths])
	var reaction_ok := not first_shot.is_empty()
	for k in first_shot.keys():
		var rec: Array = first_shot[k]
		if float(rec[0]) - float(rec[1]) < 0.45 - 0.02:
			reaction_ok = false
	_check(reaction_ok, "first shot waits the Amateur reaction time (450 ms) %s" % str(first_shot.values()))
	a.queue_free()
	b.queue_free()
	await _frames(2)

func _test_team_hostility() -> void:
	print("targeting rules")
	var a: Node = BotPlayerScript.new()
	a.call("configure", {"callsign": "TA", "team": "ALPHA", "ffa": false})
	var a2: Node = BotPlayerScript.new()
	a2.call("configure", {"callsign": "TA2", "team": "ALPHA", "ffa": false})
	var c: Node = BotPlayerScript.new()
	c.call("configure", {"callsign": "TB", "team": "BRAVO", "ffa": false})
	var f: Node = BotPlayerScript.new()
	f.call("configure", {"callsign": "TF", "team": "FFA", "ffa": true})
	_check(not a.call("_is_hostile", a2) and a.call("_is_hostile", c), "team mode: teammates safe, the other team hostile")
	_check(f.call("_is_hostile", a) and f.call("_is_hostile", c) and not f.call("_is_hostile", f), "FFA: everyone else is hostile")
	for n in [a, a2, c, f]:
		n.free()

func _test_hit_path(player: Node3D) -> void:
	print("hits through the existing paint path")
	GM.reset_match_stats()
	GM.register_round_start(5)
	var v := _make_bot({"callsign": "Victim", "team": "BRAVO", "ffa": false, "spawn": Vector3(-40, 0, 10), "seed": 5})
	var k := _make_bot({"callsign": "Killer", "team": "ALPHA", "ffa": false, "spawn": Vector3(-40, 0, 14), "seed": 6})
	k.set_physics_process(false) # a stand-in shooter: no brain, so it can't spawn-camp the victim mid-test
	await _frames(3)
	var feed: Array = []
	var cb := func(m: String): feed.append(m)
	IB.intel_feed_updated.connect(cb)
	var kills0: int = GM.local_kills
	var markers0: int = BotPlayerScript.local_hit_markers_shown
	var sub: Dictionary = v.resolve_hit_subzone(v.get_node("Hitbox_Mask").global_position)
	_check(String(sub.get("zone", "")) == "MASK / GOGGLES", "subzones mirror the practice bots (%s)" % sub.get("zone"))
	v.on_paintball_break(v.global_position + Vector3(0, 1.0, 0), k)
	_check(v.is_eliminated and v.collision_layer == 0, "bot-on-bot hit eliminates")
	_check(GM.local_kills == kills0 and BotPlayerScript.local_hit_markers_shown == markers0, "no hit marker / local kill for a bot's kill")
	_check(k.kills == 1, "shooter bot credited")
	_check(feed.size() > 0 and String(feed[-1]).contains("KILLER"), "intel feed names the shooter")
	await _sim(3.6)
	_check(not v.is_eliminated, "bot respawns after 3.2 s")
	_check(float(v.get("_respawn_flash_timer")) > 0.2, "respawned bot has spawn protection")
	v.on_paintball_break(v.global_position + Vector3(0, 1.0, 0), k)
	_check(not v.is_eliminated, "spawn-protected bot ignores a hit")
	await _sim(3.0)
	v.on_paintball_break(v.global_position + Vector3(0, 1.0, 0), player)
	_check(GM.local_kills == kills0 + 1 and BotPlayerScript.local_hit_markers_shown == markers0 + 1, "local player's kill -> hit marker + local kill")
	IB.intel_feed_updated.disconnect(cb)
	# real paintball: Killer -> Victim via PaintBallistics (after the respawn + spawn protection)
	await _sim(3.6 + 3.0)
	var deaths0: int = v.deaths
	var from: Vector3 = k.global_position + Vector3(0, 1.3, 0)
	var to: Vector3 = v.get_node("Hitbox_Torso").global_position + Vector3(0, 0.1, 0)
	PB.spawn_paintball(from, (to - from).normalized(), 285.0, k, Color.ORANGE)
	await _sim(0.6)
	_check(v.deaths == deaths0 + 1, "a real paintball from another bot eliminates (ballistics -> on_paintball_break)")
	v.queue_free()
	k.queue_free()
	await _frames(2)
