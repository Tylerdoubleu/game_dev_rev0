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
const StanceRigScript = preload("res://scripts/player/pro_paintball_rig_3d.gd")

signal hud_state_changed(state: Dictionary)
signal status_banner_sent(message: String, color: Color)
signal player_eliminated(killer_name: String)
## v0.6.2: emitted at the end of every respawn_at_map_zone (map pick, team gate, starting spot) so the arena can drop a
## death/respawn-map canvas that would otherwise stay up over a live round.
signal respawned(zone_label: String)
## v0.4.5: emitted when the movement fire lock engages (knee-slide / Superman-dive start) and releases (end of the
## post-move recovery). reason is "slide", "dive", or "" on release. Viewmodel/HUD hook: also read
## is_fire_locked_by_movement(), get_fire_lock_reason() and get_movement_fire_lock_progress() each frame.
signal movement_fire_lock_changed(locked: bool, reason: String)

enum Stance {
	STANDING,
	CROUCHING,
	PRONE
}

# ---------------------------------------------------------------------------------------------------------
# v0.5.0 MOVEMENT TUNING (deliberate tournament pace). Pre-v0.5 values in comments.
# Strafing uses the same speeds (no separate strafe multiplier). v0.6: back-pedal is slower, see below.
# ---------------------------------------------------------------------------------------------------------
const WALK_SPEED: float = 5.6          # was 6.2 (-10%)
const SPRINT_SPEED: float = 8.4        # was 10.4 (-19%)
const CROUCH_SPEED: float = 3.3        # was 3.6 (-8%)
const PRONE_SPEED: float = 1.7         # was 1.85 (-8%)
## v0.6 back-pedal: moving backwards runs at this fraction of the forward speed for the same stance/sprint state,
## blended by the backward component of the input (pure S = 0.5x, back-diagonal ~0.65x, pure strafe 1.0x).
## Sprint never boosts the backward component (pure S + Shift = walking back-pedal speed).
const BACKPEDAL_SPEED_MULT: float = 0.5
## Ground speed ramps instead of snapping (pre-v0.5 velocity was set instantly every frame).
const GROUND_ACCEL: float = 28.0       # m/s^2 from rest up to walk/crouch speed (0 -> walk in 0.20s)
const SPRINT_ACCEL: float = 9.0        # m/s^2 above walk speed (walk -> sprint in 0.31s; 0 -> sprint ~0.51s)
const GROUND_DECEL: float = 60.0       # m/s^2 when releasing keys or dropping to a slower gait (sprint -> stop 0.14s)
const SLIDE_INITIAL_SPEED: float = 15.8 # was 17.5 (-10%: ~7.4m -> ~6.6m slide)
const SLIDE_DURATION: float = 0.85
## v0.4.5: no firing during the Shift+Q knee-slide or Shift+C Superman dive, plus a short trigger-recovery after.
const MOVEMENT_FIRE_RECOVERY: float = 0.15
const DIVE_INITIAL_SPEED: float = 17.6 # was 19.5 (-10%: dive keeps a little more reach than the slide)
const DIVE_DURATION: float = 0.95

const HEIGHT_STANDING: float = 1.58
const HEIGHT_CROUCH: float = 0.92
const HEIGHT_SLIDE: float = 0.68
const HEIGHT_PRONE: float = 0.36
const HEIGHT_DIVE: float = 0.42

const BASE_FOV: float = 82.0
const SLIDE_FOV: float = 96.0
const DIVE_FOV: float = 100.0

# ---------------------------------------------------------------------------------------------------------
# v0.5.0 SHOT SPREAD (rewards bunker play). Cone half-angle (deg) = bracket base * state multiplier.
# Pre-v0.5: flat 0.75 deg square spread, +1.3 deg when moving > 3 m/s, identical for every bracket.
# ---------------------------------------------------------------------------------------------------------
const SPREAD_BASE_DEG_SPEEDBALL: float = 0.75 # RAMP_10_5 electro
const SPREAD_BASE_DEG_WOODSBALL: float = 0.60 # SEMI_ONE_PULL mechanical
const SPREAD_BASE_DEG_PUMP: float = 0.42      # PUMP_MANUAL (most accurate)
const SPREAD_MULT_POCKET: float = 0.55        # tucked in a bunker pocket (tightest)
const SPREAD_MULT_PRONE: float = 0.60
const SPREAD_MULT_CROUCH: float = 0.70
const SPREAD_MULT_STANDING: float = 1.00      # standing still
const SPREAD_MULT_WALK: float = 2.00          # at full walk speed (scales with ground speed up to this)
const SPREAD_MULT_SPRINT: float = 4.50        # at full sprint speed
const SPREAD_MULT_AIRBORNE: float = 3.00      # off the ground (falls, ramp lips)
const SPREAD_RECOVERY_TIME: float = 0.40      # s for the cone to shrink from sprint to standing (pocket ~0.45s)
const SPREAD_BLOOM_TIME: float = 0.15         # s for the cone to open from standing to sprint
const SPREAD_CROSSHAIR_MIN_FONT: int = 20     # crosshair "+" size at the tightest cone
const SPREAD_CROSSHAIR_MAX_FONT: int = 38     # crosshair "+" size at the widest cone

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
var movement_fire_recovery_timer: float = 0.0
var _movement_fire_lock_state: bool = false
var _movement_fire_lock_reason: String = ""
var _movement_fire_hint_shown: bool = false
var movement_blocked_trigger_pulls: int = 0
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
var awaiting_respawn_choice: bool = false
## v0.5 one-life CTF spectate: set by the MatchHudClient (via set_spectating) after a CTF elimination until the server's
## round_started / match_ended. Blocks movement, look and every trigger pull exactly like awaiting_respawn_choice.
var spectating: bool = false
## v0.6 server-run break: until the horn you stay at/behind your start line (red z >= +line, blue z <= -line), can look
## around, but can't cross it or shoot. MatchHudClient sets this from round_started / break_horn.
var break_hold_active: bool = false
var break_hold_line_z: float = 0.0 # signed: +40 = must keep z >= 40 (red), -40 = must keep z <= -40 (blue)
var break_blocked_trigger_pulls: int = 0
var _break_fire_hint_shown: bool = false
var spectate_blocked_trigger_pulls: int = 0
## v0.5 CTF: the server says this player carries the enemy base flag (flag_state_changed carrier == me). Visual only.
var carrying_ctf_flag: bool = false
var initial_spawn_pos: Vector3 = Vector3(0.0, 0.1, 45.5)
var initial_spawn_yaw: float = 0.0
var _net_sync_timer: float = 0.0
var _respawn_flash_timer: float = 0.0
var carrying_center_flag: bool = false
var carried_flag_mesh: MeshInstance3D = null
var breakout_boost_timer: float = 0.0
var breakout_penalty_timer: float = 0.0
var _was_moving_before_horn: bool = false

# PB-16: Exaggerated Bunker Cover Pocket + Strong Corner Edge-Detent + Deep Viewmodel Tuck
const BUNKER_POCKET_REACH: float = 1.65
const BUNKER_POCKET_IDEAL_DIST: float = 0.40
var bunker_pocket_weight: float = 0.0
# v0.5.0 ground-speed ramp + movement-driven shot spread
var ground_speed: float = 0.0
var _ground_move_dir: Vector3 = Vector3.ZERO
var shot_spread_mult: float = SPREAD_MULT_STANDING
var last_shot_base_dir: Vector3 = Vector3.ZERO
var last_shot_dir: Vector3 = Vector3.ZERO
var _spread_crosshair: Label = null
var _spread_crosshair_font: int = -1
var active_bunker_name: String = ""
var _active_bunker_node: Node3D = null
var _bunker_slam_flex_cooldown: float = 0.0
var _bunker_contact_latched: bool = false
var _latched_bunker_push_dir: Vector3 = Vector3.ZERO
var _pocket_entry_tangent: Vector3 = Vector3.ZERO
var active_bunker_normal: Vector3 = Vector3.ZERO
var active_bunker_dist: float = 99.0
var lean_exposure_scale: float = 1.0
var _edge_breakaway_hold_timer: float = 0.0
var _at_bunker_edge_side: float = 0.0
var _manual_hand_override_in_pocket: bool = false
var _auto_hand_switch_cooldown: float = 0.0
var _locked_peek_hand: int = 0
var _last_auto_hand_switch_pos: Vector3 = Vector3(999.0, 999.0, 999.0)
var _last_hand_switch_pos: Vector3 = Vector3.ZERO
var _sustained_back_escape_timer: float = 0.0

# PB-16 (#20): Exposed Hopper/Marker/Mask/Pack Sub-Hitboxes & 2.4x Wrong-Hand Exposure
var hitbox_mask: CollisionShape3D = null
# v0.4.4: stance-scaled movement capsule / torso hitbox (feet stay planted at the body origin)
const TORSO_RADIUS: float = 0.25
const HEADROOM_PROBE_RADIUS: float = 0.22
const HEADROOM_PROBE_FOOT_LIFT: float = 0.15
const HEAD_CLEARANCE: float = 0.19 # mask sphere (0.17) + skin above the eye/head pivot
var torso_col: CollisionShape3D = null
var torso_capsule: CapsuleShape3D = null
var torso_capsule_height: float = StanceRigScript.STANCE_CAPSULE_STANDING
var headroom_blocked: bool = false
var hitbox_hopper_marker: CollisionShape3D = null
var hitbox_pod_pack: CollisionShape3D = null
var hopper_exposure_multiplier: float = 1.0
var last_hit_zone: String = "TORSO / JERSEY"



