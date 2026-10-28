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
static var _vinyl_mat_cache: Dictionary = {}
static var _paint_mat_cache: Dictionary = {}
static var _puff_mesh_cached: SphereMesh = null

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
	var cache_key := base_color.to_html(false)
	if _vinyl_mat_cache.has(cache_key):
		return _vinyl_mat_cache[cache_key]
	var mat := StandardMaterial3D.new()
	var weathered := base_color.lerp(Color(0.30, 0.29, 0.27), 0.26)
	mat.albedo_color = weathered
	mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	mat.roughness = 0.44
	mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	mat.normal_enabled = not OS.has_feature("web")
	mat.normal_scale = 1.30
	mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png") if not OS.has_feature("web") else null
	mat.clearcoat_enabled = not OS.has_feature("web")
	mat.clearcoat = 0.38
	mat.clearcoat_roughness = 0.24
	mat.uv1_scale = Vector3(1.8, 1.6, 1.8)
	_vinyl_mat_cache[cache_key] = mat
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
	var cache_key := "%s_%s" % [color.to_html(false), "mask" if use_splat_mask else "solid"]
	if _paint_mat_cache.has(cache_key):
		return _paint_mat_cache[cache_key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.08
	mat.roughness = 0.10
	mat.clearcoat_enabled = not OS.has_feature("web")
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
	_paint_mat_cache[cache_key] = mat
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

		var wall_body := StaticBody3D.new()
		wall_body.name = "SafetyNetWallBody_%d" % idx
		wall_body.position = spec["pos"]
		var wall_col := CollisionShape3D.new()
		wall_col.name = "CollisionShape3D"
		var wall_box := BoxShape3D.new()
		var sz: Vector3 = spec["size"]
		wall_box.size = Vector3(maxf(sz.x, 1.2), 14.0, maxf(sz.z, 1.2))
		wall_col.shape = wall_box
		wall_body.add_child(wall_col)
		net_root.add_child(wall_body)

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

	mesh_inst.set_meta("base_scale", mesh_inst.scale)
	mesh_inst.set_meta("base_pos", mesh_inst.position)
	mesh_inst.set_meta("base_rot_deg", mesh_inst.rotation_degrees)
	# Bunkers start without pre-baked center paint splats; live paintballs project wrapped splats where they break.

static func _compute_bunker_deform(base_scale: Vector3, base_pos: Vector3, base_rot: Vector3, local_dir: Vector3, amp: float) -> Dictionary:
	var ax := absf(local_dir.x)
	var az := absf(local_dir.z)
	var world_scale_x: float = clampf(1.0 - amp * 1.18 * ax + amp * 1.05 * az, 0.44, 1.65)
	var world_scale_z: float = clampf(1.0 - amp * 1.18 * az + amp * 1.05 * ax, 0.44, 1.65)
	var world_scale_y: float = clampf(1.0 + amp * 0.68, 1.0, 1.48)
	var is_horiz_tube: bool = absf(base_rot.x) > 45.0
	var out_scale := Vector3(
		base_scale.x * world_scale_x,
		base_scale.y * (world_scale_z if is_horiz_tube else world_scale_y),
		base_scale.z * (world_scale_y if is_horiz_tube else world_scale_z)
	)
	var out_pos := base_pos + Vector3(local_dir.x * amp * 0.62, base_scale.y * (world_scale_y - 1.0) * 0.36, local_dir.z * amp * 0.62)
	var out_rot := base_rot + Vector3(local_dir.z * amp * 28.0, 0.0, -local_dir.x * amp * 28.0)
	return {"scale": out_scale, "pos": out_pos, "rot": out_rot}

static func trigger_bunker_vinyl_flex(bunker_body: Node3D, impact_dir: Vector3, intensity: float = 0.34, keep_sustained_pocket: bool = false) -> void:
	if bunker_body == null or not is_instance_valid(bunker_body):
		return
	if bool(bunker_body.get_meta("is_rigid_cover", false)) or bool(bunker_body.get_meta("rigid_cover", false)) or String(bunker_body.name).begins_with("WoodSpool") or String(bunker_body.name).begins_with("Woods_") or String(bunker_body.name).begins_with("Tower_") or String(bunker_body.name).begins_with("Heli_") or String(bunker_body.name) == "TurfFloor" or String(bunker_body.name).begins_with("SafetyNet"):
		return
	var mesh_inst := bunker_body.get_node_or_null("BunkerMesh") as MeshInstance3D
	if mesh_inst == null:
		return
	var base_scale: Vector3 = mesh_inst.get_meta("base_scale", Vector3.ONE)
	var base_pos: Vector3 = mesh_inst.get_meta("base_pos", Vector3.ZERO)
	var base_rot: Vector3 = mesh_inst.get_meta("base_rot_deg", Vector3.ZERO)
	var dir := impact_dir
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3(0, 0, -1)
	else:
		dir = dir.normalized()
	var local_dir := (bunker_body.global_transform.basis.inverse() * dir).normalized()
	var amp := clampf(intensity, 0.08, 0.52)
	var peak := _compute_bunker_deform(base_scale, base_pos, base_rot, local_dir, amp)
	mesh_inst.scale = peak["scale"]
	mesh_inst.position = peak["pos"]
	mesh_inst.rotation_degrees = peak["rot"]
	bunker_body.set_meta("last_vinyl_flex_intensity", amp)
	bunker_body.set_meta("vinyl_flex_active", true)
	if bunker_body.has_meta("vinyl_flex_tween"):
		var old_tw: Tween = bunker_body.get_meta("vinyl_flex_tween") as Tween
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
	if bunker_body.is_inside_tree():
		var settle_amp: float = amp * 0.58 if (keep_sustained_pocket or amp >= 0.25) else 0.0
		var settle := _compute_bunker_deform(base_scale, base_pos, base_rot, local_dir, settle_amp) if settle_amp > 0.01 else {"scale": base_scale, "pos": base_pos, "rot": base_rot}
		var tw := bunker_body.create_tween()
		bunker_body.set_meta("vinyl_flex_tween", tw)
		tw.set_parallel(true)
		tw.tween_property(mesh_inst, "scale", settle["scale"], 0.62).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mesh_inst, "position", settle["pos"], 0.62).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mesh_inst, "rotation_degrees", settle["rot"], 0.62).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

