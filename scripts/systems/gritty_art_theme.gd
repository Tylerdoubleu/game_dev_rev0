class_name GrittyArtTheme
extends RefCounted

## v0.2.1 Gritty 2000s Tournament Paintball Art & Realism Overhaul.
## Centralizes procedural texture loading, overcast stadium environment (with SSAO + SSR),
## outer-perimeter floodlight towers, outer-perimeter safety netting (no interior field obstructions),
## tournament scoreboards, muddy turf with slick puddles, shaped 3D inflatable bunkers (Doritos,
## Cans, Aztecs, Wedges, Snake beams) with tight physics colliders and surface-hugging paint smears,
## stacked wooden cable spools, weathered first-person marker with regulator/macroline/gauge/glove,
## HPA muzzle gas puff, and oily low-roughness paint splat decals + mist VFX.

const NEON_YELLOW_PAINT := Color(0.98, 0.84, 0.10, 1.0)
const HOT_PINK_PAINT := Color(0.96, 0.16, 0.58, 1.0)

static var _texture_cache: Dictionary = {}

static func load_texture_safe(res_path: String) -> Texture2D:
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	if DisplayServer.get_name() == "headless" and (OS.get_environment("DEDICATED_SERVER") == "1" or "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()):
		_texture_cache[res_path] = null
		return null
	if ResourceLoader.exists(res_path):
		var loaded := ResourceLoader.load(res_path) as Texture2D
		if loaded != null:
			_texture_cache[res_path] = loaded
			return loaded
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var f := FileAccess.open(abs_path, FileAccess.READ)
		if f != null and f.get_length() > 256:
			f.close()
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				var tex := ImageTexture.create_from_image(img)
				_texture_cache[res_path] = tex
				return tex
	_texture_cache[res_path] = null
	return null

static func create_overcast_stadium_environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.39, 0.43)
	sky_mat.sky_horizon_color = Color(0.55, 0.57, 0.60)
	sky_mat.ground_horizon_color = Color(0.30, 0.29, 0.27)
	sky_mat.ground_bottom_color = Color(0.13, 0.11, 0.09)
	sky_mat.sky_curve = 0.16
	sky_mat.sun_angle_max = 38.0
	sky_mat.sun_curve = 0.22
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.56, 0.58, 0.62)
	env.ambient_light_sky_contribution = 0.78
	env.ambient_light_energy = 0.88

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.06
	env.tonemap_white = 6.2

	var is_web := OS.has_feature("web")
	# Realism upgrades: Screen-Space Ambient Occlusion (SSAO) & Screen-Space Reflections (SSR) on desktop Forward+
	env.ssao_enabled = not is_web
	env.ssao_radius = 1.15
	env.ssao_intensity = 1.85
	env.ssao_power = 1.35
	env.ssao_detail = 0.55

	env.ssr_enabled = not is_web
	env.ssr_max_steps = 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0

	env.fog_enabled = not is_web
	env.fog_light_color = Color(0.50, 0.52, 0.55)
	env.fog_light_energy = 0.85
	env.fog_density = 0.0034
	env.fog_aerial_perspective = 0.42

	env.glow_enabled = not is_web
	env.glow_intensity = 0.42
	env.glow_bloom = 0.06
	return env

static func create_muddy_turf_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.82, 0.76)
	mat.albedo_texture = load_texture_safe("res://assets/textures/turf_muddy_albedo.png")
	mat.roughness = 0.90
	mat.roughness_texture = load_texture_safe("res://assets/textures/turf_muddy_roughness.png")
	mat.normal_enabled = true
	mat.normal_scale = 1.55
	mat.normal_texture = load_texture_safe("res://assets/textures/turf_muddy_normal.png")
	mat.uv1_scale = Vector3(30.0, 36.0, 1.0)
	return mat

static func create_scuffed_vinyl_material(base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var weathered := base_color.lerp(Color(0.30, 0.29, 0.27), 0.26)
	mat.albedo_color = weathered
	mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	mat.roughness = 0.44
	mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	mat.normal_enabled = true
	mat.normal_scale = 1.30
	mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.38
	mat.clearcoat_roughness = 0.24
	mat.uv1_scale = Vector3(1.8, 1.6, 1.8)
	return mat

static func create_wood_spool_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.74, 0.68)
	mat.albedo_texture = load_texture_safe("res://assets/textures/wood_spool_albedo.png")
	mat.roughness = 0.84
	mat.normal_enabled = true
	mat.normal_scale = 0.95
	mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return mat

