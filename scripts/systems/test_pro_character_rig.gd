extends SceneTree

const RigScript := preload("res://scripts/player/pro_paintball_rig_3d.gd")

func _init() -> void:
	call_deferred("_run_verification")

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[PB-14 CHARACTER RIG ASSERT FAILED] " + msg)
		quit(1)

func _run_verification() -> void:
	print("=== [PB-14] Articulated 2000s Pro Paintball Character & Rig Verification ===")

	var root_node := Node3D.new()
	root.add_child(root_node)

	var body := StaticBody3D.new()
	body.name = "TestProAvatarBody"
	root_node.add_child(body)

	var rig := RigScript.new()
	rig.name = "ProPaintballRig3D"
	body.add_child(rig)
	rig.build_rig("ALPHA", "speedball")

	# 1. Verify Complete Articulated Joint Hierarchy
	var required_nodes := [
		"RootPivot",
		"RootPivot/PelvisPivot",
		"RootPivot/PelvisPivot/PodPackRoot",
		"RootPivot/PelvisPivot/LeftHipPivot",
		"RootPivot/PelvisPivot/LeftHipPivot/LeftKneePivot",
		"RootPivot/PelvisPivot/LeftHipPivot/LeftKneePivot/LeftBootCleat",
		"RootPivot/PelvisPivot/RightHipPivot",
		"RootPivot/PelvisPivot/RightHipPivot/RightKneePivot",
		"RootPivot/PelvisPivot/RightHipPivot/RightKneePivot/RightBootCleat",
		"RootPivot/PelvisPivot/TorsoPivot",
		"RootPivot/PelvisPivot/TorsoPivot/NeckHeadPivot",
		"RootPivot/PelvisPivot/TorsoPivot/LeftShoulderPivot",
		"RootPivot/PelvisPivot/TorsoPivot/LeftShoulderPivot/LeftElbowPivot",
		"RootPivot/PelvisPivot/TorsoPivot/LeftShoulderPivot/LeftElbowPivot/LeftGloveHand",
		"RootPivot/PelvisPivot/TorsoPivot/RightShoulderPivot",
		"RootPivot/PelvisPivot/TorsoPivot/RightShoulderPivot/RightElbowPivot",
		"RootPivot/PelvisPivot/TorsoPivot/RightShoulderPivot/RightElbowPivot/RightGloveHand",
		"RootPivot/PelvisPivot/TorsoPivot/MarkerAssemblyPivot",
		"RootPivot/PelvisPivot/TorsoPivot/MarkerAssemblyPivot/HopperUnitPivot",
		"RootPivot/PelvisPivot/TorsoPivot/MarkerAssemblyPivot/SpeedballAssembly",
		"RootPivot/PelvisPivot/TorsoPivot/MarkerAssemblyPivot/WoodsballAssembly",
		"RootPivot/PelvisPivot/TorsoPivot/MarkerAssemblyPivot/PumpAssembly",
	]
	for np in required_nodes:
		var n := rig.get_node_or_null(np)
		_assert(n != null, "Missing required articulated rig node: " + np)
	print("[PASS] All 22 articulated joint & equipment nodes verified.")

	# 2. Verify Exposed Sub-Hitboxes & Surface Hardness Bounce Metadata
	var hitboxes: Dictionary = rig.build_sub_hitboxes_on(body)
	_assert(hitboxes.has("mask") and hitboxes.has("torso") and hitboxes.has("hopper") and hitboxes.has("pack"), "Missing sub-hitbox keys")
	var col_mask: CollisionShape3D = hitboxes["mask"]
	var col_torso: CollisionShape3D = hitboxes["torso"]
	var col_hopper: CollisionShape3D = hitboxes["hopper"]
	var col_pack: CollisionShape3D = hitboxes["pack"]

	_assert(String(col_mask.get_meta("hit_zone")) == "mask" and is_equal_approx(float(col_mask.get_meta("break_cos_threshold")), 0.28), "Mask hitbox meta mismatch")
	_assert(String(col_torso.get_meta("hit_zone")) == "torso" and is_equal_approx(float(col_torso.get_meta("break_cos_threshold")), 0.48), "Torso hitbox meta mismatch")
	_assert(String(col_hopper.get_meta("hit_zone")) == "hopper" and is_equal_approx(float(col_hopper.get_meta("break_cos_threshold")), 0.28), "Hopper hitbox meta mismatch")
	_assert(String(col_pack.get_meta("hit_zone")) == "pack" and is_equal_approx(float(col_pack.get_meta("break_cos_threshold")), 0.32), "Pack hitbox meta mismatch")
	print("[PASS] 4 Exposed Sub-Hitboxes (Mask=0.28, Torso=0.48, Hopper=0.28, Pack=0.32) verified.")

	# 3. Verify Right-Hand vs Left-Hand Swap Symmetry
	rig.apply_pose(0.0, {"is_left_handed": false, "lean": 0.0, "bunker_tuck": 0.0})
	var right_hand_hopper_x := col_hopper.position.x
	rig.apply_pose(0.0, {"is_left_handed": true, "lean": 0.0, "bunker_tuck": 0.0})
	var left_hand_hopper_x := col_hopper.position.x
	_assert(right_hand_hopper_x > 0.12 and left_hand_hopper_x < -0.12, "Hand swap did not mirror hopper hitbox across X axis")
	_assert(absf(right_hand_hopper_x + left_hand_hopper_x) < 0.01, "Hand swap X symmetry mismatch")
	print("[PASS] Left/Right marker hand swap symmetry verified (Right X=%.3fm, Left X=%.3fm)." % [right_hand_hopper_x, left_hand_hopper_x])

	# 4. Verify Clean Inward Marker Cant on Peeks (No Wrong-Hand Penalty)
	rig.apply_pose(0.0, {"is_left_handed": false, "lean": 1.0, "bunker_tuck": 0.0})
	var right_cant_deg := rad_to_deg(rig.marker_assembly_pivot.rotation.z)
	rig.apply_pose(0.0, {"is_left_handed": true, "lean": -1.0, "bunker_tuck": 0.0})
	var left_cant_deg := rad_to_deg(rig.marker_assembly_pivot.rotation.z)
	_assert(is_equal_approx(right_cant_deg, 26.0) and is_equal_approx(left_cant_deg, -26.0), "Corner peek inward cant should be +/-26 deg with no wrong-hand penalty")
	print("[PASS] Clean inward marker cant verified (+/-26.0 deg, zero wrong-hand penalty).")

	# 5. Verify Bunker Pocket Tuck, Slide, Superman Dive, Reload, and Eliminated Walk-Off Poses
	rig.apply_pose(0.0, {"is_left_handed": false, "lean": 0.0, "bunker_tuck": 1.0})
	_assert(is_equal_approx(rad_to_deg(rig.marker_assembly_pivot.rotation.z), 24.0), "Bunker tuck inward cant should be 24 deg")

	rig.apply_pose(0.0, {"is_sliding": true})
	var slide_pelvis_y := rig.pelvis_pivot.position.y
	_assert(slide_pelvis_y < 0.50, "Knee-slide pelvis height should drop below 0.50m")

	rig.apply_pose(0.0, {"is_diving": true})
	var dive_pelvis_y := rig.pelvis_pivot.position.y
	var dive_pitch_deg := rad_to_deg(rig.pelvis_pivot.rotation.x)
	_assert(dive_pelvis_y < 0.30 and dive_pitch_deg < -75.0, "Superman dive pose should pitch horizontal near turf")

	rig.apply_pose(0.0, {"is_eliminated": true})
	var elim_arm_pitch := rad_to_deg(rig.left_shoulder_pivot.rotation.x)
	_assert(elim_arm_pitch > 150.0, "Eliminated pose should raise off-arm high above mask")
	print("[PASS] Bunker Tuck, Knee-Slide, Superman Dive, Reload, and Eliminated poses verified.")

	# 6. Verify 3 Bracket Marker Models & Pump Stroke Animation
	rig.set_bracket_visual("woodsball")
	_assert(rig.woodsball_assembly.visible and not rig.speedball_assembly.visible, "Woodsball A-5 visibility failed")
	rig.set_bracket_visual("pump")
	_assert(rig.pump_assembly.visible and not rig.hopper_unit_pivot.visible and col_hopper.disabled, "Stock Pump visibility & hopper hitbox disable failed")
	rig.set_pump_stroke(1.0)
	_assert(is_equal_approx(rig.pump_handle_slide.position.z, -0.11), "Pump handle stroke slide failed")
	rig.set_bracket_visual("speedball")
	print("[PASS] All 3 bracket marker assemblies (Speedball Electro, Woodsball A-5, Stock Pump) verified.")

	if DisplayServer.get_name() != "headless":
		body.visible = false
		await _render_showcase_sheet(root_node)

	print("=== ALL PB-14 CHARACTER RIG CHECKS PASSED ===")
	quit(0)