static func apply_sustained_bunker_pocket_bulge(bunker_body: Node3D, push_dir: Vector3, pocket_weight: float, lean_amount: float, delta: float) -> void:
	if bunker_body == null or not is_instance_valid(bunker_body):
		return
	if bool(bunker_body.get_meta("is_rigid_cover", false)) or bool(bunker_body.get_meta("rigid_cover", false)) or String(bunker_body.name).begins_with("WoodSpool") or String(bunker_body.name).begins_with("Woods_") or String(bunker_body.name).begins_with("Tower_") or String(bunker_body.name).begins_with("Heli_") or String(bunker_body.name) == "TurfFloor" or String(bunker_body.name).begins_with("SafetyNet"):
		return
	var mesh_inst := bunker_body.get_node_or_null("BunkerMesh") as MeshInstance3D
	if mesh_inst == null:
		return
	if bunker_body.has_meta("vinyl_flex_tween"):
		var active_tw: Tween = bunker_body.get_meta("vinyl_flex_tween") as Tween
		if active_tw != null and active_tw.is_running():
			return
	var base_scale: Vector3 = mesh_inst.get_meta("base_scale", Vector3.ONE)
	var base_pos: Vector3 = mesh_inst.get_meta("base_pos", Vector3.ZERO)
	var base_rot: Vector3 = mesh_inst.get_meta("base_rot_deg", Vector3.ZERO)
	if pocket_weight <= 0.05:
		mesh_inst.scale = mesh_inst.scale.lerp(base_scale, minf(1.0, delta * 10.0))
		mesh_inst.position = mesh_inst.position.lerp(base_pos, minf(1.0, delta * 10.0))
		mesh_inst.rotation_degrees = mesh_inst.rotation_degrees.lerp(base_rot, minf(1.0, delta * 10.0))
		return
	var dir := push_dir
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3(0, 0, -1)
	else:
		dir = dir.normalized()
	var local_dir := (bunker_body.global_transform.basis.inverse() * dir).normalized()
	var press := clampf(pocket_weight * (0.26 + absf(lean_amount) * 0.14), 0.0, 0.42)
	var target := _compute_bunker_deform(base_scale, base_pos, base_rot, local_dir, press)
	mesh_inst.scale = mesh_inst.scale.lerp(target["scale"], minf(1.0, delta * 14.0))
	mesh_inst.position = mesh_inst.position.lerp(target["pos"], minf(1.0, delta * 14.0))
	mesh_inst.rotation_degrees = mesh_inst.rotation_degrees.lerp(target["rot"], minf(1.0, delta * 14.0))
	bunker_body.set_meta("vinyl_flex_active", true)

