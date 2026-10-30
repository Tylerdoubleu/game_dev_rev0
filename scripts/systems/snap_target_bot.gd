extends StaticBody3D

## Articulated opposing tournament paintball player powered by the 22-joint ProPaintballRig3D (PB-14).
## Features form-fitting bone-synced sub-hitboxes (Hitbox_Torso, Hitbox_Mask, Hitbox_HopperMarker, Hitbox_PodPack)
## and articulated 3rd-person MarkerPivot3D + HopperPivot3D compatibility nodes (#16 + #20).

const ProRigScript := preload("res://scripts/player/pro_paintball_rig_3d.gd")

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
var pro_rig: Node3D = null
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
	pro_rig = ProRigScript.new()
	pro_rig.name = "ProPaintballRig3D"
	# Face +Z (South toward Team Alpha) since OpFor bots spawn on the North (-Z) side
	pro_rig.rotation.y = PI
	add_child(pro_rig)
	var active_bracket: String = NetworkLobby.local_bracket if NetworkLobby != null else "speedball"
	pro_rig.build_rig("BRAVO", active_bracket)
	var hitboxes: Dictionary = pro_rig.build_sub_hitboxes_on(self)
	col_marker = hitboxes.get("hopper", null) as CollisionShape3D

	var is_left_bot: bool = peek_offset.x > 0.0
	pro_rig.apply_pose(0.0, {
		"velocity": Vector3.ZERO,
		"stance": 0,
		"lean": 0.0,
		"is_left_handed": is_left_bot,
		"bunker_tuck": 1.0,
		"is_eliminated": false,
		"team": "BRAVO",
		"bracket": active_bracket,
	})

	# Keep lightweight MarkerPivot3D/HopperPivot3D reference nodes synced to ProPaintballRig3D
	marker_pivot = Node3D.new()
	marker_pivot.name = "MarkerPivot3D"
	add_child(marker_pivot)
	hopper_pivot = Node3D.new()
	hopper_pivot.name = "HopperPivot3D"
	marker_pivot.add_child(hopper_pivot)
	_sync_compat_pivots()

func _sync_compat_pivots() -> void:
	if pro_rig == null or marker_pivot == null:
		return
	var m_piv := pro_rig.get("marker_assembly_pivot") as Node3D
	var h_piv := pro_rig.get("hopper_unit_pivot") as Node3D
	if m_piv != null:
		marker_pivot.global_transform = m_piv.global_transform
	if h_piv != null and hopper_pivot != null:
		hopper_pivot.global_transform = h_piv.global_transform

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
		if pro_rig != null:
			pro_rig.apply_pose(delta, {
				"velocity": Vector3.ZERO,
				"stance": 0,
				"lean": 0.0,
				"is_left_handed": peek_offset.x > 0.0,
				"bunker_tuck": 0.0,
				"is_eliminated": true,
			})
			_sync_compat_pivots()
		if respawn_timer <= 0.0:
			_respawn_bot()
		return

	timer += delta
	var prev_pos := position
	var wave := sin(timer * PI / peek_interval)
	var peek_alpha: float = clamp((wave + 0.2) / 1.2, 0.0, 1.0)
	position = base_pos.lerp(base_pos + peek_offset, peek_alpha)
	var bot_vel := (position - prev_pos) / maxf(delta, 0.001)
	apply_articulated_peek_pose(peek_alpha, delta, bot_vel)

	if is_spotted_timer > 0.0:
		is_spotted_timer -= delta

	# Fire occasional suppressive paintballs while peeking out
	if fire_at_player and peek_alpha > 0.75 and randf() < delta * 2.2:
		var origin := global_position + Vector3(0.20, 1.24, 0.58)
		if pro_rig != null and pro_rig.get("muzzle_tip_node") != null:
			origin = (pro_rig.get("muzzle_tip_node") as Node3D).global_position
		var target_pos := Vector3(0, 1.3, 14.0)
		var scene_root := get_tree().current_scene
		if scene_root != null:
			var pnode := scene_root.get_node_or_null("Player3D") as Node3D
			if pnode != null:
				target_pos = pnode.global_position + Vector3(randf_range(-0.45, 0.45), 1.15, randf_range(-0.45, 0.45))
		var dir := (target_pos - origin).normalized()
		PaintBallistics.spawn_paintball(origin, dir, 255.0, self, Color(0.2, 0.95, 0.35))