static func create_oily_paint_material(color: Color, use_splat_mask: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.08
	mat.roughness = 0.10
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.92
	mat.clearcoat_roughness = 0.06
	mat.emission_enabled = true
	mat.emission = color * 0.55
	mat.emission_energy_multiplier = 0.26
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
	puddle_mat.albedo_color = Color(0.10, 0.09, 0.08, 0.94)
	puddle_mat.metallic = 0.42
	puddle_mat.roughness = 0.04
	puddle_mat.clearcoat_enabled = true
	puddle_mat.clearcoat = 0.98
	puddle_mat.clearcoat_roughness = 0.03

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

	# Placed strictly outside the 108m x 132m playing field perimeter (|X| >= 55m, |Z| >= 67m)
	var tower_positions := [
		Vector3(-55.5, 0.0, -64.0),
		Vector3(55.5, 0.0, -64.0),
		Vector3(-55.5, 0.0, 0.0),
		Vector3(55.5, 0.0, 0.0),
		Vector3(-55.5, 0.0, 64.0),
		Vector3(55.5, 0.0, 64.0),
		Vector3(-26.0, 0.0, -67.5),
		Vector3(26.0, 0.0, -67.5)
	]

	for i in range(tower_positions.size()):
		var pos: Vector3 = tower_positions[i]
		var pole_h := 22.0
		var tower := Node3D.new()
		tower.name = "StadiumFloodlightTower_%d" % i
		tower.position = pos
		parent.add_child(tower)

		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.28
		cyl.height = pole_h
		pole.mesh = cyl
		pole.position = Vector3(0.0, pole_h * 0.5, 0.0)
		pole.material_override = pole_mat
		tower.add_child(pole)

		var crossbar := MeshInstance3D.new()
		var cb_box := BoxMesh.new()
		cb_box.size = Vector3(3.2, 0.24, 0.30)
		crossbar.mesh = cb_box
		crossbar.position = Vector3(0.0, pole_h, 0.0)
		crossbar.material_override = pole_mat
		tower.add_child(crossbar)

		for b in range(4):
			var lamp := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.52, 0.38, 0.24)
			lamp.mesh = lbox
			lamp.position = Vector3(-1.05 + b * 0.70, pole_h + 0.26, 0.08)
			lamp.material_override = bulb_mat
			tower.add_child(lamp)

		if i < 6 and not OS.has_feature("web"):
			var light := OmniLight3D.new()
			light.position = Vector3(0.0, pole_h - 0.5, 0.0)
			light.light_color = Color(0.92, 0.95, 1.0)
			light.light_energy = 2.6
			light.omni_range = 75.0
			tower.add_child(light)

