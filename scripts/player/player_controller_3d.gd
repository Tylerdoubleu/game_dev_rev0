extends CharacterBody3D

## First-person paintball player controller for v0.2 (Gritty 2000s Tournament Art Overhaul).
## Features:
## - Speedball: Separate LMB & RMB triggers (walk the trigger!) capped at 10.5 BPS total
## - Woodsball (1-Pull): Enforce holding BOTH LMB + RMB together to pull the heavy mechanical trigger
## - Pump: LMB fires, RMB racks the pump handle
## - Stances (Hold-only): Hold C for Crouch, Shift+C for Knee-Slide (stays crouched after slide only if C is held);
##   Hold Ctrl for Prone, Shift+Ctrl for Superman Dive (stays prone after dive only if Ctrl is held).
## - Head/marker bobbing when moving + 3D Pod pour animation on reload (R)
## - Weathered 2000s tournament marker viewmodel with air pressure gauge, tactical glove & paint smears

const GearBracketDataScript = preload("res://scripts/resources/gear_bracket_data.gd")
const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")

signal hud_state_changed(state: Dictionary)
signal status_banner_sent(message: String, color: Color)

enum Stance {
	STANDING,
	CROUCHING,
	PRONE
}

const WALK_SPEED: float = 6.2
const SPRINT_SPEED: float = 10.4
const CROUCH_SPEED: float = 3.6
const PRONE_SPEED: float = 1.85
const SLIDE_INITIAL_SPEED: float = 17.5
const SLIDE_DURATION: float = 0.85
const DIVE_INITIAL_SPEED: float = 19.5
const DIVE_DURATION: float = 0.95

const HEIGHT_STANDING: float = 1.58
const HEIGHT_CROUCH: float = 0.92
const HEIGHT_SLIDE: float = 0.68
const HEIGHT_PRONE: float = 0.36
const HEIGHT_DIVE: float = 0.42

const BASE_FOV: float = 82.0
const SLIDE_FOV: float = 96.0
const DIVE_FOV: float = 100.0

const LEAN_OFFSET_X: float = 0.52
const LEAN_ROLL_DEG: float = 11.5
const MOUSE_SENSITIVITY: float = 0.0024

var head_pivot: Node3D
var camera: Camera3D
var marker_rig: Node3D
var hopper_mesh: MeshInstance3D
var hopper_lid_mesh: MeshInstance3D
var pod_rig: Node3D
var pod_stream_mesh: MeshInstance3D

var yaw: float = 0.0
var pitch: float = 0.0
var current_lean: float = 0.0
var is_left_handed: bool = false

var stance: Stance = Stance.STANDING
var slide_timer: float = 0.0
var dive_timer: float = 0.0
var slide_dir: Vector3 = Vector3.ZERO
var bob_time: float = 0.0

var hopper_paint: int = 30
var pods_remaining: int = 2
var is_reloading_pod: bool = false
var reload_timer: float = 0.0
var reload_duration: float = 2.1
var pump_racked: bool = true
var woodsball_trigger_latched: bool = false
var time_since_last_shot: float = 99.0
var _shot_counter: int = 0
var lobby_open: bool = false
var initial_spawn_pos: Vector3 = Vector3(0.0, 0.1, 45.5)
var initial_spawn_yaw: float = 0.0
var _net_sync_timer: float = 0.0
var _respawn_flash_timer: float = 0.0

func _ready() -> void:
	_build_player_nodes()
	GearRuleEnforcer.bracket_changed.connect(_on_bracket_changed)
	initial_spawn_pos = global_position
	initial_spawn_yaw = yaw
	NetworkLobby.remote_player_hit_local.connect(_on_remote_player_hit_local)
	NetworkLobby.local_player_scored_kill.connect(award_kill_bonus_pod)
	_on_bracket_changed(GearRuleEnforcer.active_bracket)