func _ready() -> void:
	_build_player_nodes()
	GearRuleEnforcer.bracket_changed.connect(_on_bracket_changed)
	initial_spawn_pos = global_position
	initial_spawn_yaw = yaw
	NetworkLobby.remote_player_hit_local.connect(_on_remote_player_hit_local)
	NetworkLobby.local_player_scored_kill.connect(award_kill_bonus_pod)
	if GameManager.has_signal("breakout_countdown_updated"):
		GameManager.breakout_countdown_updated.connect(_on_breakout_countdown_updated)
	_on_bracket_changed(GearRuleEnforcer.active_bracket)

func _build_player_nodes() -> void:
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.28
	floor_stop_on_slope = true
	var col := CollisionShape3D.new()
	col.name = "Hitbox_Torso"
	var capsule := CapsuleShape3D.new()
	capsule.radius = TORSO_RADIUS
	capsule.height = StanceRigScript.STANCE_CAPSULE_STANDING
	col.shape = capsule
	col.position = Vector3(0, capsule.height * 0.5, 0)
	add_child(col)
	torso_col = col
	torso_capsule = capsule
	torso_capsule_height = capsule.height

	# PB-16 (#20): Separate Mask, Hopper/Marker, and Pod Pack sub-hitboxes
	hitbox_mask = CollisionShape3D.new()
	hitbox_mask.name = "Hitbox_Mask"
	var mask_sphere := SphereShape3D.new()
	mask_sphere.radius = 0.17
	hitbox_mask.shape = mask_sphere
	hitbox_mask.position = Vector3(0.0, HEIGHT_STANDING, 0.0)
	add_child(hitbox_mask)

	hitbox_hopper_marker = CollisionShape3D.new()
	hitbox_hopper_marker.name = "Hitbox_HopperMarker"
	var hm_box := BoxShape3D.new()
	hm_box.size = Vector3(0.18, 0.28, 0.50)
	hitbox_hopper_marker.shape = hm_box
	hitbox_hopper_marker.position = Vector3(0.22, HEIGHT_STANDING - 0.14, -0.34)
	add_child(hitbox_hopper_marker)

	hitbox_pod_pack = CollisionShape3D.new()
	hitbox_pod_pack.name = "Hitbox_PodPack"
	var pack_box := BoxShape3D.new()
	pack_box.size = Vector3(0.32, 0.26, 0.18)
	hitbox_pod_pack.shape = pack_box
	hitbox_pod_pack.position = Vector3(0.0, 0.88, 0.20)
	add_child(hitbox_pod_pack)

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

	carried_flag_mesh = MeshInstance3D.new()
	carried_flag_mesh.name = "CarriedCenterFlagCloth"
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.24, 0.16, 0.02)
	carried_flag_mesh.mesh = fbox
	carried_flag_mesh.position = Vector3(-0.34, -0.18, -0.42)
	carried_flag_mesh.rotation_degrees = Vector3(12.0, 24.0, -14.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.78, 0.06)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.65, 0.04)
	fmat.emission_energy_multiplier = 0.55
	fmat.roughness = 0.45
	carried_flag_mesh.material_override = fmat
	carried_flag_mesh.visible = false
	camera.add_child(carried_flag_mesh)


func _on_bracket_changed(bracket_or_id: Variant) -> void:
	if bracket_or_id == null:
		return
	if bracket_or_id is String:
		GearRuleEnforcer.set_active_bracket(String(bracket_or_id))
		return
	var bracket: Resource = bracket_or_id as Resource
	if bracket == null:
		return
	hopper_paint = bracket.hopper_capacity
	pods_remaining = bracket.pod_count
	is_reloading_pod = false
	if pod_rig:
		pod_rig.visible = false
	pump_racked = true
	woodsball_trigger_latched = false
	var b_id := "speedball"
	if bracket.trigger_mode == GearBracketDataScript.TriggerMode.SEMI_ONE_PULL:
		b_id = "woodsball"
	elif bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
		b_id = "pump"
	GrittyArtThemeScript.apply_first_person_bracket_visual(marker_rig, hopper_mesh, hopper_lid_mesh, b_id)
	status_banner_sent.emit("Switched Bracket: %s" % bracket.display_name, Color(0.4, 0.85, 1.0))
	_emit_hud()

func _unhandled_input(event: InputEvent) -> void:
	if lobby_open or awaiting_respawn_choice or spectating or NetworkLobby.is_dedicated_server:
		return
	if event is InputEventMouseMotion and _mouse_is_captured():
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0))
		rotation.y = yaw

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			lean_exposure_scale = clampf(lean_exposure_scale + 0.12, 0.38, 1.15)
			_emit_hud()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			lean_exposure_scale = clampf(lean_exposure_scale - 0.12, 0.38, 1.15)
			_emit_hud()

	if event.is_action_pressed("swap_shoulder"):
		is_left_handed = not is_left_handed
		if _locked_peek_hand != 0:
			_locked_peek_hand = -1 if is_left_handed else 1
		if bunker_pocket_weight > 0.25:
			_manual_hand_override_in_pocket = true
		_emit_hud()

	if event.is_action_pressed("reload_pod"):
		_start_pod_reload()

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
	if movement_fire_recovery_timer > 0.0 and slide_timer <= 0.0 and dive_timer <= 0.0:
		movement_fire_recovery_timer = maxf(0.0, movement_fire_recovery_timer - delta)
	_update_movement_fire_lock_signal()
	if _respawn_flash_timer > 0.0:
		_respawn_flash_timer = maxf(0.0, _respawn_flash_timer - delta)
	if breakout_boost_timer > 0.0:
		breakout_boost_timer = maxf(0.0, breakout_boost_timer - delta)
	if breakout_penalty_timer > 0.0:
		breakout_penalty_timer = maxf(0.0, breakout_penalty_timer - delta)

	if woodsball_trigger_latched:
		if not (Input.is_action_pressed("fire_primary") and Input.is_action_pressed("fire_secondary_walk")):
			woodsball_trigger_latched = false

	if not lobby_open and not awaiting_respawn_choice and not spectating:
		_update_movement_and_stance(delta)
	elif spectating:
		velocity = Vector3.ZERO
		ground_speed = 0.0
	_enforce_arena_bounds_and_permafall_guard()
	_update_lean_bob_and_viewmodel(delta)
	_update_exposed_profile_hitboxes(delta)
	_update_pod_reload(delta)
	_update_shot_spread(delta)

	_net_sync_timer += delta
	if _net_sync_timer >= 0.05:
		_net_sync_timer = 0.0
		var b_idx: int = 0
		if GearRuleEnforcer.active_bracket != null:
			if GearRuleEnforcer.active_bracket.trigger_mode == GearBracketDataScript.TriggerMode.SEMI_ONE_PULL:
				b_idx = 1
			elif GearRuleEnforcer.active_bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL:
				b_idx = 2
		var packed_stance: int = int(stance) | (4 if is_left_handed else 0) | (8 if bunker_pocket_weight > 0.25 else 0) | (16 if slide_timer > 0.0 else 0) | (32 if dive_timer > 0.0 else 0) | (64 if is_reloading_pod else 0) | (b_idx << 7)
		NetworkLobby.send_local_player_state(global_position, yaw, pitch, current_lean, packed_stance, _respawn_flash_timer > 0.0)

func _resolve_held_stance() -> Stance:
	if Input.is_action_pressed("prone_dive"):
		return Stance.PRONE
	elif Input.is_action_pressed("crouch_slide"):
		return Stance.CROUCHING
	return Stance.STANDING

## v0.6: 0..1 backward share of a (normalized) move input; +y is back (S). Pure S = 1, back-diagonal ~0.71, strafe 0.
static func backpedal_amount(input_vec: Vector2) -> float:
	if input_vec.length_squared() < 0.0001:
		return 0.0
	return clampf(input_vec.normalized().y, 0.0, 1.0)

## v0.6: speed multiplier for the backward share of the input (1.0 forward/strafe -> BACKPEDAL_SPEED_MULT pure back).
static func backpedal_speed_factor(input_vec: Vector2) -> float:
	return lerpf(1.0, BACKPEDAL_SPEED_MULT, backpedal_amount(input_vec))

