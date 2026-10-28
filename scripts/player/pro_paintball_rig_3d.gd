class_name ProPaintballRig3D
extends Node3D

## Articulated 2000s Pro Paintball Character Model & Procedural Animation Rig (PB-14 / Issue #16).
## Self-contained Node3D hierarchy that can be dropped into RemotePlayerAvatar, SnapTargetBot,
## or local 3P views. Includes procedural joint animation, 3 bracket marker assemblies
## (Speedball Electro + Halo B + 68/4500 HPA, Woodsball Tippmann A-5, Stock-Class Pump),
## 4+3 lumbar pod harness, and dynamic exposed sub-hitboxes (Mask, Torso, Hopper, Pack/Marker).

@export var team_id: String = "ALPHA"
@export var bracket_id: String = "speedball"

# Articulated Joint Nodes
var root_pivot: Node3D
var pelvis_pivot: Node3D
var pod_pack_root: Node3D
var torso_pivot: Node3D
var neck_head_pivot: Node3D

var left_shoulder_pivot: Node3D
var left_elbow_pivot: Node3D
var left_glove_hand: Node3D

var right_shoulder_pivot: Node3D
var right_elbow_pivot: Node3D
var right_glove_hand: Node3D

var left_hip_pivot: Node3D
var left_knee_pivot: Node3D
var left_boot_cleat: Node3D

var right_hip_pivot: Node3D
var right_knee_pivot: Node3D
var right_boot_cleat: Node3D

var marker_assembly_pivot: Node3D
var speedball_assembly: Node3D
var woodsball_assembly: Node3D
var pump_assembly: Node3D
var pump_handle_slide: Node3D
var hopper_unit_pivot: Node3D
var hopper_lid_pivot: Node3D
var muzzle_tip_node: Node3D
var reload_pod_prop: Node3D

# Materials cached for team switching / hit highlights
var _mat_jersey: StandardMaterial3D
var _mat_pants: StandardMaterial3D
var _mat_mask_shell: StandardMaterial3D
var _mat_visor_chrome: StandardMaterial3D
var _mat_carbon_tank: StandardMaterial3D
var _mat_anodized_marker: StandardMaterial3D
var _mat_dark_metal: StandardMaterial3D
var _mat_olive_drab: StandardMaterial3D
var _mat_hopper_shell: StandardMaterial3D
var _mat_pod_translucent: StandardMaterial3D
var _mat_skin_glove: StandardMaterial3D

# Procedural animation internal state
var _stride_phase: float = 0.0
var _hand_alpha: float = 0.0 # 0.0 = Right-handed (+X), 1.0 = Left-handed (-X)
var _current_lean: float = 0.0
var _current_tuck: float = 0.0
var _current_stance_f: float = 0.0
var _current_slide_alpha: float = 0.0
var _current_dive_alpha: float = 0.0
var _current_reload_alpha: float = 0.0
var _current_elim_alpha: float = 0.0
var _reload_cycle_time: float = 0.0
var _pump_stroke_alpha: float = 0.0
var _is_left_handed_state: bool = false

# Dynamic Sub-Hitboxes dictionary if attached to a CollisionObject3D
var _sub_hitboxes: Dictionary = {}

func _ready() -> void:
	if root_pivot == null:
		build_rig(team_id, bracket_id)

func build_rig(p_team: String = "ALPHA", p_bracket: String = "speedball") -> void:
	team_id = p_team.to_upper()
	bracket_id = p_bracket.to_lower()

	for child in get_children():
		child.queue_free()

	_init_materials()
	_build_joint_hierarchy()
	set_team_visual(team_id)
	set_bracket_visual(bracket_id)
	apply_pose(0.0, {})