func _build_player_nodes() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.75
	col.shape = capsule
	col.position = Vector3(0, 0.875, 0)
	add_child(col)

	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, HEIGHT_STANDING, 0)
	add_child(head_pivot)

	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.fov = BASE_FOV
	camera.current = true
	head_pivot.add_child(camera)

	marker_rig = Node3D.new()
	marker_rig.name = "MarkerViewModel"
	marker_rig.position = Vector3(0.24, -0.22, -0.45)
	camera.add_child(marker_rig)

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "MarkerBodyMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.11, 0.50)
	body_mesh.mesh = box
	marker_rig.add_child(body_mesh)

	hopper_mesh = MeshInstance3D.new()
	hopper_mesh.name = "HopperMesh"
	var h_sphere := SphereMesh.new()
	h_sphere.radius = 0.085
	h_sphere.height = 0.14
	hopper_mesh.mesh = h_sphere
	hopper_mesh.position = Vector3(0.0, 0.11, 0.04)
	marker_rig.add_child(hopper_mesh)

	hopper_lid_mesh = MeshInstance3D.new()
	hopper_lid_mesh.name = "HopperLidMesh"
	var lid_cyl := CylinderMesh.new()
	lid_cyl.top_radius = 0.045
	lid_cyl.bottom_radius = 0.045
	lid_cyl.height = 0.012
	hopper_lid_mesh.mesh = lid_cyl
	hopper_lid_mesh.position = Vector3(0.0, 0.175, 0.04)
	marker_rig.add_child(hopper_lid_mesh)

	GrittyArtThemeScript.upgrade_first_person_marker(marker_rig, body_mesh, hopper_mesh, hopper_lid_mesh)

	pod_rig = Node3D.new()
	pod_rig.name = "PodReloadRig"
	pod_rig.position = Vector3(-0.22, -0.35, -0.1)
	pod_rig.visible = false
	marker_rig.add_child(pod_rig)

	var pod_body := MeshInstance3D.new()
	var pod_cyl := CylinderMesh.new()
	pod_cyl.top_radius = 0.042
	pod_cyl.bottom_radius = 0.042
	pod_cyl.height = 0.24
	pod_body.mesh = pod_cyl
	var pod_mat := StandardMaterial3D.new()
	pod_mat.albedo_color = Color(0.82, 0.85, 0.88, 0.88)
	pod_mat.roughness = 0.22
	pod_body.material_override = pod_mat
	pod_rig.add_child(pod_body)

	pod_stream_mesh = MeshInstance3D.new()
	var stream_cyl := CylinderMesh.new()
	stream_cyl.top_radius = 0.022
	stream_cyl.bottom_radius = 0.028
	stream_cyl.height = 0.16
	pod_stream_mesh.mesh = stream_cyl
	pod_stream_mesh.position = Vector3(0.0, -0.16, 0.0)
	pod_stream_mesh.material_override = GrittyArtThemeScript.create_oily_paint_material(GrittyArtThemeScript.NEON_YELLOW_PAINT, false)
	pod_rig.add_child(pod_stream_mesh)

func _on_bracket_changed(bracket: Resource) -> void:
	if bracket == null:
		return
	hopper_paint = bracket.hopper_capacity
	pods_remaining = bracket.pod_count
	is_reloading_pod = false
	if pod_rig:
		pod_rig.visible = false
	pump_racked = true
	woodsball_trigger_latched = false
	status_banner_sent.emit("Switched Bracket: %s" % bracket.display_name, Color(0.4, 0.85, 1.0))
	_emit_hud()

func _unhandled_input(event: InputEvent) -> void:
	if lobby_open or NetworkLobby.is_dedicated_server:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0))
		rotation.y = yaw

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("swap_shoulder"):
		is_left_handed = not is_left_handed
		_emit_hud()

	if event.is_action_pressed("reload_pod"):
		_start_pod_reload()

	if event.is_action_pressed("ping_intel"):
		_ping_crosshair_target()

	if event.is_action_pressed("bracket_speedball"):
		GearRuleEnforcer.set_active_bracket("speedball")
	elif event.is_action_pressed("bracket_woodsball"):
		GearRuleEnforcer.set_active_bracket("woodsball")
	elif event.is_action_pressed("bracket_pump"):
		GearRuleEnforcer.set_active_bracket("pump")
	elif event.is_action_pressed("reset_round"):
		GameManager.reset_round()

	if event.is_action_pressed("fire_primary"):
		_handle_trigger_press(false)
	elif event.is_action_pressed("fire_secondary_walk"):
		_handle_trigger_press(true)