## Ground-gait target speed before breakout multipliers. Sprint only boosts the non-backward share of the input,
## then the back-pedal factor applies on top, so back-pedalling is 50% of the same stance's forward speed.
static func gait_target_speed(input_vec: Vector2, sprinting: bool, cur_stance: int) -> float:
	var back := backpedal_amount(input_vec)
	var base: float = WALK_SPEED
	if sprinting:
		base = lerpf(SPRINT_SPEED, WALK_SPEED, back)
	elif cur_stance == Stance.CROUCHING:
		base = CROUCH_SPEED
	elif cur_stance == Stance.PRONE:
		base = PRONE_SPEED
	return base * backpedal_speed_factor(input_vec)

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
		status_banner_sent.emit("KNEE-SLIDE! (Hold [Q] to stay crouched)", Color(0.35, 0.95, 1.0))
		if is_reloading_pod:
			_spill_active_pod("Knee-slide interrupted reload — pod spilled!")
		_emit_hud()

	# Trigger Superman Dive on Shift + Ctrl press
	if Input.is_action_just_pressed("prone_dive") and shift_held and dive_timer <= 0.0 and slide_timer <= 0.0:
		dive_timer = DIVE_DURATION
		slide_dir = move_dir if move_dir.length() > 0.1 else -transform.basis.z.normalized()
		stance = Stance.PRONE
		status_banner_sent.emit("SUPERMAN DIVE! (Hold [C] to stay prone)", Color(1.0, 0.82, 0.25))
		if is_reloading_pod:
			_spill_active_pod("Superman dive interrupted reload — pod spilled!")
		_emit_hud()

	# Update active slide / dive timers, and check held keys when complete
	if dive_timer > 0.0:
		dive_timer -= delta
		if dive_timer <= 0.0:
			dive_timer = 0.0
			movement_fire_recovery_timer = MOVEMENT_FIRE_RECOVERY
			_movement_fire_lock_reason = "dive"
			stance = _clamp_stance_to_headroom(_resolve_held_stance(), true)
			_emit_hud()
	elif slide_timer > 0.0:
		slide_timer -= delta
		if slide_timer <= 0.0:
			slide_timer = 0.0
			movement_fire_recovery_timer = MOVEMENT_FIRE_RECOVERY
			_movement_fire_lock_reason = "slide"
			stance = _clamp_stance_to_headroom(_resolve_held_stance(), true)
			_emit_hud()
	else:
		# Pure hold-to-crouch (C) and hold-to-prone (Ctrl) when not sliding/diving
		var prev_stance := stance
		stance = _clamp_stance_to_headroom(_resolve_held_stance())
		if stance != prev_stance:
			_emit_hud()

	var wants_sprint := shift_held and input_vec.length() > 0.1 and slide_timer <= 0.0 and dive_timer <= 0.0 and not crouch_held and not prone_held

	if wants_sprint and is_reloading_pod:
		_spill_active_pod("Sprint interrupted reload — pod spilled!")

	if dive_timer > 0.0:
		var dive_factor: float = clamp(dive_timer / DIVE_DURATION, 0.15, 1.0)
		velocity.x = slide_dir.x * DIVE_INITIAL_SPEED * dive_factor
		velocity.z = slide_dir.z * DIVE_INITIAL_SPEED * dive_factor
		ground_speed = minf(DIVE_INITIAL_SPEED * dive_factor, SPRINT_SPEED)
		_ground_move_dir = slide_dir
	elif slide_timer > 0.0:
		var slide_factor: float = clamp(slide_timer / SLIDE_DURATION, 0.2, 1.0)
		velocity.x = slide_dir.x * SLIDE_INITIAL_SPEED * slide_factor
		velocity.z = slide_dir.z * SLIDE_INITIAL_SPEED * slide_factor
		ground_speed = minf(SLIDE_INITIAL_SPEED * slide_factor, SPRINT_SPEED)
		_ground_move_dir = slide_dir
	else:
		if not GameManager.breakout_horn_sounded and input_vec.length() > 0.15:
			_was_moving_before_horn = true
		var speed_mult: float = 1.0
		if not GameManager.breakout_horn_sounded:
			# Hold on the starting gate net during the 3..2..1 countdown (slight lateral shuffle allowed)
			speed_mult = 0.18
		elif breakout_boost_timer > 0.0:
			speed_mult = 1.15
		elif breakout_penalty_timer > 0.0:
			speed_mult = 0.72
		var target_speed: float = gait_target_speed(input_vec, wants_sprint, stance) * speed_mult
		# v0.5.0: ramp ground speed (walk-up fast, sprint-up slower, crisp stop); direction still follows input instantly.
		var has_input: bool = move_dir.length() > 0.1
		if not has_input:
			target_speed = 0.0
		else:
			_ground_move_dir = move_dir
		var accel: float = GROUND_DECEL
		if target_speed > ground_speed:
			accel = SPRINT_ACCEL if ground_speed >= WALK_SPEED * speed_mult - 0.01 else GROUND_ACCEL
		ground_speed = move_toward(ground_speed, target_speed, accel * delta)
		velocity.x = _ground_move_dir.x * ground_speed
		velocity.z = _ground_move_dir.z * ground_speed

	_apply_bunker_cover_pocket_physics(delta, move_dir, input_vec, wants_sprint)

	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	_update_stance_capsule(delta)
	_apply_break_line_velocity_block()
	move_and_slide()
	_clamp_to_break_line()

## Target movement-capsule / torso-hitbox height for the current stance (shared table with ProPaintballRig3D).
func get_stance_capsule_target() -> float:
	if dive_timer > 0.0:
		return StanceRigScript.STANCE_CAPSULE_DIVE
	if slide_timer > 0.0:
		return StanceRigScript.STANCE_CAPSULE_SLIDE
	if stance == Stance.CROUCHING:
		return StanceRigScript.STANCE_CAPSULE_CROUCH
	if stance == Stance.PRONE:
		return StanceRigScript.STANCE_CAPSULE_PRONE
	return StanceRigScript.STANCE_CAPSULE_STANDING

## Smoothly resize the capsule around planted feet: only the center moves (height * 0.5), never the floor contact.
func _update_stance_capsule(delta: float) -> void:
	if torso_capsule == null or torso_col == null:
		return
	var target: float = get_stance_capsule_target()
	torso_capsule_height = lerpf(torso_capsule_height, target, minf(1.0, delta * 15.0))
	if absf(torso_capsule_height - target) < 0.003:
		torso_capsule_height = target
	var h: float = maxf(torso_capsule_height, TORSO_RADIUS * 2.0)
	if not is_equal_approx(torso_capsule.height, h):
		torso_capsule.height = h
		torso_col.position = Vector3(0.0, h * 0.5, 0.0)

## Total body clearance (feet to top of mask) a stance needs.
func _stance_clearance(s: Stance) -> float:
	match s:
		Stance.CROUCHING:
			return maxf(StanceRigScript.STANCE_CAPSULE_CROUCH, HEIGHT_CROUCH + HEAD_CLEARANCE)
		Stance.PRONE:
			return maxf(StanceRigScript.STANCE_CAPSULE_PRONE, HEIGHT_PRONE + HEAD_CLEARANCE)
	return maxf(StanceRigScript.STANCE_CAPSULE_STANDING, HEIGHT_STANDING + HEAD_CLEARANCE)

func _current_clearance() -> float:
	var head_top: float = (head_pivot.position.y + HEAD_CLEARANCE) if head_pivot != null else 0.0
	return maxf(torso_capsule_height, head_top)

## True when a slim capsule from just above the feet up to `clearance` overlaps nothing (ceiling / roof / canopy).
func has_headroom_for(clearance: float) -> bool:
	if not is_inside_tree():
		return true
	var probe_h: float = clearance - HEADROOM_PROBE_FOOT_LIFT
	if probe_h <= HEADROOM_PROBE_RADIUS * 2.0:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = HEADROOM_PROBE_RADIUS
	shape.height = probe_h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3(0.0, HEADROOM_PROBE_FOOT_LIFT + probe_h * 0.5, 0.0))
	q.exclude = [get_rid()]
	q.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Keep the lowest-necessary stance when there is no room to rise (fuselage roof, canopy, low overhang).
func _clamp_stance_to_headroom(desired: Stance, from_low_move: bool = false) -> Stance:
	if desired == stance and not from_low_move:
		if headroom_blocked and desired == _resolve_held_stance():
			headroom_blocked = false
		return desired # no stance change requested: never probe (avoids spurious drops on ramps/walls)
	var need: float = _stance_clearance(desired)
	if need <= _current_clearance() + 0.02 or has_headroom_for(need):
		if headroom_blocked and desired == _resolve_held_stance():
			headroom_blocked = false
		return desired
	var fallback: Stance = Stance.PRONE
	if desired == Stance.STANDING:
		var crouch_need: float = _stance_clearance(Stance.CROUCHING)
		if crouch_need <= _current_clearance() + 0.02 or has_headroom_for(crouch_need):
			fallback = Stance.CROUCHING
	if not headroom_blocked:
		headroom_blocked = true
		status_banner_sent.emit("NO HEADROOM — staying low until clear", Color(1.0, 0.75, 0.3))
	return fallback