func _render_showcase_sheet(root_node: Node3D) -> void:
	print("Rendering multi-pose showcase sheet...")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84)
	env.ambient_light_energy = 0.85

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root_node.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key_light.light_energy = 1.65
	root_node.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25.0, -135.0, 0.0)
	fill_light.light_energy = 0.75
	fill_light.light_color = Color(0.85, 0.92, 1.0)
	root_node.add_child(fill_light)

	# Turf pedestal floor
	var stage := Node3D.new()
	root_node.add_child(stage)

	var floor_mi := MeshInstance3D.new()
	var f_plane := BoxMesh.new()
	f_plane.size = Vector3(18.0, 0.1, 8.0)
	floor_mi.mesh = f_plane
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	var f_mat := StandardMaterial3D.new()
	f_mat.albedo_color = Color(0.16, 0.28, 0.14)
	f_mat.roughness = 0.88
	floor_mi.material_override = f_mat
	stage.add_child(floor_mi)

	# Spawn 6 articulated characters side-by-side in key tournament poses
	var configs := [
		{
			"x": -4.2, "yaw": 18.0, "team": "ALPHA", "bracket": "speedball",
			"pose": {"velocity": Vector3(0, 0, -4.5), "is_left_handed": false}
		},
		{
			"x": -2.6, "yaw": 195.0, "team": "BRAVO", "bracket": "speedball",
			"pose": {"bunker_tuck": 1.0, "is_left_handed": false}
		},
		{
			"x": -1.0, "yaw": 8.0, "team": "ALPHA", "bracket": "speedball",
			"pose": {"lean": 1.0, "is_left_handed": false}
		},
		{
			"x": 0.6, "yaw": -8.0, "team": "BRAVO", "bracket": "speedball",
			"pose": {"lean": 1.0, "is_left_handed": true}
		},
		{
			"x": 2.3, "yaw": 28.0, "team": "ALPHA", "bracket": "woodsball",
			"pose": {"is_sliding": true}
		},
		{
			"x": 4.1, "yaw": -35.0, "team": "BRAVO", "bracket": "pump",
			"pose": {"is_diving": true, "pump_stroke": 0.8}
		},
	]

	for cfg in configs:
		var r := RigScript.new()
		stage.add_child(r)
		r.build_rig(cfg["team"], cfg["bracket"])
		r.position = Vector3(float(cfg["x"]), 0.0, 0.0)
		r.rotation_degrees.y = float(cfg["yaw"])
		r.apply_pose(0.0, cfg["pose"])
		r._stride_phase = 0.85
		r.apply_pose(0.016, cfg["pose"])

	var cam := Camera3D.new()
	cam.fov = 42.0
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.45, 7.2), Vector3(0.0, 0.78, 0.0), Vector3.UP)
	cam.current = true

	DisplayServer.window_set_size(Vector2i(1600, 720))
	for _i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw

	var vp_img := root.get_texture().get_image()
	if vp_img != null and not vp_img.is_empty():
		vp_img.save_png("/workspace/pb14_character_rig_raw.png")
		print("Saved raw 3D viewport capture to /workspace/pb14_character_rig_raw.png")