static func _build_perimeter_safety_netting(parent: Node3D) -> void:
	var net_root := Node3D.new()
	net_root.name = "PerimeterSafetyNetting"
	parent.add_child(net_root)

	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.08, 0.09, 0.10, 0.36)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.roughness = 0.9

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.15, 0.16, 0.18)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5

	# Strictly outer boundary walls around the 108m x 132m field (no net cutting through the map!)
	var wall_specs := [
		{"pos": Vector3(0.0, 4.6, -65.6), "size": Vector3(107.2, 9.2, 0.06)},
		{"pos": Vector3(0.0, 4.6, 65.6), "size": Vector3(107.2, 9.2, 0.06)},
		{"pos": Vector3(-53.6, 4.6, 0.0), "size": Vector3(0.06, 9.2, 131.2)},
		{"pos": Vector3(53.6, 4.6, 0.0), "size": Vector3(0.06, 9.2, 131.2)}
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

	# Outer perimeter support poles along sidelines and backlines only
	for z_sign in [-1.0, 1.0]:
		for x_pos in [-48.0, -32.0, -16.0, 0.0, 16.0, 32.0, 48.0]:
			var post := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 0.08
			pcyl.bottom_radius = 0.10
			pcyl.height = 9.4
			post.mesh = pcyl
			post.position = Vector3(x_pos, 4.7, 65.6 * z_sign)
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

	# Placed outside the playing turf behind the North/South backlines so they never block lanes
	var placements := [
		{"name": "TournamentScoreboard", "pos": Vector3(0.0, 0.0, -64.2), "scale": 1.65},
		{"name": "TournamentScoreboard_South", "pos": Vector3(0.0, 0.0, 64.2), "scale": 1.65}
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

		_add_single_wood_spool_meshes(body, Vector3(0.0, 0.0, 0.0), 0.80, 0.78, wood_mat)
		if sp["stacked"]:
			_add_single_wood_spool_meshes(body, Vector3(0.0, 0.78, 0.0), 0.74, 0.74, wood_mat)
			# Extra upright flange wheel leaning beside the stacked spool + matching tight collider
			var wheel := MeshInstance3D.new()
			var wcyl := CylinderMesh.new()
			wcyl.top_radius = 0.70
			wcyl.bottom_radius = 0.70
			wcyl.height = 0.12
			wheel.mesh = wcyl
			wheel.position = Vector3(0.74, 0.66, 0.30)
			wheel.rotation_degrees = Vector3(90.0, -24.0, 8.0)
			wheel.material_override = wood_mat
			body.add_child(wheel)

			var wheel_col := CollisionShape3D.new()
			wheel_col.name = "WheelCollider"
			var wshape := CylinderShape3D.new()
			wshape.radius = 0.70
			wshape.height = 0.12
			wshape.margin = 0.001
			wheel_col.shape = wshape
			wheel_col.position = wheel.position
			wheel_col.rotation_degrees = wheel.rotation_degrees
			body.add_child(wheel_col)

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

	# Exact core cylinder collider (recessed inner drum so shots pass cleanly between flanges!)
	var core_col := CollisionShape3D.new()
	var core_shape := CylinderShape3D.new()
	core_shape.radius = radius * 0.56
	core_shape.height = height
	core_shape.margin = 0.001
	core_col.shape = core_shape
	core_col.position = core.position
	parent.add_child(core_col)

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

		var flange_col := CollisionShape3D.new()
		var fshape := CylinderShape3D.new()
		fshape.radius = radius
		fshape.height = 0.08
		fshape.margin = 0.001
		flange_col.shape = fshape
		flange_col.position = flange.position
		parent.add_child(flange_col)

static func _create_tapered_bunker_mesh(size: Vector3, top_x_ratio: float, top_z_ratio: float) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var thx := hx * top_x_ratio
	var thz := hz * top_z_ratio

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var b0 := Vector3(-hx, -hy, -hz)
	var b1 := Vector3(hx, -hy, -hz)
	var b2 := Vector3(hx, -hy, hz)
	var b3 := Vector3(-hx, -hy, hz)

	var t0 := Vector3(-thx, hy, -thz)
	var t1 := Vector3(thx, hy, -thz)
	var t2 := Vector3(thx, hy, thz)
	var t3 := Vector3(-thx, hy, thz)

	_add_quad_to_st(st, b3, b2, t2, t3) # +Z face
	_add_quad_to_st(st, b1, b0, t0, t1) # -Z face
	_add_quad_to_st(st, b2, b1, t1, t2) # +X face
	_add_quad_to_st(st, b0, b3, t3, t0) # -X face
	_add_quad_to_st(st, t3, t2, t1, t0) # Top face
	_add_quad_to_st(st, b0, b1, b2, b3) # Bottom face

	st.generate_tangents()
	return st.commit()

static func _add_quad_to_st(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	# Godot 4 uses clockwise (CW) winding for front-facing triangles: (v0 -> v3 -> v2) and (v0 -> v2 -> v1)
	var n := (v1 - v0).cross(v3 - v0).normalized()
	st.set_normal(n)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(v0)
	st.set_normal(n)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v3)
	st.set_normal(n)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(v2)

	st.set_normal(n)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(v0)
	st.set_normal(n)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(v2)
	st.set_normal(n)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v1)

static func _create_curved_bunker_splat_mesh(radius_x: float, radius_z: float, arc_center_angle: float, arc_span: float, height_span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps_u := 8
	var steps_v := 4
	for iu in range(steps_u):
		var u0 := float(iu) / float(steps_u)
		var u1 := float(iu + 1) / float(steps_u)
		var a0 := arc_center_angle + (u0 - 0.5) * arc_span
		var a1 := arc_center_angle + (u1 - 0.5) * arc_span
		for iv in range(steps_v):
			var v0 := float(iv) / float(steps_v)
			var v1 := float(iv + 1) / float(steps_v)
			var y0 := (v0 - 0.5) * height_span
			var y1 := (v1 - 0.5) * height_span

			var p00 := Vector3(sin(a0) * radius_x, y0, cos(a0) * radius_z)
			var p10 := Vector3(sin(a1) * radius_x, y0, cos(a1) * radius_z)
			var p11 := Vector3(sin(a1) * radius_x, y1, cos(a1) * radius_z)
			var p01 := Vector3(sin(a0) * radius_x, y1, cos(a0) * radius_z)

			var n0 := Vector3(sin(a0), 0.0, cos(a0)).normalized()
			var n1 := Vector3(sin(a1), 0.0, cos(a1)).normalized()

			st.set_normal(n0); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_normal(n1); st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
			st.set_normal(n1); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)

			st.set_normal(n0); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_normal(n1); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_normal(n0); st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)
	return st.commit()

