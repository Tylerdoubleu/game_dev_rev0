extends Node

## Pooled 3D paintball simulation with gravity, drag, Magnus seam drift & aerodynamic wake wobble
## (flight-path uncertainty), bounce-vs-break angle checks, surface-wrapping oily paint splat
## meshes (roughness ~ 0.10 + clearcoat that hug curved bunkers/spools/edges), and paint mist bursts.

const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")

const GRAVITY: float = 9.81
const AIR_DRAG: float = 0.26
const FPS_TO_MPS: float = 0.3048
const MAX_ACTIVE_BALLS: int = 200
const MAX_SPLATS: int = 160
const BOUNCE_ANGLE_COS_THRESHOLD: float = 0.42
const STADIUM_WIND_ACCEL := Vector3(0.32, -0.04, -0.14)

var projectiles: Array[Dictionary] = []
var splat_nodes: Array[Node3D] = []
var mist_burst_count: int = 0
var _ball_mesh: SphereMesh
var _ball_material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.04
	_ball_mesh.height = 0.08
	_ball_material = GrittyArtThemeScript.create_oily_paint_material(GrittyArtThemeScript.NEON_YELLOW_PAINT, false)

func clear_all() -> void:
	for p in projectiles:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	projectiles.clear()
	for s in splat_nodes:
		if is_instance_valid(s):
			s.queue_free()
	splat_nodes.clear()
	mist_burst_count = 0

func spawn_paintball(origin: Vector3, direction: Vector3, speed_fps: float, shooter: Node, color: Color = GrittyArtThemeScript.NEON_YELLOW_PAINT) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	if projectiles.size() >= MAX_ACTIVE_BALLS:
		var oldest: Dictionary = projectiles.pop_front()
		if is_instance_valid(oldest["node"]):
			oldest["node"].queue_free()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _ball_mesh
	var mat := GrittyArtThemeScript.create_oily_paint_material(color, false)
	mesh_inst.material_override = mat
	scene_root.add_child(mesh_inst)
	mesh_inst.global_position = origin

	# Real .68 cal gelatin paintball flight uncertainty:
	# 1) Chrono muzzle velocity variance (+/- 5.5 FPS)
	var varied_fps: float = speed_fps + _rng.randf_range(-5.5, 5.5)
	var speed_mps: float = varied_fps * FPS_TO_MPS * 0.68
	var fwd := direction.normalized()

	# Build an orthonormal basis perpendicular to the flight vector for Magnus curve & wake wobble
	var ref_up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side_axis := fwd.cross(ref_up).normalized()
	var up_axis := side_axis.cross(fwd).normalized()

	# 2) Per-ball Magnus seam/spin drift acceleration + corkscrew wake turbulence
	var spin_angle := _rng.randf_range(0.0, TAU)
	var spin_mag := _rng.randf_range(0.55, 1.55)
	var spin_accel := (side_axis * cos(spin_angle) + up_axis * sin(spin_angle)) * spin_mag
	var wobble_axis := (side_axis * -sin(spin_angle) + up_axis * cos(spin_angle)).normalized()

	projectiles.append({
		"node": mesh_inst,
		"velocity": fwd * speed_mps,
		"shooter": shooter,
		"color": color,
		"bounces": 0,
		"age": 0.0,
		"spin_accel": spin_accel,
		"spin_drift": spin_accel,
		"wobble_axis": wobble_axis,
		"wobble_freq": _rng.randf_range(11.5, 17.5),
		"wobble_phase": _rng.randf_range(0.0, TAU),
		"wobble_amp": _rng.randf_range(0.65, 1.35)
	})