func _physics_process(delta: float) -> void:
	if NetworkLobby.is_dedicated_server:
		return
	time_since_last_shot += delta
	if _respawn_flash_timer > 0.0:
		_respawn_flash_timer = maxf(0.0, _respawn_flash_timer - delta)

	if woodsball_trigger_latched:
		if not (Input.is_action_pressed("fire_primary") and Input.is_action_pressed("fire_secondary_walk")):
			woodsball_trigger_latched = false

	if not lobby_open:
		_update_movement_and_stance(delta)
	_update_lean_bob_and_viewmodel(delta)
	_update_pod_reload(delta)

	_net_sync_timer += delta
	if _net_sync_timer >= 0.05:
		_net_sync_timer = 0.0
		NetworkLobby.send_local_player_state(global_position, yaw, pitch, current_lean, int(stance), _respawn_flash_timer > 0.0)

func _resolve_held_stance() -> Stance:
	if Input.is_action_pressed("prone_dive"):
		return Stance.PRONE
	elif Input.is_action_pressed("crouch_slide"):
		return Stance.CROUCHING
	return Stance.STANDING

func _update_movement_and_stance(delta: float) -> void:
	var input_vec := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	).normalized()

	var move_dir := (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var shift_held := Input.is_action_pressed("sprint")
	var crouch_held := Input.is_action_pressed("crouch_slide")
	var prone_held := Input.is_action_pressed("prone_dive")

	# Trigger Knee-Slide on Shift + C press
	if Input.is_action_just_pressed("crouch_slide") and shift_held and slide_timer <= 0.0 and dive_timer <= 0.0:
		slide_timer = SLIDE_DURATION
		slide_dir = move_dir if move_dir.length() > 0.1 else -transform.basis.z.normalized()
		stance = Stance.CROUCHING
		status_banner_sent.emit("KNEE-SLIDE! (Hold [C] to stay crouched)", Color(0.35, 0.95, 1.0))
		if is_reloading_pod:
			_spill_active_pod("Knee-slide interrupted reload — pod spilled!")
		_emit_hud()

	# Trigger Superman Dive on Shift + Ctrl press
	if Input.is_action_just_pressed("prone_dive") and shift_held and dive_timer <= 0.0 and slide_timer <= 0.0:
		dive_timer = DIVE_DURATION
		slide_dir = move_dir if move_dir.length() > 0.1 else -transform.basis.z.normalized()
		stance = Stance.PRONE
		status_banner_sent.emit("SUPERMAN DIVE! (Hold [Ctrl] to stay prone)", Color(1.0, 0.82, 0.25))
		if is_reloading_pod:
			_spill_active_pod("Superman dive interrupted reload — pod spilled!")
		_emit_hud()

	# Update active slide / dive timers, and check held keys when complete
	if dive_timer > 0.0:
		dive_timer -= delta
		if dive_timer <= 0.0:
			dive_timer = 0.0
			stance = _resolve_held_stance()
			_emit_hud()
	elif slide_timer > 0.0:
		slide_timer -= delta
		if slide_timer <= 0.0:
			slide_timer = 0.0
			stance = _resolve_held_stance()
			_emit_hud()
	else:
		# Pure hold-to-crouch (C) and hold-to-prone (Ctrl) when not sliding/diving
		var prev_stance := stance
		stance = _resolve_held_stance()
		if stance != prev_stance:
			_emit_hud()

	var wants_sprint := shift_held and input_vec.y < -0.1 and slide_timer <= 0.0 and dive_timer <= 0.0 and not crouch_held and not prone_held

	if wants_sprint and is_reloading_pod:
		_spill_active_pod("Sprint interrupted reload — pod spilled!")

	if dive_timer > 0.0:
		var dive_factor: float = clamp(dive_timer / DIVE_DURATION, 0.15, 1.0)
		velocity.x = slide_dir.x * DIVE_INITIAL_SPEED * dive_factor
		velocity.z = slide_dir.z * DIVE_INITIAL_SPEED * dive_factor
	elif slide_timer > 0.0:
		var slide_factor: float = clamp(slide_timer / SLIDE_DURATION, 0.2, 1.0)
		velocity.x = slide_dir.x * SLIDE_INITIAL_SPEED * slide_factor
		velocity.z = slide_dir.z * SLIDE_INITIAL_SPEED * slide_factor
	else:
		var target_speed: float = WALK_SPEED
		if wants_sprint:
			target_speed = SPRINT_SPEED
		elif stance == Stance.CROUCHING:
			target_speed = CROUCH_SPEED
		elif stance == Stance.PRONE:
			target_speed = PRONE_SPEED
		velocity.x = move_dir.x * target_speed
		velocity.z = move_dir.z * target_speed

	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

func _update_lean_bob_and_viewmodel(delta: float) -> void:
	var target_lean: float = 0.0
	if Input.is_action_pressed("lean_left"):
		target_lean = -1.0
		is_left_handed = true
	elif Input.is_action_pressed("lean_right"):
		target_lean = 1.0
		is_left_handed = false

	current_lean = lerp(current_lean, target_lean, min(1.0, delta * 12.0))

	var base_height: float = HEIGHT_STANDING
	var target_fov: float = BASE_FOV
	var slide_roll_deg: float = 0.0
	var dive_pitch_offset: float = 0.0

	if dive_timer > 0.0:
		base_height = HEIGHT_DIVE
		target_fov = DIVE_FOV
		dive_pitch_offset = deg_to_rad(-8.0 * (dive_timer / DIVE_DURATION))
	elif slide_timer > 0.0:
		base_height = HEIGHT_SLIDE
		target_fov = SLIDE_FOV
		slide_roll_deg = -7.5 if not is_left_handed else 7.5
	elif stance == Stance.CROUCHING:
		base_height = HEIGHT_CROUCH
	elif stance == Stance.PRONE:
		base_height = HEIGHT_PRONE

	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	var bob_y: float = 0.0
	var bob_x: float = 0.0
	if horiz_speed > 0.4 and slide_timer <= 0.0 and dive_timer <= 0.0:
		var bob_freq: float = 13.5 if horiz_speed > 7.5 else (9.5 if stance == Stance.STANDING else 6.8)
		var bob_amp_y: float = 0.095 if horiz_speed > 7.5 else (0.055 if stance == Stance.STANDING else 0.032)
		bob_time += delta * bob_freq
		bob_y = sin(bob_time) * bob_amp_y
		bob_x = cos(bob_time * 0.5) * bob_amp_y * 0.65
	else:
		bob_time = 0.0

	head_pivot.position.y = lerp(head_pivot.position.y, base_height + bob_y, min(1.0, delta * 15.0))
	head_pivot.position.x = lerp(head_pivot.position.x, current_lean * LEAN_OFFSET_X + bob_x, min(1.0, delta * 14.0))
	camera.fov = lerp(camera.fov, target_fov, min(1.0, delta * 10.0))
	camera.rotation.x = clamp(pitch + dive_pitch_offset, deg_to_rad(-85.0), deg_to_rad(85.0))
	camera.rotation.z = deg_to_rad(-current_lean * LEAN_ROLL_DEG + slide_roll_deg)

	var hand_sign: float = -1.0 if is_left_handed else 1.0
	var target_hand_x: float = 0.17 * hand_sign + bob_x * 0.35
	var reload_dip_y: float = -0.29 if is_reloading_pod else (-0.22 + bob_y * 0.45)
	marker_rig.position.x = lerp(marker_rig.position.x, target_hand_x, min(1.0, delta * 14.0))
	marker_rig.position.y = lerp(marker_rig.position.y, reload_dip_y, min(1.0, delta * 12.0))
	var target_marker_roll: float = deg_to_rad(18.0 * hand_sign) if is_reloading_pod else 0.0
	marker_rig.rotation.z = lerp(marker_rig.rotation.z, target_marker_roll, min(1.0, delta * 12.0))

	if is_reloading_pod:
		var pct: float = clamp(1.0 - (reload_timer / reload_duration), 0.0, 1.0)
		pod_rig.visible = true
		hopper_lid_mesh.rotation.z = deg_to_rad(110.0 * hand_sign)
		hopper_lid_mesh.position.x = -0.05 * hand_sign
		var shake_y: float = sin(pct * 45.0) * 0.015 if (pct > 0.2 and pct < 0.88) else 0.0
		pod_rig.position = Vector3(-0.04 * hand_sign, 0.34 + shake_y, 0.04)
		pod_rig.rotation = Vector3(deg_to_rad(15.0), 0.0, deg_to_rad(-148.0 * hand_sign))
		pod_stream_mesh.visible = (pct > 0.18 and pct < 0.88)
	else:
		pod_rig.visible = false
		hopper_lid_mesh.rotation.z = 0.0
		hopper_lid_mesh.position.x = 0.0

func _handle_trigger_press(is_secondary_trigger: bool) -> void:
	if is_reloading_pod:
		return

	var bracket: Resource = GearRuleEnforcer.active_bracket
	if bracket == null:
		return

	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.RAMP_10_5:
		_fire_single_paintball(bracket)
		return

	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.SEMI_ONE_PULL:
		var both_held := Input.is_action_pressed("fire_primary") and Input.is_action_pressed("fire_secondary_walk")
		if not both_held:
			status_banner_sent.emit("1-Pull Mode: Press & hold BOTH [LMB + RMB] together to fire!", Color(1.0, 0.75, 0.25))
			return
		if woodsball_trigger_latched:
			return
		woodsball_trigger_latched = true
		_fire_single_paintball(bracket)
		return

	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
		if is_secondary_trigger:
			pump_racked = true
			status_banner_sent.emit("Pump handle racked! Ready to fire [LMB].", Color(0.8, 0.95, 1.0))
			_emit_hud()
			return
		elif not pump_racked:
			status_banner_sent.emit("Pump not racked! Press [RMB] to rack pump.", Color(1.0, 0.65, 0.2))
			return
		_fire_single_paintball(bracket)

func _fire_single_paintball(bracket: Resource) -> void:
	if time_since_last_shot < GearRuleEnforcer.get_min_shot_interval():
		return

	if hopper_paint <= 0:
		status_banner_sent.emit("HOPPER EMPTY! Press [R] behind cover to pour a pod.", Color(1.0, 0.35, 0.35))
		return

	hopper_paint -= 1
	time_since_last_shot = 0.0
	_shot_counter += 1
	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
		pump_racked = false

	marker_rig.position.z = -0.39

	var spread_rad := deg_to_rad(0.75 + (1.3 if velocity.length() > 3.0 else 0.0))
	var forward_dir := -camera.global_transform.basis.z.normalized()
	var right_dir := camera.global_transform.basis.x.normalized()
	var up_dir := camera.global_transform.basis.y.normalized()
	var rand_x := randf_range(-spread_rad, spread_rad)
	var rand_y := randf_range(-spread_rad, spread_rad)

	# Sightline-convergent snap-peeking: if the eye/crosshair line of sight clears the near bunker,
	# ensure the off-center barrel doesn't clip an invisible near-bunker edge when peeking!
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var cam_origin := camera.global_position
	var aim_target := cam_origin + forward_dir * 45.0
	var cam_q := PhysicsRayQueryParameters3D.create(cam_origin, aim_target)
	cam_q.exclude = [get_rid()]
	var cam_hit: Dictionary = space_state.intersect_ray(cam_q)
	if not cam_hit.is_empty():
		aim_target = cam_hit["position"]

	var muzzle_pos := marker_rig.global_position + forward_dir * 0.46
	var near_check_q := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + (aim_target - muzzle_pos).normalized() * 2.4)
	near_check_q.exclude = [get_rid()]
	var near_hit: Dictionary = space_state.intersect_ray(near_check_q)
	if not near_hit.is_empty() and (cam_hit.is_empty() or cam_origin.distance_to(cam_hit["position"]) > 2.8):
		# Tuck barrel origin slightly toward the peeking eye line so tight snap-shots clear the bunker edge cleanly
		muzzle_pos = cam_origin.lerp(muzzle_pos, 0.28) + forward_dir * 0.22

	var base_dir := (aim_target - muzzle_pos).normalized()
	var shot_dir := (base_dir + right_dir * rand_x + up_dir * rand_y).normalized()

	# Pneumatic bolt kick + subtle camera micro-recoil + HPA muzzle vapor puff
	pitch = clamp(pitch + deg_to_rad(randf_range(0.18, 0.36)), deg_to_rad(-80.0), deg_to_rad(80.0))
	yaw += deg_to_rad(randf_range(-0.16, 0.16))
	rotation.y = yaw
	GrittyArtThemeScript.spawn_muzzle_gas_puff(get_tree().current_scene, muzzle_pos, forward_dir)
	var paint_col := GrittyArtThemeScript.HOT_PINK_PAINT if (_shot_counter % 2 == 0) else GrittyArtThemeScript.NEON_YELLOW_PAINT
	PaintBallistics.spawn_paintball(muzzle_pos, shot_dir, bracket.muzzle_fps, self, paint_col)
	NetworkLobby.broadcast_paintball_shot(muzzle_pos, shot_dir, bracket.muzzle_fps)
	_emit_hud()