static func upgrade_first_person_marker(marker_rig: Node3D, body_mesh: MeshInstance3D, hopper_mesh: MeshInstance3D, hopper_lid_mesh: MeshInstance3D) -> void:
	# Hide legacy generic box mesh; we build 3 distinct bracket-specific 3D marker assemblies inside marker_rig
	body_mesh.visible = false

	# Shared materials
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.50, 0.52, 0.55)
	metal_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	metal_mat.metallic = 0.88
	metal_mat.roughness = 0.28
	metal_mat.roughness_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_roughness.png")
	metal_mat.normal_enabled = true
	metal_mat.normal_scale = 0.95
	metal_mat.normal_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_normal.png")

	var dark_metal_mat := StandardMaterial3D.new()
	dark_metal_mat.albedo_color = Color(0.16, 0.17, 0.19)
	dark_metal_mat.metallic = 0.82
	dark_metal_mat.roughness = 0.34

	var anno_blue_mat := StandardMaterial3D.new()
	anno_blue_mat.albedo_color = Color(0.14, 0.42, 0.88)
	anno_blue_mat.metallic = 0.92
	anno_blue_mat.roughness = 0.22

	var olive_drab_mat := StandardMaterial3D.new()
	olive_drab_mat.albedo_color = Color(0.27, 0.33, 0.22)
	olive_drab_mat.roughness = 0.68
	olive_drab_mat.metallic = 0.25

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.82, 0.64, 0.24)
	brass_mat.metallic = 0.88
	brass_mat.roughness = 0.26

	var wood_grip_mat := StandardMaterial3D.new()
	wood_grip_mat.albedo_color = Color(0.38, 0.23, 0.13)
	wood_grip_mat.roughness = 0.62

	var carbon_mat := StandardMaterial3D.new()
	var c_tex := load_texture_safe("res://assets/textures/carbon_hpa_tank.png")
	if c_tex != null:
		carbon_mat.albedo_texture = c_tex
		carbon_mat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		carbon_mat.albedo_color = Color(0.15, 0.16, 0.18)
	carbon_mat.metallic = 0.45
	carbon_mat.roughness = 0.22
	carbon_mat.clearcoat_enabled = true
	carbon_mat.clearcoat = 0.85
	carbon_mat.clearcoat_roughness = 0.12

	var smoke_tube_mat := StandardMaterial3D.new()
	smoke_tube_mat.albedo_color = Color(0.75, 0.80, 0.86, 0.55)
	smoke_tube_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_tube_mat.roughness = 0.18

	var hopper_mat := StandardMaterial3D.new()
	hopper_mat.albedo_color = Color(0.20, 0.21, 0.23)
	hopper_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	hopper_mat.roughness = 0.26
	hopper_mat.clearcoat_enabled = true
	hopper_mat.clearcoat = 0.68
	hopper_mat.clearcoat_roughness = 0.16
	hopper_mesh.material_override = hopper_mat
	hopper_mesh.scale = Vector3(0.88, 0.92, 1.35)

	var yellow_smear := MeshInstance3D.new()
	yellow_smear.name = "HopperPaintSmearYellow"
	var ys_sphere := SphereMesh.new()
	ys_sphere.radius = 0.0865
	ys_sphere.height = 0.1415
	yellow_smear.mesh = ys_sphere
	yellow_smear.position = hopper_mesh.position
	yellow_smear.scale = hopper_mesh.scale
	yellow_smear.material_override = create_oily_paint_material(NEON_YELLOW_PAINT, true)
	marker_rig.add_child(yellow_smear)

	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.18, 0.18, 0.20, 0.92)
	lid_mat.roughness = 0.32
	hopper_lid_mesh.material_override = lid_mat

	# =========================================================================
	# 1. SPEEDBALL ELECTRO VIEWMODEL (2004 Stacked-Tube Intimidator / Ego + Halo B + 68/4500 HPA)
	# =========================================================================
	var sb_root := Node3D.new()
	sb_root.name = "FP_SpeedballAssembly"
	marker_rig.add_child(sb_root)

	var upper_tube := MeshInstance3D.new()
	upper_tube.name = "UpperBoltTube"
	var ut_cyl := CylinderMesh.new()
	ut_cyl.top_radius = 0.019
	ut_cyl.bottom_radius = 0.019
	ut_cyl.height = 0.25
	upper_tube.mesh = ut_cyl
	upper_tube.rotation_degrees.x = 90.0
	upper_tube.position = Vector3(0.0, 0.028, 0.0)
	upper_tube.material_override = anno_blue_mat
	sb_root.add_child(upper_tube)

	var lower_tube := MeshInstance3D.new()
	lower_tube.name = "LowerRammerTube"
	var lt_cyl := CylinderMesh.new()
	lt_cyl.top_radius = 0.018
	lt_cyl.bottom_radius = 0.018
	lt_cyl.height = 0.23
	lower_tube.mesh = lt_cyl
	lower_tube.rotation_degrees.x = 90.0
	lower_tube.position = Vector3(0.0, -0.006, 0.01)
	lower_tube.material_override = metal_mat
	sb_root.add_child(lower_tube)

	var milled_web := MeshInstance3D.new()
	var mw_box := BoxMesh.new()
	mw_box.size = Vector3(0.028, 0.042, 0.19)
	milled_web.mesh = mw_box
	milled_web.position = Vector3(0.0, 0.01, 0.01)
	milled_web.material_override = anno_blue_mat
	sb_root.add_child(milled_web)

	# Exposed reciprocating Delrin bolt at rear of upper tube
	var bolt_pin := MeshInstance3D.new()
	bolt_pin.name = "ElectroBoltPin"
	var bp_cyl := CylinderMesh.new()
	bp_cyl.top_radius = 0.015
	bp_cyl.bottom_radius = 0.015
	bp_cyl.height = 0.055
	bolt_pin.mesh = bp_cyl
	bolt_pin.rotation_degrees.x = 90.0
	bolt_pin.position = Vector3(0.0, 0.028, 0.13)
	bolt_pin.material_override = dark_metal_mat
	sb_root.add_child(bolt_pin)

	var feedneck := MeshInstance3D.new()
	feedneck.name = "ClampingFeedneck"
	var fn_cyl := CylinderMesh.new()
	fn_cyl.top_radius = 0.020
	fn_cyl.bottom_radius = 0.022
	fn_cyl.height = 0.055
	feedneck.mesh = fn_cyl
	feedneck.position = Vector3(0.0, 0.062, 0.04)
	feedneck.material_override = anno_blue_mat
	sb_root.add_child(feedneck)

	# Hyper2 vertical inline regulator + braided macroline
	var reg := MeshInstance3D.new()
	reg.name = "InlineRegulator"
	var reg_cyl := CylinderMesh.new()
	reg_cyl.top_radius = 0.018
	reg_cyl.bottom_radius = 0.020
	reg_cyl.height = 0.115
	reg.mesh = reg_cyl
	reg.position = Vector3(0.0, -0.072, -0.095)
	reg.material_override = anno_blue_mat
	sb_root.add_child(reg)

	# Double-trigger competition frame + glowing LED indicator
	var grip_frame := MeshInstance3D.new()
	var gf_box := BoxMesh.new()
	gf_box.size = Vector3(0.032, 0.115, 0.048)
	grip_frame.mesh = gf_box
	grip_frame.position = Vector3(0.0, -0.068, 0.055)
	grip_frame.rotation_degrees.x = -16.0
	grip_frame.material_override = dark_metal_mat
	sb_root.add_child(grip_frame)

	var trigger_guard := MeshInstance3D.new()
	var tg_box := BoxMesh.new()
	tg_box.size = Vector3(0.014, 0.075, 0.045)
	trigger_guard.mesh = tg_box
	trigger_guard.position = Vector3(0.0, -0.062, 0.005)
	trigger_guard.material_override = anno_blue_mat
	sb_root.add_child(trigger_guard)

	var led_dot := MeshInstance3D.new()
	var led_box := BoxMesh.new()
	led_box.size = Vector3(0.035, 0.008, 0.008)
	led_dot.mesh = led_box
	led_dot.position = Vector3(0.0, -0.035, 0.06)
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.2, 1.0, 0.35)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.2, 1.0, 0.35)
	led_mat.emission_energy_multiplier = 2.5
	led_dot.material_override = led_mat
	sb_root.add_child(led_dot)

	# Two-piece 14" Ultralite ported barrel (anodized blue back + matte carbon tip)
	var barrel_back := MeshInstance3D.new()
	barrel_back.name = "MarkerBarrel"
	var bb_cyl := CylinderMesh.new()
	bb_cyl.top_radius = 0.017
	bb_cyl.bottom_radius = 0.019
	bb_cyl.height = 0.18
	barrel_back.mesh = bb_cyl
	barrel_back.rotation_degrees.x = 90.0
	barrel_back.position = Vector3(0.0, 0.028, -0.20)
	barrel_back.material_override = anno_blue_mat
	sb_root.add_child(barrel_back)

	var barrel_tip := MeshInstance3D.new()
	barrel_tip.name = "PortedCarbonTip"
	var bt_cyl := CylinderMesh.new()
	bt_cyl.top_radius = 0.014
	bt_cyl.bottom_radius = 0.015
	bt_cyl.height = 0.26
	barrel_tip.mesh = bt_cyl
	barrel_tip.rotation_degrees.x = 90.0
	barrel_tip.position = Vector3(0.0, 0.028, -0.41)
	barrel_tip.material_override = dark_metal_mat
	sb_root.add_child(barrel_tip)

	# 68ci / 4500psi Carbon-Fiber HPA Tank mounted on bottom-line ASA
	var hpa_tank := MeshInstance3D.new()
	hpa_tank.name = "CarbonHPATank68_4500"
	var hpa_cap := CapsuleMesh.new()
	hpa_cap.radius = 0.052
	hpa_cap.height = 0.24
	hpa_tank.mesh = hpa_cap
	hpa_tank.rotation_degrees.x = 90.0
	hpa_tank.position = Vector3(0.0, -0.115, 0.22)
	hpa_tank.material_override = carbon_mat
	sb_root.add_child(hpa_tank)

	# =========================================================================
	# 2. WOODSBALL MECHANICAL VIEWMODEL (Tippmann A-5 Carbine + Cyclone Side-Feed + Shroud + Stock)
	# =========================================================================
	var wb_root := Node3D.new()
	wb_root.name = "FP_WoodsballAssembly"
	wb_root.visible = false
	marker_rig.add_child(wb_root)

	var a5_body := MeshInstance3D.new()
	a5_body.name = "A5CastReceiver"
	var a5_box := BoxMesh.new()
	a5_box.size = Vector3(0.048, 0.088, 0.30)
	a5_body.mesh = a5_box
	a5_body.position = Vector3(0.0, 0.008, 0.01)
	a5_body.material_override = olive_drab_mat
	wb_root.add_child(a5_body)

	# Raised Picatinny top rail + Front & Rear Ghost-Ring Iron Sights (clear center sightline!)
	var pic_rail := MeshInstance3D.new()
	pic_rail.name = "PicatinnyTopRail"
	var pr_box := BoxMesh.new()
	pr_box.size = Vector3(0.024, 0.014, 0.28)
	pic_rail.mesh = pr_box
	pic_rail.position = Vector3(0.0, 0.058, 0.0)
	pic_rail.material_override = dark_metal_mat
	wb_root.add_child(pic_rail)

	var rear_sight := MeshInstance3D.new()
	var rs_box := BoxMesh.new()
	rs_box.size = Vector3(0.026, 0.026, 0.018)
	rear_sight.mesh = rs_box
	rear_sight.position = Vector3(0.0, 0.076, 0.11)
	rear_sight.material_override = dark_metal_mat
	wb_root.add_child(rear_sight)

	var front_sight := MeshInstance3D.new()
	var fs_box := BoxMesh.new()
	fs_box.size = Vector3(0.018, 0.030, 0.016)
	front_sight.mesh = fs_box
	front_sight.position = Vector3(0.0, 0.076, -0.34)
	front_sight.material_override = dark_metal_mat
	wb_root.add_child(front_sight)

	# Ventilated Cylindrical Forend Barrel Shroud + Heavy Muzzle Brake + Vertical Foregrip
	var shroud := MeshInstance3D.new()
	shroud.name = "VentilatedShroud"
	var sh_cyl := CylinderMesh.new()
	sh_cyl.top_radius = 0.028
	sh_cyl.bottom_radius = 0.028
	sh_cyl.height = 0.24
	shroud.mesh = sh_cyl
	shroud.rotation_degrees.x = 90.0
	shroud.position = Vector3(0.0, 0.018, -0.25)
	shroud.material_override = dark_metal_mat
	wb_root.add_child(shroud)

	var wb_barrel := MeshInstance3D.new()
	var wbb_cyl := CylinderMesh.new()
	wbb_cyl.top_radius = 0.015
	wbb_cyl.bottom_radius = 0.015
	wbb_cyl.height = 0.18
	wb_barrel.mesh = wbb_cyl
	wb_barrel.rotation_degrees.x = 90.0
	wb_barrel.position = Vector3(0.0, 0.018, -0.42)
	wb_barrel.material_override = metal_mat
	wb_root.add_child(wb_barrel)

	var v_foregrip := MeshInstance3D.new()
	v_foregrip.name = "VerticalForegrip"
	var vf_cyl := CylinderMesh.new()
	vf_cyl.top_radius = 0.016
	vf_cyl.bottom_radius = 0.018
	vf_cyl.height = 0.105
	v_foregrip.mesh = vf_cyl
	v_foregrip.position = Vector3(0.0, -0.055, -0.22)
	v_foregrip.material_override = olive_drab_mat
	wb_root.add_child(v_foregrip)

	# Cyclone Side-Feed Ratchet Turbine mounted on right side of receiver
	var cyclone_ratchet := MeshInstance3D.new()
	cyclone_ratchet.name = "CycloneRatchetHousing"
	var cr_cyl := CylinderMesh.new()
	cr_cyl.top_radius = 0.040
	cr_cyl.bottom_radius = 0.040
	cr_cyl.height = 0.062
	cyclone_ratchet.mesh = cr_cyl
	cyclone_ratchet.position = Vector3(0.055, 0.032, 0.02)
	cyclone_ratchet.material_override = dark_metal_mat
	wb_root.add_child(cyclone_ratchet)

	# Collapsible Rear Carbine Stock
	var stock_tube := MeshInstance3D.new()
	stock_tube.name = "CollapsibleCarbineStock"
	var st_box := BoxMesh.new()
	st_box.size = Vector3(0.034, 0.065, 0.22)
	stock_tube.mesh = st_box
	stock_tube.position = Vector3(0.0, -0.005, 0.24)
	stock_tube.material_override = dark_metal_mat
	wb_root.add_child(stock_tube)

	# =========================================================================
	# 3. STOCK-CLASS PUMP VIEWMODEL (Phantom / CCM Sniper Pump + 10-Round Tube + Sliding Pump + 12g CO2)
	# =========================================================================
	var pump_root := Node3D.new()
	pump_root.name = "FP_PumpAssembly"
	pump_root.visible = false
	marker_rig.add_child(pump_root)

	var pump_rec := MeshInstance3D.new()
	pump_rec.name = "StockPumpReceiver"
	var pr_cyl := CylinderMesh.new()
	pr_cyl.top_radius = 0.017
	pr_cyl.bottom_radius = 0.017
	pr_cyl.height = 0.27
	pump_rec.mesh = pr_cyl
	pump_rec.rotation_degrees.x = 90.0
	pump_rec.position = Vector3(0.0, 0.012, 0.01)
	pump_rec.material_override = dark_metal_mat
	pump_root.add_child(pump_rec)

	# Horizontal 10-Round Spring-Feed Tube mounted sleekly along the top (NO bulky hopper!)
	var ten_round_tube := MeshInstance3D.new()
	ten_round_tube.name = "TenRoundFeedTube"
	var tr_cyl := CylinderMesh.new()
	tr_cyl.top_radius = 0.014
	tr_cyl.bottom_radius = 0.014
	tr_cyl.height = 0.24
	ten_round_tube.mesh = tr_cyl
	ten_round_tube.rotation_degrees.x = 90.0
	ten_round_tube.position = Vector3(0.0, 0.048, -0.02)
	ten_round_tube.material_override = smoke_tube_mat
	pump_root.add_child(ten_round_tube)

	var brass_feed_ring := MeshInstance3D.new()
	var bfr_cyl := CylinderMesh.new()
	bfr_cyl.top_radius = 0.016
	bfr_cyl.bottom_radius = 0.016
	bfr_cyl.height = 0.032
	brass_feed_ring.mesh = bfr_cyl
	brass_feed_ring.rotation_degrees.x = 90.0
	brass_feed_ring.position = Vector3(0.0, 0.048, 0.02)
	brass_feed_ring.material_override = brass_mat
	pump_root.add_child(brass_feed_ring)

	var brass_cap := MeshInstance3D.new()
	brass_cap.name = "BrassFeedCap"
	var bc_cyl := CylinderMesh.new()
	bc_cyl.top_radius = 0.016
	bc_cyl.bottom_radius = 0.016
	bc_cyl.height = 0.022
	brass_cap.mesh = bc_cyl
	brass_cap.rotation_degrees.x = 90.0
	brass_cap.position = Vector3(0.0, 0.048, 0.105)
	brass_cap.material_override = brass_mat
	pump_root.add_child(brass_cap)

	# Long precision sniper barrel + front brass bead sight
	var sniper_barrel := MeshInstance3D.new()
	sniper_barrel.name = "SniperPumpBarrel"
	var sb_cyl := CylinderMesh.new()
	sb_cyl.top_radius = 0.012
	sb_cyl.bottom_radius = 0.014
	sb_cyl.height = 0.34
	sniper_barrel.mesh = sb_cyl
	sniper_barrel.rotation_degrees.x = 90.0
	sniper_barrel.position = Vector3(0.0, 0.012, -0.29)
	sniper_barrel.material_override = dark_metal_mat
	pump_root.add_child(sniper_barrel)

	var front_bead := MeshInstance3D.new()
	var fb_sph := SphereMesh.new()
	fb_sph.radius = 0.005
	fb_sph.height = 0.010
	front_bead.mesh = fb_sph
	front_bead.position = Vector3(0.0, 0.028, -0.44)
	front_bead.material_override = brass_mat
	pump_root.add_child(front_bead)

	# Dual Stainless Guide Rods + Animated Ribbed Under-Barrel Pump Handle
	for rod_x in [-0.012, 0.012]:
		var guide_rod := MeshInstance3D.new()
		var gr_cyl := CylinderMesh.new()
		gr_cyl.top_radius = 0.0035
		gr_cyl.bottom_radius = 0.0035
		gr_cyl.height = 0.22
		guide_rod.mesh = gr_cyl
		guide_rod.rotation_degrees.x = 90.0
		guide_rod.position = Vector3(rod_x, -0.014, -0.21)
		guide_rod.material_override = metal_mat
		pump_root.add_child(guide_rod)

	var pump_slide := Node3D.new()
	pump_slide.name = "PumpSlideRoot"
	pump_slide.position = Vector3(0.0, -0.018, -0.25)
	pump_root.add_child(pump_slide)

	var ribbed_pump := MeshInstance3D.new()
	ribbed_pump.name = "RibbedPumpGrip"
	var rp_cyl := CylinderMesh.new()
	rp_cyl.top_radius = 0.025
	rp_cyl.bottom_radius = 0.025
	rp_cyl.height = 0.12
	ribbed_pump.mesh = rp_cyl
	ribbed_pump.rotation_degrees.x = 90.0
	ribbed_pump.material_override = wood_grip_mat
	pump_slide.add_child(ribbed_pump)

	# Classic 45-degree Walnut Grip Frame + Rear 12-gram CO2 Quick-Change Cartridge
	var pump_grip := MeshInstance3D.new()
	var pg_box := BoxMesh.new()
	pg_box.size = Vector3(0.028, 0.11, 0.044)
	pump_grip.mesh = pg_box
	pump_grip.position = Vector3(0.0, -0.062, 0.06)
	pump_grip.rotation_degrees.x = -18.0
	pump_grip.material_override = wood_grip_mat
	pump_root.add_child(pump_grip)

	var co2_cart := MeshInstance3D.new()
	co2_cart.name = "TwelveGramCO2"
	var co2_cyl := CylinderMesh.new()
	co2_cyl.top_radius = 0.014
	co2_cyl.bottom_radius = 0.011
	co2_cyl.height = 0.105
	co2_cart.mesh = co2_cyl
	co2_cart.rotation_degrees.x = 76.0
	co2_cart.position = Vector3(0.0, -0.032, 0.165)
	co2_cart.material_override = brass_mat
	pump_root.add_child(co2_cart)

	# 4. Visible Air Pressure Gauge near the grip (shown on Speedball & Woodsball HPA/CO2 setups)
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

