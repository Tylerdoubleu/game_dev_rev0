extends SceneTree
## v0.7 bot ball-drop compensation (Tyler: bots must aim for the drop at every tier, Rookie included). Checks:
##  - BotPlayer.ball_speed_mps() == the speed PaintBallistics.spawn_paintball really gives a ball (+/-5.5 fps chrono)
##  - the solver (same gravity / drag / wind integration as PaintBallistics) lands its own simulated ball on the aim
##    point at 10..40 m, and the launch pitch rises with range
##  - an Amateur bot with ZERO aim error and ZERO spread hits a stationary chest-high target at 10, 20 and 30 m with
##    real PaintBallistics balls (Magnus / wobble jitter still on, so >= 8 of 10 at 10/20 m, >= 6 of 10 at 30 m)
##  - lead: Amateur leads a moving target by velocity x flight time, Rookie only partly (lead_factor)
##  - Rookie (real aim error + spread) hit rate on a stationary target at 20 m over N shots is reported (>= 15%; ~25-35% typical)
##  - every one of those shots still leaves inside the fire cone (body forward vs ball dir < 10 deg)
## Run: godot --headless --path . -s scripts/systems/test_bot_ballistics.gd

var BotPlayerScript: GDScript
var BotDifficultyScript: GDScript
var arena: Node3D
var failures: Array[String] = []
var started := false
const FAR := Vector3(0.0, 0.0, 35.0) # on the field (the bot motor clamps to it); arena colliders are switched off
const TARGET_SRC := "extends StaticBody3D\nvar hits := 0\nvar bounces := 0\nfunc on_paintball_break(_p, _s):\n\thits += 1\nfunc on_paintball_bounce(_p):\n\tbounces += 1\n"

func _initialize() -> void:
	BotPlayerScript = load("res://scripts/bots/bot_player.gd")
	BotDifficultyScript = load("res://scripts/bots/bot_difficulty.gd")
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

func _make_target() -> StaticBody3D:
	var gd := GDScript.new()
	gd.source_code = TARGET_SRC
	gd.reload()
	var t := StaticBody3D.new()
	t.set_script(gd)
	t.name = "BallisticsTarget"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	t.add_child(cs)
	var torso := Node3D.new()
	torso.name = "Hitbox_Torso"
	torso.position = Vector3(0, 1.15, 0) # aim point = torso + 0.15 = 1.30 m, chest
	t.add_child(torso)
	arena.add_child(t)
	return t

