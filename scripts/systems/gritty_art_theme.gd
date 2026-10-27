class_name GrittyArtTheme
extends RefCounted

## v0.2 Gritty 2000s Tournament Paintball Art Overhaul (PB-09 / Issue #10).
## Centralizes procedural texture loading, overcast stadium environment, floodlight towers,
## perimeter safety netting, tournament scoreboard, muddy turf with slick puddles,
## scuffed vinyl bunkers, stacked wooden cable spools, weathered first-person marker with
## pressure gauge & tactical glove, and oily low-roughness paint splat decals + mist VFX.

const NEON_YELLOW_PAINT := Color(0.98, 0.84, 0.10, 1.0)
const HOT_PINK_PAINT := Color(0.96, 0.16, 0.58, 1.0)

static var _texture_cache: Dictionary = {}

static func load_texture_safe(res_path: String) -> Texture2D:
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	if ResourceLoader.exists(res_path):
		var loaded := ResourceLoader.load(res_path) as Texture2D
		if loaded != null:
			_texture_cache[res_path] = loaded
			return loaded
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_texture_cache[res_path] = tex
			return tex
	return null

static func create_overcast_stadium_environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.40, 0.43)
	sky_mat.sky_horizon_color = Color(0.54, 0.56, 0.58)
	sky_mat.ground_horizon_color = Color(0.32, 0.31, 0.29)
	sky_mat.ground_bottom_color = Color(0.14, 0.12, 0.10)
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 45.0
	sky_mat.sun_curve = 0.25
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.56, 0.58, 0.62)
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.85

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.50, 0.52, 0.55)
	env.fog_light_energy = 0.85
	env.fog_density = 0.0042
	env.fog_aerial_perspective = 0.35

	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	return env

static func create_muddy_turf_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.84, 0.78)
	mat.albedo_texture = load_texture_safe("res://assets/textures/turf_muddy_albedo.png")
	mat.roughness = 0.92
	mat.roughness_texture = load_texture_safe("res://assets/textures/turf_muddy_roughness.png")
	mat.normal_enabled = true
	mat.normal_scale = 1.45
	mat.normal_texture = load_texture_safe("res://assets/textures/turf_muddy_normal.png")
	mat.uv1_scale = Vector3(28.0, 34.0, 1.0)
	return mat

static func create_scuffed_vinyl_material(base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Desaturate and weather the tournament vinyl color slightly for gritty 2000s realism
	var weathered := base_color.lerp(Color(0.32, 0.31, 0.29), 0.28)
	mat.albedo_color = weathered
	mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	mat.roughness = 0.48
	mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	mat.normal_enabled = true
	mat.normal_scale = 1.25
	mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.32
	mat.clearcoat_roughness = 0.28
	mat.uv1_scale = Vector3(1.8, 1.6, 1.8)
	return mat

static func create_wood_spool_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.68)
	mat.albedo_texture = load_texture_safe("res://assets/textures/wood_spool_albedo.png")
	mat.roughness = 0.84
	mat.normal_enabled = true
	mat.normal_scale = 0.85
	mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return mat