static func apply_first_person_bracket_visual(marker_rig: Node3D, hopper_mesh: MeshInstance3D, hopper_lid_mesh: MeshInstance3D, bracket_id: String) -> void:
	set_first_person_bracket_visual(marker_rig, hopper_mesh, hopper_lid_mesh, bracket_id)

static func set_first_person_bracket_visual(marker_rig: Node3D, hopper_mesh: MeshInstance3D, hopper_lid_mesh: MeshInstance3D, bracket_id: String) -> void:
	if marker_rig == null:
		return
	var b_id := bracket_id.to_lower()
	var sb := marker_rig.get_node_or_null("FP_SpeedballAssembly") as Node3D
	var wb := marker_rig.get_node_or_null("FP_WoodsballAssembly") as Node3D
	var pm := marker_rig.get_node_or_null("FP_PumpAssembly") as Node3D
	var smear := marker_rig.get_node_or_null("HopperPaintSmearYellow") as Node3D
	var gauge := marker_rig.get_node_or_null("MarkerPressureGauge") as Node3D

	if sb != null:
		sb.visible = (b_id == "speedball")
	if wb != null:
		wb.visible = (b_id == "woodsball")
	if pm != null:
		pm.visible = (b_id == "pump")
	if gauge != null:
		gauge.visible = (b_id != "pump")

	var show_hopper := (b_id != "pump")
	if hopper_mesh != null:
		hopper_mesh.visible = show_hopper
		if b_id == "woodsball":
			# Cyclone side-feed hopper offset to the right of the A-5 receiver so center iron sights stay clear!
			hopper_mesh.position = Vector3(0.062, 0.095, 0.02)
			hopper_mesh.scale = Vector3(0.95, 0.82, 1.12)
		else:
			# Speedball centered Halo B egg loader on top of clamping feedneck
			hopper_mesh.position = Vector3(0.0, 0.115, 0.04)
			hopper_mesh.scale = Vector3(0.88, 0.92, 1.35)
	if smear != null and hopper_mesh != null:
		smear.visible = show_hopper
		smear.position = hopper_mesh.position
		smear.scale = hopper_mesh.scale
	if hopper_lid_mesh != null and hopper_mesh != null:
		hopper_lid_mesh.visible = show_hopper
		hopper_lid_mesh.position = hopper_mesh.position + Vector3(0.0, 0.062, 0.02)

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

	if _puff_mesh_cached == null:
		_puff_mesh_cached = SphereMesh.new()
		_puff_mesh_cached.radius = 0.022
		_puff_mesh_cached.height = 0.044
		var puff_mat := StandardMaterial3D.new()
		puff_mat.albedo_color = Color(0.88, 0.92, 0.96, 0.28)
		puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_puff_mesh_cached.material = puff_mat
	particles.mesh = _puff_mesh_cached

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