func _run() -> void:
	await _frames(4)
	Engine.time_scale = 1.0
	var PB: Node = root.get_node("PaintBallistics")
	var m: Node = arena.call("start_solo_ffa", {"bots": 1, "tier": "amateur", "kills_to_win": 99})
	var bot: Node3D = (m.get("bots") as Array)[0]
	bot.set_physics_process(false)
	var player := arena.get_node_or_null("Player3D") as Node3D
	if player != null:
		player.set_physics_process(false)
		player.global_position = Vector3(0, -50, -400) # out of every line here
	# a clean range: switch off every arena collider (bunkers, net, floor) so only the target can stop a ball
	var off := 0
	for c in arena.find_children("*", "CollisionObject3D", true, false):
		if c != bot and not bot.is_ancestor_of(c) and c != player and (player == null or not player.is_ancestor_of(c)):
			(c as CollisionObject3D).collision_layer = 0
			off += 1
	print("    %d arena colliders off" % off)
	await _frames(2)

	print("[1] launch speed matches PaintBallistics.spawn_paintball")
	var spd: float = bot.call("ball_speed_mps")
	var tol: float = 5.5 * PB.FPS_TO_MPS * 0.68 + 0.01
	var worst := 0.0
	for i in 20:
		PB.spawn_paintball(FAR + Vector3(0, 30, 0), Vector3.FORWARD, float(bot.get("muzzle_fps")), bot)
		worst = maxf(worst, absf((PB.projectiles[PB.projectiles.size() - 1]["velocity"] as Vector3).length() - spd))
	_check(worst <= tol, "bot predicts %.2f m/s, real balls within %.2f m/s (chrono +/-%.2f)" % [spd, worst, tol])
	PB.clear_all()

	print("[2] solver lands its own simulated ball on the aim point")
	var dt: float = BotPlayerScript.ball_dt()
	var prev_pitch := -90.0
	var solver_ok := true
	for r in [5.0, 10.0, 20.0, 30.0, 40.0]:
		var o := Vector3(0, 1.5, 0)
		var tgt := Vector3(r * 0.6, 1.3, -r * 0.8)
		var sol: Dictionary = BotPlayerScript.ballistic_aim_dir(o, tgt, spd, dt)
		var d: Vector3 = sol["dir"]
		var flat := Vector3(tgt.x - o.x, 0, tgt.z - o.z)
		var land: Dictionary = BotPlayerScript.simulate_ball(o, d, spd, flat.normalized(), flat.length(), dt)
		var miss := (land["pos"] as Vector3).distance_to(tgt)
		var pitch := rad_to_deg(asin(d.y))
		var naive_drop := (tgt - o).normalized().y
		print("    %4.0f m: pitch %+.2f deg (straight line %+.2f), flight %.3f s, sim miss %.3f m" % [r, pitch, rad_to_deg(asin(naive_drop)), float(sol["t"]), miss])
		if miss > 0.03 or pitch <= prev_pitch:
			solver_ok = false
		prev_pitch = pitch
	_check(solver_ok, "simulated miss < 3 cm at 5..40 m and launch pitch rises with range")
	var o30 := Vector3(0, 1.5, 0)
	var t30 := Vector3(0, 1.3, -30)
	var straight: Dictionary = BotPlayerScript.simulate_ball(o30, (t30 - o30).normalized(), spd, Vector3.FORWARD, 30.0, dt)
	var drop30 := t30.y - (straight["pos"] as Vector3).y
	_check(drop30 > 0.8, "control: aiming straight at a chest 30 m out lands %.2f m low (below the chest) - why the bots must compensate" % drop30)

	print("[3] Amateur, zero aim error + zero spread, stationary target, real balls")
	var target := _make_target()
	var am: Resource = BotDifficultyScript.make("amateur")
	am.set("aim_error_at_20m", 0.0)
	bot.set("difficulty", am)
	bot.set("base_spread_deg", 0.0)
	var ranges := {10.0: 8, 20.0: 8, 30.0: 6}
	var audit := {"n": 0, "bad": 0}
	for r in ranges:
		var res: Dictionary = await _volley(bot, target, r, 10, audit)
		_check(int(res["hits"]) >= int(ranges[r]), "Amateur @ %d m: %d/10 breaks on the chest target (+%d bounces), mean impact %.2f m off the chest point" % [int(r), int(res["hits"]), int(res["bounces"]), float(res["mean_off"])])

	print("[4] lead on a moving target (velocity x flight time x lead_factor)")
	var mover := CharacterBody3D.new()
	mover.name = "Mover"
	arena.add_child(mover)
	mover.global_position = FAR + Vector3(0, 0, -20)
	bot.global_position = FAR
	mover.velocity = Vector3(4.0, 0, 0)
	bot.set("current_target", mover)
	bot.set("burst_kind", "snap")
	bot.set("aim_offset", Vector3.ZERO)
	for tier in ["amateur", "rookie"]:
		bot.set("difficulty", BotDifficultyScript.make(tier))
		var sol: Dictionary = bot.call("shot_solution", bot.call("eye_position"))
		var still: Vector3 = BotPlayerScript.aim_points_of(mover)[1]
		var led: float = (sol["impact"] as Vector3).x - still.x
		var want: float = 4.0 * float(sol["t"]) * float(bot.get("difficulty").get("lead_factor"))
		_check(absf(led - want) < 0.06, "%s leads %.2f m (4 m/s x %.3f s x %.2f = %.2f)" % [tier, led, float(sol["t"]), float(bot.get("difficulty").get("lead_factor")), want])
	mover.queue_free()

	print("[5] Rookie (real aim error + real spread), stationary target @ 20 m")
	bot.set("difficulty", BotDifficultyScript.make("rookie"))
	bot.set("base_spread_deg", load("res://scripts/player/movement_rules.gd").SPREAD_BASE_DEG_SPEEDBALL)
	var n := 100
	var rk: Dictionary = await _volley(bot, target, 20.0, n, audit, true)
	var rate := float(rk["hits"]) / float(n)
	print("    ROOKIE_HIT_RATE_20M %d/%d = %.0f%%" % [int(rk["hits"]), n, rate * 100.0])
	_check(rate >= 0.15, "Rookie @ 20 m: %d/%d breaks (%.0f%%), +%d bounces, mean impact %.2f m off" % [int(rk["hits"]), n, rate * 100.0, int(rk["bounces"]), float(rk["mean_off"])])
	_check(int(audit["n"]) > 0 and int(audit["bad"]) == 0, "all %d ballistic shots left inside the %d deg fire cone (%d outside)" % [int(audit["n"]), 10, int(audit["bad"])])

	arena.call("stop_solo_ffa")
	await _frames(2)
	if failures.is_empty():
		print("BOT BALLISTICS TEST: ALL PASSED")
		quit(0)
	else:
		print("BOT BALLISTICS TEST: FAILED ", failures)
		quit(1)