func _update_lean_bob_and_viewmodel(delta: float) -> void:
	var target_lean: float = 0.0
	var is_holding_peek: bool = (InputMap.has_action("lean_peek") and Input.is_action_pressed("lean_peek")) or (InputMap.has_action("lean_right") and Input.is_action_pressed("lean_right"))
	if is_holding_peek:
		# Lock peek direction when [E] is pressed (unless player explicitly swaps hand via [X]), preventing mid-peek flip-flopping
		if _locked_peek_hand == 0:
			_locked_peek_hand = -1 if is_left_handed else 1
		target_lean = float(_locked_peek_hand) * lean_exposure_scale
	else:
		_locked_peek_hand = 0

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

	var tuck_factor: float = bunker_pocket_weight * clampf(1.0 - absf(current_lean), 0.0, 1.0)
	var pocket_crouch_sink: float = -0.16 * tuck_factor if (stance == Stance.STANDING and slide_timer <= 0.0 and dive_timer <= 0.0) else -0.06 * tuck_factor
	var pocket_fov_tighten: float = -6.5 * tuck_factor
	var corner_peek_boost: float = 1.28 if (bunker_pocket_weight > 0.35 and absf(current_lean) > 0.05) else 1.0

	head_pivot.position.y = lerp(head_pivot.position.y, base_height + pocket_crouch_sink + bob_y, min(1.0, delta * 15.0))
	head_pivot.position.x = lerp(head_pivot.position.x, current_lean * LEAN_OFFSET_X * corner_peek_boost + bob_x, min(1.0, delta * 14.0))
	camera.fov = lerp(camera.fov, target_fov + pocket_fov_tighten, min(1.0, delta * 10.0))
	camera.rotation.x = clamp(pitch + dive_pitch_offset, deg_to_rad(-85.0), deg_to_rad(85.0))
	camera.rotation.z = deg_to_rad(-current_lean * LEAN_ROLL_DEG * corner_peek_boost + slide_roll_deg)

	var hand_sign: float = -1.0 if is_left_handed else 1.0
	var target_hand_x: float = (0.17 - 0.105 * tuck_factor) * hand_sign + bob_x * 0.35
	var reload_dip_y: float = -0.29 if is_reloading_pod else (-0.22 - 0.055 * tuck_factor + bob_y * 0.45)
	var target_marker_roll: float = deg_to_rad(18.0 * hand_sign) if is_reloading_pod else deg_to_rad(-24.0 * hand_sign * tuck_factor)
	var target_marker_pitch: float = deg_to_rad(18.0 * tuck_factor)
	# v0.4.5 art: while firing is locked by a knee-slide or Superman dive, the marker drops out of the
	# shooting line (muzzle down, canted outward), then rises back over the 0.15s recovery so the player
	# can read exactly when they're able to shoot again.
	var move_lock_w: float = 0.0 if is_reloading_pod else get_movement_fire_lock_progress()
	if move_lock_w > 0.0:
		var is_dive_lock: bool = get_fire_lock_reason() == "dive"
		var lock_drop_y: float = -0.17 if is_dive_lock else -0.12
		var lock_in_x: float = -0.07 if is_dive_lock else 0.03
		var lock_roll: float = deg_to_rad((38.0 if is_dive_lock else -30.0) * hand_sign)
		var lock_pitch: float = deg_to_rad(-22.0 if is_dive_lock else -30.0)
		target_hand_x = lerpf(target_hand_x, target_hand_x + lock_in_x * hand_sign, move_lock_w)
		reload_dip_y = lerpf(reload_dip_y, reload_dip_y + lock_drop_y, move_lock_w)
		target_marker_roll = lerpf(target_marker_roll, lock_roll, move_lock_w)
		target_marker_pitch = lerpf(target_marker_pitch, lock_pitch, move_lock_w)
	marker_rig.position.x = lerp(marker_rig.position.x, target_hand_x, min(1.0, delta * 14.0))
	marker_rig.position.y = lerp(marker_rig.position.y, reload_dip_y, min(1.0, delta * 12.0))
	marker_rig.rotation.z = lerp(marker_rig.rotation.z, target_marker_roll, min(1.0, delta * 14.0))
	marker_rig.rotation.x = lerp(marker_rig.rotation.x, target_marker_pitch, min(1.0, delta * 14.0))

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
		hopper_lid_mesh.position.x = get_meta("hopper_lid_base_x", hopper_lid_mesh.position.x) if false else (0.062 if (GearRuleEnforcer.active_bracket != null and GearRuleEnforcer.active_bracket.trigger_mode == GearBracketDataScript.TriggerMode.SEMI_ONE_PULL) else 0.0)
	var pm_slide_1p := (marker_rig.get_node_or_null("FP_PumpAssembly/PumpSlideRoot") if marker_rig != null else null) as Node3D
	if pm_slide_1p == null and marker_rig != null:
		pm_slide_1p = marker_rig.get_node_or_null("Pump1PAssembly/PumpHandleSlide1P") as Node3D
	if pm_slide_1p != null:
		var target_pump_z := -0.25 if pump_racked else -0.14
		pm_slide_1p.position.z = lerpf(pm_slide_1p.position.z, target_pump_z, minf(1.0, delta * 18.0))
	var electro_bolt := (marker_rig.get_node_or_null("FP_SpeedballAssembly/ElectroBoltPin") if marker_rig != null else null) as Node3D
	if electro_bolt != null:
		var bolt_kick := clampf(1.0 - (time_since_last_shot / 0.075), 0.0, 1.0)
		electro_bolt.position.z = lerpf(0.13, 0.175, bolt_kick)

## v0.4.5: true for the whole knee-slide (slide_timer > 0), the whole Superman dive (dive_timer > 0), and the
## MOVEMENT_FIRE_RECOVERY window after either ends.
func is_fire_locked_by_movement() -> bool:
	return slide_timer > 0.0 or dive_timer > 0.0 or movement_fire_recovery_timer > 0.0

## "slide" or "dive" while locked (during the move and its recovery), "" when free to fire.
func get_fire_lock_reason() -> String:
	if slide_timer > 0.0:
		return "slide"
	if dive_timer > 0.0:
		return "dive"
	if movement_fire_recovery_timer > 0.0:
		return _movement_fire_lock_reason
	return ""

## True while in the post-slide/dive recovery tail only.
func is_in_movement_fire_recovery() -> bool:
	return slide_timer <= 0.0 and dive_timer <= 0.0 and movement_fire_recovery_timer > 0.0

## 1.0 while sliding/diving, ramps 1.0 -> 0.0 across the recovery, 0.0 when free to fire.
func get_movement_fire_lock_progress() -> float:
	if slide_timer > 0.0 or dive_timer > 0.0:
		return 1.0
	return clampf(movement_fire_recovery_timer / MOVEMENT_FIRE_RECOVERY, 0.0, 1.0)

func _update_movement_fire_lock_signal() -> void:
	var locked := is_fire_locked_by_movement()
	if slide_timer > 0.0:
		_movement_fire_lock_reason = "slide"
	elif dive_timer > 0.0:
		_movement_fire_lock_reason = "dive"
	if locked != _movement_fire_lock_state:
		_movement_fire_lock_state = locked
		if not locked:
			_movement_fire_hint_shown = false # re-arm the one-shot hint for the next slide/dive
		movement_fire_lock_changed.emit(locked, get_fire_lock_reason())
		_emit_hud()

## v0.6 break hold (see break_hold_active). line_z is signed; active = false releases the player at the horn.
func set_break_hold(active: bool, line_z: float = 0.0) -> void:
	break_hold_active = active
	break_hold_line_z = line_z
	_break_fire_hint_shown = false
	if active:
		_clamp_to_break_line()

## How far past the start line the player is (m, > 0 = crossed). 0 when no break hold is active.
func break_line_overshoot(pos: Vector3 = Vector3.INF) -> float:
	if not break_hold_active or is_zero_approx(break_hold_line_z):
		return 0.0
	var p := global_position if pos == Vector3.INF else pos
	return maxf(0.0, (break_hold_line_z - p.z) if break_hold_line_z > 0.0 else (p.z - break_hold_line_z))

func _apply_break_line_velocity_block() -> void:
	if not break_hold_active or is_zero_approx(break_hold_line_z):
		return
	var dt := get_physics_process_delta_time()
	var next_z := global_position.z + velocity.z * dt
	if break_hold_line_z > 0.0 and velocity.z < 0.0 and next_z < break_hold_line_z:
		velocity.z = minf(0.0, (break_hold_line_z - global_position.z) / maxf(dt, 0.0001)) if global_position.z > break_hold_line_z else 0.0
	elif break_hold_line_z < 0.0 and velocity.z > 0.0 and next_z > break_hold_line_z:
		velocity.z = maxf(0.0, (break_hold_line_z - global_position.z) / maxf(dt, 0.0001)) if global_position.z < break_hold_line_z else 0.0

func _clamp_to_break_line() -> void:
	if break_line_overshoot() > 0.0:
		global_position.z = break_hold_line_z
		velocity.z = 0.0