static func create_oily_paint_material(color: Color, use_splat_mask: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.08
	mat.roughness = 0.12
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.88
	mat.clearcoat_roughness = 0.08
	mat.emission_enabled = true
	mat.emission = color * 0.65
	mat.emission_energy_multiplier = 0.32
	if use_splat_mask:
		var mask_tex := load_texture_safe("res://assets/textures/paint_splat_mask.png")
		if mask_tex != null:
			mat.albedo_texture = mask_tex
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.25
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func build_stadium_props(arena_root: Node3D) -> Node3D:
	var container := Node3D.new()
	container.name = "GrittyStadiumProps"
	arena_root.add_child(container)

	_build_mud_puddles_and_tracks(container)
	_build_floodlight_towers(container)
	_build_perimeter_safety_netting(container)
	_build_tournament_scoreboards(container)
	_build_wooden_cable_spools(container)
	return container

static func _build_mud_puddles_and_tracks(parent: Node3D) -> void:
	var puddle_mat := StandardMaterial3D.new()
	puddle_mat.albedo_color = Color(0.11, 0.10, 0.09, 0.92)
	puddle_mat.metallic = 0.35
	puddle_mat.roughness = 0.06
	puddle_mat.clearcoat_enabled = true
	puddle_mat.clearcoat = 0.95
	puddle_mat.clearcoat_roughness = 0.04

	var puddle_specs := [
		{"pos": Vector3(-1.1, 0.008, 41.8), "size": Vector3(1.8, 0.01, 4.6), "rot_y": -14.0},
		{"pos": Vector3(1.4, 0.008, 34.0), "size": Vector3(2.4, 0.01, 5.2), "rot_y": 8.0},
		{"pos": Vector3(-8.5, 0.008, 22.0), "size": Vector3(3.1, 0.01, 6.0), "rot_y": 12.0},
		{"pos": Vector3(0.0, 0.008, 2.5), "size": Vector3(5.5, 0.01, 2.8), "rot_y": 3.0},
		{"pos": Vector3(-34.5, 0.008, 12.0), "size": Vector3(2.2, 0.01, 8.5), "rot_y": 0.0},
		{"pos": Vector3(33.0, 0.008, 16.0), "size": Vector3(2.6, 0.01, 6.5), "rot_y": -6.0},
	]
	for idx in range(puddle_specs.size()):
		var spec: Dictionary = puddle_specs[idx]
		var pmesh := MeshInstance3D.new()
		pmesh.name = "MudPuddle_%d" % idx
		var bm := BoxMesh.new()
		bm.size = spec["size"]
		pmesh.mesh = bm
		pmesh.position = spec["pos"]
		pmesh.rotation_degrees.y = spec["rot_y"]
		pmesh.material_override = puddle_mat
		parent.add_child(pmesh)

static func _build_floodlight_towers(parent: Node3D) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.18, 0.19, 0.21)
	pole_mat.metallic = 0.72
	pole_mat.roughness = 0.45

	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.98, 0.96, 0.88)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(0.96, 0.94, 0.84)
	bulb_mat.emission_energy_multiplier = 6.5

	var tower_positions := [
		Vector3(-44.0, 0.0, -44.0),
		Vector3(44.0, 0.0, -44.0),
		Vector3(-44.0, 0.0, 0.0),
		Vector3(44.0, 0.0, 0.0),
		Vector3(-44.0, 0.0, 44.0),
		Vector3(44.0, 0.0, 44.0),
		Vector3(-6.0, 0.0, 16.0),
		Vector3(14.0, 0.0, 8.0)
	]

	for i in range(tower_positions.size()):
		var pos: Vector3 = tower_positions[i]
		var is_field_backdrop := i >= 6
		var pole_h := 16.5 if is_field_backdrop else 21.0
		var tower := Node3D.new()
		tower.name = "StadiumFloodlightTower_%d" % i
		tower.position = pos
		parent.add_child(tower)

		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.24
		cyl.height = pole_h
		pole.mesh = cyl
		pole.position = Vector3(0.0, pole_h * 0.5, 0.0)
		pole.material_override = pole_mat
		tower.add_child(pole)

		var crossbar := MeshInstance3D.new()
		var cb_box := BoxMesh.new()
		cb_box.size = Vector3(2.8, 0.22, 0.28)
		crossbar.mesh = cb_box
		crossbar.position = Vector3(0.0, pole_h, 0.0)
		crossbar.material_override = pole_mat
		tower.add_child(crossbar)

		for b in range(4):
			var lamp := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.48, 0.36, 0.24)
			lamp.mesh = lbox
			lamp.position = Vector3(-0.96 + b * 0.64, pole_h + 0.24, 0.08)
			lamp.material_override = bulb_mat
			tower.add_child(lamp)

		if i < 6:
			var light := OmniLight3D.new()
			light.position = Vector3(0.0, pole_h - 0.5, 0.0)
			light.light_color = Color(0.92, 0.95, 1.0)
			light.light_energy = 2.4
			light.omni_range = 62.0
			tower.add_child(light)