func _start_pod_reload() -> void:
	var bracket: Resource = GearRuleEnforcer.active_bracket
	if bracket == null or is_reloading_pod:
		return
	if pods_remaining <= 0:
		status_banner_sent.emit("OUT OF PODS! Every shot counts!", Color(1.0, 0.3, 0.3))
		return
	if hopper_paint >= bracket.hopper_capacity:
		status_banner_sent.emit("Hopper is already full!", Color(0.75, 0.9, 1.0))
		return

	pods_remaining -= 1
	is_reloading_pod = true
	reload_timer = reload_duration
	status_banner_sent.emit("Pouring pod into hopper... DO NOT sprint, slide, or dive!", Color(1.0, 0.85, 0.25))
	_emit_hud()

func _update_pod_reload(delta: float) -> void:
	marker_rig.position.z = lerp(marker_rig.position.z, -0.45, min(1.0, delta * 16.0))
	if not is_reloading_pod:
		return
	reload_timer -= delta
	_emit_hud()
	if reload_timer <= 0.0:
		is_reloading_pod = false
		var bracket: Resource = GearRuleEnforcer.active_bracket
		var space_left: int = int(bracket.hopper_capacity) - hopper_paint
		var added: int = min(space_left, int(bracket.pod_capacity))
		var overfill_spilled: int = max(0, int(bracket.pod_capacity) - added)
		hopper_paint += added
		if overfill_spilled > 0:
			_spawn_spilled_paint_burst(overfill_spilled)
			status_banner_sent.emit("Pod loaded (+%d paint, %d spilled from overfilling early!)" % [added, overfill_spilled], Color(1.0, 0.78, 0.25))
		else:
			status_banner_sent.emit("Clean pod reload! (+%d paint)" % added, Color(0.35, 1.0, 0.45))
		_emit_hud()