static func decorate_bunker_mesh(bunker_body: StaticBody3D, mesh_inst: MeshInstance3D, size: Vector3, base_color: Color) -> void:
	mesh_inst.material_override = create_scuffed_vinyl_material(base_color)
	var bname := bunker_body.name

	var is_cylinder_can := false
	var is_horizontal_tube := false

	if "Dorito" in bname:
		# Authentic tapered 3D pyramid Dorito inflatable
		mesh_inst.mesh = _create_tapered_bunker_mesh(size, 0.14, 0.14)
	elif "Wedge" in bname:
		# Low profile tapered attacking wedge
		mesh_inst.mesh = _create_tapered_bunker_mesh(size, 0.55, 0.22)
	elif "Aztec" in bname or "Temple" in bname or "Gate" in bname or "Win" in bname or "Center50_W" in bname or "BackCenter" in bname:
		# Tapered tournament temple / Aztec / gate prism
		mesh_inst.mesh = _create_tapered_bunker_mesh(size, 0.72, 0.58)
	elif "Can" in bname or "Tower" in bname or "Pin" in bname or (size.y >= 1.8 and abs(size.x - size.z) < 0.75):
		# Cylindrical / dome-topped inflatable Can
		is_cylinder_can = true
		var cap := CapsuleMesh.new()
		cap.radius = min(size.x, size.z) * 0.48
		cap.height = max(size.y, cap.radius * 2.05)
		cap.radial_segments = 24
		cap.rings = 6
		mesh_inst.mesh = cap
	elif size.y < 1.3 and size.z > 3.0:
		# Horizontal cylindrical bolster / snake beam
		is_horizontal_tube = true
		var cyl := CapsuleMesh.new()
		cyl.radius = min(size.x, size.y) * 0.48
		cyl.height = size.z
		cyl.radial_segments = 20
		cyl.rings = 6
		mesh_inst.mesh = cyl
		mesh_inst.rotation_degrees.x = 90.0
	else:
		# Slightly tapered inflatable cake / brick / knuckle so edges aren't razor-sharp boxes
		mesh_inst.mesh = _create_tapered_bunker_mesh(size, 0.86, 0.82)

	# Tighten and shape the bunker's CollisionShape3D to match the exact 3D mesh geometry (zero invisible corner walls!)
	for child in bunker_body.get_children():
		if child is CollisionShape3D:
			var cshape_node := child as CollisionShape3D
			cshape_node.transform = mesh_inst.transform
			if is_cylinder_can:
				var cap_shape_can := CapsuleShape3D.new()
				cap_shape_can.radius = min(size.x, size.z) * 0.48
				cap_shape_can.height = max(size.y, cap_shape_can.radius * 2.05)
				cap_shape_can.margin = 0.001
				cshape_node.shape = cap_shape_can
			elif is_horizontal_tube:
				var cap_shape := CapsuleShape3D.new()
				cap_shape.radius = min(size.x, size.y) * 0.48
				cap_shape.height = size.z
				cap_shape.margin = 0.001
				cshape_node.shape = cap_shape
			else:
				var conv := mesh_inst.mesh.create_convex_shape(true, false)
				conv.margin = 0.001
				cshape_node.shape = conv
			break

	# Bunkers start without pre-baked center paint splats; live paintballs project wrapped splats where they break.