## Fires `n` single-ball bursts from the bot at the target `r` m away (target facing a random side each time so the
## bot has to turn a little), waits for every ball to land. new_burst_each -> a fresh aim error sample per shot.
func _volley(bot: Node3D, target: StaticBody3D, r: float, n: int, audit: Dictionary, _new_burst_each := true) -> Dictionary:
	var PB: Node = root.get_node("PaintBallistics")
	PB.clear_all()
	target.set("hits", 0)
	target.set("bounces", 0)
	bot.global_position = FAR
	target.global_position = FAR + Vector3(0, 0, -r)
	bot.set("yaw", 0.0)
	bot.rotation.y = 0.0
	await _frames(2)
	var impacts := []
	var fired := 0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var guard := 0
	while fired < n and guard < n * 400:
		guard += 1
		bot.set("current_target", target)
		bot.set("burst_pause", 0.0)
		if int(bot.get("burst_left")) <= 0:
			bot.call("_start_burst", "snap")
			bot.set("burst_left", 1)
			bot.set("shot_cd", 0.0)
		var before: int = int(bot.get("shots_fired"))
		bot.call("_tick_fire", dt)
		bot.call("_motor", dt)
		bot.call("_pose", dt)
		if int(bot.get("shots_fired")) > before:
			fired += 1
			impacts.append(bot.get("last_shot_impact"))
			audit["n"] = int(audit["n"]) + 1
			if rad_to_deg((bot.get("last_shot_body_fwd") as Vector3).angle_to(bot.get("last_shot_dir"))) >= 10.0:
				audit["bad"] = int(audit["bad"]) + 1
			await _frames(3) # a few real ticks between balls
	if fired < n:
		print("    (fired %d/%d: waits %d, no-los %d, dropped %d, pose_w %.2f, aim err %.1f, eliminated %s)" % [fired, n, int(bot.get("shots_waited_for_turn")), int(bot.get("shots_blocked_no_los")), int(bot.get("bursts_dropped_unaligned")), float(bot.get("_aim_pose_w")), float(bot.call("aim_error_deg_to", target.global_position + Vector3(0, 1.3, 0))), str(bot.get("is_eliminated"))])
	await _frames(90) # 1.5 s: every ball has landed or flown past
	var tp: Array = BotPlayerScript.aim_points_of(target)
	var chest: Vector3 = tp[tp.size() - 1]
	var off := 0.0
	for p in impacts:
		off += (p as Vector3).distance_to(chest)
	return {"hits": int(target.get("hits")), "bounces": int(target.get("bounces")), "mean_off": off / maxf(1.0, impacts.size())}
