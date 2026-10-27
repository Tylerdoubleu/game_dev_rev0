extends CharacterBody3D

## First-person paintball player controller for v0.1.0-playtest.
## TODO(PB-01 / Issue #1): Upgrade discrete Q/E lean and slide to analog peeking and hopper/elbow hitboxes.
## TODO(PB-03 / Issue #3): Upgrade timed reload bar to staged manual pod pour, physical spills, and spatial audio cues.

const GearBracketDataScript = preload("res://scripts/resources/gear_bracket_data.gd")

signal hud_state_changed(state: Dictionary)
signal status_banner_sent(message: String, color: Color)

const WALK_SPEED: float = 5.4
const SPRINT_SPEED: float = 8.8
const SLIDE_SPEED: float = 11.2
const SLIDE_DURATION: float = 0.55
const LEAN_OFFSET_X: float = 0.48
const LEAN_ROLL_DEG: float = 11.0
const MOUSE_SENSITIVITY: float = 0.0024

var head_pivot: Node3D
var camera: Camera3D
var marker_rig: Node3D
var hopper_mesh: MeshInstance3D

var yaw: float = 0.0
var pitch: float = 0.0
var current_lean: float = 0.0
var is_left_handed: bool = false
var is_crouching: bool = false
var slide_timer: float = 0.0
var slide_dir: Vector3 = Vector3.ZERO

var hopper_paint: int = 200
var pods_remaining: int = 4
var is_reloading_pod: bool = false
var reload_timer: float = 0.0
var reload_duration: float = 2.0
var pump_racked: bool = true
var time_since_last_shot: float = 99.0

func _ready() -> void:
	_build_player_nodes()
	GearRuleEnforcer.bracket_changed.connect(_on_bracket_changed)
	_on_bracket_changed(GearRuleEnforcer.active_bracket)
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build_player_nodes() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	col.shape = capsule
	col.position = Vector3(0, 0.875, 0)
	add_child(col)

	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 1.55, 0)
	add_child(head_pivot)

	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.fov = 82.0
	camera.current = true
	head_pivot.add_child(camera)

	marker_rig = Node3D.new()
	marker_rig.name = "MarkerViewModel"
	marker_rig.position = Vector3(0.24, -0.22, -0.45)
	camera.add_child(marker_rig)

	var body_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.11, 0.48)
	body_mesh.mesh = box
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.15, 0.55, 0.95)
	marker_mat.metallic = 0.65
	marker_mat.roughness = 0.25
	body_mesh.material_override = marker_mat
	marker_rig.add_child(body_mesh)

	hopper_mesh = MeshInstance3D.new()
	var h_sphere := SphereMesh.new()
	h_sphere.radius = 0.085
	h_sphere.height = 0.14
	hopper_mesh.mesh = h_sphere
	hopper_mesh.position = Vector3(0.0, 0.11, 0.04)
	var hopper_mat := StandardMaterial3D.new()
	hopper_mat.albedo_color = Color(0.12, 0.12, 0.14)
	hopper_mesh.material_override = hopper_mat
	marker_rig.add_child(hopper_mesh)

func _on_bracket_changed(bracket: Resource) -> void:
	if bracket == null:
		return
	hopper_paint = bracket.hopper_capacity
	pods_remaining = bracket.pod_count
	is_reloading_pod = false
	pump_racked = true
	status_banner_sent.emit("Switched Bracket: %s" % bracket.display_name, Color(0.4, 0.85, 1.0))
	_emit_hud()

func _unhandled_input(event: InputEvent) -> void:
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
		_attempt_fire(false)
	elif event.is_action_pressed("fire_secondary_walk"):
		_attempt_fire(true)

func _physics_process(delta: float) -> void:
	time_since_last_shot += delta

	var bracket: Resource = GearRuleEnforcer.active_bracket
	if bracket and bracket.trigger_mode == GearBracketDataScript.TriggerMode.RAMP_10_5:
		if Input.is_action_pressed("fire_primary"):
			_attempt_fire(false)

	_update_movement_and_stance(delta)
	_update_lean_and_viewmodel(delta)
	_update_pod_reload(delta)