static func build_woodsball_crash_site_map(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "WoodsballCrashSiteRoot"
	parent.add_child(root)

	var wood_mat := create_wood_spool_material()

	var dark_timber_mat := StandardMaterial3D.new()
	dark_timber_mat.albedo_color = Color(0.32, 0.22, 0.14)
	dark_timber_mat.albedo_texture = load_texture_safe("res://assets/textures/wood_spool_albedo.png")
	dark_timber_mat.roughness = 0.88

	var heli_olive_mat := StandardMaterial3D.new()
	heli_olive_mat.albedo_color = Color(0.22, 0.27, 0.19)
	heli_olive_mat.albedo_texture = load_texture_safe("res://assets/textures/vinyl_scuffed_albedo.png")
	heli_olive_mat.metallic = 0.55
	heli_olive_mat.roughness = 0.62

	var charred_metal_mat := StandardMaterial3D.new()
	charred_metal_mat.albedo_color = Color(0.14, 0.15, 0.16)
	charred_metal_mat.metallic = 0.78
	charred_metal_mat.roughness = 0.48

	var camo_net_mat := StandardMaterial3D.new()
	camo_net_mat.albedo_color = Color(0.18, 0.26, 0.15, 0.76)
	camo_net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	camo_net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	camo_net_mat.roughness = 0.92

	# =========================================================================
	# 1. CENTER-50 DOWNED BLACKHAWK / HUEY HELICOPTER CRASH SITE
	# =========================================================================
	# Main Fuselage Cabin (angled across the 50-yard line so Z = +1.85m Flag Station sits right outside the open cargo door)
	var heli_cabin := _spawn_rigid_cover_box(
		root,
		"Heli_CrashFuselage_Center50",
		Vector3(0.0, 1.15, -0.35),
		Vector3(8.4, 2.35, 2.15),
		Vector3(-6.0, 10.0, 0.0),
		heli_olive_mat
	)

	# Cockpit Nose Cone (+X side of fuselage)
	_spawn_rigid_cover_box(
		root,
		"Heli_CockpitNose",
		Vector3(4.8, 0.92, -1.05),
		Vector3(2.6, 1.85, 1.95),
		Vector3(0.0, 10.0, -8.0),
		charred_metal_mat
	)

	# Broken Tail Boom (stretching toward -X / -Z with rotor pylon cover)
	_spawn_rigid_cover_box(
		root,
		"Heli_BrokenTailBoom",
		Vector3(-5.8, 0.85, 0.95),
		Vector3(5.6, 1.55, 1.25),
		Vector3(4.0, -18.0, 5.0),
		heli_olive_mat
	)

	_spawn_rigid_cover_box(
		root,
		"Heli_TailRotorPylon",
		Vector3(-8.5, 1.35, 1.85),
		Vector3(1.5, 2.65, 0.85),
		Vector3(0.0, -18.0, 0.0),
		charred_metal_mat
	)

	#Bent Main Rotor Mast & 4 Twisted Rotor Blades overhead
	var rotor_hub := MeshInstance3D.new()
	rotor_hub.name = "HeliRotorHub"
	var rhub_cyl := CylinderMesh.new()
	rhub_cyl.top_radius = 0.32
	rhub_cyl.bottom_radius = 0.38
	rhub_cyl.height = 0.95
	rotor_hub.mesh = rhub_cyl
	rotor_hub.position = Vector3(0.0, 2.85, 0.0)
	rotor_hub.rotation_degrees = Vector3(8.0, 22.0, -11.0)
	rotor_hub.material_override = charred_metal_mat
	root.add_child(rotor_hub)

	for b_i in range(4):
		var blade := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(6.8, 0.06, 0.34)
		blade.mesh = bbox
		blade.position = Vector3(0.0, 3.22, 0.0)
		blade.rotation_degrees = Vector3(-6.0 + float(b_i % 2) * 11.0, 22.0 + float(b_i) * 90.0, -8.0)
		blade.material_override = charred_metal_mat
		root.add_child(blade)

	# =========================================================================
	# 2. FOUR ELEVATED WOODEN SNIPER TOWERS WITH PLAYABLE ASSAULT RAMPS & CAMO NETTING
	# =========================================================================
	# Two midfield flank watchtowers (West X=-24m, East X=+24m) and two home/opfor fortresses (Z=+28m, Z=-28m)
	_build_wooden_assault_tower(root, "Tower_WestFlank", Vector3(-25.0, 0.0, 0.0), 0.0, wood_mat, dark_timber_mat, camo_net_mat, true)
	_build_wooden_assault_tower(root, "Tower_EastFlank", Vector3(25.0, 0.0, 0.0), 180.0, wood_mat, dark_timber_mat, camo_net_mat, true)
	_build_wooden_assault_tower(root, "Tower_SouthRidge", Vector3(-11.5, 0.0, 24.0), 90.0, wood_mat, dark_timber_mat, camo_net_mat, false)
	_build_wooden_assault_tower(root, "Tower_NorthRidge", Vector3(11.5, 0.0, -24.0), -90.0, wood_mat, dark_timber_mat, camo_net_mat, false)

	# =========================================================================
	# 3. RIGID TIMBER LOG BARRICADES, STACKED WOODEN SPOOLS & CAMO NET BUNKERS
	# =========================================================================
	for side in [-1.0, 1.0]:
		var prefix: String = "Home_" if side > 0.0 else "OpFor_"
		# Breakout Gate & Back Center (Rigid Timber Bunkers at exact tactical coordinates so Breakout & Flag Hang work!)
		_spawn_rigid_cover_box(root, prefix + "BreakoutGate", Vector3(0.0, 1.15, 48.0 * side), Vector3(3.8, 2.3, 1.2), Vector3.ZERO, dark_timber_mat)
		_spawn_rigid_cover_box(root, prefix + "BackCenter", Vector3(0.0, 1.10, 38.0 * side), Vector3(3.2, 2.2, 1.4), Vector3.ZERO, wood_mat)

		# Breakout Spools & Timber Bolsters
		_spawn_woods_spool_cluster(root, prefix + "BreakoutCan_L", Vector3(-2.6, 0.0, 41.8 * side), true, wood_mat)
		_spawn_woods_spool_cluster(root, prefix + "BreakoutCan_R", Vector3(-1.8, 0.0, 36.2 * side), true, wood_mat)
		_spawn_rigid_cover_box(root, prefix + "BreakoutBolster", Vector3(-0.3, 0.55, 35.0 * side), Vector3(1.0, 1.1, 3.4), Vector3.ZERO, dark_timber_mat)

		# Mid-Back Timber Bunkers & Log Walls
		_spawn_rigid_cover_box(root, prefix + "BackBrick_L", Vector3(-11.0, 1.05, 31.0 * side), Vector3(2.8, 2.1, 1.5), Vector3(0.0, 12.0 * side, 0.0), wood_mat)
		_spawn_rigid_cover_box(root, prefix + "BackBrick_R", Vector3(11.0, 1.05, 31.0 * side), Vector3(2.8, 2.1, 1.5), Vector3(0.0, -12.0 * side, 0.0), wood_mat)
		_spawn_woods_spool_cluster(root, prefix + "OuterTower_L", Vector3(-22.0, 0.0, 31.0 * side), true, wood_mat)
		_spawn_woods_spool_cluster(root, prefix + "OuterTower_R", Vector3(22.0, 0.0, 31.0 * side), true, wood_mat)

		# Midfield Rigid Timber Trenches & Spool Stacks (Z = 16m..19m)
		_spawn_rigid_cover_box(root, prefix + "CenterAztec", Vector3(0.0, 1.15, 19.0 * side), Vector3(3.0, 2.3, 1.6), Vector3.ZERO, dark_timber_mat)
		_spawn_woods_spool_cluster(root, prefix + "MidCan_L", Vector3(-8.5, 0.0, 17.5 * side), true, wood_mat)
		_spawn_woods_spool_cluster(root, prefix + "MidCan_R", Vector3(8.5, 0.0, 17.5 * side), true, wood_mat)
		_spawn_rigid_cover_box(root, prefix + "WideTemple_L", Vector3(-18.5, 1.05, 16.5 * side), Vector3(2.6, 2.1, 1.8), Vector3(0.0, -18.0 * side, 0.0), wood_mat)
		_spawn_rigid_cover_box(root, prefix + "WideTemple_R", Vector3(18.5, 1.05, 16.5 * side), Vector3(2.6, 2.1, 1.8), Vector3(0.0, 18.0 * side, 0.0), wood_mat)

		# 40-Yard Crash-Perimeter Avionics Crates & Spools (Z = 9m)
		_spawn_rigid_cover_box(root, prefix + "40_Pin_L", Vector3(-6.2, 0.95, 9.2 * side), Vector3(1.9, 1.9, 1.9), Vector3(0.0, 24.0, 0.0), heli_olive_mat)
		_spawn_rigid_cover_box(root, prefix + "40_Pin_R", Vector3(6.2, 0.95, 9.2 * side), Vector3(1.9, 1.9, 1.9), Vector3(0.0, -18.0, 0.0), heli_olive_mat)
		_spawn_woods_spool_cluster(root, prefix + "40_Wedge_L", Vector3(-14.5, 0.0, 9.5 * side), true, wood_mat)
		_spawn_woods_spool_cluster(root, prefix + "40_Wedge_R", Vector3(14.5, 0.0, 9.5 * side), true, wood_mat)

		# Far Right Flank (Timber Dorito Highway) & Far Left Flank (Woodland Trench)
		_spawn_rigid_cover_box(root, prefix + "Dorito_Corner", Vector3(32.0, 1.1, 35.0 * side), Vector3(2.6, 2.2, 2.2), Vector3(0.0, 35.0, 0.0), dark_timber_mat)
		_spawn_woods_spool_cluster(root, prefix + "Dorito_1", Vector3(34.5, 0.0, 23.0 * side), true, wood_mat)
		_spawn_rigid_cover_box(root, prefix + "Dorito_2", Vector3(36.5, 1.05, 11.5 * side), Vector3(2.5, 2.1, 2.2), Vector3(0.0, 25.0, 0.0), wood_mat)

		_spawn_rigid_cover_box(root, prefix + "Snake_Corner", Vector3(-33.0, 1.1, 35.0 * side), Vector3(2.8, 2.2, 2.0), Vector3.ZERO, dark_timber_mat)
		_spawn_woods_spool_cluster(root, prefix + "Snake_GodCan", Vector3(-28.5, 0.0, 24.5 * side), true, wood_mat)

		# Overhead Camo Netting Canopies strung between tall timber poles
		_build_camo_net_canopy(root, Vector3(-15.0, 4.6, 22.0 * side), Vector3(10.0, 0.08, 7.5), camo_net_mat, dark_timber_mat)
		_build_camo_net_canopy(root, Vector3(15.0, 4.6, 22.0 * side), Vector3(10.0, 0.08, 7.5), camo_net_mat, dark_timber_mat)

	# 50-Yard Line Timber & Spool Bunkers flanking the Helicopter Crash
	_spawn_woods_spool_cluster(root, "Bunker_50_MiniWin_Left", Vector3(-11.0, 0.0, 0.0), true, wood_mat)
	_spawn_woods_spool_cluster(root, "Bunker_50_MiniWin_Right", Vector3(11.0, 0.0, 0.0), true, wood_mat)
	_spawn_rigid_cover_box(root, "Bunker_50_Insert_Left", Vector3(-17.5, 1.1, 0.0), Vector3(2.4, 2.2, 1.8), Vector3(0.0, 15.0, 0.0), dark_timber_mat)
	_spawn_rigid_cover_box(root, "Bunker_50_Insert_Right", Vector3(17.5, 1.1, 0.0), Vector3(2.4, 2.2, 1.8), Vector3(0.0, -15.0, 0.0), dark_timber_mat)
	_spawn_woods_spool_cluster(root, "Bunker_50_GiantDorito", Vector3(38.0, 0.0, 0.0), true, wood_mat)

	# Far-Left Woodland Log Trench (Snake equivalent with rigid logs & knuckle barricades)
	_spawn_rigid_cover_box(root, "Snake_Beam_Home1", Vector3(-35.0, 0.48, 15.0), Vector3(1.1, 0.96, 9.5), Vector3.ZERO, dark_timber_mat)
	_spawn_rigid_cover_box(root, "Snake_Beam_Home2", Vector3(-37.2, 0.48, 5.5), Vector3(1.1, 0.96, 9.5), Vector3.ZERO, wood_mat)
	_spawn_rigid_cover_box(root, "Snake_Beam_OpFor2", Vector3(-37.2, 0.48, -5.5), Vector3(1.1, 0.96, 9.5), Vector3.ZERO, wood_mat)
	_spawn_rigid_cover_box(root, "Snake_Beam_OpFor1", Vector3(-35.0, 0.48, -15.0), Vector3(1.1, 0.96, 9.5), Vector3.ZERO, dark_timber_mat)

	_spawn_rigid_cover_box(root, "Snake_Knuckle_HomeEntry", Vector3(-35.0, 0.75, 20.0), Vector3(2.6, 1.5, 1.3), Vector3.ZERO, wood_mat)
	_spawn_rigid_cover_box(root, "Snake_Knuckle_HomeMid", Vector3(-36.1, 0.75, 10.2), Vector3(2.8, 1.5, 1.3), Vector3.ZERO, dark_timber_mat)
	_spawn_rigid_cover_box(root, "Snake_Knuckle_Center50", Vector3(-37.2, 0.85, 0.0), Vector3(3.0, 1.7, 1.5), Vector3.ZERO, wood_mat)
	_spawn_rigid_cover_box(root, "Snake_Knuckle_OpForMid", Vector3(-36.1, 0.75, -10.2), Vector3(2.8, 1.5, 1.3), Vector3.ZERO, dark_timber_mat)
	_spawn_rigid_cover_box(root, "Snake_Knuckle_OpForEntry", Vector3(-35.0, 0.75, -20.0), Vector3(2.6, 1.5, 1.3), Vector3.ZERO, wood_mat)

	# Woodland Perimeter Pine Trees outside the netting/sidelines for authentic woodsball atmosphere
	_build_perimeter_pine_trees(root, dark_timber_mat, camo_net_mat)

	return root

static func _spawn_rigid_cover_box(parent: Node3D, b_name: String, pos: Vector3, size: Vector3, rot_deg: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = b_name
	body.position = pos
	body.rotation_degrees = rot_deg
	body.set_meta("is_rigid_cover", true)
	body.set_meta("rigid_cover", true)
	body.set_meta("is_cover_bunker", true)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "BunkerMesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	parent.add_child(body)
	return body

static func _spawn_woods_spool_cluster(parent: Node3D, s_name: String, pos: Vector3, stacked: bool, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = s_name
	body.position = pos
	body.set_meta("is_rigid_cover", true)
	body.set_meta("rigid_cover", true)
	body.set_meta("is_cover_bunker", true)
	parent.add_child(body)
	_add_single_wood_spool_meshes(body, Vector3.ZERO, 0.92, 0.88, mat)
	if stacked:
		_add_single_wood_spool_meshes(body, Vector3(0.0, 0.88, 0.0), 0.84, 0.84, mat)
	return body

static func _build_wooden_assault_tower(parent: Node3D, t_name: String, base_pos: Vector3, yaw_deg: float, wood_mat: Material, dark_timber_mat: Material, camo_mat: Material, dual_ramps: bool) -> void:
	var tower_root := Node3D.new()
	tower_root.name = t_name
	tower_root.position = base_pos
	tower_root.rotation_degrees.y = yaw_deg
	parent.add_child(tower_root)

	var deck_h: float = 2.85
	var deck_w: float = 5.2
	var deck_d: float = 4.6

	# 4 Heavy Corner Timber Support Posts
	var post_idx := 0
	for px in [-2.35, 2.35]:
		for pz in [-2.05, 2.05]:
			post_idx += 1
			_spawn_rigid_cover_box(
				tower_root,
				"%s_Post_%d" % [t_name, post_idx],
				Vector3(px, (deck_h + 2.4) * 0.5, pz),
				Vector3(0.36, deck_h + 2.4, 0.36),
				Vector3.ZERO,
				dark_timber_mat
			)

	# Elevated Wooden Deck Platform (Walkable floor at Y = 2.85m)
	var deck_body := StaticBody3D.new()
	deck_body.name = "WalkableFloor_%s_Deck" % t_name
	deck_body.position = Vector3(0.0, deck_h, 0.0)
	var dcol := CollisionShape3D.new()
	var dbox := BoxShape3D.new()
	dbox.size = Vector3(deck_w, 0.28, deck_d)
	dcol.shape = dbox
	deck_body.add_child(dcol)
	var dmesh := MeshInstance3D.new()
	var dbm := BoxMesh.new()
	dbm.size = Vector3(deck_w, 0.28, deck_d)
	dmesh.mesh = dbm
	dmesh.material_override = wood_mat
	deck_body.add_child(dmesh)
	tower_root.add_child(deck_body)

	# Waist/Chest-High Sniper Parapet Walls on the Tower Deck (Rigid cover with PB-16 pocket physics on the tower!)
	_spawn_rigid_cover_box(tower_root, "%s_Parapet_Front" % t_name, Vector3(0.0, deck_h + 0.68, -2.05), Vector3(2.8, 1.15, 0.32), Vector3.ZERO, dark_timber_mat)
	_spawn_rigid_cover_box(tower_root, "%s_Parapet_Back" % t_name, Vector3(0.0, deck_h + 0.68, 2.05), Vector3(2.8, 1.15, 0.32), Vector3.ZERO, dark_timber_mat)
	if not dual_ramps:
		_spawn_rigid_cover_box(tower_root, "%s_Parapet_Left" % t_name, Vector3(-2.05, deck_h + 0.68, 0.0), Vector3(0.32, 1.15, 2.8), Vector3.ZERO, dark_timber_mat)

	# Overhead Camo Netting Roof above the sniper tower
	var roof := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(deck_w + 0.8, 0.08, deck_d + 0.8)
	roof.mesh = rbm
	roof.position = Vector3(0.0, deck_h + 2.45, 0.0)
	roof.material_override = camo_mat
	tower_root.add_child(roof)

	# Walkable Assault Ramp(s) (21.0 deg slope, 7.6m long, 2.0m wide) connecting ground Y=0 flush to deck Y=2.72m
	var ramp_len: float = 7.6
	var ramp_angle_deg: float = 21.0
	_build_walkable_ramp(tower_root, "WalkableRamp_%s_South" % t_name, Vector3(1.25, 1.28, 2.20 + 3.45), Vector3(2.0, 0.24, ramp_len), Vector3(ramp_angle_deg, 0.0, 0.0), wood_mat)
	if dual_ramps:
		_build_walkable_ramp(tower_root, "WalkableRamp_%s_North" % t_name, Vector3(-1.25, 1.28, -2.20 - 3.45), Vector3(2.0, 0.24, ramp_len), Vector3(-ramp_angle_deg, 0.0, 0.0), wood_mat)

static func _build_walkable_ramp(parent: Node3D, r_name: String, pos: Vector3, size: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var rbody := StaticBody3D.new()
	rbody.name = r_name
	rbody.position = pos
	rbody.rotation_degrees = rot_deg
	var rcol := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = size
	rcol.shape = rbox
	rbody.add_child(rcol)
	var rmesh := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = size
	rmesh.mesh = rbm
	rmesh.material_override = mat
	rbody.add_child(rmesh)
	parent.add_child(rbody)

static func _build_camo_net_canopy(parent: Node3D, pos: Vector3, size: Vector3, camo_mat: Material, pole_mat: Material) -> void:
	var canopy := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = size
	canopy.mesh = cbm
	canopy.position = pos
	canopy.rotation_degrees = Vector3(3.0, 8.0, -2.0)
	canopy.material_override = camo_mat
	parent.add_child(canopy)

	for sx in [-size.x * 0.46, size.x * 0.46]:
		for sz in [-size.z * 0.46, size.z * 0.46]:
			var pole := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 0.09
			pcyl.bottom_radius = 0.12
			pcyl.height = pos.y
			pole.mesh = pcyl
			pole.position = Vector3(pos.x + sx, pos.y * 0.5, pos.z + sz)
			pole.material_override = pole_mat
			parent.add_child(pole)

static func _build_perimeter_pine_trees(parent: Node3D, trunk_mat: Material, foliage_mat: Material) -> void:
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.14, 0.24, 0.13)
	tree_mat.roughness = 0.90

	var tree_coords := [
		Vector3(-50.0, 0.0, -45.0), Vector3(-50.0, 0.0, -18.0), Vector3(-50.0, 0.0, 18.0), Vector3(-50.0, 0.0, 45.0),
		Vector3(50.0, 0.0, -45.0), Vector3(50.0, 0.0, -18.0), Vector3(50.0, 0.0, 18.0), Vector3(50.0, 0.0, 45.0),
		Vector3(-28.0, 0.0, -61.0), Vector3(28.0, 0.0, -61.0), Vector3(-28.0, 0.0, 61.0), Vector3(28.0, 0.0, 61.0)
	]
	for tc in tree_coords:
		var tnode := Node3D.new()
		tnode.position = tc
		parent.add_child(tnode)
		var trunk := MeshInstance3D.new()
		var tcyl := CylinderMesh.new()
		tcyl.top_radius = 0.22
		tcyl.bottom_radius = 0.36
		tcyl.height = 5.5
		trunk.mesh = tcyl
		trunk.position = Vector3(0.0, 2.75, 0.0)
		trunk.material_override = trunk_mat
		tnode.add_child(trunk)

		for tier in range(3):
			var cone := MeshInstance3D.new()
			var ccyl := CylinderMesh.new()
			ccyl.top_radius = 0.15
			ccyl.bottom_radius = 2.6 - float(tier) * 0.55
			ccyl.height = 3.6
			cone.mesh = ccyl
			cone.position = Vector3(0.0, 4.2 + float(tier) * 2.1, 0.0)
			cone.material_override = tree_mat
			tnode.add_child(cone)