func _spill_active_pod(reason: String) -> void:
	is_reloading_pod = false
	reload_timer = 0.0
	_spawn_spilled_paint_burst(16)
	status_banner_sent.emit(reason, Color(1.0, 0.28, 0.28))
	_emit_hud()

func _spawn_spilled_paint_burst(count: int) -> void:
	var forward_dir := -camera.global_transform.basis.z.normalized()
	var origin := marker_rig.global_position + Vector3(0, 0.1, 0)
	for i in range(min(count, 18)):
		var scatter := Vector3(randf_range(-0.65, 0.65), randf_range(-0.2, 0.35), randf_range(-0.65, 0.65))
		var dir := (forward_dir * 0.4 + scatter).normalized()
		var spill_col := GrittyArtThemeScript.NEON_YELLOW_PAINT if (i % 2 == 0) else GrittyArtThemeScript.HOT_PINK_PAINT
		PaintBallistics.spawn_paintball(origin, dir, 32.0, self, spill_col)

func _ping_crosshair_target() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from_pos := camera.global_position
	var to_pos := from_pos - camera.global_transform.basis.z * 140.0
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		var label: String = col.name if col else "Bunker"
		IntelBus.report_spot(label, hit["position"], 3.5)
		status_banner_sent.emit("PINGED: %s" % label, Color(1.0, 0.9, 0.2))