static func _build_perimeter_safety_netting(parent: Node3D) -> void:
	var net_root := Node3D.new()
	net_root.name = "PerimeterSafetyNetting"
	parent.add_child(net_root)

	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.08, 0.09, 0.10, 0.42)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.roughness = 0.9

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.15, 0.16, 0.18)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5

	var wall_specs := [
		{"pos": Vector3(0.0, 4.2, -52.0), "size": Vector3(88.0, 8.4, 0.08)},
		{"pos": Vector3(0.0, 4.2, 52.0), "size": Vector3(88.0, 8.4, 0.08)},
		{"pos": Vector3(-44.0, 4.2, 0.0), "size": Vector3(0.08, 8.4, 104.0)},
		{"pos": Vector3(44.0, 4.2, 0.0), "size": Vector3(0.08, 8.4, 104.0)},
		# Inner tournament backdrop netting visible behind midfield
		{"pos": Vector3(0.0, 3.4, 24.0), "size": Vector3(76.0, 6.8, 0.05)}
	]
	for idx in range(wall_specs.size()):
		var spec: Dictionary = wall_specs[idx]
		var panel := MeshInstance3D.new()
		panel.name = "SafetyNetPanel_%d" % idx
		var bm := BoxMesh.new()
		bm.size = spec["size"]
		panel.mesh = bm
		panel.position = spec["pos"]
		panel.material_override = net_mat
		net_root.add_child(panel)

	for x_pos in [-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0]:
		var post := MeshInstance3D.new()
		var pcyl := CylinderMesh.new()
		pcyl.top_radius = 0.07
		pcyl.bottom_radius = 0.09
		pcyl.height = 7.2
		post.mesh = pcyl
		post.position = Vector3(x_pos, 3.6, 24.0)
		post.material_override = post_mat
		net_root.add_child(post)

static func _build_tournament_scoreboards(parent: Node3D) -> void:
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.12, 0.13, 0.15)
	board_mat.roughness = 0.45
	board_mat.metallic = 0.55

	var red_banner_mat := StandardMaterial3D.new()
	red_banner_mat.albedo_color = Color(0.68, 0.20, 0.16)
	red_banner_mat.roughness = 0.55

	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.95, 0.88, 0.65)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.95, 0.82, 0.45)
	led_mat.emission_energy_multiplier = 2.6

	var placements := [
		{"name": "TournamentScoreboard", "pos": Vector3(6.8, 0.0, 23.5), "scale": 1.0},
		{"name": "TournamentScoreboard_North", "pos": Vector3(0.0, 0.0, -50.0), "scale": 1.6}
	]

	for p in placements:
		var sb := Node3D.new()
		sb.name = p["name"]
		sb.position = p["pos"]
		var s: float = p["scale"]
		sb.scale = Vector3(s, s, s)
		parent.add_child(sb)

		for leg_x in [-1.6, 1.6]:
			var leg := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.18, 5.8, 0.18)
			leg.mesh = lbox
			leg.position = Vector3(leg_x, 2.9, 0.0)
			leg.material_override = board_mat
			sb.add_child(leg)

		var main_board := MeshInstance3D.new()
		var mb_box := BoxMesh.new()
		mb_box.size = Vector3(4.2, 2.2, 0.35)
		main_board.mesh = mb_box
		main_board.position = Vector3(0.0, 6.4, 0.0)
		main_board.material_override = board_mat
		sb.add_child(main_board)

		var sub_banner := MeshInstance3D.new()
		var sb_box := BoxMesh.new()
		sb_box.size = Vector3(2.8, 0.85, 0.32)
		sub_banner.mesh = sb_box
		sub_banner.position = Vector3(0.0, 4.75, 0.0)
		sub_banner.material_override = red_banner_mat
		sb.add_child(sub_banner)

		for dx in [-1.1, 0.0, 1.1]:
			var digit := MeshInstance3D.new()
			var dbox := BoxMesh.new()
			dbox.size = Vector3(0.55, 0.65, 0.06)
			digit.mesh = dbox
			digit.position = Vector3(dx, 6.4, 0.19)
			digit.material_override = led_mat
			sb.add_child(digit)

static func _build_wooden_cable_spools(parent: Node3D) -> void:
	var wood_mat := create_wood_spool_material()
	var spool_placements := [
		{"name": "WoodSpool_BreakoutRight", "pos": Vector3(1.85, 0.0, 41.2), "stacked": true},
		{"name": "WoodSpool_Center50Left", "pos": Vector3(-5.2, 0.0, 0.0), "stacked": true},
		{"name": "WoodSpool_Center50Right", "pos": Vector3(5.2, 0.0, 0.0), "stacked": false},
		{"name": "WoodSpool_TransitionLeft", "pos": Vector3(-14.0, 0.0, 18.0), "stacked": true},
		{"name": "WoodSpool_TransitionRight", "pos": Vector3(14.0, 0.0, -18.0), "stacked": true}
	]

	for sp in spool_placements:
		var body := StaticBody3D.new()
		body.name = sp["name"]
		body.position = sp["pos"]
		parent.add_child(body)

		var total_h := 1.55 if sp["stacked"] else 0.85
		var col := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = 0.82
		cshape.height = total_h
		col.shape = cshape
		col.position = Vector3(0.0, total_h * 0.5, 0.0)
		body.add_child(col)

		_add_single_wood_spool_meshes(body, Vector3(0.0, 0.0, 0.0), 0.82, 0.78, wood_mat)
		if sp["stacked"]:
			_add_single_wood_spool_meshes(body, Vector3(0.0, 0.78, 0.0), 0.76, 0.74, wood_mat)
			# Extra upright flange wheel leaning beside the stacked spool (just like concept art!)
			var wheel := MeshInstance3D.new()
			var wcyl := CylinderMesh.new()
			wcyl.top_radius = 0.72
			wcyl.bottom_radius = 0.72
			wcyl.height = 0.14
			wheel.mesh = wcyl
			wheel.position = Vector3(0.76, 0.68, 0.32)
			wheel.rotation_degrees = Vector3(90.0, -24.0, 8.0)
			wheel.material_override = wood_mat
			body.add_child(wheel)

