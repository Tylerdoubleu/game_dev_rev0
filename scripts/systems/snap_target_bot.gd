extends StaticBody3D

## Greybox opposing player target that snap-peeks from behind a bunker and fires paintballs.
## One clean break eliminates the target; glancing bounces leave it alive!
## TODO(BACKLOG-06): Replace simple sinusoidal peek timer with NavigationAgent3D bunker-to-bunker AI.

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
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.65
	col.shape = cap
	col.position = Vector3(0, 0.825, 0)
	add_child(col)

	mesh_inst = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.34
	cap_mesh.height = 1.65
	mesh_inst.mesh = cap_mesh
	mesh_inst.position = Vector3(0, 0.825, 0)

	base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.9, 0.18, 0.22)
	base_mat.roughness = 0.4
	mesh_inst.material_override = base_mat
	add_child(mesh_inst)

	# Mask/Goggle visor indicator
	var visor := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.42, 0.18, 0.25)
	visor.mesh = vbox
	visor.position = Vector3(0, 1.32, 0.25)
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.1, 0.1, 0.12)
	visor.material_override = vmat
	add_child(visor)

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
		var origin := global_position + Vector3(0, 1.35, 0.4)
		var dir := (Vector3(0, 1.3, 14.0) - origin).normalized()
		PaintBallistics.spawn_paintball(origin, dir, 250.0, self, Color(0.2, 0.95, 0.35))

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
