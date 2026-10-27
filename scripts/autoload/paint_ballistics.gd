extends Node

## Pooled 3D paintball simulation with gravity, drag, bounce-vs-break angle checks,
## glossy oily paint splat decals (roughness ~ 0.12 + clearcoat), and airborne paint mist bursts.

const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")

const GRAVITY: float = 9.81
const AIR_DRAG: float = 0.24
const FPS_TO_MPS: float = 0.3048
const MAX_ACTIVE_BALLS: int = 200
const MAX_SPLATS: int = 160
const BOUNCE_ANGLE_COS_THRESHOLD: float = 0.42

var projectiles: Array[Dictionary] = []
var splat_nodes: Array[Node3D] = []
var mist_burst_count: int = 0
var _ball_mesh: SphereMesh
var _ball_material: StandardMaterial3D
var _splat_mesh: QuadMesh

func _ready() -> void:
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.04
	_ball_mesh.height = 0.08
	_ball_material = GrittyArtThemeScript.create_oily_paint_material(GrittyArtThemeScript.NEON_YELLOW_PAINT, false)

	_splat_mesh = QuadMesh.new()
	_splat_mesh.size = Vector2(0.42, 0.42)

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

	var speed_mps: float = speed_fps * FPS_TO_MPS * 0.68
	projectiles.append({
		"node": mesh_inst,
		"velocity": direction.normalized() * speed_mps,
		"shooter": shooter,
		"color": color,
		"bounces": 0,
		"age": 0.0
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
		if p["age"] > 5.5:
			node.queue_free()
			projectiles.remove_at(i)
			continue

		var vel: Vector3 = p["velocity"]
		vel.y -= GRAVITY * delta
		vel *= max(0.0, 1.0 - AIR_DRAG * delta)
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

			if p["bounces"] == 0 and impact_cos < BOUNCE_ANGLE_COS_THRESHOLD:
				p["bounces"] += 1
				p["velocity"] = vel.bounce(hit_normal) * 0.45
				node.global_position = hit_pos + hit_normal * 0.03
				if collider and collider.has_method("on_paintball_bounce"):
					collider.on_paintball_bounce(hit_pos)
				continue

			_spawn_splat(hit_pos, hit_normal, p["color"])
			if collider and collider.has_method("on_paintball_break"):
				collider.on_paintball_break(hit_pos, p["shooter"])
			elif collider is Node and collider.get_parent() and collider.get_parent().has_method("on_paintball_break"):
				collider.get_parent().on_paintball_break(hit_pos, p["shooter"])

			node.queue_free()
			projectiles.remove_at(i)

func _spawn_splat(pos: Vector3, normal: Vector3, color: Color) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	if splat_nodes.size() >= MAX_SPLATS:
		var old_splat: Node3D = splat_nodes.pop_front()
		if is_instance_valid(old_splat):
			old_splat.queue_free()

	var splat := MeshInstance3D.new()
	splat.name = "OilyPaintSplatDecal"
	splat.mesh = _splat_mesh
	splat.material_override = GrittyArtThemeScript.create_oily_paint_material(color, true)
	scene_root.add_child(splat)
	splat.global_position = pos + normal * 0.015

	var up := Vector3.UP
	if abs(normal.dot(up)) > 0.98:
		up = Vector3.RIGHT
	var basis_x := up.cross(normal).normalized()
	var basis_y := normal.cross(basis_x).normalized()
	splat.global_transform.basis = Basis(basis_x, basis_y, normal)
	splat_nodes.append(splat)

	GrittyArtThemeScript.spawn_paint_mist_burst(scene_root, pos, normal, color)
	mist_burst_count += 1