func _load_texture_safe(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var tex := load(res_path) as Texture2D
		if tex != null:
			return tex
	# Fallback direct image load if Godot import cache hasn't run yet in headless mode
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _init_materials() -> void:
	_mat_jersey = StandardMaterial3D.new()
	_mat_jersey.roughness = 0.62
	_mat_jersey.metallic = 0.05

	_mat_pants = StandardMaterial3D.new()
	_mat_pants.albedo_color = Color(0.88, 0.88, 0.90)
	_mat_pants.roughness = 0.72
	var pants_tex := _load_texture_safe("res://assets/textures/slide_pants_2004.png")
	if pants_tex != null:
		_mat_pants.albedo_texture = pants_tex

	_mat_mask_shell = StandardMaterial3D.new()
	_mat_mask_shell.albedo_color = Color(0.13, 0.14, 0.16)
	_mat_mask_shell.roughness = 0.42
	_mat_mask_shell.metallic = 0.15

	_mat_visor_chrome = StandardMaterial3D.new()
	_mat_visor_chrome.albedo_color = Color(0.95, 0.68, 0.14)
	_mat_visor_chrome.metallic = 0.92
	_mat_visor_chrome.roughness = 0.08
	_mat_visor_chrome.emission_enabled = true
	_mat_visor_chrome.emission = Color(0.32, 0.20, 0.04)
	_mat_visor_chrome.emission_energy_multiplier = 0.35

	_mat_carbon_tank = StandardMaterial3D.new()
	_mat_carbon_tank.albedo_color = Color(0.90, 0.90, 0.92)
	_mat_carbon_tank.roughness = 0.24
	_mat_carbon_tank.metallic = 0.45
	var tank_tex := _load_texture_safe("res://assets/textures/carbon_hpa_tank.png")
	if tank_tex != null:
		_mat_carbon_tank.albedo_texture = tank_tex

	_mat_anodized_marker = StandardMaterial3D.new()
	_mat_anodized_marker.metallic = 0.86
	_mat_anodized_marker.roughness = 0.20

	_mat_dark_metal = StandardMaterial3D.new()
	_mat_dark_metal.albedo_color = Color(0.16, 0.17, 0.19)
	_mat_dark_metal.metallic = 0.78
	_mat_dark_metal.roughness = 0.28

	_mat_olive_drab = StandardMaterial3D.new()
	_mat_olive_drab.albedo_color = Color(0.27, 0.31, 0.22)
	_mat_olive_drab.metallic = 0.25
	_mat_olive_drab.roughness = 0.62

	_mat_hopper_shell = StandardMaterial3D.new()
	_mat_hopper_shell.albedo_color = Color(0.12, 0.13, 0.15, 0.88)
	_mat_hopper_shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_hopper_shell.roughness = 0.18
	_mat_hopper_shell.metallic = 0.22

	_mat_pod_translucent = StandardMaterial3D.new()
	_mat_pod_translucent.albedo_color = Color(0.92, 0.84, 0.18, 0.82)
	_mat_pod_translucent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_pod_translucent.roughness = 0.20

	_mat_skin_glove = StandardMaterial3D.new()
	_mat_skin_glove.albedo_color = Color(0.18, 0.20, 0.23)
	_mat_skin_glove.roughness = 0.55

func _build_joint_hierarchy() -> void:
	root_pivot = Node3D.new()
	root_pivot.name = "RootPivot"
	add_child(root_pivot)

	pelvis_pivot = Node3D.new()
	pelvis_pivot.name = "PelvisPivot"
	pelvis_pivot.position = Vector3(0.0, 0.88, 0.0)
	root_pivot.add_child(pelvis_pivot)

	# Pelvis / Baggy Tournament Hip Mesh
	var pelvis_mesh := _make_capsule(0.19, 0.34, _mat_pants)
	pelvis_mesh.name = "PelvisMesh"
	pelvis_mesh.rotation.z = deg_to_rad(90.0)
	pelvis_pivot.add_child(pelvis_mesh)

	# 4+3 Tournament Lumbar Pod Pack on Lower Back (+Z)
	_build_pod_pack()

	# Left & Right Legs (Hip -> Knee -> BootCleat)
	left_hip_pivot = _build_leg_chain("Left", -0.135)
	left_knee_pivot = left_hip_pivot.get_node("LeftKneePivot") as Node3D
	left_boot_cleat = left_knee_pivot.get_node("LeftBootCleat") as Node3D

	right_hip_pivot = _build_leg_chain("Right", 0.135)
	right_knee_pivot = right_hip_pivot.get_node("RightKneePivot") as Node3D
	right_boot_cleat = right_knee_pivot.get_node("RightBootCleat") as Node3D

	# Torso Pivot (Baggy 2004 Pro Jersey + Padded Shoulders + Chest Protector)
	torso_pivot = Node3D.new()
	torso_pivot.name = "TorsoPivot"
	torso_pivot.position = Vector3(0.0, 0.08, 0.0)
	pelvis_pivot.add_child(torso_pivot)

	var chest_mesh := _make_capsule(0.225, 0.58, _mat_jersey)
	chest_mesh.name = "BaggyJerseyChest"
	chest_mesh.position = Vector3(0.0, 0.25, 0.0)
	chest_mesh.scale = Vector3(1.12, 1.0, 0.86)
	torso_pivot.add_child(chest_mesh)

	var collar_mesh := _make_cylinder(0.105, 0.12, 0.07, _mat_mask_shell)
	collar_mesh.name = "NeopreneNeckGuard"
	collar_mesh.position = Vector3(0.0, 0.51, 0.0)
	torso_pivot.add_child(collar_mesh)

	# Neck & Head Pivot (JT Proflex-style 2000s Goggle System)
	_build_head_and_mask()

	# Left & Right Arms (Shoulder -> Elbow -> GloveHand)
	left_shoulder_pivot = _build_arm_chain("Left", -0.245)
	left_elbow_pivot = left_shoulder_pivot.get_node("LeftElbowPivot") as Node3D
	left_glove_hand = left_elbow_pivot.get_node("LeftGloveHand") as Node3D

	right_shoulder_pivot = _build_arm_chain("Right", 0.245)
	right_elbow_pivot = right_shoulder_pivot.get_node("RightElbowPivot") as Node3D
	right_glove_hand = right_elbow_pivot.get_node("RightGloveHand") as Node3D

	# Reload Pod Prop in Left Hand (visible during reload)
	reload_pod_prop = _make_cylinder(0.034, 0.034, 0.20, _mat_pod_translucent)
	reload_pod_prop.name = "ReloadPodProp"
	reload_pod_prop.position = Vector3(0.0, -0.04, -0.06)
	reload_pod_prop.rotation.x = deg_to_rad(75.0)
	reload_pod_prop.visible = false
	left_glove_hand.add_child(reload_pod_prop)

	# Marker Assembly Pivot (attached under TorsoPivot so it tracks spine lean/pitch + shoulder swap)
	_build_marker_assemblies()

func _build_pod_pack() -> void:
	pod_pack_root = Node3D.new()
	pod_pack_root.name = "PodPackRoot"
	pod_pack_root.position = Vector3(0.0, 0.06, 0.175)
	pelvis_pivot.add_child(pod_pack_root)

	# Neoprene lumbar belt + harness backplate
	var belt := _make_box(Vector3(0.34, 0.14, 0.08), _mat_mask_shell)
	belt.name = "HarnessBelt"
	pod_pack_root.add_child(belt)

	# 4 vertical 140-round translucent paint pods strapped across the lower back
	var pod_offsets := [-0.115, -0.038, 0.038, 0.115]
	for i in range(pod_offsets.size()):
		var px: float = pod_offsets[i]
		var sleeve := _make_cylinder(0.036, 0.036, 0.15, _mat_mask_shell)
		sleeve.name = "PodSleeve_%d" % i
		sleeve.position = Vector3(px, 0.01, 0.045)
		pod_pack_root.add_child(sleeve)

		var pod := _make_cylinder(0.033, 0.031, 0.22, _mat_pod_translucent)
		pod.name = "PaintPod_%d" % i
		pod.position = Vector3(px, -0.01, 0.045)
		pod_pack_root.add_child(pod)

		var cap := _make_cylinder(0.037, 0.037, 0.025, _mat_pants)
		cap.name = "PodFlipLid_%d" % i
		cap.position = Vector3(px, -0.125, 0.045)
		pod_pack_root.add_child(cap)

func _build_leg_chain(side_prefix: String, hip_x: float) -> Node3D:
	var hip := Node3D.new()
	hip.name = "%sHipPivot" % side_prefix
	hip.position = Vector3(hip_x, -0.04, 0.0)
	pelvis_pivot.add_child(hip)

	# Baggy upper thigh slide pants
	var thigh := _make_capsule(0.105, 0.44, _mat_pants)
	thigh.name = "%sThighMesh" % side_prefix
	thigh.position = Vector3(0.0, -0.20, 0.0)
	hip.add_child(thigh)

	var knee := Node3D.new()
	knee.name = "%sKneePivot" % side_prefix
	knee.position = Vector3(0.0, -0.40, 0.0)
	hip.add_child(knee)

	# Articulated Kevlar Knee Pad
	var knee_pad := _make_box(Vector3(0.13, 0.14, 0.14), _mat_mask_shell)
	knee_pad.name = "%sKevlarKneePad" % side_prefix
	knee_pad.position = Vector3(0.0, -0.02, -0.03)
	knee.add_child(knee_pad)

	# Baggy lower shin pants flaring over cleats
	var shin := _make_capsule(0.095, 0.42, _mat_pants)
	shin.name = "%sShinMesh" % side_prefix
	shin.position = Vector3(0.0, -0.20, 0.0)
	knee.add_child(shin)

	var boot := Node3D.new()
	boot.name = "%sBootCleat" % side_prefix
	boot.position = Vector3(0.0, -0.40, 0.0)
	knee.add_child(boot)

	var cleat_mesh := _make_box(Vector3(0.11, 0.08, 0.24), _mat_mask_shell)
	cleat_mesh.name = "%sCleatShoe" % side_prefix
	cleat_mesh.position = Vector3(0.0, -0.02, -0.04)
	boot.add_child(cleat_mesh)

	return hip

func _build_arm_chain(side_prefix: String, shoulder_x: float) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.name = "%sShoulderPivot" % side_prefix
	shoulder.position = Vector3(shoulder_x, 0.43, 0.0)
	torso_pivot.add_child(shoulder)

	# Baggy jersey upper sleeve
	var upper_arm := _make_capsule(0.078, 0.33, _mat_jersey)
	upper_arm.name = "%sUpperSleeve" % side_prefix
	upper_arm.position = Vector3(0.0, -0.14, 0.0)
	shoulder.add_child(upper_arm)

	var elbow := Node3D.new()
	elbow.name = "%sElbowPivot" % side_prefix
	elbow.position = Vector3(0.0, -0.28, 0.0)
	shoulder.add_child(elbow)

	# Padded forearm + jersey cuff
	var forearm := _make_capsule(0.068, 0.30, _mat_jersey)
	forearm.name = "%sForearmPad" % side_prefix
	forearm.position = Vector3(0.0, -0.13, 0.0)
	elbow.add_child(forearm)

	var glove := Node3D.new()
	glove.name = "%sGloveHand" % side_prefix
	glove.position = Vector3(0.0, -0.26, 0.0)
	elbow.add_child(glove)

	var glove_mesh := _make_box(Vector3(0.08, 0.09, 0.11), _mat_skin_glove)
	glove_mesh.name = "%sHalfFingerGlove" % side_prefix
	glove_mesh.position = Vector3(0.0, -0.02, -0.02)
	glove.add_child(glove_mesh)

	return shoulder

func _build_head_and_mask() -> void:
	neck_head_pivot = Node3D.new()
	neck_head_pivot.name = "NeckHeadPivot"
	neck_head_pivot.position = Vector3(0.0, 0.56, 0.0)
	torso_pivot.add_child(neck_head_pivot)

	# Upper cranium + backwards beanie / headband wrap
	var cranium := _make_sphere(0.145, 0.29, _mat_mask_shell)
	cranium.name = "CraniumShell"
	cranium.position = Vector3(0.0, 0.07, 0.01)
	neck_head_pivot.add_child(cranium)

	# Iconic 2004 Woven Headband / Goggle Strap
	var strap := _make_cylinder(0.152, 0.152, 0.048, _mat_jersey)
	strap.name = "ProHeadbandStrap"
	strap.position = Vector3(0.0, 0.10, 0.005)
	neck_head_pivot.add_child(strap)

	# Curved Gold/Iridium Chromed Thermal Goggle Lens (looking -Z)
	var lens := _make_cylinder(0.148, 0.142, 0.105, _mat_visor_chrome)
	lens.name = "ThermalIridiumLens"
	lens.position = Vector3(0.0, 0.065, -0.035)
	lens.scale = Vector3(1.04, 1.0, 0.85)
	neck_head_pivot.add_child(lens)

	# Goggle Brow Peak / Sun Visor
	var visor_peak := _make_box(Vector3(0.26, 0.024, 0.14), _mat_mask_shell)
	visor_peak.name = "MaskSunVisorPeak"
	visor_peak.position = Vector3(0.0, 0.135, -0.09)
	visor_peak.rotation.x = deg_to_rad(12.0)
	neck_head_pivot.add_child(visor_peak)

	# Vented JT Proflex Flexible Lower Skirt / Mouthpiece
	var lower_skirt := _make_cylinder(0.125, 0.095, 0.14, _mat_mask_shell)
	lower_skirt.name = "VentedFaceplateSkirt"
	lower_skirt.position = Vector3(0.0, -0.02, -0.055)
	lower_skirt.scale = Vector3(1.0, 1.0, 0.92)
	neck_head_pivot.add_child(lower_skirt)

func _build_marker_assemblies() -> void:
	marker_assembly_pivot = Node3D.new()
	marker_assembly_pivot.name = "MarkerAssemblyPivot"
	marker_assembly_pivot.position = Vector3(0.19, 0.34, -0.26)
	torso_pivot.add_child(marker_assembly_pivot)

	muzzle_tip_node = Node3D.new()
	muzzle_tip_node.name = "MuzzleTip"
	muzzle_tip_node.position = Vector3(0.0, 0.04, -0.46)
	marker_assembly_pivot.add_child(muzzle_tip_node)

	# Shared Hopper Unit Pivot (so Halo B / Cyclone tilts and exposes realistic sub-hitbox)
	hopper_unit_pivot = Node3D.new()
	hopper_unit_pivot.name = "HopperUnitPivot"
	hopper_unit_pivot.position = Vector3(0.0, 0.16, -0.02)
	marker_assembly_pivot.add_child(hopper_unit_pivot)

	var halo_shell := _make_sphere(0.095, 0.17, _mat_hopper_shell)
	halo_shell.name = "HaloBShell"
	halo_shell.scale = Vector3(0.88, 0.92, 1.38)
	hopper_unit_pivot.add_child(halo_shell)

	var feed_neck := _make_cylinder(0.018, 0.018, 0.06, _mat_anodized_marker)
	feed_neck.name = "ClampingFeedneck"
	feed_neck.position = Vector3(0.0, -0.075, 0.02)
	hopper_unit_pivot.add_child(feed_neck)

	hopper_lid_pivot = Node3D.new()
	hopper_lid_pivot.name = "HopperLidPivot"
	hopper_lid_pivot.position = Vector3(0.0, 0.065, 0.06)
	hopper_unit_pivot.add_child(hopper_lid_pivot)

	var lid_disc := _make_cylinder(0.042, 0.042, 0.012, _mat_anodized_marker)
	lid_disc.position = Vector3(0.0, 0.0, 0.03)
	hopper_lid_pivot.add_child(lid_disc)

	# 1. SPEEDBALL ASSEMBLY (2004 Stacked-Tube Intimidator/Autococker + 14" Barrel + 68/4500 Carbon HPA)
	speedball_assembly = Node3D.new()
	speedball_assembly.name = "SpeedballAssembly"
	marker_assembly_pivot.add_child(speedball_assembly)

	var upper_tube := _make_cylinder(0.019, 0.019, 0.23, _mat_anodized_marker)
	upper_tube.rotation.x = deg_to_rad(90.0)
	upper_tube.position = Vector3(0.0, 0.055, -0.02)
	speedball_assembly.add_child(upper_tube)

	var lower_tube := _make_cylinder(0.018, 0.018, 0.21, _mat_anodized_marker)
	lower_tube.rotation.x = deg_to_rad(90.0)
	lower_tube.position = Vector3(0.0, 0.022, -0.02)
	speedball_assembly.add_child(lower_tube)

	var grip_frame := _make_box(Vector3(0.032, 0.11, 0.048), _mat_dark_metal)
	grip_frame.position = Vector3(0.0, -0.045, 0.02)
	grip_frame.rotation.x = deg_to_rad(-16.0)
	speedball_assembly.add_child(grip_frame)

	var hpr_reg := _make_cylinder(0.018, 0.016, 0.105, _mat_anodized_marker)
	hpr_reg.position = Vector3(0.0, -0.035, -0.105)
	speedball_assembly.add_child(hpr_reg)

	var barrel_back := _make_cylinder(0.015, 0.015, 0.16, _mat_anodized_marker)
	barrel_back.rotation.x = deg_to_rad(90.0)
	barrel_back.position = Vector3(0.0, 0.055, -0.19)
	speedball_assembly.add_child(barrel_back)

	var barrel_front := _make_cylinder(0.013, 0.013, 0.22, _mat_dark_metal)
	barrel_front.rotation.x = deg_to_rad(90.0)
	barrel_front.position = Vector3(0.0, 0.055, -0.36)
	speedball_assembly.add_child(barrel_front)

	# 68ci / 4500psi Carbon-Fiber HPA Tank mounted on bottom-line ASA
	var hpa_bottle := _make_capsule(0.056, 0.25, _mat_carbon_tank)
	hpa_bottle.name = "CarbonHPATank68_4500"
	hpa_bottle.rotation.x = deg_to_rad(90.0)
	hpa_bottle.position = Vector3(0.0, -0.095, 0.185)
	speedball_assembly.add_child(hpa_bottle)

	# 2. WOODSBALL ASSEMBLY (Tippmann A-5 Carbine + Cyclone Side-Feed + Shroud + Stock)
	woodsball_assembly = Node3D.new()
	woodsball_assembly.name = "WoodsballAssembly"
	woodsball_assembly.visible = false
	marker_assembly_pivot.add_child(woodsball_assembly)

	var a5_receiver := _make_box(Vector3(0.046, 0.085, 0.28), _mat_olive_drab)
	a5_receiver.position = Vector3(0.0, 0.03, -0.02)
	woodsball_assembly.add_child(a5_receiver)

	var a5_shroud := _make_cylinder(0.024, 0.024, 0.22, _mat_dark_metal)
	a5_shroud.rotation.x = deg_to_rad(90.0)
	a5_shroud.position = Vector3(0.0, 0.04, -0.25)
	woodsball_assembly.add_child(a5_shroud)

	var a5_stock := _make_box(Vector3(0.036, 0.075, 0.20), _mat_dark_metal)
	a5_stock.position = Vector3(0.0, 0.01, 0.18)
	woodsball_assembly.add_child(a5_stock)

	var cyclone_ratchet := _make_cylinder(0.038, 0.038, 0.055, _mat_dark_metal)
	cyclone_ratchet.position = Vector3(0.048, 0.06, -0.03)
	woodsball_assembly.add_child(cyclone_ratchet)

	# 3. STOCK-CLASS PUMP ASSEMBLY (Ribbed Pump Handle + 10-Round Horizontal Feed Tube + 12g CO2)
	pump_assembly = Node3D.new()
	pump_assembly.name = "PumpAssembly"
	pump_assembly.visible = false
	marker_assembly_pivot.add_child(pump_assembly)

	var pump_receiver := _make_cylinder(0.017, 0.017, 0.26, _mat_dark_metal)
	pump_receiver.rotation.x = deg_to_rad(90.0)
	pump_receiver.position = Vector3(0.0, 0.04, -0.03)
	pump_assembly.add_child(pump_receiver)

	var ten_round_tube := _make_cylinder(0.013, 0.013, 0.22, _mat_pod_translucent)
	ten_round_tube.rotation.x = deg_to_rad(90.0)
	ten_round_tube.position = Vector3(0.0, 0.075, -0.04)
	pump_assembly.add_child(ten_round_tube)

	var pump_barrel := _make_cylinder(0.012, 0.012, 0.26, _mat_dark_metal)
	pump_barrel.rotation.x = deg_to_rad(90.0)
	pump_barrel.position = Vector3(0.0, 0.04, -0.26)
	pump_assembly.add_child(pump_barrel)

	pump_handle_slide = Node3D.new()
	pump_handle_slide.name = "PumpHandleSlide"
	pump_handle_slide.position = Vector3(0.0, 0.008, -0.20)
	pump_assembly.add_child(pump_handle_slide)

	var ribbed_handle := _make_cylinder(0.025, 0.025, 0.11, _mat_anodized_marker)
	ribbed_handle.rotation.x = deg_to_rad(90.0)
	pump_handle_slide.add_child(ribbed_handle)

	var co2_cartridge := _make_cylinder(0.014, 0.011, 0.09, _mat_anodized_marker)
	co2_cartridge.rotation.x = deg_to_rad(75.0)
	co2_cartridge.position = Vector3(0.0, -0.055, 0.11)
	pump_assembly.add_child(co2_cartridge)

func set_team_visual(p_team: String) -> void:
	team_id = p_team.to_upper()
	var is_alpha := (team_id == "ALPHA")
	var jersey_path := "res://assets/textures/jersey_pro_alpha.png" if is_alpha else "res://assets/textures/jersey_pro_bravo.png"
	var j_tex := _load_texture_safe(jersey_path)
	if j_tex != null:
		_mat_jersey.albedo_texture = j_tex
		_mat_jersey.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		_mat_jersey.albedo_color = Color(0.14, 0.42, 0.88) if is_alpha else Color(0.84, 0.18, 0.22)

	_mat_anodized_marker.albedo_color = Color(0.16, 0.48, 0.96) if is_alpha else Color(0.92, 0.18, 0.22)
	_mat_visor_chrome.albedo_color = Color(0.96, 0.72, 0.15) if is_alpha else Color(0.96, 0.42, 0.12)

func set_bracket_visual(p_bracket: String) -> void:
	bracket_id = p_bracket.to_lower()
	if speedball_assembly == null:
		return
	speedball_assembly.visible = (bracket_id == "speedball")
	woodsball_assembly.visible = (bracket_id == "woodsball")
	pump_assembly.visible = (bracket_id == "pump")

	if hopper_unit_pivot != null:
		# Stock-class pump uses horizontal 10-round feed tube instead of bulky top hopper!
		hopper_unit_pivot.visible = (bracket_id != "pump")
		if bracket_id == "woodsball":
			# Cyclone side-feed offset to the right of the A-5 receiver
			hopper_unit_pivot.position = Vector3(0.055, 0.13, -0.03)
		else:
			hopper_unit_pivot.position = Vector3(0.0, 0.16, -0.02)
	_sync_sub_hitboxes()

func set_pump_stroke(alpha: float) -> void:
	_pump_stroke_alpha = clampf(alpha, 0.0, 1.0)
	if pump_handle_slide != null:
		pump_handle_slide.position.z = lerpf(-0.20, -0.11, _pump_stroke_alpha)

## Creates and attaches 4 distinct form-fitting sub-hitboxes on `body` (Mask, Torso, Hopper, Pack/Marker)
## with surface hardness `break_cos_threshold` metadata so edge-hand discipline matters in firefights.
func build_sub_hitboxes_on(body: CollisionObject3D) -> Dictionary:
	if body == null:
		return {}

	var col_mask := body.get_node_or_null("Col_MaskHead") as CollisionShape3D
	if col_mask == null:
		col_mask = CollisionShape3D.new()
		col_mask.name = "Col_MaskHead"
		var s_mask := SphereShape3D.new()
		s_mask.radius = 0.155
		col_mask.shape = s_mask
		body.add_child(col_mask)
	col_mask.set_meta("hit_zone", "mask")
	col_mask.set_meta("break_cos_threshold", 0.28) # Hard polycarbonate lens/mask

	var col_torso := body.get_node_or_null("Col_TorsoJersey") as CollisionShape3D
	if col_torso == null:
		col_torso = CollisionShape3D.new()
		col_torso.name = "Col_TorsoJersey"
		var c_torso := CapsuleShape3D.new()
		c_torso.radius = 0.23
		c_torso.height = 1.24
		col_torso.shape = c_torso
		body.add_child(col_torso)
	col_torso.set_meta("hit_zone", "torso")
	col_torso.set_meta("break_cos_threshold", 0.48) # Baggy padded jersey bounces glancing shots

	var col_hopper := body.get_node_or_null("Col_HopperLoader") as CollisionShape3D
	if col_hopper == null:
		col_hopper = CollisionShape3D.new()
		col_hopper.name = "Col_HopperLoader"
		var s_hop := SphereShape3D.new()
		s_hop.radius = 0.115
		col_hopper.shape = s_hop
		body.add_child(col_hopper)
	col_hopper.set_meta("hit_zone", "hopper")
	col_hopper.set_meta("break_cos_threshold", 0.28) # Hard shell Halo B loader

	var col_pack := body.get_node_or_null("Col_MarkerPack") as CollisionShape3D
	if col_pack == null:
		col_pack = CollisionShape3D.new()
		col_pack.name = "Col_MarkerPack"
		var b_pack := BoxShape3D.new()
		b_pack.size = Vector3(0.22, 0.24, 0.38)
		col_pack.shape = b_pack
		body.add_child(col_pack)
	col_pack.set_meta("hit_zone", "pack")
	col_pack.set_meta("break_cos_threshold", 0.32) # Hard anodized marker / pod pack

	_sub_hitboxes = {
		"mask": col_mask,
		"torso": col_torso,
		"hopper": col_hopper,
		"pack": col_pack,
	}
	_sync_sub_hitboxes()
	return _sub_hitboxes

## Procedural Animation State Machine: smoothly poses all joints and updates sub-hitboxes.
func apply_pose(delta: float, params: Dictionary) -> void:
	if root_pivot == null:
		build_rig(team_id, bracket_id)

	var dt := clampf(delta, 0.0, 0.25)
	var blend := 1.0 if dt <= 0.0001 else clampf(dt * 14.0, 0.05, 1.0)

	var vel: Vector3 = params.get("velocity", Vector3.ZERO)
	var horiz_speed := Vector2(vel.x, vel.z).length()
	var stance_idx: int = int(params.get("stance", 0))
	var target_lean: float = clampf(float(params.get("lean", 0.0)), -1.0, 1.0)
	var is_left: bool = bool(params.get("is_left_handed", _is_left_handed_state))
	_is_left_handed_state = is_left
	var target_tuck: float = clampf(float(params.get("bunker_tuck", 0.0)), 0.0, 1.0)
	var is_sliding: bool = bool(params.get("is_sliding", false))
	var is_diving: bool = bool(params.get("is_diving", false))
	var is_reloading: bool = bool(params.get("is_reloading", false))
	var is_eliminated: bool = bool(params.get("is_eliminated", false))

	if params.has("team"):
		var req_team := String(params["team"]).to_upper()
		if req_team != team_id:
			set_team_visual(req_team)
	if params.has("bracket"):
		var req_bracket := String(params["bracket"]).to_lower()
		if req_bracket != bracket_id:
			set_bracket_visual(req_bracket)
	if params.has("pump_stroke"):
		set_pump_stroke(float(params["pump_stroke"]))

	_hand_alpha = lerpf(_hand_alpha, 1.0 if is_left else 0.0, blend)
	_current_lean = lerpf(_current_lean, target_lean, blend)
	_current_tuck = lerpf(_current_tuck, target_tuck, blend)
	_current_stance_f = lerpf(_current_stance_f, float(stance_idx), blend)
	_current_slide_alpha = lerpf(_current_slide_alpha, 1.0 if is_sliding else 0.0, blend)
	_current_dive_alpha = lerpf(_current_dive_alpha, 1.0 if is_diving else 0.0, blend)
	_current_reload_alpha = lerpf(_current_reload_alpha, 1.0 if is_reloading else 0.0, blend)
	_current_elim_alpha = lerpf(_current_elim_alpha, 1.0 if is_eliminated else 0.0, blend)

	if is_reloading:
		_reload_cycle_time += maxf(dt, 0.033) * 5.0
	else:
		_reload_cycle_time = 0.0

	# Advance walk/sprint stride cycle
	if horiz_speed > 0.15 and not is_sliding and not is_diving:
		var step_freq := clampf(horiz_speed * 1.45, 2.5, 11.5)
		_stride_phase += maxf(dt, 0.016) * step_freq
	elif dt > 0.0:
		_stride_phase = lerpf(_stride_phase, 0.0, clampf(dt * 6.0, 0.0, 1.0))

	var stride_sin := sin(_stride_phase)
	var stride_cos := cos(_stride_phase * 2.0)
	var move_factor := clampf(horiz_speed / 6.5, 0.0, 1.0) * (1.0 - _current_slide_alpha) * (1.0 - _current_dive_alpha)

	# 1. Pelvis Height & Orientation (Stance + Tuck + Slide + Superman Dive)
	var base_pelvis_y := 0.88
	if _current_stance_f <= 1.0:
		base_pelvis_y = lerpf(0.88, 0.58, _current_stance_f)
	else:
		base_pelvis_y = lerpf(0.58, 0.26, _current_stance_f - 1.0)

	base_pelvis_y -= _current_tuck * 0.14
	base_pelvis_y = lerpf(base_pelvis_y, 0.42, _current_slide_alpha)
	base_pelvis_y = lerpf(base_pelvis_y, 0.25, _current_dive_alpha)

	var bob_y := stride_cos * 0.035 * move_factor
	pelvis_pivot.position = Vector3(_current_lean * 0.16, base_pelvis_y + bob_y, 0.0)

	# Pelvis pitch/roll for slide & Superman dive
	var pelvis_pitch_deg := 0.0
	if _current_stance_f > 1.0:
		pelvis_pitch_deg = lerpf(0.0, -78.0, _current_stance_f - 1.0)
	pelvis_pitch_deg = lerpf(pelvis_pitch_deg, 18.0, _current_slide_alpha)
	pelvis_pitch_deg = lerpf(pelvis_pitch_deg, -82.0, _current_dive_alpha)

	pelvis_pivot.rotation.x = deg_to_rad(pelvis_pitch_deg)
	pelvis_pivot.rotation.z = deg_to_rad(-_current_lean * 8.0 + _current_slide_alpha * 14.0)
	pelvis_pivot.rotation.y = deg_to_rad(stride_sin * 5.0 * move_factor - _current_slide_alpha * 22.0)

	# 2. Legs (Walk/Sprint Stride, Crouch Knee Bend, Knee-Slide, Prone/Dive Extension)
	var crouch_bend := clampf(_current_stance_f, 0.0, 1.0) * 46.0 + _current_tuck * 22.0
	var l_hip_pitch := stride_sin * 38.0 * move_factor + crouch_bend
	var r_hip_pitch := -stride_sin * 38.0 * move_factor + crouch_bend
	var l_knee_pitch := -(maxf(0.0, -stride_sin) * 48.0 * move_factor + crouch_bend * 1.45)
	var r_knee_pitch := -(maxf(0.0, stride_sin) * 48.0 * move_factor + crouch_bend * 1.45)

	# Knee-Slide override (lead right leg extended forward, left leg tucked sharply under)
	if _current_slide_alpha > 0.01:
		l_hip_pitch = lerpf(l_hip_pitch, 32.0, _current_slide_alpha)
		l_knee_pitch = lerpf(l_knee_pitch, -108.0, _current_slide_alpha)
		r_hip_pitch = lerpf(r_hip_pitch, -54.0, _current_slide_alpha)
		r_knee_pitch = lerpf(r_knee_pitch, -16.0, _current_slide_alpha)

	# Superman Dive / Prone override (legs extended straight back)
	var prone_or_dive := maxf(_current_dive_alpha, clampf(_current_stance_f - 1.0, 0.0, 1.0))
	if prone_or_dive > 0.01:
		l_hip_pitch = lerpf(l_hip_pitch, -12.0, prone_or_dive)
		r_hip_pitch = lerpf(r_hip_pitch, -12.0, prone_or_dive)
		l_knee_pitch = lerpf(l_knee_pitch, -18.0, prone_or_dive)
		r_knee_pitch = lerpf(r_knee_pitch, -18.0, prone_or_dive)

	left_hip_pivot.rotation = Vector3(deg_to_rad(l_hip_pitch), 0.0, deg_to_rad(-3.0))
	right_hip_pivot.rotation = Vector3(deg_to_rad(r_hip_pitch), 0.0, deg_to_rad(3.0))
	left_knee_pivot.rotation = Vector3(deg_to_rad(l_knee_pitch), 0.0, 0.0)
	right_knee_pivot.rotation = Vector3(deg_to_rad(r_knee_pitch), 0.0, 0.0)
	left_boot_cleat.rotation.x = deg_to_rad(-l_hip_pitch * 0.35 - l_knee_pitch * 0.35)
	right_boot_cleat.rotation.x = deg_to_rad(-r_hip_pitch * 0.35 - r_knee_pitch * 0.35)

	# 3. Torso Spine Lean, Sprint Forward Tilt, and Bunker Pocket Tuck
	var torso_pitch_deg := -14.0 * move_factor - 18.0 * _current_tuck - 12.0 * clampf(_current_stance_f, 0.0, 1.0)
	torso_pitch_deg = lerpf(torso_pitch_deg, -22.0, _current_slide_alpha)
	torso_pitch_deg = lerpf(torso_pitch_deg, 18.0, _current_dive_alpha)

	var torso_roll_deg := -_current_lean * 18.0
	torso_pivot.rotation = Vector3(
		deg_to_rad(torso_pitch_deg),
		deg_to_rad(-stride_sin * 6.0 * move_factor),
		deg_to_rad(torso_roll_deg)
	)

	# 4. Head & JT Proflex Mask Counter-Leveling
	var head_pitch_deg := -torso_pitch_deg * 0.65
	if _current_dive_alpha > 0.01 or _current_stance_f > 1.0:
		head_pitch_deg = 52.0 # Look forward downfield while prone/diving
	head_pitch_deg = lerpf(head_pitch_deg, -24.0, _current_elim_alpha)
	neck_head_pivot.rotation = Vector3(
		deg_to_rad(head_pitch_deg),
		0.0,
		deg_to_rad(_current_lean * 11.0) # Keep goggles level with horizon during corner snap
	)

	# 5. Marker Hand Swap, Bunker Pocket Cant, & Corner Peek Hopper Discipline
	# hand_sign: +1.0 = Right-handed (+X shoulder), -1.0 = Left-handed (-X shoulder)
	var hand_sign := lerpf(1.0, -1.0, _hand_alpha)

	# Check whether player's marker hand matches the corner they are peeking:
	# Right peek (_current_lean > 0) matches Right hand (hand_sign > 0) -> alignment > 0
	# Left peek (_current_lean < 0) matches Left hand (hand_sign < 0) -> alignment > 0
	# Wrong hand on corner -> alignment < 0!
	var peek_alignment := _current_lean * hand_sign

	var base_marker_x := 0.19 * hand_sign
	var marker_y := 0.34 - _current_tuck * 0.07
	var marker_z := -0.26 + _current_tuck * 0.08

	var marker_cant_z_deg := 0.0
	if peek_alignment >= -0.05:
		# MATCHED HAND (or neutral): cant marker INWARD toward head/bunker centerline (26 deg)
		# and tuck grip toward nose so the Halo B hopper hides behind the mask/bunker edge!
		var inward_cant := (absf(_current_lean) * 26.0) + (_current_tuck * 24.0)
		marker_cant_z_deg = hand_sign * inward_cant
		base_marker_x = (0.19 * hand_sign) - (_current_lean * 0.022)
	else:
		# WRONG HAND FOR CORNER: player reaches across body to clear the opposite bunker edge,
		# pushing the marker & outside elbow past the corner and canting the hopper OUTWARD (~2.4x exposure)!
		var peek_side := signf(_current_lean)
		var CrossReachAlpha := absf(_current_lean)
		base_marker_x = lerpf(0.19 * hand_sign, peek_side * 0.29, CrossReachAlpha)
		marker_cant_z_deg = -peek_side * (28.0 * CrossReachAlpha)

	var marker_pitch_deg := 18.0 * _current_tuck
	marker_pitch_deg = lerpf(marker_pitch_deg, -18.0, _current_reload_alpha)
	marker_pitch_deg = lerpf(marker_pitch_deg, -48.0, _current_elim_alpha)
	marker_pitch_deg = lerpf(marker_pitch_deg, 58.0, _current_dive_alpha)

	marker_assembly_pivot.position = Vector3(base_marker_x, marker_y, marker_z)
	marker_assembly_pivot.rotation = Vector3(
		deg_to_rad(marker_pitch_deg),
		deg_to_rad(-hand_sign * 4.0 * (1.0 - _current_tuck)),
		deg_to_rad(marker_cant_z_deg)
	)

	# Hopper Lid flips open during reload
	if hopper_lid_pivot != null:
		hopper_lid_pivot.rotation.x = deg_to_rad(-115.0 * _current_reload_alpha)

	# 6. Articulated Shoulder & Elbow Positioning (Trigger Arm, Foregrip Arm, Reload & Eliminated Sign)
	var r_sh_pitch := 52.0 + 14.0 * _current_tuck
	var r_sh_yaw := -12.0 * hand_sign
	var r_sh_roll := -16.0 + 10.0 * _current_tuck
	var r_elb_pitch := 62.0 + 18.0 * _current_tuck

	var l_sh_pitch := 58.0 + 12.0 * _current_tuck
	var l_sh_yaw := 22.0 * hand_sign
	var l_sh_roll := 16.0 - 10.0 * _current_tuck
	var l_elb_pitch := 54.0 + 18.0 * _current_tuck

	# Wrong-hand corner peek flares the outside elbow out into the lane
	if peek_alignment < -0.1:
		if is_left:
			l_sh_roll += 28.0 * absf(_current_lean)
		else:
			r_sh_roll -= 28.0 * absf(_current_lean)

	# Reloading animation: off-hand reaches back to 4+3 pod pack, then pours pod into Halo B hopper
	if _current_reload_alpha > 0.02:
		reload_pod_prop.visible = true
		var pour_phase := 0.5 + 0.5 * sin(_reload_cycle_time)
		var reach_pitch := lerpf(-42.0, 78.0, pour_phase)
		var reach_yaw := lerpf(-38.0, 28.0, pour_phase)
		var reach_elb := lerpf(85.0, 68.0, pour_phase)
		l_sh_pitch = lerpf(l_sh_pitch, reach_pitch, _current_reload_alpha)
		l_sh_yaw = lerpf(l_sh_yaw, reach_yaw, _current_reload_alpha)
		l_elb_pitch = lerpf(l_elb_pitch, reach_elb, _current_reload_alpha)
	else:
		reload_pod_prop.visible = false

	# Classic Tournament "DEAD / HIT!" Walk-Off Gesture: raise left arm high above mask, drop marker barrel
	if _current_elim_alpha > 0.02:
		l_sh_pitch = lerpf(l_sh_pitch, 168.0, _current_elim_alpha)
		l_sh_yaw = lerpf(l_sh_yaw, 0.0, _current_elim_alpha)
		l_sh_roll = lerpf(l_sh_roll, 8.0, _current_elim_alpha)
		l_elb_pitch = lerpf(l_elb_pitch, 12.0, _current_elim_alpha)
		r_sh_pitch = lerpf(r_sh_pitch, 18.0, _current_elim_alpha)
		r_elb_pitch = lerpf(r_elb_pitch, 24.0, _current_elim_alpha)

	right_shoulder_pivot.rotation = Vector3(deg_to_rad(r_sh_pitch), deg_to_rad(r_sh_yaw), deg_to_rad(r_sh_roll))
	right_elbow_pivot.rotation = Vector3(deg_to_rad(r_elb_pitch), 0.0, 0.0)

	left_shoulder_pivot.rotation = Vector3(deg_to_rad(l_sh_pitch), deg_to_rad(l_sh_yaw), deg_to_rad(l_sh_roll))
	left_elbow_pivot.rotation = Vector3(deg_to_rad(l_elb_pitch), 0.0, 0.0)

	_sync_sub_hitboxes()

func _sync_sub_hitboxes() -> void:
	if _sub_hitboxes.is_empty():
		return

	var col_mask := _sub_hitboxes.get("mask", null) as CollisionShape3D
	if col_mask != null and is_instance_valid(col_mask) and neck_head_pivot != null:
		var body_parent := col_mask.get_parent_node_3d()
		if body_parent != null:
			var head_local := body_parent.to_local(neck_head_pivot.global_position + neck_head_pivot.global_transform.basis * Vector3(0.0, 0.05, -0.02))
			col_mask.position = head_local

	var col_torso := _sub_hitboxes.get("torso", null) as CollisionShape3D
	if col_torso != null and is_instance_valid(col_torso) and pelvis_pivot != null:
		var body_parent := col_torso.get_parent_node_3d()
		if body_parent != null:
			col_torso.position = body_parent.to_local(pelvis_pivot.global_position + Vector3(0.0, 0.16, 0.0))
			col_torso.rotation = torso_pivot.rotation

	var col_hopper := _sub_hitboxes.get("hopper", null) as CollisionShape3D
	if col_hopper != null and is_instance_valid(col_hopper) and hopper_unit_pivot != null:
		col_hopper.disabled = (bracket_id == "pump")
		var body_parent := col_hopper.get_parent_node_3d()
		if body_parent != null:
			col_hopper.position = body_parent.to_local(hopper_unit_pivot.global_position)

	var col_pack := _sub_hitboxes.get("pack", null) as CollisionShape3D
	if col_pack != null and is_instance_valid(col_pack) and marker_assembly_pivot != null:
		var body_parent := col_pack.get_parent_node_3d()
		if body_parent != null:
			col_pack.position = body_parent.to_local(marker_assembly_pivot.global_position)
			col_pack.rotation = marker_assembly_pivot.rotation

## Returns peek exposure metrics for testing and gameplay verification.
## Specifically quantifies how much further laterally the hopper/elbow sticks out past the
## center/bunker line when peeking with the wrong hand vs matched hand.
func get_peek_exposure_metrics() -> Dictionary:
	var hopper_local := to_local(hopper_unit_pivot.global_position)
	var muzzle_local := to_local(muzzle_tip_node.global_position)
	var head_local := to_local(neck_head_pivot.global_position)
	# Lateral exposure of the hopper outer shell beyond the head centerline on the peeking side
	var peek_dir := signf(_current_lean) if absf(_current_lean) > 0.05 else (1.0 if not _is_left_handed_state else -1.0)
	var hopper_outer_edge_x := (hopper_local.x * peek_dir) + 0.115
	var head_center_x := head_local.x * peek_dir
	var hopper_overhang := maxf(0.02, hopper_outer_edge_x - head_center_x)
	return {
		"hopper_local": hopper_local,
		"muzzle_local": muzzle_local,
		"head_local": head_local,
		"hopper_overhang_m": hopper_overhang,
		"marker_cant_deg": rad_to_deg(marker_assembly_pivot.rotation.z),
	}

func _make_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

func _make_capsule(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	return mi

func _make_cylinder(top_r: float, bot_r: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = mat
	return mi

func _make_sphere(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	mi.mesh = sm
	mi.material_override = mat
	return mi
