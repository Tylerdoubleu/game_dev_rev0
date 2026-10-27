extends SceneTree

func _initialize() -> void:
	print("=== Running Paintball Prototype v0.1.2-playtest Headless Verification ===")
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

	enforcer.set_active_bracket("woodsball")
	assert(enforcer.active_bracket.hopper_capacity == 15, "Woodsball 40%-reduced hopper should be 15")
	enforcer.set_active_bracket("pump")
	assert(enforcer.active_bracket.hopper_capacity == 6, "Pump 40%-reduced hopper should be 6")
	enforcer.set_active_bracket("speedball")
	assert(enforcer.active_bracket.hopper_capacity == 24, "Speedball 40%-reduced hopper should be 24")

	ballistics.spawn_paintball(Vector3(0, 1.5, 10), Vector3(0, 0, -1), 290.0, null)
	assert(ballistics.projectiles.size() == 1, "Paintball should be spawned in PaintBallistics")

	print("=== All Prototype v0.1.2-playtest Smoke Checks PASSED ===")
	quit(0)
	return true
