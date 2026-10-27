extends SceneTree

func _initialize() -> void:
	print("=== Running Paintball Prototype v0.2 Gritty 2000s Art Overhaul Verification ===")
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

	# 2. Verify Overcast Stadium Environment, Floodlights, Netting, Scoreboard & Wooden Spools
	var arena := current_scene
	var world_env := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_env != null and world_env.environment != null, "WorldEnvironment must exist")
	assert(world_env.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemapping should be active")
	assert(world_env.environment.fog_enabled, "Overcast stadium fog should be enabled")

	var props := arena.get_node_or_null("GrittyStadiumProps")
	assert(props != null, "GrittyStadiumProps container must exist")
	assert(props.get_node_or_null("PerimeterSafetyNetting") != null, "Perimeter safety netting must exist")
	assert(props.get_node_or_null("TournamentScoreboard") != null, "Tournament scoreboard must exist")
	assert(props.get_node_or_null("StadiumFloodlightTower_0") != null, "Floodlight towers must exist")
	assert(props.get_node_or_null("WoodSpool_BreakoutRight") != null, "Wooden cable spools must exist")

	# 3. Verify Muddy Turf & Scuffed Vinyl Bunker Materials
	var turf_mesh := arena.get_node_or_null("TurfFloor/TurfFloorMesh") as MeshInstance3D
	assert(turf_mesh != null and turf_mesh.material_override is StandardMaterial3D, "TurfFloorMesh must have StandardMaterial3D")
	var turf_mat := turf_mesh.material_override as StandardMaterial3D
	assert(turf_mat.albedo_texture != null and turf_mat.normal_texture != null, "Turf material must have muddy albedo & normal textures")

	var center_bunker_mesh := arena.get_node_or_null("Bunker_Center50_W/BunkerMesh") as MeshInstance3D
	assert(center_bunker_mesh != null and center_bunker_mesh.material_override is StandardMaterial3D, "Bunker must have scuffed vinyl material")
	var vinyl_mat := center_bunker_mesh.material_override as StandardMaterial3D
	assert(vinyl_mat.albedo_texture != null and vinyl_mat.normal_texture != null, "Vinyl material must have scuffed textures")

	# 4. Verify Weathered First-Person Marker ViewModel & Pressure Gauge
	var player := arena.get_node_or_null("Player3D")
	assert(player != null, "Player3D must exist")
	var gauge := player.get_node_or_null("HeadPivot/FirstPersonCamera/MarkerViewModel/MarkerPressureGauge")
	var barrel := player.get_node_or_null("HeadPivot/FirstPersonCamera/MarkerViewModel/MarkerBarrel")
	var glove := player.get_node_or_null("HeadPivot/FirstPersonCamera/MarkerViewModel/TacticalGloveGrip")
	assert(gauge != null and barrel != null and glove != null, "Weathered marker must include pressure gauge, barrel, and tactical glove")

	# 5. Verify Glossy Oily Paintball, Splat Decal & Mist Burst VFX
	ballistics.spawn_paintball(Vector3(0, 1.5, 10), Vector3(0, 0, -1), 290.0, null)
	assert(ballistics.projectiles.size() == 1, "Paintball should be spawned in PaintBallistics")
	var ball_node := ballistics.projectiles[0]["node"] as MeshInstance3D
	var ball_mat := ball_node.material_override as StandardMaterial3D
	assert(ball_mat.roughness <= 0.15 and ball_mat.clearcoat_enabled, "Paintball must use glossy oily clearcoat material")

	ballistics._spawn_splat(Vector3(0, 1.0, 0), Vector3(0, 0, 1), Color(0.96, 0.16, 0.58))
	assert(ballistics.splat_nodes.size() >= 1, "Oily paint splat decal must be created")
	assert(ballistics.mist_burst_count >= 1, "Airborne paint mist burst must be triggered on break")

	print("=== All Prototype v0.2 Gritty 2000s Art Overhaul Smoke Checks PASSED ===")
	quit(0)
	return true
