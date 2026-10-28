extends StaticBody3D

## Articulated opposing tournament paintball player that snap-peeks from behind cover and fires paintballs.
## Features form-fitting sub-hitboxes (Hitbox_Torso, Hitbox_Mask, Hitbox_HopperMarker, Hitbox_PodPack)
## and articulated 3rd-person MarkerPivot3D + HopperPivot3D cant/tilt on snap-peeks (#16 + #20).

@export var bot_name: String = "OpFor_Dorito_1"
@export var peek_offset: Vector3 = Vector3(0.75, 0.0, 0.0)
@export var peek_interval: float = 2.4
@export var fire_at_player: bool = true

var base_pos: Vector3
var timer: float = 0.0
var is_eliminated: bool = false
var respawn_timer: float = 0.0
const BOT_RESPAWN_DELAY: float = 3.2
var is_spotted_timer: float = 0.0
var mesh_inst: MeshInstance3D
var base_mat: StandardMaterial3D
var marker_pivot: Node3D = null
var hopper_pivot: Node3D = null
var col_marker: CollisionShape3D = null
var last_hit_zone: String = "TORSO / JERSEY"

func _ready() -> void:
	base_pos = position
	if not NetworkLobby.fill_bots_enabled:
		visible = false
		queue_free()
		return
	timer = randf_range(0.0, peek_interval)
	_build_visual_and_collider()
	IntelBus.enemy_spotted.connect(_on_enemy_spotted)

func _build_visual_and_collider() -> void:
	# 1. Tight Torso & Legs Collider
	var col_torso := CollisionShape3D.new()
	col_torso.name = "Hitbox_Torso"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.32
	col_torso.shape = cap
	col_torso.position = Vector3(0, 0.66, 0)
	add_child(col_torso)

	# 2. Head & Mask Collider
	var col_head := CollisionShape3D.new()
	col_head.name = "Hitbox_Mask"
	var h_sphere := SphereShape3D.new()
	h_sphere.radius = 0.17
	col_head.shape = h_sphere
	col_head.position = Vector3(0, 1.44, 0.03)
	add_child(col_head)

	# 3. Peeking Marker & Hopper Collider (allows hopper/hand hits on the snap!)
	col_marker = CollisionShape3D.new()
	col_marker.name = "Hitbox_HopperMarker"
	var m_box := BoxShape3D.new()
	m_box.size = Vector3(0.20, 0.28, 0.52)
	col_marker.shape = m_box
	col_marker.position = Vector3(0.20, 1.24, 0.28)
	add_child(col_marker)

	# 4. Lumbar Pod Pack Collider
	var col_pack := CollisionShape3D.new()
	col_pack.name = "Hitbox_PodPack"
	var p_box := BoxShape3D.new()
	p_box.size = Vector3(0.32, 0.26, 0.18)
	col_pack.shape = p_box
	col_pack.position = Vector3(0.0, 0.86, -0.19)
	add_child(col_pack)

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

	# Lumbar Pod Pack Mesh
	var pack_mesh := MeshInstance3D.new()
	pack_mesh.name = "PodPackMesh3D"
	var pm_box := BoxMesh.new()
	pm_box.size = Vector3(0.30, 0.24, 0.15)
	pack_mesh.mesh = pm_box
	pack_mesh.position = Vector3(0.0, 0.86, -0.18)
	pack_mesh.material_override = mask_mat
	add_child(pack_mesh)

	# Articulated OpFor Marker & Loader Pivot (#16)
	var peek_sign: float = -1.0 if peek_offset.x < 0.0 else 1.0
	marker_pivot = Node3D.new()
	marker_pivot.name = "MarkerPivot3D"
	marker_pivot.position = Vector3(0.20 * peek_sign, 1.18, 0.28)
	add_child(marker_pivot)

	var gun_mesh := MeshInstance3D.new()
	gun_mesh.name = "MarkerBody3D"
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.06, 0.12, 0.50)
	gun_mesh.mesh = gbox
	gun_mesh.material_override = mask_mat
	marker_pivot.add_child(gun_mesh)

	hopper_pivot = Node3D.new()
	hopper_pivot.name = "HopperPivot3D"
	hopper_pivot.position = Vector3(0.0, 0.12, -0.06)
	marker_pivot.add_child(hopper_pivot)

	var loader_mesh := MeshInstance3D.new()
	loader_mesh.name = "HopperMesh3D"
	var lsphere := SphereMesh.new()
	lsphere.radius = 0.085
	lsphere.height = 0.15
	loader_mesh.mesh = lsphere
	loader_mesh.material_override = mask_mat
	hopper_pivot.add_child(loader_mesh)

