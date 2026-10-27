extends StaticBody3D

## Articulated opposing tournament paintball player that snap-peeks from behind cover and fires paintballs.
## Features form-fitting hitboxes (torso, head/mask, and peeking marker/hopper).
## One clean break eliminates the target; glancing bounces leave it alive!

@export var bot_name: String = "OpFor_Dorito_1"
@export var peek_offset: Vector3 = Vector3(0.75, 0.0, 0.0)
@export var peek_interval: float = 2.4
@export var fire_at_player: bool = true

var base_pos: Vector3
var timer: float = 0.0
var is_eliminated: bool = false
var is_spotted_timer: float = 0.0
var mesh_inst: MeshInstance3D
var base_mat: StandardMaterial3D

func _ready() -> void:
	base_pos = position
	timer = randf_range(0.0, peek_interval)
	_build_visual_and_collider()
	IntelBus.enemy_spotted.connect(_on_enemy_spotted)

func _build_visual_and_collider() -> void:
	# 1. Tight Torso & Legs Collider
	var col_torso := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.32
	col_torso.shape = cap
	col_torso.position = Vector3(0, 0.66, 0)
	add_child(col_torso)

	# 2. Head & Mask Collider
	var col_head := CollisionShape3D.new()
	var h_sphere := SphereShape3D.new()
	h_sphere.radius = 0.17
	col_head.shape = h_sphere
	col_head.position = Vector3(0, 1.44, 0.03)
	add_child(col_head)

	# 3. Peeking Marker & Hopper Collider (allows hopper/hand hits on the snap!)
	var col_marker := CollisionShape3D.new()
	var m_box := BoxShape3D.new()
	m_box.size = Vector3(0.18, 0.28, 0.52)
	col_marker.shape = m_box
	col_marker.position = Vector3(0.20, 1.24, 0.28)
	add_child(col_marker)

	# Visual Tournament Jersey Torso
	mesh_inst = MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.24
	torso_mesh.height = 1.28
	mesh_inst.mesh = torso_mesh
	mesh_inst.position = Vector3(0, 0.68, 0)

	base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.76, 0.16, 0.18)
	base_mat.roughness = 0.58
	mesh_inst.material_override = base_mat
	add_child(mesh_inst)

	# Helmet / Paintball Mask Shell
	var head_mesh := MeshInstance3D.new()
	var h_mesh := SphereMesh.new()
	h_mesh.radius = 0.165
	h_mesh.height = 0.34
	head_mesh.mesh = h_mesh
	head_mesh.position = Vector3(0, 1.44, 0.02)
	var mask_mat := StandardMaterial3D.new()
	mask_mat.albedo_color = Color(0.15, 0.16, 0.18)
	mask_mat.roughness = 0.42
	head_mesh.material_override = mask_mat
	add_child(head_mesh)

	# Chromed / Tinted Thermal Goggle Lens Visor
	var visor := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.31, 0.13, 0.18)
	visor.mesh = vbox
	visor.position = Vector3(0, 1.45, 0.12)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.85, 0.58, 0.15)
	vmat.metallic = 0.85
	vmat.roughness = 0.12
	visor.material_override = vmat
	add_child(visor)

	# OpFor Marker & Loader held in snap-shooting stance
	var gun_mesh := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.06, 0.12, 0.50)
	gun_mesh.mesh = gbox
	gun_mesh.position = Vector3(0.20, 1.18, 0.28)
	gun_mesh.material_override = mask_mat
	add_child(gun_mesh)

	var loader_mesh := MeshInstance3D.new()
	var lsphere := SphereMesh.new()
	lsphere.radius = 0.085
	lsphere.height = 0.15
	loader_mesh.mesh = lsphere
	loader_mesh.position = Vector3(0.20, 1.30, 0.22)
	loader_mesh.material_override = mask_mat
	add_child(loader_mesh)

func _process(delta: float) -> void:
	if is_eliminated:
		return

	timer += delta
	var wave := sin(timer * PI / peek_interval)
	var peek_alpha: float = clamp((wave + 0.2) / 1.2, 0.0, 1.0)
	position = base_pos.lerp(base_pos + peek_offset, peek_alpha)

	if is_spotted_timer > 0.0:
		is_spotted_timer -= delta
		base_mat.emission_enabled = true
		base_mat.emission = Color(1.0, 0.85, 0.1)
		base_mat.emission_energy_multiplier = 1.4
	else:
		base_mat.emission_enabled = false

	# Fire occasional suppressive paintballs while peeking out
	if fire_at_player and peek_alpha > 0.75 and randf() < delta * 2.2:
		var origin := global_position + Vector3(0.20, 1.24, 0.58)
		var dir := (Vector3(0, 1.3, 14.0) - origin).normalized()
		PaintBallistics.spawn_paintball(origin, dir, 255.0, self, Color(0.2, 0.95, 0.35))

func on_paintball_break(_hit_pos: Vector3, _shooter: Node) -> void:
	if is_eliminated:
		return
	is_eliminated = true
	base_mat.albedo_color = Color(0.28, 0.28, 0.3)
	base_mat.emission_enabled = false
	rotation.x = deg_to_rad(-75.0)
	IntelBus.intel_feed_updated.emit("ELIMINATED: %s (Clean Hit!)" % bot_name)
	GameManager.notify_enemy_eliminated()

func on_paintball_bounce(_hit_pos: Vector3) -> void:
	if is_eliminated:
		return
	IntelBus.intel_feed_updated.emit("BOUNCE on %s — Still Alive!" % bot_name)

func _on_enemy_spotted(target_name: String, _pos: Vector3, duration: float) -> void:
	if target_name == name or target_name == bot_name:
		is_spotted_timer = duration