static func _add_single_wood_spool_meshes(parent: Node3D, base_offset: Vector3, radius: float, height: float, mat: Material) -> void:
	var core := MeshInstance3D.new()
	var core_cyl := CylinderMesh.new()
	core_cyl.top_radius = radius * 0.56
	core_cyl.bottom_radius = radius * 0.56
	core_cyl.height = height
	core.mesh = core_cyl
	core.position = base_offset + Vector3(0.0, height * 0.5, 0.0)
	core.material_override = mat
	parent.add_child(core)

	for flange_y in [0.05, height * 0.5, height - 0.05]:
		var flange := MeshInstance3D.new()
		var fcyl := CylinderMesh.new()
		fcyl.top_radius = radius
		fcyl.bottom_radius = radius
		fcyl.height = 0.08
		flange.mesh = fcyl
		flange.position = base_offset + Vector3(0.0, flange_y, 0.0)
		flange.material_override = mat
		parent.add_child(flange)

static func decorate_bunker_mesh(bunker_body: StaticBody3D, mesh_inst: MeshInstance3D, size: Vector3, base_color: Color) -> void:
	mesh_inst.material_override = create_scuffed_vinyl_material(base_color)

	# Give tall narrow bunkers a dome-topped inflatable silhouette (like real speedball tombstone/temple cans)
	if size.y >= 1.8 and abs(size.x - size.z) < 0.75:
		var cap := CapsuleMesh.new()
		cap.radius = max(size.x, size.z) * 0.5
		cap.height = max(size.y, cap.radius * 2.1)
		mesh_inst.mesh = cap
	elif size.y < 1.3 and size.z > 3.0:
		# Horizontal cylindrical bolster / snake beam
		var cyl := CapsuleMesh.new()
		cyl.radius = size.y * 0.5
		cyl.height = size.z
		mesh_inst.mesh = cyl
		mesh_inst.rotation_degrees.x = 90.0

	# Add glossy neon yellow & hot pink paint splat patches on bunker faces
	var yellow_mat := create_oily_paint_material(NEON_YELLOW_PAINT, true)
	var pink_mat := create_oily_paint_material(HOT_PINK_PAINT, true)

	for s_idx in range(2):
		var splat_quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.65, 0.75)
		splat_quad.mesh = qm
		var is_pink := ((bunker_body.name.hash() + s_idx) % 2) == 0
		splat_quad.material_override = pink_mat if is_pink else yellow_mat
		var z_sign := 1.0 if s_idx == 0 else -1.0
		splat_quad.position = Vector3((s_idx - 0.5) * 0.25, 0.1, (size.z * 0.5 + 0.02) * z_sign)
		if z_sign < 0.0:
			splat_quad.rotation_degrees.y = 180.0
		bunker_body.add_child(splat_quad)