func _physics_process(delta: float) -> void:
	var scene_root: Node3D = get_tree().current_scene as Node3D
	if scene_root == null:
		return
	var space_state: PhysicsDirectSpaceState3D = scene_root.get_world_3d().direct_space_state

	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var node: Node3D = p["node"]
		if not is_instance_valid(node):
			projectiles.remove_at(i)
			continue

		p["age"] += delta
		var age: float = p["age"]
		if age > 5.5:
			node.queue_free()
			projectiles.remove_at(i)
			continue

		var vel: Vector3 = p["velocity"]
		vel.y -= GRAVITY * delta
		vel *= max(0.0, 1.0 - AIR_DRAG * delta)

		# Apply realistic paintball flight-path uncertainty (Magnus seam drift + wake corkscrew + stadium breeze)
		var downrange_ramp: float = clamp(age * 4.5, 0.25, 1.45)
		var spin_accel: Vector3 = p.get("spin_accel", Vector3.ZERO)
		var wobble_axis: Vector3 = p.get("wobble_axis", Vector3.RIGHT)
		var wobble_wave: float = sin(age * float(p.get("wobble_freq", 14.0)) + float(p.get("wobble_phase", 0.0))) * float(p.get("wobble_amp", 0.9))
		vel += (spin_accel * downrange_ramp + wobble_axis * wobble_wave + STADIUM_WIND_ACCEL) * delta
		p["velocity"] = vel

		var from_pos: Vector3 = node.global_position
		var to_pos: Vector3 = from_pos + vel * delta

		var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
		if is_instance_valid(p["shooter"]) and p["shooter"] is CollisionObject3D:
			query.exclude = [p["shooter"].get_rid()]

		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			node.global_position = to_pos
		else:
			var hit_pos: Vector3 = hit["position"]
			var hit_normal: Vector3 = hit["normal"]
			var collider: Object = hit["collider"]
			var impact_cos: float = abs(vel.normalized().dot(hit_normal))
			var bounce_thresh: float = BOUNCE_ANGLE_COS_THRESHOLD
			if collider != null and collider.has_method("resolve_hit_subzone"):
				var sub_info: Dictionary = collider.call("resolve_hit_subzone", hit_pos)
				bounce_thresh = float(sub_info.get("bounce_cos_threshold", BOUNCE_ANGLE_COS_THRESHOLD))

			if p["bounces"] == 0 and impact_cos < bounce_thresh:
				p["bounces"] += 1
				p["velocity"] = vel.bounce(hit_normal) * 0.45
				node.global_position = hit_pos + hit_normal * 0.03
				if collider and collider.has_method("on_paintball_bounce"):
					collider.on_paintball_bounce(hit_pos)
				continue

			_spawn_splat(hit_pos, hit_normal, p["color"], collider)
			if collider is Node3D:
				GrittyArtThemeScript.trigger_bunker_vinyl_flex(collider as Node3D, vel.normalized(), 0.05)
			var local_player := scene_root.get_node_or_null("Player3D") as Node3D
			if local_player != null and p["shooter"] != local_player and collider != local_player:
				if local_player.global_position.distance_to(hit_pos) < 1.85 and local_player.has_method("add_visor_splatter"):
					local_player.call("add_visor_splatter", 0.30, p["color"], "NEAR-MISS BUNKER SPRAY ON VISOR")
			if collider and collider.has_method("on_paintball_break"):
				collider.on_paintball_break(hit_pos, p["shooter"])
			elif collider is Node and collider.get_parent() and collider.get_parent().has_method("on_paintball_break"):
				collider.get_parent().on_paintball_break(hit_pos, p["shooter"])

			node.queue_free()
			projectiles.remove_at(i)