func _update_movement_and_stance(delta: float) -> void:
	var input_vec := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	).normalized()

	var move_dir := (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var wants_sprint := Input.is_action_pressed("sprint") and input_vec.y < -0.1

	if Input.is_action_just_pressed("crouch_slide"):
		if wants_sprint and slide_timer <= 0.0 and move_dir.length() > 0.1:
			slide_timer = SLIDE_DURATION
			slide_dir = move_dir
			is_crouching = true
			if is_reloading_pod:
				_spill_active_pod("Knee-slide interrupted reload — pod spilled!")
		else:
			is_crouching = not is_crouching

	if wants_sprint and is_reloading_pod:
		_spill_active_pod("Sprint interrupted reload — pod spilled!")

	if slide_timer > 0.0:
		slide_timer -= delta
		var slide_factor: float = clamp(slide_timer / SLIDE_DURATION, 0.25, 1.0)
		velocity.x = slide_dir.x * SLIDE_SPEED * slide_factor
		velocity.z = slide_dir.z * SLIDE_SPEED * slide_factor
	else:
		var target_speed: float = WALK_SPEED
		if wants_sprint:
			target_speed = SPRINT_SPEED
		elif is_crouching:
			target_speed = WALK_SPEED * 0.55
		velocity.x = move_dir.x * target_speed
		velocity.z = move_dir.z * target_speed

	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

func _update_lean_and_viewmodel(delta: float) -> void:
	var target_lean: float = 0.0
	if Input.is_action_pressed("lean_left"):
		target_lean = -1.0
		is_left_handed = true
	elif Input.is_action_pressed("lean_right"):
		target_lean = 1.0
		is_left_handed = false

	current_lean = lerp(current_lean, target_lean, min(1.0, delta * 12.0))
	var target_height: float = 1.02 if (is_crouching or slide_timer > 0.0) else 1.55
	head_pivot.position.y = lerp(head_pivot.position.y, target_height, min(1.0, delta * 12.0))
	head_pivot.position.x = current_lean * LEAN_OFFSET_X
	camera.rotation.x = pitch
	camera.rotation.z = deg_to_rad(-current_lean * LEAN_ROLL_DEG)

	var target_hand_x: float = -0.24 if is_left_handed else 0.24
	var reload_dip_y: float = -0.34 if is_reloading_pod else -0.22
	marker_rig.position.x = lerp(marker_rig.position.x, target_hand_x, min(1.0, delta * 14.0))
	marker_rig.position.y = lerp(marker_rig.position.y, reload_dip_y, min(1.0, delta * 10.0))

func _attempt_fire(is_secondary_trigger: bool) -> void:
	if is_reloading_pod:
		return

	var bracket: Resource = GearRuleEnforcer.active_bracket
	if bracket == null:
		return

	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
		if is_secondary_trigger:
			pump_racked = true
			status_banner_sent.emit("Pump handle racked!", Color(0.8, 0.95, 1.0))
			_emit_hud()
			return
		elif not pump_racked:
			status_banner_sent.emit("Pump not racked! Press RMB to rack pump.", Color(1.0, 0.65, 0.2))
			return

	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.SEMI_ONE_PULL and is_secondary_trigger:
		status_banner_sent.emit("Woodsball Bracket: Strict 1-Pull Semi (RMB walking disabled)", Color(1.0, 0.7, 0.2))
		return

	if time_since_last_shot < GearRuleEnforcer.get_min_shot_interval():
		return

	if hopper_paint <= 0:
		status_banner_sent.emit("Hopper Empty! Press [R] behind cover to reload a pod.", Color(1.0, 0.35, 0.35))
		return

	hopper_paint -= 1
	time_since_last_shot = 0.0
	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
		pump_racked = false

	var spread_rad := deg_to_rad(0.9 + (1.4 if velocity.length() > 2.5 else 0.0))
	var forward_dir := -camera.global_transform.basis.z.normalized()
	var right_dir := camera.global_transform.basis.x.normalized()
	var up_dir := camera.global_transform.basis.y.normalized()
	var rand_x := randf_range(-spread_rad, spread_rad)
	var rand_y := randf_range(-spread_rad, spread_rad)
	var shot_dir := (forward_dir + right_dir * rand_x + up_dir * rand_y).normalized()

	var muzzle_pos := marker_rig.global_position + forward_dir * 0.35
	PaintBallistics.spawn_paintball(muzzle_pos, shot_dir, bracket.muzzle_fps, self, Color(1.0, 0.48, 0.05))
	_emit_hud()

func _start_pod_reload() -> void:
	var bracket: Resource = GearRuleEnforcer.active_bracket
	if bracket == null or is_reloading_pod:
		return
	if pods_remaining <= 0:
		status_banner_sent.emit("No pods remaining!", Color(1.0, 0.3, 0.3))
		return
	if hopper_paint >= bracket.hopper_capacity:
		status_banner_sent.emit("Hopper is already full!", Color(0.75, 0.9, 1.0))
		return

	pods_remaining -= 1
	is_reloading_pod = true
	reload_timer = reload_duration
	status_banner_sent.emit("Pouring pod into hopper... DO NOT sprint or slide!", Color(1.0, 0.85, 0.25))
	_emit_hud()

func _update_pod_reload(delta: float) -> void:
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
			status_banner_sent.emit("Pod loaded (+%d paint, %d spilled from overfilling early!)" % [added, overfill_spilled], Color(1.0, 0.78, 0.25))
		else:
			status_banner_sent.emit("Clean pod reload! (+%d paint)" % added, Color(0.35, 1.0, 0.45))
		_emit_hud()

func _spill_active_pod(reason: String) -> void:
	is_reloading_pod = false
	reload_timer = 0.0
	status_banner_sent.emit(reason, Color(1.0, 0.28, 0.28))
	_emit_hud()

func _ping_crosshair_target() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from_pos := camera.global_position
	var to_pos := from_pos - camera.global_transform.basis.z * 80.0
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		var label: String = col.name if col else "Bunker"
		IntelBus.report_spot(label, hit["position"], 3.0)
		status_banner_sent.emit("PINGED: %s" % label, Color(1.0, 0.9, 0.2))

func _emit_hud() -> void:
	var bracket: Resource = GearRuleEnforcer.active_bracket
	hud_state_changed.emit({
		"bracket_name": bracket.display_name if bracket else "",
		"hopper": hopper_paint,
		"hopper_max": bracket.hopper_capacity if bracket else 200,
		"pods": pods_remaining,
		"pod_cap": bracket.pod_capacity if bracket else 140,
		"hand": "LEFT HAND" if is_left_handed else "RIGHT HAND",
		"reloading": is_reloading_pod,
		"reload_pct": clamp(1.0 - (reload_timer / reload_duration), 0.0, 1.0) if is_reloading_pod else 0.0,
		"pump_mode": bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL if bracket else false,
		"pump_racked": pump_racked
	})
