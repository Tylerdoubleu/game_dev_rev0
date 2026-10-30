extends SceneTree
## v0.5.0 tuning test: slower deliberate movement + movement-driven shot spread (rewards bunker play).
## Checks speeds/accel ramps, slide & dive distances, PB-16 pocket entry + Shift breakaway, measured spread cones per
## state (pocket/crouch tightest, sprint >= 3x standing), spread recovery timing, bracket accuracy ordering,
## that the paintball actually spawned flies along the spread shot direction, the slide/dive fire lock, and the
## tower ramp walk-up (walking and sprinting).
## Run: godot --headless --path . -s scripts/systems/test_sprint_tuning.gd

var C: Dictionary = {}
const OLD := {"walk": 6.2, "sprint": 10.4, "crouch": 3.6, "prone": 1.85, "slide": 17.5, "dive": 19.5}

var arena: Node
var player: CharacterBody3D
var failures: Array[String] = []
var report := {}
var dt := 1.0 / 60.0

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	_run.call_deferred()

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _find_player(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.has_method("get_shot_spread_deg"):
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p != null:
			return p
	return null

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch_slide", "prone_dive", "fire_primary"]:
		Input.action_release(a)

func _place(pos: Vector3, yaw: float) -> void:
	_release_all()
	player.global_position = pos
	player.rotation.y = yaw
	player.set("yaw", yaw)
	player.set("pitch", 0.0)
	player.velocity = Vector3.ZERO
	player.set("ground_speed", 0.0)
	player.set("bunker_pocket_weight", 0.0)
	player.set("slide_timer", 0.0)
	player.set("dive_timer", 0.0)
	player.set("movement_fire_recovery_timer", 0.0)
	player.set("stance", 0)

func _hspeed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

## Find a straight lane with no obstacles at body height so speed measurements aren't polluted by collisions.
func _clear_lane(len_m: float) -> Array:
	var space := (player as CharacterBody3D).get_world_3d().direct_space_state
	for x in [-44.0, 44.0, -38.0, 38.0, -32.0, 32.0, -20.0, 20.0, -12.0, 12.0]:
		for z0 in [30.0, 20.0, 10.0]:
			var ok := true
			for h in [0.3, 0.9, 1.5]:
				for dx in [-0.4, 0.0, 0.4]:
					var q := PhysicsRayQueryParameters3D.create(Vector3(x + dx, h, z0), Vector3(x + dx, h, z0 - len_m))
					q.exclude = [player.get_rid()]
					if not space.intersect_ray(q).is_empty():
						ok = false
			var fq := PhysicsRayQueryParameters3D.create(Vector3(x, 2.0, z0), Vector3(x, -1.0, z0))
			var floor_hit := space.intersect_ray(fq)
			if ok and not floor_hit.is_empty() and absf(float(floor_hit["position"].y)) < 0.2:
				return [Vector3(x, 0.1, z0), 0.0] # yaw 0 -> forward is -Z
	return []

## Hold the given actions, return [steady speed, seconds to reach 95% of target].
func _measure_gait(actions: Array, target: float, hold_frames: int) -> Array:
	var lane := _clear_lane(16.0)
	_place(lane[0], lane[1])
	await _frames(3)
	for a in actions:
		Input.action_press(a)
	var t95 := -1.0
	for i in hold_frames:
		await physics_frame
		if t95 < 0.0 and float(player.get("ground_speed")) >= target * 0.95:
			t95 = (i + 1) * dt
	var spd := _hspeed()
	_release_all()
	await _frames(2)
	return [spd, t95]

## Like _measure_gait, but yaws the player so the local input direction runs straight down the cleared -Z lane.
func _measure_gait_dir(actions: Array, local_dir: Vector2, target: float, hold_frames: int) -> Array:
	var lane := _clear_lane(16.0)
	var d := local_dir.normalized()
	_place(lane[0], atan2(d.x, -d.y))
	await _frames(3)
	for a in actions:
		Input.action_press(a)
	await _frames(hold_frames)
	var spd := _hspeed()
	_release_all()
	await _frames(2)
	return [spd, 0.0]

func _sample_cone(n: int) -> Array:
	# Fire n shots (rate limiter + paint bypassed) at the CURRENT smoothed spread; return [max deg, mean deg].
	var yaw0: float = player.get("yaw")
	var pitch0: float = player.get("pitch")
	var maxd := 0.0
	var sum := 0.0
	for i in n:
		player.set("time_since_last_shot", 10.0)
		player.set("hopper_paint", 500)
		player.call("_fire_single_paintball", root.get_node("GearRuleEnforcer").get("active_bracket"))
		var b: Vector3 = player.get("last_shot_base_dir")
		var d: Vector3 = player.get("last_shot_dir")
		var ang := rad_to_deg(b.angle_to(d))
		maxd = maxf(maxd, ang)
		sum += ang
		player.set("yaw", yaw0)
		player.set("pitch", pitch0)
		player.rotation.y = yaw0
	return [maxd, sum / float(n)]

func _run() -> void:
	await _frames(5)
	root.get_node("NetworkLobby").call("select_map", "woodsball_crash")
	await _frames(5)
	player = _find_player(arena)
	C = player.get_script().get_script_constant_map()
	var gre := root.get_node("GearRuleEnforcer")
	gre.call("set_active_bracket", "speedball")
	var gm := root.get_node("GameManager")
	gm.set("breakout_horn_sounded", true)
	player.set("breakout_boost_timer", 0.0)
	player.set("breakout_penalty_timer", 0.0)
	player.set("lobby_open", false)
	player.set("awaiting_respawn_choice", false)

	print("--- Movement speeds (before -> after) ---")
	_check(float(C["SPRINT_SPEED"]) <= OLD["sprint"] * 0.85 and float(C["SPRINT_SPEED"]) >= OLD["sprint"] * 0.75, "Sprint %.2f -> %.2f m/s (%.0f%% slower, target 15-25%%)" % [OLD["sprint"], float(C["SPRINT_SPEED"]), 100.0 * (1.0 - float(C["SPRINT_SPEED"]) / OLD["sprint"])])
	_check(float(C["WALK_SPEED"]) < OLD["walk"] and float(C["WALK_SPEED"]) >= OLD["walk"] * 0.85, "Walk %.2f -> %.2f m/s (slightly slower)" % [OLD["walk"], float(C["WALK_SPEED"])])
	var walk: Array = await _measure_gait(["move_forward"], float(C["WALK_SPEED"]), 60)
	_check(absf(walk[0] - float(C["WALK_SPEED"])) < 0.1, "Measured walk %.2f m/s" % walk[0])
	_check(walk[1] > 0.1 and walk[1] < 0.3, "Walk ramp 0 -> 95%% in %.2fs" % walk[1])
	var sprint: Array = await _measure_gait(["move_forward", "sprint"], float(C["SPRINT_SPEED"]), 90)
	_check(absf(sprint[0] - float(C["SPRINT_SPEED"])) < 0.1, "Measured sprint %.2f m/s" % sprint[0])
	_check(sprint[1] >= 0.35 and sprint[1] <= 0.7, "Sprint ramp 0 -> 95%% in %.2fs (was instant)" % sprint[1])
	var strafe: Array = await _measure_gait(["move_right", "sprint"], float(C["SPRINT_SPEED"]), 90)
	_check(absf(strafe[0] - float(C["SPRINT_SPEED"])) < 0.4, "Measured sprint-strafe %.2f m/s (strafe = same gait speeds)" % strafe[0])
	var crouch: Array = await _measure_gait(["move_forward", "crouch_slide"], float(C["CROUCH_SPEED"]), 60)
	_check(absf(crouch[0] - float(C["CROUCH_SPEED"])) < 0.1, "Measured crouch-walk %.2f m/s (was %.2f)" % [crouch[0], OLD["crouch"]])
	var prone: Array = await _measure_gait(["move_forward", "prone_dive"], float(C["PRONE_SPEED"]), 60)
	_check(absf(prone[0] - float(C["PRONE_SPEED"])) < 0.1, "Measured prone crawl %.2f m/s (was %.2f)" % [prone[0], OLD["prone"]])
	report["speeds"] = {"walk": walk, "sprint": sprint, "strafe": strafe, "crouch": crouch, "prone": prone}

	print("--- v0.6 back-pedal (50% of forward for the same stance / sprint state) ---")
	var PS: Script = player.get_script()
	var wk := float(C["WALK_SPEED"])
	var sp := float(C["SPRINT_SPEED"])
	var bm := float(C["BACKPEDAL_SPEED_MULT"])
	_check(is_equal_approx(bm, 0.5), "BACKPEDAL_SPEED_MULT is 0.5")
	var diag := Vector2(1.0, 1.0).normalized()
	_check(is_equal_approx(float(PS.call("backpedal_speed_factor", Vector2(0, 1))), 0.5), "Pure S factor 0.5x")
	_check(is_equal_approx(float(PS.call("backpedal_speed_factor", Vector2(1, 0))), 1.0) and is_equal_approx(float(PS.call("backpedal_speed_factor", Vector2(-1, 0))), 1.0), "Pure strafe factor 1.0x")
	_check(is_equal_approx(float(PS.call("backpedal_speed_factor", Vector2(0, -1))), 1.0), "Forward factor 1.0x")
	_check(absf(float(PS.call("backpedal_speed_factor", diag)) - (1.0 - 0.5 * diag.y)) < 0.001, "Back-diagonal factor %.3fx (proportional to the back component %.3f)" % [float(PS.call("backpedal_speed_factor", diag)), diag.y])
	_check(absf(float(PS.call("backpedal_speed_factor", Vector2(1.0, -1.0).normalized())) - 1.0) < 0.001, "Forward-diagonal unaffected")
	for st in [[0, wk, "standing"], [1, float(C["CROUCH_SPEED"]), "crouch"], [2, float(C["PRONE_SPEED"]), "prone"]]:
		_check(is_equal_approx(float(PS.call("gait_target_speed", Vector2(0, 1), false, st[0])), st[1] * 0.5), "%s back-pedal target = 50%% of %s forward (%.2f)" % [st[2], st[2], st[1] * 0.5])
	_check(is_equal_approx(float(PS.call("gait_target_speed", Vector2(0, 1), true, 0)), wk * 0.5), "Sprint + pure S = walking back-pedal %.2f (no sprint speed)" % (wk * 0.5))
	_check(is_equal_approx(float(PS.call("gait_target_speed", Vector2(1, 0), true, 0)), sp), "Sprint strafe keeps full sprint speed")
	_check(float(PS.call("gait_target_speed", diag, true, 0)) < float(PS.call("gait_target_speed", Vector2(1, 0), false, 0)), "Sprint back-diagonal %.2f is slower than a plain walk-strafe" % float(PS.call("gait_target_speed", diag, true, 0)))
	var bp := {}
	for g in [["back", ["move_back"], Vector2(0, 1), wk * 0.5], ["back_sprint", ["move_back", "sprint"], Vector2(0, 1), wk * 0.5],
			["back_crouch", ["move_back", "crouch_slide"], Vector2(0, 1), float(C["CROUCH_SPEED"]) * 0.5],
			["back_diag", ["move_back", "move_right"], diag, wk * (1.0 - 0.5 * diag.y)],
			["back_diag_sprint", ["move_back", "move_right", "sprint"], diag, float(PS.call("gait_target_speed", diag, true, 0))],
			["strafe_walk", ["move_left"], Vector2(-1, 0), wk]]:
		var m: Array = await _measure_gait_dir(g[1], g[2], float(g[3]), 75)
		bp[g[0]] = m[0]
		_check(absf(m[0] - float(g[3])) < 0.12, "Measured %s %.2f m/s (target %.2f)" % [g[0], m[0], g[3]])
	report["backpedal"] = bp

	print("--- Knee-slide / Superman dive distance ---")
	for mv in ["crouch_slide", "prone_dive"]:
		var lane := _clear_lane(20.0)
		_place(lane[0], lane[1])
		await _frames(2)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _frames(45)
		var p0 := player.global_position
		Input.action_press(mv)
		await _frames(2)
		var tn := "slide_timer" if mv == "crouch_slide" else "dive_timer"
		var guard := 0
		while float(player.get(tn)) > 0.0 and guard < 120:
			await physics_frame
			guard += 1
		var dist := Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
		var lo := 5.0 if mv == "crouch_slide" else 5.5
		_check(dist >= lo and dist <= 9.0, "%s covers %.2f m (sensible bunker-to-bunker gap)" % ["Knee-slide" if mv == "crouch_slide" else "Superman dive", dist])
		report[mv] = dist
		_release_all()
		await _frames(30)

	print("--- PB-16 pocket entry, spread per state ---")
	# Home_BackCenter rigid timber (0,0,38): walk in from the open side, let the pocket latch.
	_place(Vector3(0.0, 0.1, 42.0), 0.0)
	await _frames(2)
	Input.action_press("move_forward")
	var latched := false
	for i in 120:
		await physics_frame
		if float(player.get("bunker_pocket_weight")) > 0.25:
			latched = true
			break
	_release_all()
	await _frames(40)
	_check(latched and float(player.get("bunker_pocket_weight")) > 0.25, "Walking into Home_BackCenter latches the PB-16 bunker pocket (weight %.2f)" % float(player.get("bunker_pocket_weight")))
	var pocket_deg: float = player.call("get_shot_spread_deg")
	var pocket_cone: Array = _sample_cone(300)

	# Shift breakaway (Shift + move away) still pops you out of the pocket
	Input.action_press("move_back")
	Input.action_press("sprint")
	await _frames(20)
	_check(float(player.get("bunker_pocket_weight")) <= 0.25, "Shift + move away breaks out of the pocket")
	_release_all()

	var lane2 := _clear_lane(16.0)
	_place(lane2[0], lane2[1])
	await _frames(40)
	var stand_deg: float = player.call("get_shot_spread_deg")
	var stand_cone: Array = _sample_cone(300)
	Input.action_press("crouch_slide")
	await _frames(40)
	var crouch_deg: float = player.call("get_shot_spread_deg")
	var crouch_cone: Array = _sample_cone(300)
	_release_all()
	await _frames(10)
	Input.action_press("move_forward")
	await _frames(40)
	var walk_deg: float = player.call("get_shot_spread_deg")
	var walk_cone: Array = _sample_cone(300)
	_release_all()
	_place(lane2[0], lane2[1])
	await _frames(2)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	var sprint_deg: float = player.call("get_shot_spread_deg")
	var sprint_cone: Array = _sample_cone(300)

	# The spawned paintball travels along the spread shot_dir (same vector broadcast to the network).
	var balls := root.get_node("PaintBallistics")
	var projs: Array = balls.get("projectiles")
	var last_v: Vector3 = (projs[projs.size() - 1] as Dictionary)["velocity"]
	var shot_d: Vector3 = player.get("last_shot_dir")
	_check(rad_to_deg(last_v.normalized().angle_to(shot_d)) < 0.01, "Spawned paintball velocity follows the spread shot_dir (angle %.4f deg)" % rad_to_deg(last_v.normalized().angle_to(shot_d)))

	# Recovery: release at full sprint, time until the cone is back to standing-tight
	_release_all()
	var rec_t := -1.0
	for i in 90:
		await physics_frame
		if float(player.get("shot_spread_mult")) <= float(C["SPREAD_MULT_STANDING"]) + 0.01:
			rec_t = (i + 1) * dt
			break
	_check(rec_t >= 0.3 and rec_t <= 0.5, "Sprint -> stop: spread recovers to standing-tight in %.2fs (target 0.3-0.5s)" % rec_t)
	# Re-sprint then crouch-stop: recovery into the tighter crouch cone
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	_release_all()
	Input.action_press("crouch_slide")
	var rec_c := -1.0
	for i in 90:
		await physics_frame
		if float(player.get("shot_spread_mult")) <= float(C["SPREAD_MULT_CROUCH"]) + 0.01:
			rec_c = (i + 1) * dt
			break
	_check(rec_c >= 0.3 and rec_c <= 0.55, "Sprint -> crouch settle: spread recovers in %.2fs" % rec_c)
	_release_all()
	await _frames(30)

	print("    state      cone deg (live)   measured max / mean")
	for row in [["pocket", pocket_deg, pocket_cone], ["crouch", crouch_deg, crouch_cone], ["standing", stand_deg, stand_cone], ["walk", walk_deg, walk_cone], ["sprint", sprint_deg, sprint_cone]]:
		print("    %-9s  %.3f             %.3f / %.3f" % [row[0], row[1], row[2][0], row[2][1]])
	_check(pocket_cone[0] < crouch_cone[0] and crouch_cone[0] < stand_cone[0] and stand_cone[0] < walk_cone[0] and walk_cone[0] < sprint_cone[0], "Measured cone ordering pocket < crouch < standing < walk < sprint")
	_check(sprint_cone[0] >= 3.0 * stand_cone[0] and sprint_cone[0] <= 5.5 * stand_cone[0], "Sprint cone %.2fx the stationary cone (target 3-5x)" % (sprint_cone[0] / stand_cone[0]))
	_check(sprint_cone[0] <= sprint_deg + 0.01 and sprint_cone[0] >= sprint_deg * 0.9, "Sprint shots stay inside the live cone (max %.3f vs %.3f)" % [sprint_cone[0], sprint_deg])

	print("--- Bracket accuracy ---")
	var base := {}
	for b in ["speedball", "woodsball", "pump"]:
		gre.call("set_active_bracket", b)
		base[b] = float(player.call("get_bracket_base_spread_deg"))
	print("    base cone: ", base)
	_check(base["pump"] < base["woodsball"] and base["woodsball"] < base["speedball"], "Pump is most accurate, then woodsball, then speedball")
	gre.call("set_active_bracket", "speedball")

	print("--- Slide / dive fire lock still active ---")
	for mv in ["crouch_slide", "prone_dive"]:
		var lane3 := _clear_lane(20.0)
		_place(lane3[0], lane3[1])
		await _frames(2)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _frames(40)
		var spawned0: int = int(balls.get("total_spawned"))
		var paint0: int = int(player.get("hopper_paint"))
		Input.action_press(mv)
		await _frames(2)
		while bool(player.call("is_fire_locked_by_movement")):
			player.set("time_since_last_shot", 10.0)
			player.call("_handle_trigger_press", false)
			await physics_frame
		_check(int(balls.get("total_spawned")) == spawned0 and int(player.get("hopper_paint")) == paint0, "%s: 0 paintballs, 0 paint while locked" % mv)
		_release_all()
		player.set("time_since_last_shot", 10.0)
		player.call("_handle_trigger_press", false)
		_check(int(balls.get("total_spawned")) == spawned0 + 1, "%s: next pull after recovery fires" % mv)
		await _frames(20)

	print("--- Tower ramp walk-up ---")
	var deck_top: float = GrittyArtTheme.TOWER_DECK_TOP
	for gait in [["move_forward"], ["move_forward", "sprint"]]:
		_place(Vector3(-25.0 + 1.1, 0.2, 10.4), 0.0)
		await _frames(2)
		for a in gait:
			Input.action_press(a)
		await _frames(720)
		var y := player.global_position.y
		_release_all()
		_check(y > deck_top - 0.15, "West tower ramp %s reaches the deck (y %.2f, deck %.2f)" % ["walk" if gait.size() == 1 else "sprint", y, deck_top])
		await _frames(5)

	if failures.is_empty():
		print("=== [PASS] v0.5.0 slower movement + sprint shot spread ===")
		quit(0)
	else:
		print("=== [FAIL] %d sprint-tuning checks failed ===" % failures.size())
		for f in failures:
			print("   - ", f)
		quit(1)