func apply_articulated_peek_pose(peek_alpha: float, delta: float = 0.016, bot_vel: Vector3 = Vector3.ZERO) -> void:
	# Bot faces +Z (South), so world +X is bot's local LEFT (-X) and world -X is bot's local RIGHT (+X)
	var is_left_bot: bool = peek_offset.x > 0.0
	var local_lean_sign: float = -1.0 if is_left_bot else 1.0
	if pro_rig != null:
		pro_rig.apply_pose(delta, {
			"velocity": bot_vel,
			"stance": 0,
			"lean": local_lean_sign * peek_alpha,
			"is_left_handed": is_left_bot,
			"bunker_tuck": 1.0 - peek_alpha * 0.85,
			"is_eliminated": is_eliminated,
		})
		_sync_compat_pivots()

func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	var h_col := get_node_or_null("Hitbox_HopperMarker") as Node3D
	if h_col != null and world_hit_pos.distance_to(h_col.global_position) <= 0.30:
		last_hit_zone = "HOPPER / MARKER"
		return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	var m_col := get_node_or_null("Hitbox_Mask") as Node3D
	if m_col != null and world_hit_pos.distance_to(m_col.global_position) <= 0.26:
		last_hit_zone = "MASK / GOGGLES"
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.28}
	var p_col := get_node_or_null("Hitbox_PodPack") as Node3D
	if p_col != null and world_hit_pos.distance_to(p_col.global_position) <= 0.28:
		last_hit_zone = "POD PACK"
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.32}
	last_hit_zone = "TORSO / JERSEY"
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	if is_eliminated or GameManager.match_ended or not visible or not NetworkLobby.fill_bots_enabled:
		return
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "TORSO / JERSEY"))
	if shooter != null and shooter.has_method("award_kill_bonus_pod"):
		shooter.call("award_kill_bonus_pod", "%s [%s]" % [bot_name, zone_lbl])
		MovementAudioDirector.show_local_hit_marker() # v0.6: only the local player who fired gets the marker
	_apply_elimination("ELIMINATED: %s [%s HIT] (+1 BONUS POD! Respawning at gate...)" % [bot_name, zone_lbl])
	NetworkLobby.broadcast_bot_eliminated(name)

func eliminate_from_network() -> void:
	if is_eliminated:
		return
	_apply_elimination("TEAMMATE ELIMINATED: %s!" % bot_name)

func _apply_elimination(feed_msg: String) -> void:
	is_eliminated = true
	respawn_timer = BOT_RESPAWN_DELAY
	if pro_rig != null:
		pro_rig.apply_pose(0.0, {
			"velocity": Vector3.ZERO,
			"stance": 0,
			"lean": 0.0,
			"is_left_handed": peek_offset.x > 0.0,
			"bunker_tuck": 0.0,
			"is_eliminated": true,
		})
		_sync_compat_pivots()
	IntelBus.intel_feed_updated.emit(feed_msg)
	GameManager.notify_enemy_eliminated()

func _respawn_bot() -> void:
	is_eliminated = false
	position = base_pos
	rotation.x = 0.0
	if pro_rig != null:
		pro_rig.apply_pose(0.0, {
			"velocity": Vector3.ZERO,
			"stance": 0,
			"lean": 0.0,
			"is_left_handed": peek_offset.x > 0.0,
			"bunker_tuck": 1.0,
			"is_eliminated": false,
		})
		_sync_compat_pivots()

func on_paintball_bounce(hit_pos: Vector3) -> void:
	if is_eliminated:
		return
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "JERSEY"))
	IntelBus.intel_feed_updated.emit("BOUNCE on %s [%s] — Still Alive!" % [bot_name, zone_lbl])

func _on_enemy_spotted(target_name: String, _pos: Vector3, duration: float) -> void:
	if target_name == name or target_name == bot_name:
		is_spotted_timer = duration
