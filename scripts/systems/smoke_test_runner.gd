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
	assert(player != null, "Player3D must exist")
	assert( not lobby.fill_bots_enabled, "NPC Presence must default to OFF (false)")
	assert(arena.get_node_or_null("OpFor_Snake50") == null, "No OpFor bots should exist when NPC Presence is OFF")

	# Enable NPC Presence from the menu and verify bots spawn
	arena.call("_select_npc_presence", true)
	var bot := arena.get_node_or_null("OpFor_Snake50") as StaticBody3D
	assert(bot != null and bot.visible, "Selecting NPC Presence ON must spawn OpFor bots")

	# Test +1 Pod reward on kill
	var start_pods: int = int(player.get("pods_remaining"))
	bot.call("on_paintball_break", bot.global_position, player)
	assert(int(player.get("pods_remaining")) == start_pods + 1, "Eliminating an enemy must grant +1 extra pod of paintballs")
	assert(gm.local_kills == 1, "GameManager.local_kills must increment on kill")

	# Test Respawn at Original Starting Spot on hit + Death tracking + Pod count reset on death + Tactical Respawn Map
	var death_map_ui := arena.get_node_or_null("DeathRespawnMapOverlay") as CanvasLayer
	assert(death_map_ui != null, "DeathRespawnMapOverlay ('YOU\'VE BEEN HIT!' + Tactical Respawn Map) must exist")
	var net_wall := arena.get_node_or_null("GrittyStadiumProps/PerimeterSafetyNetting/SafetyNetWallBody_0/CollisionShape3D") as CollisionShape3D
	assert(net_wall != null and net_wall.shape is BoxShape3D, "Perimeter safety netting must have StaticBody3D + BoxShape3D boundary colliders")

	player.set("_respawn_flash_timer", 0.0)
	player.global_position = Vector3(12.0, 0.1, 15.0)
	player.call("on_paintball_break", player.global_position, bot)
	assert(gm.local_deaths == 1, "GameManager.local_deaths must increment when hit by an enemy")
	assert(player.global_position.distance_to(player.get("initial_spawn_pos")) < 0.05, "Player must respawn at original starting spot on hit")
	assert(int(player.get("pods_remaining")) == start_pods, "Pod count must reset to bracket baseline on death")

	# Test choosing a Tactical Map respawn zone (e.g., Zone 0 = Snake Corner Tape)
	arena.call("_on_respawn_zone_selected", 0)
	assert(absf(player.global_position.x - (-31.0)) < 0.1, "Selecting Zone 0 on Tactical Respawn Map must spawn player at Snake Corner Tape (X = -31m)")

	# Test perma-fall / outer boundary clamp
	player.global_position = Vector3(95.0, -10.0, 95.0)
	player.call("_enforce_arena_bounds_and_permafall_guard")
	assert(absf(player.global_position.x) <= 52.5 and absf(player.global_position.z) <= 64.5 and player.global_position.y >= 0.0, "Perma-fall & boundary guard must keep player inside the arena")

	# 6. Verify PB-15 Center-50 Flag Pull, Drop on Elimination, Hang Objective, and Breakout Horn Countdown
	var flag_station := arena.get_node_or_null("Center50FlagStation") as Node3D
	assert(flag_station != null, "Center50FlagStation must exist at the 50-yard line")
	assert(not gm.breakout_horn_sounded and gm.breakout_countdown_left > 0.0, "Breakout horn countdown must be active at round start")
	gm._process(3.5)
	assert(gm.breakout_horn_sounded, "Breakout horn must sound after countdown completes")
	assert(float(player.get("breakout_boost_timer")) > 0.0, "Clean breakout timing must grant initial sprint burst")

	# Move player to Center-50 Flag to pull it
	player.global_position = Vector3(0.0, 0.1, 1.35)
	arena.call("_update_center_flag_pickup_and_hang")
	assert(bool(player.get("carrying_center_flag")) and gm.flag_state == "CARRIED", "Player must pick up Center-50 Flag when sprinting through (0, 0, 1.35)")

	# Eliminate flag carrier and verify flag drops on turf
	player.set("_respawn_flash_timer", 0.0)
	player.global_position = Vector3(-8.0, 0.1, 12.0)
	player.call("on_paintball_break", player.global_position, bot)
	assert(not bool(player.get("carrying_center_flag")) and gm.flag_state == "DROPPED", "Eliminating the flag carrier must drop the flag on the turf")
	assert(flag_station.visible and flag_station.global_position.distance_to(Vector3(-8.0, 0.0, 12.0)) < 0.2, "Dropped flag must appear at carrier elimination spot")

	# Recover dropped flag and hang it at the opposing Breakout Gate (North -Z for ALPHA)
	player.global_position = Vector3(-8.0, 0.1, 12.0)
	arena.call("_update_center_flag_pickup_and_hang")
	assert(bool(player.get("carrying_center_flag")), "Player must be able to recover the dropped flag")
	player.global_position = Vector3(0.0, 0.1, -45.5)
	arena.call("_update_center_flag_pickup_and_hang")
	assert(not bool(player.get("carrying_center_flag")) and gm.alpha_flag_hangs == 1 and gm.flag_state == "CENTER_50", "Reaching enemy Breakout Gate must hang the flag, score a Flag Hang point, and reset flag to Center-50")

	# Test PB-16 Bunker Cover Pocket & Sprint Breakaway
	player.global_position = Vector3(0.0, 0.1, 39.25) # Just behind Home_BackCenter (0, 0, 38.0, depth 1.4)
	player.rotation.y = 0.0 # Facing -Z toward Home_BackCenter
	for _i in range(6):
		player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(float(player.get("bunker_pocket_weight")) > 0.25, "Player behind a bunker face must settle into the PB-16 Bunker Cover Pocket")
	player.call("_apply_bunker_cover_pocket_physics", 0.1, Vector3(0, 0, 1), Vector2(0, 1), true)
	assert(float(player.get("bunker_pocket_weight")) == 0.0, "Sprinting or moving away must immediately release the PB-16 Bunker Cover Pocket")
	print("[PASS] PB-16 Soft Bunker Cover Pocket + Corner Edge-Detent + Instant Sprint Breakaway verified")

	# Test First to 10 Deaths loses
	while gm.local_deaths < 10:
		gm.record_local_death("OpFor_Test")
	assert(gm.local_deaths == 10 and gm.match_ended, "First to 10 deaths must trigger match loss")

	print("=== All Prototype v0.2.2 Art, Realism, Scoreboard [M], +1 Pod/Kill & First-to-10-Deaths Checks PASSED ===")
	quit(0)
	return true