static func upgrade_first_person_marker(marker_rig: Node3D, body_mesh: MeshInstance3D, hopper_mesh: MeshInstance3D, hopper_lid_mesh: MeshInstance3D) -> void:
	# 1. Weathered scratched anodized gunmetal/silver marker body
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.50, 0.52, 0.55)
	metal_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	metal_mat.metallic = 0.88
	metal_mat.roughness = 0.28
	metal_mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	metal_mat.normal_enabled = true
	metal_mat.normal_scale = 0.95
	metal_mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")
	body_mesh.material_override = metal_mat

	# Anodized tournament blue accent milling & clamping feedneck
	var anno_blue_mat := StandardMaterial3D.new()
	anno_blue_mat.albedo_color = Color(0.16, 0.34, 0.68)
	anno_blue_mat.metallic = 0.90
	anno_blue_mat.roughness = 0.24

	var feedneck := MeshInstance3D.new()
	feedneck.name = "ClampingFeedneck"
	var fn_cyl := CylinderMesh.new()
	fn_cyl.top_radius = 0.020
	fn_cyl.bottom_radius = 0.022
	fn_cyl.height = 0.055
	feedneck.mesh = fn_cyl
	feedneck.position = Vector3(0.0, 0.058, 0.04)
	feedneck.material_override = anno_blue_mat
	marker_rig.add_child(feedneck)

	# Foregrip Hyper-style inline regulator
	var reg := MeshInstance3D.new()
	reg.name = "InlineRegulator"
	var reg_cyl := CylinderMesh.new()
	reg_cyl.top_radius = 0.018
	reg_cyl.bottom_radius = 0.020
	reg_cyl.height = 0.11
	reg.mesh = reg_cyl
	reg.position = Vector3(0.0, -0.075, -0.14)
	reg.material_override = anno_blue_mat
	marker_rig.add_child(reg)

	# 2. Two-piece ported competition barrel (anno back + matte carbon/gunmetal front tip)
	var barrel := MeshInstance3D.new()
	barrel.name = "MarkerBarrel"
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.015
	bcyl.bottom_radius = 0.019
	bcyl.height = 0.44
	barrel.mesh = bcyl
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.025, -0.39)
	barrel.material_override = metal_mat
	marker_rig.add_child(barrel)

	# 3. Scuffed dark loader/hopper with wrapped paint smear
	var hopper_mat := StandardMaterial3D.new()
	hopper_mat.albedo_color = Color(0.20, 0.21, 0.23)
	hopper_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	hopper_mat.roughness = 0.26
	hopper_mat.clearcoat_enabled = true
	hopper_mat.clearcoat = 0.68
	hopper_mat.clearcoat_roughness = 0.16
	hopper_mesh.material_override = hopper_mat

	var yellow_smear := MeshInstance3D.new()
	yellow_smear.name = "HopperPaintSmearYellow"
	var ys_sphere := SphereMesh.new()
	ys_sphere.radius = 0.0865
	ys_sphere.height = 0.1415
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
	needle.name = "GaugeNeedle"
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

static func spawn_muzzle_gas_puff(scene_root: Node, muzzle_pos: Vector3, forward_dir: Vector3) -> void:
	if scene_root == null:
		return
	var puff_root := Node3D.new()
	puff_root.name = "HpaMuzzleVaporPuff"
	scene_root.add_child(puff_root)
	puff_root.global_position = muzzle_pos

	var particles := CPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 10
	particles.lifetime = 0.18

	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.022
	puff_mesh.height = 0.044
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(0.88, 0.92, 0.96, 0.28)
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	puff_mesh.material = puff_mat
	particles.mesh = puff_mesh

	particles.direction = forward_dir.normalized()
	particles.spread = 22.0
	particles.initial_velocity_min = 3.5
	particles.initial_velocity_max = 8.0
	particles.damping_min = 18.0
	particles.damping_max = 26.0
	particles.gravity = Vector3(0.0, 0.8, 0.0)
	puff_root.add_child(particles)

	var timer := scene_root.get_tree().create_timer(0.25)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(puff_root):
			puff_root.queue_free()
	)

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
	particles.amount = 24
	particles.lifetime = 0.55

	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.026
	droplet_mesh.height = 0.052
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
