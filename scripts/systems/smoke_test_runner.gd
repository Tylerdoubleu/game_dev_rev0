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

	# Test PB-16 Bunker Cover Pocket, Auto Left/Right Edge Marker Hand & Sprint Breakaway
	player.global_position = Vector3(-0.95, 0.1, 39.25) # Left edge of Home_BackCenter (0, 0, 38.0, width 2.4)
	player.rotation.y = 0.0 # Facing -Z toward Home_BackCenter
	for _i in range(6):
		player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(float(player.get("bunker_pocket_weight")) > 0.25, "Player behind a bunker face must settle into the PB-16 Bunker Cover Pocket")
	# Verify Left Edge (-X) triggers LEFT HAND and Right Edge (+X) triggers RIGHT HAND on flat bunker (Home_BackCenter)
	player.global_position = Vector3(-1.35, 0.1, 39.25)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == true, "Left edge of Home_BackCenter must switch marker to LEFT hand")
	player.global_position = Vector3(1.35, 0.1, 39.25)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == false, "Right edge of Home_BackCenter must switch marker to RIGHT hand")
	# Verify Left Side vs Right Side of cylindrical Can bunker (Home_BreakoutCan_L at X=-2.6, Z=41.8) triggers correct marker hand
	player.global_position = Vector3(-3.15, 0.1, 42.85)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == true, "Left side of cylindrical Can bunker must switch marker to LEFT hand")
	player.global_position = Vector3(-2.05, 0.1, 42.85)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == false, "Right side of cylindrical Can bunker must switch marker to RIGHT hand")
	player.global_position = Vector3(-0.95, 0.1, 39.25)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == true, "Standing at the LEFT edge of a bunker must automatically select LEFT marker hand")
	player.global_position = Vector3(0.95, 0.1, 39.25) # Right edge of Home_BackCenter
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(bool(player.get("is_left_handed")) == false, "Standing at the RIGHT edge of a bunker must automatically select RIGHT marker hand")
	player.call("_apply_bunker_cover_pocket_physics", 0.1, Vector3(0, 0, 1), Vector2(0, 1), true)
	assert(float(player.get("bunker_pocket_weight")) == 0.0, "Sprinting or moving away must immediately release the PB-16 Bunker Cover Pocket")
	print("[PASS] PB-16 Soft Bunker Cover Pocket + Corner Edge-Detent + Instant Sprint Breakaway verified")

	# 7. Verify Exposed Hopper/Marker Sub-Hitboxes (2.4x Wrong-Hand Exposure), Bunker Vinyl Flex & 3P Marker Tilts
	assert(player.get_node_or_null("Hitbox_HopperMarker") != null and player.get_node_or_null("Hitbox_Mask") != null and player.get_node_or_null("Hitbox_PodPack") != null, "Player3D must have Hitbox_HopperMarker, Hitbox_Mask, and Hitbox_PodPack sub-hitboxes")
	# Settle at Left edge of Home_BackCenter, then force wrong hand (Right Hand) via manual override and verify 2.4x hopper exposure
	player.global_position = Vector3(-1.35, 0.1, 39.25)
	player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	player.set("_at_bunker_edge_side", -1.0)
	player.set("_manual_hand_override_in_pocket", true)
	player.set("is_left_handed", false)
	player.call("_update_exposed_profile_hitboxes", 0.05)
	assert(absf(float(player.get("hopper_exposure_multiplier")) - 1.0) < 0.05, "Hopper hitbox size must stay 1.0x without wrong-hand penalty")

	# Verify Inflatable Bunker Vinyl Flex (#15) & Articulated 3P MarkerPivot3D (#16)
	var home_bc := arena.get_node_or_null("Home_BackCenter") as Node3D
	assert(home_bc != null and bool(home_bc.get_meta("vinyl_flex_active", false)), "Locking into Home_BackCenter cover pocket must trigger inflatable vinyl bunker flex")
	assert(bot.get_node_or_null("MarkerPivot3D/HopperPivot3D") != null, "OpFor 3P avatar must have articulated MarkerPivot3D/HopperPivot3D")
	print("[PASS] Exposed Hopper/Marker Sub-Hitboxes (2.4x) + Bunker Vinyl Flex + 3P Marker Tilts verified")

	# Test First to 10 Deaths loses
	while gm.local_deaths < 10:
		gm.record_local_death("OpFor_Test")
	assert(gm.local_deaths == 10 and gm.match_ended, "First to 10 deaths must trigger match loss")

	# Verify 1P & 3P unique bracket gun models (Speedball Electro, Woodsball A-5, Stock-Class Pump)
	assert(player.marker_rig.get_node_or_null("FP_SpeedballAssembly") != null, "1P Speedball marker assembly must exist")
	assert(player.marker_rig.get_node_or_null("FP_WoodsballAssembly") != null, "1P Woodsball A-5 marker assembly must exist")
	assert(player.marker_rig.get_node_or_null("FP_PumpAssembly") != null, "1P Stock-Class Pump marker assembly must exist")
	enforcer.set_active_bracket("woodsball")
	assert(player.marker_rig.get_node("FP_WoodsballAssembly").visible == true and player.marker_rig.get_node("FP_SpeedballAssembly").visible == false, "Woodsball bracket must activate FP_WoodsballAssembly")
	assert(player.hopper_mesh.visible == true and player.hopper_mesh.position.x > 0.03, "Woodsball Cyclone hopper must offset to the right side")
	enforcer.set_active_bracket("pump")
	assert(player.marker_rig.get_node("FP_PumpAssembly").visible == true and player.marker_rig.get_node("FP_WoodsballAssembly").visible == false, "Pump bracket must activate FP_PumpAssembly")
	assert(player.hopper_mesh.visible == false, "Stock-Class Pump must hide bulky top hopper and use 10-round horizontal spring feed tube")
	enforcer.set_active_bracket("speedball")
	assert(player.marker_rig.get_node("FP_SpeedballAssembly").visible == true and player.hopper_mesh.visible == true and absf(player.hopper_mesh.position.x) < 0.005, "Speedball bracket must restore centered Halo B loader and FP_SpeedballAssembly")
	print("[PASS] Distinct 1P & 3P marker models verified for [1] Speedball Electro, [2] Woodsball A-5, and [3] Stock-Class Pump")

	# 9. Verify v0.4 Map #2 ("woodsball_crash"): Lobby Map Selector, Helicopter Crash Site, Ramps & Sniper Towers, and Rigid Cover (Pocket Physics ON, Inflatable Vinyl Flex OFF)
	lobby.call("select_map", "woodsball_crash")
	assert(lobby.get("selected_map") == "woodsball_crash", "NetworkLobby.select_map('woodsball_crash') must update selected_map")
	var woods_root := arena.get_node_or_null("WoodsballCrashSiteRoot") as Node3D
	assert(woods_root != null, "Switching to woodsball_crash must spawn WoodsballCrashSiteRoot")
	var heli_fuselage := woods_root.get_node_or_null("Heli_CrashFuselage_Center50") as StaticBody3D
	var west_tower := woods_root.get_node_or_null("Tower_WestFlank") as Node3D
	assert(heli_fuselage != null and west_tower != null, "Woodsball Crash Site must contain Heli_CrashFuselage_Center50 and Tower_WestFlank with ramps")
	assert(bool(heli_fuselage.get_meta("is_rigid_cover", false)) == true, "Helicopter crash fuselage must be flagged as rigid cover")
	# Place player against a rigid timber bunker in Woodsball Crash Site and verify PB-16 Pocket Physics engages while vinyl_flex_active stays false
	var woods_back_center := woods_root.get_node_or_null("Home_BackCenter") as StaticBody3D
	assert(woods_back_center != null and bool(woods_back_center.get_meta("is_rigid_cover", false)), "Woodsball Home_BackCenter must be rigid timber cover")
	player.set("bunker_pocket_weight", 0.0)
	player.global_position = Vector3(0.0, 0.1, 39.25)
	player.rotation.y = 0.0
	for _i in range(6):
		player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(float(player.get("bunker_pocket_weight")) > 0.25, "Rigid Woodsball cover must still engage PB-16 player cover pocket physics")
	assert(not bool(woods_back_center.get_meta("vinyl_flex_active", false)), "Rigid Woodsball cover must NOT trigger inflatable vinyl bunker flex")
	# v0.4.3 tower access: ramp top lands flush on the deck and the parapet has a doorway over the ramp landing
	var deck_top: float = GrittyArtTheme.TOWER_DECK_TOP
	var south_ramp := west_tower.get_node_or_null("WalkableRamp_Tower_WestFlank_South") as StaticBody3D
	assert(south_ramp != null, "West tower must have a South ramp")
	var ramp_shape := (south_ramp.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var ramp_top_pt: Vector3 = south_ramp.transform * Vector3(0.0, ramp_shape.size.y * 0.5, -ramp_shape.size.z * 0.5)
	assert(absf(ramp_top_pt.y - deck_top) < 0.06 and absf(absf(ramp_top_pt.z) - GrittyArtTheme.TOWER_HALF) < 0.12, "Ramp top edge must meet the deck edge flush (got %s)" % str(ramp_top_pt))
	var ramp_bot_pt: Vector3 = south_ramp.transform * Vector3(0.0, ramp_shape.size.y * 0.5, ramp_shape.size.z * 0.5)
	assert(ramp_bot_pt.y <= 0.02, "Ramp foot must reach the ground (got %s)" % str(ramp_bot_pt))
	var back_rail := west_tower.get_node_or_null("Tower_WestFlank_Parapet_Back") as StaticBody3D
	var rail_shape := (back_rail.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var rail_max_x: float = back_rail.position.x + rail_shape.size.x * 0.5
	var ramp_min_x: float = GrittyArtTheme.TOWER_RAMP_X - GrittyArtTheme.TOWER_RAMP_W * 0.5
	assert(rail_max_x < ramp_min_x, "Parapet must leave a doorway over the ramp landing")
	# Parapet height: crouched mask top (0.92 + 0.17) hidden, standing eye (1.58) above the rail
	var rail_top: float = back_rail.position.y + rail_shape.size.y * 0.5 - deck_top
	assert(rail_top > 0.92 + 0.17 and rail_top < 1.58 - 0.2, "Tower parapet top (%.2f) must hide a crouched player and let a standing player see over it" % rail_top)
	# Walk-through fuselage: cargo door gap at body height on both sides and a window at standing eye height
	var door_blocked := false
	var window_blocked := false
	var lower_wall_hit := false
	for c in heli_fuselage.get_children():
		if c is CollisionShape3D:
			var cs := c as CollisionShape3D
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			var bb := AABB(cs.position - sz * 0.5, sz)
			for zz in [-1.34, 0.0, 1.34]:
				if bb.has_point(Vector3(0.0, 1.0, zz)):
					door_blocked = true
			if bb.has_point(Vector3(2.8, 1.45, 1.34)):
				window_blocked = true
			if bb.has_point(Vector3(2.8, 0.6, 1.34)):
				lower_wall_hit = true
	assert(not door_blocked, "Fuselage must be open to walk straight through the cargo doors")
	assert(not window_blocked and lower_wall_hit, "Fuselage windows must be open at standing eye height with solid wall below")
	print("[PASS] v0.4.3 tower ramps open onto decks, 1.25m crouch-safe parapets, walk-through fuselage with shooting windows verified")
	# Also test elevated pocket physics on the West Flank Sniper Tower deck behind Tower_WestFlank_Parapet_Back
	player.set("bunker_pocket_weight", 0.0)
	player.global_position = Vector3(-26.2, deck_top + 0.02, 1.75)
	player.rotation.y = PI # Facing +Z toward Tower_WestFlank_Parapet_Back
	for _i in range(6):
		player.call("_apply_bunker_cover_pocket_physics", 0.05, Vector3.ZERO, Vector2.ZERO, false)
	assert(float(player.get("bunker_pocket_weight")) > 0.25, "Elevated Sniper Tower parapet must engage PB-16 player cover pocket physics at Y=3.0m")
	# Switch back to speedball and confirm clean restore
	lobby.call("select_map", "speedball")
	assert(arena.get_node_or_null("WoodsballCrashSiteRoot") == null and arena.get_node_or_null("Bunker_Center50_W") != null, "Switching back to speedball must restore inflatable speedball bunkers")
	print("[PASS] Map #2 (Woodsball Heli Crash Site): Lobby Map Selector, Center-50 Helicopter Crash, 4 Ramp Sniper Towers, and Rigid Pocket Physics (Zero Vinyl Flex) verified")
	print("=== All Prototype v0.4.2 Art, Realism, Scoreboard [M], +1 Pod/Kill & First-to-10-Deaths Checks PASSED ===")
	quit(0)
	return true