func _build_wrapped_splat_mesh(space_state: PhysicsDirectSpaceState3D, center_pos: Vector3, center_normal: Vector3, radius: float = 0.21, grid_steps: int = 5) -> ArrayMesh:
	var up := Vector3.UP if abs(center_normal.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tangent_x := up.cross(center_normal).normalized()
	var tangent_y := center_normal.cross(tangent_x).normalized()

	# Random rotation around the surface normal so every splat looks organic
	var rot_angle := _rng.randf_range(0.0, TAU)
	var rx := (tangent_x * cos(rot_angle) + tangent_y * sin(rot_angle)).normalized()
	var ry := (-tangent_x * sin(rot_angle) + tangent_y * cos(rot_angle)).normalized()

	var verts: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var uvs: Array[Vector2] = []

	for iy in range(grid_steps + 1):
		var v := float(iy) / float(grid_steps)
		var dy := (v - 0.5) * 2.0 * radius
		for ix in range(grid_steps + 1):
			var u := float(ix) / float(grid_steps)
			var dx := (u - 0.5) * 2.0 * radius
			var offset := rx * dx + ry * dy
			var sample_origin := center_pos + offset + center_normal * 0.14
			var sample_end := center_pos + offset - center_normal * 0.22

			var local_pos := offset + center_normal * 0.007
			var local_norm := center_normal

			if space_state != null:
				var q := PhysicsRayQueryParameters3D.create(sample_origin, sample_end)
				var h: Dictionary = space_state.intersect_ray(q)
				if not h.is_empty() and h["position"].distance_to(center_pos) <= radius * 1.65:
					local_pos = (h["position"] - center_pos) + h["normal"] * 0.007
					local_norm = h["normal"]
				else:
					# Wrap around curved cylinder/edge by casting radially inward toward the hit core
					var inward_target := center_pos - center_normal * 0.08
					var q_wrap := PhysicsRayQueryParameters3D.create(center_pos + offset * 0.85 + center_normal * 0.06, inward_target)
					var h_wrap: Dictionary = space_state.intersect_ray(q_wrap)
					if not h_wrap.is_empty() and h_wrap["position"].distance_to(center_pos) <= radius * 1.5:
						local_pos = (h_wrap["position"] - center_pos) + h_wrap["normal"] * 0.007
						local_norm = h_wrap["normal"]
					else:
						# Pull overhang tightly to the hit surface edge so nothing floats in mid-air
						local_pos = offset * 0.35 + center_normal * 0.006

			verts.append(local_pos)
			norms.append(local_norm)
			uvs.append(Vector2(u, v))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := grid_steps + 1
	for iy in range(grid_steps):
		for ix in range(grid_steps):
			var i00 := iy * stride + ix
			var i10 := i00 + 1
			var i01 := (iy + 1) * stride + ix
			var i11 := i01 + 1

			st.set_normal(norms[i00]); st.set_uv(uvs[i00]); st.add_vertex(verts[i00])
			st.set_normal(norms[i10]); st.set_uv(uvs[i10]); st.add_vertex(verts[i10])
			st.set_normal(norms[i11]); st.set_uv(uvs[i11]); st.add_vertex(verts[i11])

			st.set_normal(norms[i00]); st.set_uv(uvs[i00]); st.add_vertex(verts[i00])
			st.set_normal(norms[i11]); st.set_uv(uvs[i11]); st.add_vertex(verts[i11])
			st.set_normal(norms[i01]); st.set_uv(uvs[i01]); st.add_vertex(verts[i01])

	return st.commit()

func _spawn_splat(pos: Vector3, normal: Vector3, color: Color, collider: Object = null) -> void:
	var scene_root: Node3D = get_tree().current_scene as Node3D
	if scene_root == null:
		return

	if splat_nodes.size() >= MAX_SPLATS:
		var old_splat: Node3D = splat_nodes.pop_front()
		if is_instance_valid(old_splat):
			old_splat.queue_free()

	var n := normal.normalized() if normal.length_squared() >= 0.001 else Vector3.UP
	var decal := Decal.new()
	decal.name = "OilyPaintSplatDecal"
	decal.size = Vector3(0.46, 0.36, 0.46)
	decal.texture_albedo = GrittyArtThemeScript.load_texture_safe("res://assets/textures/paint_splat_mask.png")
	decal.modulate = color
	decal.albedo_mix = 0.96
	decal.normal_fade = 0.25

	# Parent to static cover bunkers or OpFor bots so bunker-rub detection & moving bots carry their splats
	if collider is Node3D and not collider.has_meta("remote_peer_id") and collider.name != "Player3D" and String(collider.name) != "TurfFloor":
		collider.add_child(decal)
	else:
		scene_root.add_child(decal)
	decal.global_position = pos

	var up := Vector3.FORWARD if abs(n.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var bx := up.cross(n).normalized()
	var bz := n.cross(bx).normalized()
	if bx.length_squared() > 0.001 and bz.length_squared() > 0.001:
		decal.global_transform.basis = Basis(bx, n, bz).rotated(n, _rng.randf_range(0.0, TAU))

	# Also attach our surface-wrapped glossy clearcoat mesh (use fast 2x2 grid on WebGL2 to avoid 72 raycasts per shot)
	var space_state: PhysicsDirectSpaceState3D = scene_root.get_world_3d().direct_space_state if (not OS.has_feature("web") and scene_root.get_world_3d()) else null
	var grid_res: int = 2 if OS.has_feature("web") else 5
	var wrapped_mesh := MeshInstance3D.new()
	wrapped_mesh.name = "WrappedGlossyOverlay"
	wrapped_mesh.top_level = true
	wrapped_mesh.mesh = _build_wrapped_splat_mesh(space_state, pos, n, 0.21, grid_res)
	wrapped_mesh.material_override = GrittyArtThemeScript.create_oily_paint_material(color, true)
	decal.add_child(wrapped_mesh)
	wrapped_mesh.global_position = pos
	wrapped_mesh.global_rotation = Vector3.ZERO

	splat_nodes.append(decal)

	GrittyArtThemeScript.spawn_paint_mist_burst(scene_root, pos, n, color)
	mist_burst_count += 1