func _get_stance_label() -> String:
	if dive_timer > 0.0:
		return "SUPERMAN DIVE"
	if slide_timer > 0.0:
		return "KNEE-SLIDE"
	match stance:
		Stance.CROUCHING:
			return "CROUCH (Holding [C])"
		Stance.PRONE:
			return "PRONE (Holding [Ctrl])"
		_:
			return "STANDING"

func _emit_hud() -> void:
	var bracket: Resource = GearRuleEnforcer.active_bracket
	hud_state_changed.emit({
		"bracket_name": bracket.display_name if bracket else "",
		"hopper": hopper_paint,
		"hopper_max": bracket.hopper_capacity if bracket else 30,
		"pods": pods_remaining,
		"pod_cap": bracket.pod_capacity if bracket else 30,
		"hand": "LEFT HAND" if is_left_handed else "RIGHT HAND",
		"stance": _get_stance_label(),
		"reloading": is_reloading_pod,
		"reload_pct": clamp(1.0 - (reload_timer / reload_duration), 0.0, 1.0) if is_reloading_pod else 0.0,
		"pump_mode": bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL if bracket else false,
		"pump_racked": pump_racked
	})

func set_lobby_open_state(is_open: bool) -> void:
	lobby_open = is_open
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED)

func respawn_at_team_gate(team: String) -> void:
	var side := 1.0 if team == "ALPHA" else -1.0
	initial_spawn_pos = Vector3(0.0, 0.1, 45.5 * side)
	initial_spawn_yaw = 0.0 if side > 0.0 else PI
	global_position = initial_spawn_pos
	velocity = Vector3.ZERO
	yaw = initial_spawn_yaw
	pitch = 0.0
	rotation.y = yaw
	is_reloading_pod = false
	reload_timer = 0.0
	_on_bracket_changed(GearRuleEnforcer.active_bracket)

