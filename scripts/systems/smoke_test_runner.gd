extends SceneTree

func _initialize() -> void:
	print("=== Running Paintball Prototype v0.2.1 Gritty 2000s Art & Realism Verification ===")
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	assert(packed != null, "Failed to load speedball_arena_01.tscn")
	var arena := packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	var enforcer := root.get_node_or_null("GearRuleEnforcer")
	var ballistics := root.get_node_or_null("PaintBallistics")
	var gm := root.get_node_or_null("GameManager")
	assert(enforcer != null and ballistics != null and gm != null, "Missing autoload singletons")

	# 1. Verify PB-08 40%-reduced ammo capacities remain intact
	enforcer.set_active_bracket("woodsball")
	assert(enforcer.active_bracket.hopper_capacity == 15, "Woodsball 40%-reduced hopper should be 15")
	enforcer.set_active_bracket("pump")
	assert(enforcer.active_bracket.hopper_capacity == 6, "Pump 40%-reduced hopper should be 6")
	enforcer.set_active_bracket("speedball")
	assert(enforcer.active_bracket.hopper_capacity == 24, "Speedball 40%-reduced hopper should be 24")

	# 2. Verify Overcast Stadium Environment (ACES, SSAO, SSR, Fog) & Outer-Perimeter Netting
	var arena := current_scene
	var world_env := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_env != null and world_env.environment != null, "WorldEnvironment must exist")
	assert(world_env.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemapping should be active")
	assert(world_env.environment.ssao_enabled and world_env.environment.ssr_enabled, "SSAO and SSR should be enabled for v0.2.1 realism")

	var props := arena.get_node_or_null("GrittyStadiumProps")
	assert(props != null, "GrittyStadiumProps container must exist")
	var net_root := props.get_node_or_null("PerimeterSafetyNetting")
	assert(net_root != null, "Perimeter safety netting must exist")
	for child in net_root.get_children():
		if child is Node3D:
			var p: Vector3 = child.position
			assert(abs(p.x) >= 53.5 or abs(p.z) >= 65.5, "Safety net element must be on outer perimeter, not cutting through map: " + str(p))

	# 3. Verify Shaped Bunker Colliders (Dorito ConvexPolygonShape3D, Can CylinderShape3D, Snake CapsuleShape3D)
	var dorito_col := arena.get_node_or_null("Home_Dorito_1/CollisionShape3D") as CollisionShape3D
	assert(dorito_col != null and dorito_col.shape is ConvexPolygonShape3D, "Dorito bunker must use form-fitting ConvexPolygonShape3D")
	var can_col := arena.get_node_or_null("Home_MidCan_L/CollisionShape3D") as CollisionShape3D
	assert(can_col != null and can_col.shape is CylinderShape3D, "Can bunker must use form-fitting CylinderShape3D")
	var snake_col := arena.get_node_or_null("Snake_Beam_Home1/CollisionShape3D") as CollisionShape3D
	assert(snake_col != null and snake_col.shape is CapsuleShape3D, "Snake beam must use form-fitting CapsuleShape3D")

	# 4. Verify Wrapped Decal Paint Splatters & Flight Uncertainty (Spin Drift)
	ballistics.spawn_paintball(Vector3(0, 1.5, 10), Vector3(0, 0, -1), 290.0, null)
	assert(ballistics.projectiles.size() == 1, "Paintball should be spawned in PaintBallistics")
	assert(ballistics.projectiles[0].has("spin_drift"), "Paintball must include per-shot Magnus/seam spin_drift")

	ballistics._spawn_splat(Vector3(0, 1.0, 0), Vector3(0, 0, 1), Color(0.96, 0.16, 0.58))
	assert(ballistics.splat_nodes.size() >= 1 and ballistics.splat_nodes[0] is Decal, "Paint splat must be a wrapped Decal node")
	assert(ballistics.mist_burst_count >= 1, "Airborne paint mist burst must be triggered on break")

	print("=== All Prototype v0.2.1 Gritty 2000s Art & Realism Smoke Checks PASSED ===")
	quit(0)
	return true