func _handle_trigger_press(is_secondary_trigger: bool) -> void:
	if spectating:
		spectate_blocked_trigger_pulls += 1
		return
	if break_hold_active:
		break_blocked_trigger_pulls += 1
		if not _break_fire_hint_shown:
			_break_fire_hint_shown = true
			status_banner_sent.emit("WAIT FOR THE HORN - NO SHOTS ON THE BREAK", Color(1.0, 0.75, 0.3))
		return
	if is_reloading_pod:
		return
	if is_fire_locked_by_movement():
		# Silent block: no shot, paint, rate/ramp state, pump rack, 1-pull latch, FX or dry-fire click.
		# Firing resumes on the next trigger pull after the slide/dive + recovery (no buffered/auto shot).
		movement_blocked_trigger_pulls += 1
		if not _movement_fire_hint_shown:
			_movement_fire_hint_shown = true
			status_banner_sent.emit("DIVING - CAN'T SHOOT" if get_fire_lock_reason() == "dive" else "SLIDING - CAN'T SHOOT", Color(1.0, 0.75, 0.3))
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

## v0.5.0: bracket base cone half-angle (deg); pump is tightest, speedball widest.
func get_bracket_base_spread_deg(bracket: Resource = null) -> float:
	if bracket == null:
		bracket = GearRuleEnforcer.active_bracket
	if bracket == null:
		return SPREAD_BASE_DEG_SPEEDBALL
	match bracket.trigger_mode:
		GearBracketDataScript.TriggerMode.PUMP_MANUAL:
			return SPREAD_BASE_DEG_PUMP
		GearBracketDataScript.TriggerMode.SEMI_ONE_PULL:
			return SPREAD_BASE_DEG_WOODSBALL
	return SPREAD_BASE_DEG_SPEEDBALL

## Spread multiplier the cone is heading toward this frame: posture floor, opened up by ground speed.
func get_target_spread_mult() -> float:
	var posture: float = SPREAD_MULT_STANDING
	if bunker_pocket_weight > 0.25:
		posture = SPREAD_MULT_POCKET
	elif stance == Stance.PRONE:
		posture = SPREAD_MULT_PRONE
	elif stance == Stance.CROUCHING:
		posture = SPREAD_MULT_CROUCH
	var spd: float = ground_speed
	var m: float
	if spd <= WALK_SPEED:
		m = lerpf(posture, SPREAD_MULT_WALK, clampf(spd / WALK_SPEED, 0.0, 1.0))
	else:
		m = lerpf(SPREAD_MULT_WALK, SPREAD_MULT_SPRINT, clampf((spd - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0))
	if slide_timer > 0.0 or dive_timer > 0.0:
		m = SPREAD_MULT_SPRINT
	elif not is_on_floor() and is_inside_tree():
		m = maxf(m, SPREAD_MULT_AIRBORNE)
	return m

## Current (smoothed) cone half-angle in degrees that the next shot uses.
func get_shot_spread_deg() -> float:
	return get_bracket_base_spread_deg() * shot_spread_mult

func _update_shot_spread(delta: float) -> void:
	var target: float = get_target_spread_mult()
	var span: float = SPREAD_MULT_SPRINT - SPREAD_MULT_STANDING
	var rate: float = span / (SPREAD_BLOOM_TIME if target > shot_spread_mult else SPREAD_RECOVERY_TIME)
	shot_spread_mult = move_toward(shot_spread_mult, target, rate * delta)
	_update_spread_crosshair()

func _update_spread_crosshair() -> void:
	if _spread_crosshair == null or not is_instance_valid(_spread_crosshair):
		_spread_crosshair = null
		var p := get_parent()
		if p == null:
			return
		_spread_crosshair = p.get_node_or_null("PlaytestHUD/SpreadCrosshair") as Label
		if _spread_crosshair == null:
			return
	var t: float = clampf((shot_spread_mult - SPREAD_MULT_POCKET) / (SPREAD_MULT_SPRINT - SPREAD_MULT_POCKET), 0.0, 1.0)
	var font: int = int(round(lerpf(float(SPREAD_CROSSHAIR_MIN_FONT), float(SPREAD_CROSSHAIR_MAX_FONT), t)))
	if font != _spread_crosshair_font:
		_spread_crosshair_font = font
		_spread_crosshair.add_theme_font_size_override("font_size", font)
		_spread_crosshair.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, lerpf(0.9, 0.55, t)))

## Random direction inside a circular cone of half-angle spread_deg around base_dir (uniform over the disc).
static func apply_spread_cone(base_dir: Vector3, right_dir: Vector3, up_dir: Vector3, spread_deg: float) -> Vector3:
	var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
	var th: float = randf() * TAU
	return (base_dir + right_dir * (r * cos(th)) + up_dir * (r * sin(th))).normalized()

func _fire_single_paintball(bracket: Resource) -> void:
	if spectating or break_hold_active:
		return
	if is_fire_locked_by_movement():
		return
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

	var spread_deg := get_shot_spread_deg()
	var forward_dir := -camera.global_transform.basis.z.normalized()
	var right_dir := camera.global_transform.basis.x.normalized()
	var up_dir := camera.global_transform.basis.y.normalized()

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
	# v0.5.0: movement-driven cone; the same shot_dir goes to local ballistics and the network broadcast.
	var shot_dir := apply_spread_cone(base_dir, right_dir, up_dir, spread_deg)
	last_shot_base_dir = base_dir
	last_shot_dir = shot_dir

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
	var tuck_z_pull: float = 0.09 * bunker_pocket_weight * clampf(1.0 - absf(current_lean), 0.0, 1.0)
	marker_rig.position.z = lerp(marker_rig.position.z, -0.45 + tuck_z_pull, min(1.0, delta * 16.0))
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

func _get_stance_label() -> String:
	var base_lbl := "STANDING"
	if dive_timer > 0.0:
		base_lbl = "SUPERMAN DIVE"
	elif slide_timer > 0.0:
		base_lbl = "KNEE-SLIDE"
	elif stance == Stance.CROUCHING:
		base_lbl = "CROUCH (Holding [Q])"
	elif stance == Stance.PRONE:
		base_lbl = "PRONE (Holding [C])"
	if bunker_pocket_weight > 0.25 and not active_bunker_name.is_empty():
		return "%s [TUCKED: %s]" % [base_lbl, active_bunker_name]
	return base_lbl

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
		"fire_locked_movement": is_fire_locked_by_movement(),
		"fire_lock_reason": get_fire_lock_reason(),
		"spread_deg": get_shot_spread_deg(),
		"reload_pct": clamp(1.0 - (reload_timer / reload_duration), 0.0, 1.0) if is_reloading_pod else 0.0,
		"pump_mode": bracket.trigger_mode == GearBracketDataScript.TriggerMode.PUMP_MANUAL if bracket else false,
		"pump_racked": pump_racked,
		"carrying_flag": carrying_center_flag,
		"carrying_ctf_flag": carrying_ctf_flag,
		"spectating": spectating,
		"breakout_boost": breakout_boost_timer > 0.0,
		"bunker_tucked": bunker_pocket_weight > 0.25,
		"bunker_name": active_bunker_name,
		"hopper_exposure": hopper_exposure_multiplier
	})

func set_lobby_open_state(is_open: bool) -> void:
	lobby_open = is_open
	_sync_mouse_capture()

## v0.6.2: _unhandled_input ignores mouse look while lobby_open / awaiting_respawn_choice / spectating is set, so a flag
## left over from a previous life/round leaves the cursor locked with dead aim (and no CLICK TO RESUME card).
## Called on every respawn, on round_started, on returned_to_lobby and on a network match start.
## awaiting_respawn_choice and spectating are always cleared. lobby_open mirrors the arena's TAB/Esc lobby canvas: it is
## cleared unless that canvas is actually on screen (an open menu keeps blocking input, a stale flag never does).
var last_input_block_clear: String = ""
func clear_input_blocks(reason: String = "", sync: bool = true) -> void:
	last_input_block_clear = reason
	awaiting_respawn_choice = false
	set_spectating(false)
	if lobby_open and not _lobby_canvas_on_screen():
		lobby_open = false
	if sync:
		_sync_mouse_capture()

func _lobby_canvas_on_screen() -> bool:
	if not is_inside_tree() or get_tree().current_scene == null:
		return false
	var lc: Variant = get_tree().current_scene.get("lobby_canvas")
	return lc is CanvasLayer and is_instance_valid(lc) and (lc as CanvasLayer).visible

## v0.6.1: the arena's MouseCaptureGuard owns the mouse mode (web Pointer Lock needs a user gesture: a capture from
## here can be refused, then it shows CLICK TO RESUME and re-captures on the next click). Esc no longer toggles the
## mouse here (the arena's Esc/TAB menu does, through the guard).
## Mouse look reads the guard's view of the lock (the real Input mode in a build; its simulated mode in tests).
func _mouse_is_captured() -> bool:
	if is_inside_tree():
		var g := get_tree().get_first_node_in_group("mouse_capture_guard")
		if g != null and g.has_method("is_captured"):
			return bool(g.call("is_captured"))
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

func _sync_mouse_capture() -> void:
	if not is_inside_tree():
		return
	if get_tree().get_nodes_in_group("mouse_capture_guard").is_empty():
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if (lobby_open or awaiting_respawn_choice) else Input.MOUSE_MODE_CAPTURED)
		return
	get_tree().call_group("mouse_capture_guard", "sync_capture")