func set_bot_enabled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	position = base_pos if enabled else Vector3(base_pos.x, -50.0, base_pos.z)
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = not enabled

func _process(delta: float) -> void:
	if not NetworkLobby.fill_bots_enabled:
		set_bot_enabled(false)
		queue_free()
		return
	if GameManager.match_ended or not visible:
		return
	if is_eliminated:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn_bot()
		return

	timer += delta
	var wave := sin(timer * PI / peek_interval)
	var peek_alpha: float = clamp((wave + 0.2) / 1.2, 0.0, 1.0)
	position = base_pos.lerp(base_pos + peek_offset, peek_alpha)
	apply_articulated_peek_pose(peek_alpha)

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
		var target_pos := Vector3(0, 1.3, 14.0)
		var scene_root := get_tree().current_scene
		if scene_root != null:
			var pnode := scene_root.get_node_or_null("Player3D") as Node3D
			if pnode != null:
				target_pos = pnode.global_position + Vector3(randf_range(-0.45, 0.45), 1.15, randf_range(-0.45, 0.45))
		var dir := (target_pos - origin).normalized()
		PaintBallistics.spawn_paintball(origin, dir, 255.0, self, Color(0.2, 0.95, 0.35))

func apply_articulated_peek_pose(peek_alpha: float) -> void:
	var peek_sign: float = -1.0 if peek_offset.x < 0.0 else 1.0
	if marker_pivot != null:
		marker_pivot.position = Vector3((0.16 + 0.08 * peek_alpha) * peek_sign, 1.18, 0.28)
		var cant_deg: float = lerpf(-12.0 * peek_sign, -22.0 * peek_sign, peek_alpha)
		marker_pivot.rotation_degrees = Vector3(0.0, 0.0, cant_deg)
		if hopper_pivot != null:
			hopper_pivot.rotation_degrees = Vector3(0.0, 0.0, cant_deg * 0.45)
		if col_marker != null:
			col_marker.position = marker_pivot.position + Vector3(0.0, 0.06, 0.0)

func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	if marker_pivot != null and world_hit_pos.distance_to(marker_pivot.global_position + Vector3(0.0, 0.08, 0.0)) <= 0.30:
		last_hit_zone = "HOPPER / MARKER"
		return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	var local_hit := to_local(world_hit_pos)
	if local_hit.y >= 1.30:
		last_hit_zone = "MASK / GOGGLES"
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.26}
	if local_hit.z <= -0.10 and local_hit.y >= 0.65 and local_hit.y <= 1.15:
		last_hit_zone = "POD PACK"
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.36}
	last_hit_zone = "TORSO / JERSEY"
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	if is_eliminated or GameManager.match_ended or not visible or not NetworkLobby.fill_bots_enabled:
		return
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "TORSO / JERSEY"))
	if shooter != null and shooter.has_method("award_kill_bonus_pod"):
		shooter.call("award_kill_bonus_pod", "%s [%s]" % [bot_name, zone_lbl])
	_apply_elimination("ELIMINATED: %s [%s HIT] (+1 BONUS POD! Respawning at gate...)" % [bot_name, zone_lbl])
	NetworkLobby.broadcast_bot_eliminated(name)

func eliminate_from_network() -> void:
	if is_eliminated:
		return
	_apply_elimination("TEAMMATE ELIMINATED: %s!" % bot_name)

func _apply_elimination(feed_msg: String) -> void:
	is_eliminated = true
	respawn_timer = BOT_RESPAWN_DELAY
	base_mat.albedo_color = Color(0.28, 0.28, 0.3)
	base_mat.emission_enabled = false
	rotation.x = deg_to_rad(-75.0)
	IntelBus.intel_feed_updated.emit(feed_msg)
	GameManager.notify_enemy_eliminated()

func _respawn_bot() -> void:
	is_eliminated = false
	position = base_pos
	rotation.x = 0.0
	base_mat.albedo_color = Color(0.76, 0.16, 0.18)
	base_mat.emission_enabled = false

func on_paintball_bounce(hit_pos: Vector3) -> void:
	if is_eliminated:
		return
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "JERSEY"))
	IntelBus.intel_feed_updated.emit("BOUNCE on %s [%s] — Still Alive!" % [bot_name, zone_lbl])

func _on_enemy_spotted(target_name: String, _pos: Vector3, duration: float) -> void:
	if target_name == name or target_name == bot_name:
		is_spotted_timer = duration
