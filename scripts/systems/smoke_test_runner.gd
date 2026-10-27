extends SceneTree

func _initialize() -> void:
	print("=== Running Paintball Prototype v0.2.2 Gritty 2000s Art, Realism & Multiplayer Rules Verification ===")
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	assert(packed != null, "Failed to load speedball_arena_01.tscn")
	var arena := packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	var enforcer := root.get_node_or_null("GearRuleEnforcer")
	var ballistics := root.get_node_or_null("PaintBallistics")
	var gm := root.get_node_or_null("GameManager")
	var lobby := root.get_node_or_null("NetworkLobby")
	assert(enforcer != null and ballistics != null and gm != null and lobby != null, "Missing autoload singletons")

	# 1. Verify PB-08 40%-reduced ammo capacities remain intact
	enforcer.set_active_bracket("woodsball")
	assert(enforcer.active_bracket.hopper_capacity == 15, "Woodsball 40%-reduced hopper should be 15")
	enforcer.set_active_bracket("pump")
	assert(enforcer.active_bracket.hopper_capacity == 6, "Pump 40%-reduced hopper should be 6")
	enforcer.set_active_bracket("speedball")
	assert(enforcer.active_bracket.hopper_capacity == 24, "Speedball 40%-reduced hopper should be 24")

	# 2. Verify Overcast Stadium Environment & Outer-Perimeter Netting
	var arena := current_scene
	var world_env := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_env != null and world_env.environment != null, "WorldEnvironment must exist")
	var props := arena.get_node_or_null("GrittyStadiumProps")
	assert(props != null, "GrittyStadiumProps container must exist")
	var net_root := props.get_node_or_null("PerimeterSafetyNetting")
	assert(net_root != null, "Perimeter safety netting must exist")
	for child in net_root.get_children():
		if child is Node3D:
			var p: Vector3 = child.position
			assert(abs(p.x) >= 53.5 or abs(p.z) >= 65.5, "Safety net element must be on outer perimeter: " + str(p))

	# 3. Verify Shaped Bunker Colliders
	var dorito_col := arena.get_node_or_null("Home_Dorito_1/CollisionShape3D") as CollisionShape3D
	assert(dorito_col != null and dorito_col.shape is ConvexPolygonShape3D, "Dorito bunker must use ConvexPolygonShape3D")
	var can_col := arena.get_node_or_null("Home_MidCan_L/CollisionShape3D") as CollisionShape3D
	assert(can_col != null and (can_col.shape is CapsuleShape3D or can_col.shape is CylinderShape3D), "Can bunker must use CapsuleShape3D/CylinderShape3D")

	# 4. Verify Wrapped Decal Paint Splatters & Flight Uncertainty
	ballistics.spawn_paintball(Vector3(0, 1.5, 10), Vector3(0, 0, -1), 290.0, null)
	assert(ballistics.projectiles.size() == 1, "Paintball should be spawned in PaintBallistics")
	assert(ballistics.projectiles[0].has("spin_drift"), "Paintball must include per-shot Magnus/seam spin_drift")
	ballistics._spawn_splat(Vector3(0, 1.0, 0), Vector3(0, 0, 1), Color(0.96, 0.16, 0.58))
	assert(ballistics.splat_nodes.size() >= 1 and ballistics.splat_nodes[0] is Decal, "Paint splat must be a wrapped Decal node")

	# 5. Verify v0.2.2 Opening Menu NPC Presence, Scoreboard [M], +1 Pod per Kill, Respawn at Original Spot, and First-to-10-Deaths
	var lobby_ui := arena.get_node_or_null("TournamentLobbyOverlay") as CanvasLayer
	var scoreboard_ui := arena.get_node_or_null("ScoreboardOverlay") as CanvasLayer
	assert(lobby_ui != null and scoreboard_ui != null, "TournamentLobbyOverlay and ScoreboardOverlay [M] must exist")
	assert(InputMap.has_action("toggle_scoreboard"), "InputMap must bind [M] to toggle_scoreboard")

	var player := arena.get_node_or_null("Player3D") as CharacterBody3D
	var bot := arena.get_node_or_null("OpFor_Snake50") as StaticBody3D
	assert(player != null and bot != null, "Player3D and OpFor_Snake50 must exist")

	# Test +1 Pod reward on kill
	var start_pods: int = int(player.get("pods_remaining"))
	bot.call("on_paintball_break", bot.global_position, player)
	assert(int(player.get("pods_remaining")) == start_pods + 1, "Eliminating an enemy must grant +1 extra pod of paintballs")
	assert(gm.local_kills == 1, "GameManager.local_kills must increment on kill")

	# Test Respawn at Original Starting Spot on hit + Death tracking
	player.global_position = Vector3(12.0, 0.1, 15.0)
	player.call("on_paintball_break", player.global_position, bot)
	assert(gm.local_deaths == 1, "GameManager.local_deaths must increment when hit by an enemy")
	assert(player.global_position.distance_to(player.get("initial_spawn_pos")) < 0.05, "Player must respawn at original starting spot on hit")

	# Test First to 10 Deaths loses
	for _i in range(9):
		gm.record_local_death("OpFor_Test")
	assert(gm.local_deaths == 10 and gm.match_ended, "First to 10 deaths must trigger match loss")

	print("=== All Prototype v0.2.2 Art, Realism, Scoreboard [M], +1 Pod/Kill & First-to-10-Deaths Checks PASSED ===")
	quit(0)
	return true