func respawn_at_starting_spot() -> void:
	global_position = initial_spawn_pos
	velocity = Vector3.ZERO
	yaw = initial_spawn_yaw
	pitch = 0.0
	rotation.y = yaw
	is_reloading_pod = false
	reload_timer = 0.0
	_on_bracket_changed(GearRuleEnforcer.active_bracket)

func award_kill_bonus_pod(victim_label: String = "Enemy") -> void:
	pods_remaining += 1
	GameManager.record_local_kill(victim_label)
	status_banner_sent.emit("ELIMINATED %s! +1 BONUS POD AWARDED (Pods: %d)" % [victim_label, pods_remaining], Color(0.30, 1.0, 0.45))
	_emit_hud()

func on_paintball_break(_hit_pos: Vector3, shooter: Node) -> void:
	if _respawn_flash_timer > 0.2 or GameManager.match_ended:
		return
	var killer_name: String = "OpFor NPC"
	if shooter != null and "bot_name" in shooter:
		killer_name = String(shooter.get("bot_name"))
	_handle_local_elimination(killer_name)

func on_paintball_bounce(_hit_pos: Vector3) -> void:
	status_banner_sent.emit("LUCKY BOUNCE ON YOUR JERSEY — No Break, Keep Playing!", Color(0.45, 0.95, 1.0))

func _on_remote_player_hit_local(shooter_name: String) -> void:
	_handle_local_elimination(shooter_name)

func _handle_local_elimination(killer_name: String) -> void:
	_respawn_flash_timer = 1.2
	GameManager.record_local_death(killer_name)
	respawn_at_starting_spot()
	if GameManager.match_ended:
		status_banner_sent.emit("MATCH OVER — Reached 10 Deaths! Press [T] or [M] to Review Scoreboard", Color(1.0, 0.25, 0.25))
	else:
		status_banner_sent.emit("HIT BY %s! Respawned at Original Starting Spot (Deaths: %d / %d)" % [killer_name, GameManager.local_deaths, GameManager.MAX_DEATHS_TO_LOSE], Color(1.0, 0.32, 0.32))