func _enforce_arena_bounds_and_permafall_guard() -> void:
	# Hard outer perimeter clamp inside the 108m x 132m safety netting so players can never exit the map
	var clamped_x := clampf(global_position.x, -52.4, 52.4)
	var clamped_z := clampf(global_position.z, -64.4, 64.4)
	if clamped_x != global_position.x or clamped_z != global_position.z:
		global_position.x = clamped_x
		global_position.z = clamped_z
	# Safety floor check: if anything ever pushes the player below turf, immediately snap back onto the field
	if global_position.y < -1.5:
		global_position = Vector3(clampf(global_position.x, -48.0, 48.0), 0.2, clampf(global_position.z, -46.0, 46.0))
		velocity = Vector3.ZERO
		ground_speed = 0.0
		status_banner_sent.emit("Returned to field boundary!", Color(1.0, 0.85, 0.25))

func respawn_at_team_gate(team: String) -> void:
	var side := 1.0 if team == "ALPHA" else -1.0
	initial_spawn_pos = Vector3(0.0, 0.1, 45.5 * side)
	initial_spawn_yaw = 0.0 if side > 0.0 else PI
	respawn_at_map_zone(initial_spawn_pos, initial_spawn_yaw, "Team %s Breakout Gate" % team)

func respawn_at_starting_spot() -> void:
	respawn_at_map_zone(initial_spawn_pos, initial_spawn_yaw, "Breakout Gate")

func respawn_at_map_zone(spawn_pos: Vector3, spawn_yaw: float, zone_label: String = "Breakout Gate") -> void:
	clear_input_blocks("respawn", false)
	_respawn_flash_timer = 2.8
	global_position = spawn_pos
	velocity = Vector3.ZERO
	ground_speed = 0.0
	shot_spread_mult = SPREAD_MULT_STANDING
	yaw = spawn_yaw
	pitch = 0.0
	rotation.y = yaw
	is_reloading_pod = false
	reload_timer = 0.0
	_on_bracket_changed(GearRuleEnforcer.active_bracket)
	respawned.emit(zone_label)
	_sync_mouse_capture()
	status_banner_sent.emit("DROPPED IN AT: %s (2.8s Spawn Protection Active!)" % zone_label.to_upper(), Color(0.35, 1.0, 0.55))

func award_kill_bonus_pod(victim_label: String = "Enemy") -> void:
	pods_remaining += 1
	GameManager.record_local_kill(victim_label)
	status_banner_sent.emit("ELIMINATED %s! +1 BONUS POD AWARDED (Pods: %d)" % [victim_label, pods_remaining], Color(0.30, 1.0, 0.45))
	_emit_hud()

func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	var local_hit := to_local(world_hit_pos)
	if hitbox_hopper_marker != null:
		var hm_box := hitbox_hopper_marker.shape as BoxShape3D
		var hm_rel := local_hit - hitbox_hopper_marker.position
		if hm_box != null and absf(hm_rel.x) <= hm_box.size.x * 0.62 and absf(hm_rel.y) <= hm_box.size.y * 0.62 and absf(hm_rel.z) <= hm_box.size.z * 0.62:
			last_hit_zone = "HOPPER / MARKER"
			return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	if hitbox_mask != null and local_hit.distance_to(hitbox_mask.position) <= 0.24:
		last_hit_zone = "MASK / GOGGLES"
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.26}
	if hitbox_pod_pack != null and local_hit.distance_to(hitbox_pod_pack.position) <= 0.26:
		last_hit_zone = "POD PACK"
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.36}
	last_hit_zone = "TORSO / JERSEY"
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func is_wrong_hand_peek() -> bool:
	return false

func _update_exposed_profile_hitboxes(_delta: float) -> void:
	var hand_sign: float = -1.0 if is_left_handed else 1.0
	hopper_exposure_multiplier = 1.0
	if hitbox_mask != null and head_pivot != null:
		hitbox_mask.position = head_pivot.position
	if hitbox_hopper_marker != null and head_pivot != null:
		var hm_box := hitbox_hopper_marker.shape as BoxShape3D
		if hm_box != null:
			hm_box.size = Vector3(0.18, 0.28, 0.50)
		hitbox_hopper_marker.position = Vector3(
			head_pivot.position.x + 0.20 * hand_sign,
			head_pivot.position.y - 0.12,
			-0.34
		)
	if hitbox_pod_pack != null and head_pivot != null:
		hitbox_pod_pack.position = Vector3(head_pivot.position.x * 0.4, maxf(0.32, head_pivot.position.y - 0.68), 0.20)


func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	if _respawn_flash_timer > 0.2 or awaiting_respawn_choice or spectating or GameManager.match_ended:
		return
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "TORSO"))
	var killer_name: String = "OpFor NPC"
	if shooter != null and "bot_name" in shooter:
		killer_name = String(shooter.get("bot_name"))
	_handle_local_elimination("%s [%s]" % [killer_name, zone_lbl])

func on_paintball_bounce(hit_pos: Vector3) -> void:
	var sub := resolve_hit_subzone(hit_pos)
	var zone_lbl: String = String(sub.get("zone", "JERSEY"))
	status_banner_sent.emit("LUCKY BOUNCE OFF YOUR %s — Keep Playing!" % zone_lbl, Color(0.45, 0.95, 1.0))

func _on_remote_player_hit_local(shooter_name: String) -> void:
	_handle_local_elimination(shooter_name)

func _on_breakout_countdown_updated(seconds_left: float, horn_sounded: bool) -> void:
	if not horn_sounded:
		if absf(seconds_left - GameManager.BREAKOUT_COUNTDOWN_DURATION) < 0.05:
			_was_moving_before_horn = false
			breakout_boost_timer = 0.0
			breakout_penalty_timer = 0.0
		return
	# v0.6: no false starts - the start line is a wall, so creeping before the horn is neither flagged nor penalised.
	if not _was_moving_before_horn:
		breakout_boost_timer = 1.5
		status_banner_sent.emit("BUZZER! CLEAN BREAKOUT! (+15% Sprint Burst for 1.5s — Go Get Center Flag!)", Color(0.30, 1.0, 0.50))
	_emit_hud()

## True while the server's match is a live one-life CTF round (asked of the scene's MatchHudClient; no local rules).
func _is_one_life_round_live() -> bool:
	if not is_inside_tree():
		return false
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("is_one_life_round_live"):
		return bool(scene_root.call("is_one_life_round_live"))
	return false

## Spectate input lock (v0.5). Movement, look, triggers, reload/ping are all ignored while on; the viewmodel hides.
func set_spectating(on: bool) -> void:
	if spectating == on:
		return
	spectating = on
	velocity = Vector3.ZERO
	ground_speed = 0.0
	if marker_rig != null:
		marker_rig.visible = not on
	if on and carrying_ctf_flag:
		set_carrying_ctf_flag(false)
	_emit_hud()

## First-person view of the enemy flag we carry (server flag_state_changed carrier == me). Purely visual.
func set_carrying_ctf_flag(carrying: bool, flag_color: Color = Color(1.0, 0.78, 0.06)) -> void:
	carrying_ctf_flag = carrying
	if carried_flag_mesh != null:
		carried_flag_mesh.visible = carrying or carrying_center_flag
		var mat := carried_flag_mesh.material_override as StandardMaterial3D
		if mat != null:
			var c := flag_color if carrying else Color(1.0, 0.78, 0.06)
			mat.albedo_color = c
			mat.emission = c * 0.8
	_emit_hud()

func set_carrying_center_flag(carrying: bool) -> void:
	carrying_center_flag = carrying
	if carried_flag_mesh != null:
		carried_flag_mesh.visible = carrying
	_emit_hud()

func _handle_local_elimination(killer_name: String) -> void:
	if awaiting_respawn_choice or spectating or GameManager.match_ended:
		return
	var death_pos := global_position
	if _is_one_life_round_live():
		# v0.5 one-life CTF: the server keeps us dead until round_started, so do NOT respawn locally (shots from a
		# local respawn get rejected). Stay where we fell, lock input and let the MatchHudClient spectate teammates.
		GameManager.record_local_death(killer_name)
		set_spectating(true)
		player_eliminated.emit(killer_name)
		status_banner_sent.emit("ELIMINATED BY %s - ONE LIFE PER ROUND: SPECTATING UNTIL THE NEXT ROUND" % killer_name.to_upper(), Color(1.0, 0.32, 0.32))
		return
	if carrying_center_flag:
		set_carrying_center_flag(false)
		var scene_root := get_tree().current_scene
		if scene_root != null and scene_root.has_method("drop_center_flag_at"):
			scene_root.call("drop_center_flag_at", death_pos, NetworkLobby.local_callsign)
	_respawn_flash_timer = 2.8
	GameManager.record_local_death(killer_name)
	# Immediately reset pod count and position to starting spot as baseline, then open Tactical Respawn Map on interactive clients
	respawn_at_starting_spot()
	player_eliminated.emit(killer_name)
	if GameManager.match_ended:
		status_banner_sent.emit("MATCH OVER — Reached 10 Deaths! Press [T] or [M] to Review Scoreboard", Color(1.0, 0.25, 0.25))
	else:
		status_banner_sent.emit("YOU'VE BEEN HIT BY %s! Select your Respawn Zone on the Tactical Map (Deaths: %d / %d)" % [killer_name, GameManager.local_deaths, GameManager.MAX_DEATHS_TO_LOSE], Color(1.0, 0.22, 0.48))