static func upgrade_first_person_marker(marker_rig: Node3D, body_mesh: MeshInstance3D, hopper_mesh: MeshInstance3D, hopper_lid_mesh: MeshInstance3D) -> void:
	# 1. Weathered scratched anodized gunmetal/silver marker body
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.54, 0.55, 0.57)
	metal_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	metal_mat.metallic = 0.85
	metal_mat.roughness = 0.32
	metal_mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	metal_mat.normal_enabled = true
	metal_mat.normal_scale = 0.9
	metal_mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	body_mesh.material_override = metal_mat

	# 2. Ported competition barrel extending forward from marker body
	var barrel := MeshInstance3D.new()
	barrel.name = "MarkerBarrel"
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.016
	bcyl.bottom_radius = 0.020
	bcyl.height = 0.42
	barrel.mesh = bcyl
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.025, -0.38)
	barrel.material_override = metal_mat
	marker_rig.add_child(barrel)

	# 3. Scuffed dark loader/hopper with yellow & pink tournament paint residue
	var hopper_mat := StandardMaterial3D.new()
	hopper_mat.albedo_color = Color(0.24, 0.24, 0.25)
	hopper_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	hopper_mat.roughness = 0.28
	hopper_mat.clearcoat_enabled = true
	hopper_mat.clearcoat = 0.65
	hopper_mat.clearcoat_roughness = 0.18
	hopper_mesh.material_override = hopper_mat

	# Paint smear decals on hopper & marker body
	var yellow_smear := MeshInstance3D.new()
	yellow_smear.name = "HopperPaintSmearYellow"
	var ys_sphere := SphereMesh.new()
	ys_sphere.radius = 0.087
	ys_sphere.height = 0.142
	yellow_smear.mesh = ys_sphere
	yellow_smear.position = hopper_mesh.position
	yellow_smear.material_override = create_oily_paint_material(NEON_YELLOW_PAINT, true)
	marker_rig.add_child(yellow_smear)

	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.18, 0.18, 0.20, 0.92)
	lid_mat.roughness = 0.32
	hopper_lid_mesh.material_override = lid_mat

	# 4. Visible Air Pressure Gauge near the grip (cylindrical bezel + white dial + red needle)
	var gauge_root := Node3D.new()
	gauge_root.name = "MarkerPressureGauge"
	gauge_root.position = Vector3(-0.042, -0.025, 0.08)
	gauge_root.rotation_degrees = Vector3(18.0, -28.0, 82.0)
	marker_rig.add_child(gauge_root)

	var bezel := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 0.026
	gcyl.bottom_radius = 0.026
	gcyl.height = 0.018
	bezel.mesh = gcyl
	bezel.material_override = metal_mat
	gauge_root.add_child(bezel)

	var dial := MeshInstance3D.new()
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = 0.021
	dcyl.bottom_radius = 0.021
	dcyl.height = 0.020
	dial.mesh = dcyl
	var dial_mat := StandardMaterial3D.new()
	dial_mat.albedo_color = Color(0.92, 0.92, 0.90)
	dial_mat.roughness = 0.2
	dial.material_override = dial_mat
	gauge_root.add_child(dial)

	var needle := MeshInstance3D.new()
	var nbox := BoxMesh.new()
	nbox.size = Vector3(0.004, 0.022, 0.016)
	needle.mesh = nbox
	needle.position = Vector3(0.0, 0.002, -0.004)
	needle.rotation_degrees.y = 32.0
	var needle_mat := StandardMaterial3D.new()
	needle_mat.albedo_color = Color(0.88, 0.15, 0.15)
	needle.material_override = needle_mat
	gauge_root.add_child(needle)

	# 5. Weathered tactical glove & paint-splattered sleeve holding the marker grip
	var glove := MeshInstance3D.new()
	glove.name = "TacticalGloveGrip"
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.085, 0.12, 0.16)
	glove.mesh = gbox
	glove.position = Vector3(-0.02, -0.085, 0.05)
	glove.rotation_degrees = Vector3(14.0, -10.0, 8.0)
	var glove_mat := StandardMaterial3D.new()
	glove_mat.albedo_color = Color(0.16, 0.16, 0.17)
	glove_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	glove_mat.roughness = 0.78
	glove.material_override = glove_mat
	marker_rig.add_child(glove)

static func spawn_paint_mist_burst(scene_root: Node, pos: Vector3, normal: Vector3, color: Color) -> Node3D:
	var burst_root := Node3D.new()
	burst_root.name = "PaintMistBurst"
	scene_root.add_child(burst_root)
	burst_root.global_position = pos + normal * 0.04

	var particles := CPUParticles3D.new()
	particles.name = "MistParticles"
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = 22
	particles.lifetime = 0.55

	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.028
	droplet_mesh.height = 0.056
	droplet_mesh.material = create_oily_paint_material(color, false)
	particles.mesh = droplet_mesh

	particles.direction = (normal + Vector3(0.0, 0.35, 0.0)).normalized()
	particles.spread = 62.0
	particles.initial_velocity_min = 2.2
	particles.initial_velocity_max = 6.8
	particles.gravity = Vector3(0.0, -9.8, 0.0)
	particles.scale_amount_min = 0.45
	particles.scale_amount_max = 1.45
	burst_root.add_child(particles)

	var timer := scene_root.get_tree().create_timer(0.75)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(burst_root):
			burst_root.queue_free()
	)
	return burst_root