func _is_cover_bunker_collider(col: Object) -> bool:
	if col == null or not (col is StaticBody3D):
		return false
	var sbody := col as StaticBody3D
	var n: String = String(sbody.name)
	if n == "TurfFloor" or n.begins_with("Walkable") or n.begins_with("Ramp_") or n.begins_with("TowerFloor_") or n.begins_with("SafetyNet") or n.begins_with("RemotePlayer") or n.begins_with("OpFor_Snake50") or n.begins_with("OpFor_SnakeCorner") or n.begins_with("OpFor_CenterAztec") or n.begins_with("OpFor_Dorito2") or n.begins_with("OpFor_BackCenter"):
		return false
	if bool(sbody.get_meta("is_rigid_cover", false)) or bool(sbody.get_meta("rigid_cover", false)) or bool(sbody.get_meta("is_cover_bunker", false)):
		return true
	return n.begins_with("Bunker_") or n.begins_with("Home_") or n.begins_with("OpFor_") or n.begins_with("Snake_") or n.begins_with("Spool") or n.begins_with("WoodSpool") or n.begins_with("Heli_") or n.begins_with("Tower_") or n.begins_with("Woods_")

func _probe_nearest_bunker_cover() -> Dictionary:
	var w3d := get_world_3d()
	if w3d == null:
		return {}
	var space_state := w3d.direct_space_state
	if space_state == null:
		return {}
	var fwd := -transform.basis.z.normalized()
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0, 0, -1)
	else:
		fwd = fwd.normalized()

	var origin := global_position + Vector3(0.0, 0.55, 0.0)
	var best_hit: Dictionary = {}
	var best_score: float = 999.0
	# 12-ray 360-degree horizontal ring so turning your camera sideways down the tape never drops the bunker pocket
	for i in range(12):
		var ang: float = float(i) * (TAU / 12.0)
		var d := Vector3(sin(ang), 0.0, cos(ang)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * BUNKER_POCKET_REACH)
		q.exclude = [get_rid()]
		var res: Dictionary = space_state.intersect_ray(q)
		if not res.is_empty() and _is_cover_bunker_collider(res.get("collider")):
			var hit_pos: Vector3 = res["position"]
			var dist: float = Vector2(hit_pos.x - origin.x, hit_pos.z - origin.z).length()
			# Slightly favor the bunker face in front of look/movement when equidistant, but keep full 360 lock
			var sticky_bonus: float = 0.28 if (_active_bunker_node != null and res.get("collider") == _active_bunker_node) else 0.0
			var score: float = dist - sticky_bonus
			if score < best_score:
				best_score = score
				best_hit = res
				best_hit["horiz_dist"] = dist
	return best_hit

func _is_path_ahead_clear(move_dir: Vector3, reach: float) -> bool:
	var w3d := get_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		return false
	var ahead := Vector3(move_dir.x, 0.0, move_dir.z)
	if ahead.length_squared() < 0.01:
		ahead = -transform.basis.z
		ahead.y = 0.0
	if ahead.length_squared() < 0.001:
		return false
	ahead = ahead.normalized()
	for h in [0.55, 1.25]:
		var o := global_position + Vector3(0.0, h, 0.0)
		var q := PhysicsRayQueryParameters3D.create(o, o + ahead * reach)
		q.exclude = [get_rid()]
		var res: Dictionary = w3d.direct_space_state.intersect_ray(q)
		if not res.is_empty() and _is_cover_bunker_collider(res.get("collider")):
			return false
	return true

func _apply_bunker_cover_pocket_physics(delta: float, move_dir: Vector3, input_vec: Vector2, wants_sprint: bool) -> void:
	var hit := _probe_nearest_bunker_cover()
	if _bunker_slam_flex_cooldown > 0.0:
		_bunker_slam_flex_cooldown = maxf(0.0, _bunker_slam_flex_cooldown - delta)
	if _auto_hand_switch_cooldown > 0.0:
		_auto_hand_switch_cooldown = maxf(0.0, _auto_hand_switch_cooldown - delta)
	# v0.4.3: Walk-through openings (heli cargo doors, tower ramp doorways). Pressing forward toward a clear
	# opening in a pass-through structure never latches the cover pocket, so you can walk straight through.
	if not hit.is_empty() and input_vec.y < -0.5:
		var hcol: Object = hit.get("collider")
		if hcol is Node and bool((hcol as Node).get_meta("opening_passthrough", false)) and _is_path_ahead_clear(move_dir, 1.1):
			hit = {}
	if hit.is_empty():
		var was_tucked := bunker_pocket_weight > 0.25
		bunker_pocket_weight = move_toward(bunker_pocket_weight, 0.0, delta * 7.5)
		if _active_bunker_node != null and is_instance_valid(_active_bunker_node):
			GrittyArtThemeScript.apply_sustained_bunker_pocket_bulge(_active_bunker_node, Vector3.ZERO, bunker_pocket_weight, 0.0, delta)
		if bunker_pocket_weight <= 0.01:
			active_bunker_name = ""
			_active_bunker_node = null
		_bunker_contact_latched = false
		_pocket_entry_tangent = Vector3.ZERO
		_edge_breakaway_hold_timer = 0.0
		_at_bunker_edge_side = 0.0
		_manual_hand_override_in_pocket = false
		if was_tucked and bunker_pocket_weight <= 0.25:
			_emit_hud()
		return

	var col: Node3D = hit["collider"] as Node3D
	var raw_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	raw_normal.y = 0.0
	if raw_normal.length_squared() < 0.001 and col != null:
		raw_normal = (global_position - col.global_position)
		raw_normal.y = 0.0
	if raw_normal.length_squared() < 0.001:
		return
	var n := raw_normal.normalized() # Points outward from bunker surface toward player
	var dist: float = float(hit.get("horiz_dist", 0.5))

	# Shift + look/steer away is the primary way to break out of the bunker pocket!
	# Pressing S without Shift stays sticky inside the bunker pocket (only detaching if you walk far outside the 1.65m probe reach).
	var fwd_look := -transform.basis.z.normalized()
	fwd_look.y = 0.0
	if fwd_look.length_squared() > 0.001:
		fwd_look = fwd_look.normalized()
	var sprinting_out: bool = (wants_sprint or Input.is_action_pressed("sprint")) and (move_dir.dot(n) > -0.05 or fwd_look.dot(n) > 0.15)
	if sprinting_out:
		var was_tucked := bunker_pocket_weight > 0.25
		if _active_bunker_node != null and is_instance_valid(_active_bunker_node):
			GrittyArtThemeScript.trigger_bunker_vinyl_flex(_active_bunker_node, n, 0.20)
		bunker_pocket_weight = 0.0
		active_bunker_name = ""
		_active_bunker_node = null
		_bunker_contact_latched = false
		_pocket_entry_tangent = Vector3.ZERO
		_edge_breakaway_hold_timer = 0.0
		_at_bunker_edge_side = 0.0
		_manual_hand_override_in_pocket = false
		if was_tucked:
			status_banner_sent.emit("BROKE OUT OF COVER! (Shift + Move/Look Away)", Color(0.55, 0.95, 1.0))
			_emit_hud()
		return

	# Settle strongly into the bunker pocket!
	var prev_weight := bunker_pocket_weight
	bunker_pocket_weight = move_toward(bunker_pocket_weight, 1.0, delta * 11.5)
	active_bunker_name = IntelBus.format_bunker_callout(String(col.name), global_position) if col != null else "BUNKER"
	active_bunker_normal = n
	active_bunker_dist = dist

	# 1. Exaggerated slide/dive catch: sliding or diving into a bunker magnetic-catches you behind the vinyl
	if slide_timer > 0.0 or dive_timer > 0.0:
		var into_bunker_speed := -Vector2(velocity.x, velocity.z).dot(Vector2(n.x, n.z))
		if into_bunker_speed > 0.0 and dist < 1.15:
			velocity.x *= 0.45
			velocity.z *= 0.45

	# 2. Strong magnetic surface-normal snap toward the ideal 0.40m tuck pocket distance
	var dist_err: float = dist - BUNKER_POCKET_IDEAL_DIST
	var radial_pull: float = clampf(-dist_err * 14.5, -8.2, 8.2) * bunker_pocket_weight
	velocity.x += n.x * radial_pull
	velocity.z += n.z * radial_pull

	# 3. Camera-Right-aligned Tangent-Rail Strafe + Automatic Bunker-Edge Marker Hand Selection
	# Ensure `tangent` always points to the PLAYER'S RIGHT (+X) when facing downfield/through the bunker (-n),
	# so -tangent is ALWAYS the player's LEFT edge and +tangent is ALWAYS the player's RIGHT edge!
	var tangent := Vector3(-n.z, 0.0, n.x).normalized()
	var cam_right := transform.basis.x
	cam_right.y = 0.0
	if cam_right.length_squared() > 0.001:
		cam_right = cam_right.normalized()
	if tangent.dot(cam_right) < 0.0:
		tangent = -tangent

	# Continuous Left/Right Bunker-Edge Detection & Automatic Marker Hand Assignment:
	# 1) Test actual ±0.52m (LEAN_OFFSET_X) left/right peek sightlines along both -n and camera forward (cam_fwd),
	#    so flat walls, cylindrical Cans/Spools, and angled Doritos all detect which peek lane clears the bunker!
	# 2) Fall back to camera-right offset from bunker center (global_position - col.global_position).dot(cam_right),
	#    which works even on curved cylinders where radial normal n is parallel to (pos - center).
	var space_state := get_world_3d().direct_space_state
	var probe_base := global_position + Vector3(0.0, 0.55, 0.0)
	var probe_dir := (-n + fwd_look * 0.22).normalized()
	var left_origin := probe_base - tangent * LEAN_OFFSET_X
	var right_origin := probe_base + tangent * LEAN_OFFSET_X

	var q_left := PhysicsRayQueryParameters3D.create(left_origin, left_origin + probe_dir * (BUNKER_POCKET_REACH + 0.55))
	q_left.exclude = [get_rid()]
	var hit_left: Dictionary = space_state.intersect_ray(q_left)
	var left_edge_open: bool = (hit_left.is_empty() or hit_left.get("collider") != col)

	var q_right := PhysicsRayQueryParameters3D.create(right_origin, right_origin + probe_dir * (BUNKER_POCKET_REACH + 0.55))
	q_right.exclude = [get_rid()]
	var hit_right: Dictionary = space_state.intersect_ray(q_right)
	var right_edge_open: bool = (hit_right.is_empty() or hit_right.get("collider") != col)

	var prev_hand := is_left_handed
	var prev_edge_side := _at_bunker_edge_side
	var actively_peeking: bool = (_locked_peek_hand != 0 or absf(current_lean) > 0.08)
	var switched_bunker_now: bool = (_active_bunker_node != col)
	if switched_bunker_now or _pocket_entry_tangent.length_squared() < 0.001 or prev_weight <= 0.25:
		_pocket_entry_tangent = cam_right if cam_right.length_squared() > 0.001 else tangent
		_auto_hand_switch_cooldown = 0.0
	var stable_tangent: Vector3 = _pocket_entry_tangent.normalized()
	# Compute offset along the locked bunker entry tangent so mouse panning or curved Can/Spool normals never flip the axis
	var rel_offset: float = (global_position - col.global_position).dot(stable_tangent) if col != null else 0.0
	if absf(rel_offset) <= 0.08 and col != null:
		rel_offset = (global_position - col.global_position).dot(cam_right)
	var moved_far_in_pocket: bool = (global_position.distance_to(_last_hand_switch_pos) > 0.32)
	var deliberate_strafe_left: bool = (input_vec.x < -0.35)
	var deliberate_strafe_right: bool = (input_vec.x > 0.35)
	var is_initial_entry_or_reposition: bool = (prev_weight <= 0.25 or switched_bunker_now or moved_far_in_pocket)
	if not actively_peeking and _auto_hand_switch_cooldown <= 0.0:
		if deliberate_strafe_left and not is_left_handed:
			is_left_handed = true
			_manual_hand_override_in_pocket = false
			_auto_hand_switch_cooldown = 0.28
			_last_hand_switch_pos = global_position
		elif deliberate_strafe_right and is_left_handed:
			is_left_handed = false
			_manual_hand_override_in_pocket = false
			_auto_hand_switch_cooldown = 0.28
			_last_hand_switch_pos = global_position
		elif is_initial_entry_or_reposition and not _manual_hand_override_in_pocket:
			if left_edge_open and not right_edge_open and rel_offset < -0.15:
				_at_bunker_edge_side = -1.0
				is_left_handed = true
				_last_hand_switch_pos = global_position
			elif right_edge_open and not left_edge_open and rel_offset > 0.15:
				_at_bunker_edge_side = 1.0
				is_left_handed = false
				_last_hand_switch_pos = global_position
			elif col != null:
				if rel_offset < -0.22:
					_at_bunker_edge_side = -1.0
					is_left_handed = true
					_last_hand_switch_pos = global_position
				elif rel_offset > 0.22:
					_at_bunker_edge_side = 1.0
					is_left_handed = false
					_last_hand_switch_pos = global_position
	if prev_hand != is_left_handed:
		_emit_hud()

	if move_dir.length() > 0.08 and slide_timer <= 0.0 and dive_timer <= 0.0:
		# Project movement cleanly along the bunker tangent rail; pressing W straight into the bunker holds still without sliding or jiggling
		var pressing_into_bunker: bool = (input_vec.y < -0.1 and absf(input_vec.x) < 0.15 and move_dir.dot(-n) > 0.55 and dist <= BUNKER_POCKET_IDEAL_DIST + 0.28)
		var tang_speed: float = 0.0 if pressing_into_bunker else velocity.dot(tangent) * 0.72
		var normal_speed: float = velocity.dot(n)
		var damped_normal: float = 0.0
		if not pressing_into_bunker:
			damped_normal = normal_speed * 0.16 if normal_speed > 0.0 else (n.dot(Vector3(velocity.x, 0.0, velocity.z)) * 0.25 if dist > BUNKER_POCKET_IDEAL_DIST + 0.18 else 0.0)
		velocity.x = tangent.x * tang_speed + n.x * damped_normal
		velocity.z = tangent.z * tang_speed + n.z * damped_normal

		if absf(tang_speed) > 0.35 and absf(input_vec.x) > 0.35 and not actively_peeking:
			var side_sign: float = signf(input_vec.x) # -1.0 = pressing Left (A), +1.0 = pressing Right (D)
			if is_left_handed != (side_sign < 0.0) and _auto_hand_switch_cooldown <= 0.0:
				is_left_handed = (side_sign < 0.0)
				_auto_hand_switch_cooldown = 0.28
				_last_hand_switch_pos = global_position
			_manual_hand_override_in_pocket = false
			var moving_into_open_edge: bool = (left_edge_open if side_sign < 0.0 else right_edge_open)
			if moving_into_open_edge:
				# Reached the peeking corner edge of the bunker! Hard corner detent latch for 0.45s unless held through
				_edge_breakaway_hold_timer += delta
				_at_bunker_edge_side = side_sign
				if _edge_breakaway_hold_timer < 0.45:
					velocity.x -= tangent.x * tang_speed * 0.96
					velocity.z -= tangent.z * tang_speed * 0.96
			else:
				_edge_breakaway_hold_timer = 0.0
	else:
		# When idle in the pocket, bleed off residual lateral drift so you stay locked in cover
		velocity.x = move_toward(velocity.x, n.x * radial_pull, delta * 18.0)
		velocity.z = move_toward(velocity.z, n.z * radial_pull, delta * 18.0)
		_edge_breakaway_hold_timer = 0.0

	var switched_bunker: bool = (_active_bunker_node != col)
	if _active_bunker_node != null and switched_bunker and is_instance_valid(_active_bunker_node):
		GrittyArtThemeScript.apply_sustained_bunker_pocket_bulge(_active_bunker_node, Vector3.ZERO, 0.0, 0.0, delta)
		_bunker_contact_latched = false
	_active_bunker_node = col

	# Trigger exaggerated vinyl impact bulge ONLY once when first latching into a bunker pocket (never repeat when pressing W inside the pocket!)
	if not _bunker_contact_latched and ((prev_weight <= 0.25 and bunker_pocket_weight > 0.25) or switched_bunker):
		_bunker_contact_latched = true
		_latched_bunker_push_dir = -n
		if col != null and _bunker_slam_flex_cooldown <= 0.0:
			_bunker_slam_flex_cooldown = 0.55
			var flex_amp: float = 0.42 if (slide_timer > 0.0 or dive_timer > 0.0) else 0.34
			GrittyArtThemeScript.trigger_bunker_vinyl_flex(col, _latched_bunker_push_dir, flex_amp)
	elif col != null and bunker_pocket_weight > 0.15:
		if _latched_bunker_push_dir.length_squared() < 0.001:
			_latched_bunker_push_dir = -n
		# Steady sustained pocket bulge along locked entry vector (zero W jiggle)
		GrittyArtThemeScript.apply_sustained_bunker_pocket_bulge(col, _latched_bunker_push_dir, bunker_pocket_weight, current_lean, delta)

	if prev_weight <= 0.25 and bunker_pocket_weight > 0.25:
		status_banner_sent.emit("LOCKED IN COVER: %s — [E] Peek (%s Hand) | [X] Swap Hand | [Q] Crouch | [C] Prone | [Shift] Break Out" % [active_bunker_name, "LEFT" if is_left_handed else "RIGHT"], Color(0.35, 1.0, 0.58))
		_emit_hud()
