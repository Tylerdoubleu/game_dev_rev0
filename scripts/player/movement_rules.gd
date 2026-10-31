extends RefCounted
## v0.7 shared movement + shot-spread rules for the local player (PlayerController3D) and the BotPlayer.
## Single source of truth: the player controller aliases every constant below under its old name (so tests that read
## its script constants keep working) and calls these static helpers, and bots run the exact same numbers.
## Values unchanged from v0.5.0 / v0.6 (see the comments in player_controller_3d.gd for the pre-v0.5 history).

const StanceRigScript = preload("res://scripts/player/pro_paintball_rig_3d.gd")

## Stance ids (== PlayerController3D.Stance).
const STANCE_STANDING: int = 0
const STANCE_CROUCHING: int = 1
const STANCE_PRONE: int = 2

# --- gait -------------------------------------------------------------------------------------------------------
const WALK_SPEED: float = 5.6
const SPRINT_SPEED: float = 8.4
const CROUCH_SPEED: float = 3.3
const PRONE_SPEED: float = 1.7
const BACKPEDAL_SPEED_MULT: float = 0.5
const GROUND_ACCEL: float = 28.0
const SPRINT_ACCEL: float = 9.0
const GROUND_DECEL: float = 60.0
# --- knee-slide / Superman dive + movement fire lock -----------------------------------------------------------
const SLIDE_INITIAL_SPEED: float = 15.8
const SLIDE_DURATION: float = 0.85
const MOVEMENT_FIRE_RECOVERY: float = 0.15
const DIVE_INITIAL_SPEED: float = 17.6
const DIVE_DURATION: float = 0.95
# --- eye heights per stance --------------------------------------------------------------------------------------
const HEIGHT_STANDING: float = 1.58
const HEIGHT_CROUCH: float = 0.92
const HEIGHT_SLIDE: float = 0.68
const HEIGHT_PRONE: float = 0.36
const HEIGHT_DIVE: float = 0.42
# --- body ---------------------------------------------------------------------------------------------------------
const TORSO_RADIUS: float = 0.25
# --- shot spread (cone half-angle deg = bracket base * state multiplier) -----------------------------------------
const SPREAD_BASE_DEG_SPEEDBALL: float = 0.75
const SPREAD_BASE_DEG_WOODSBALL: float = 0.60
const SPREAD_BASE_DEG_PUMP: float = 0.42
const SPREAD_MULT_POCKET: float = 0.55
const SPREAD_MULT_PRONE: float = 0.60
const SPREAD_MULT_CROUCH: float = 0.70
const SPREAD_MULT_STANDING: float = 1.00
const SPREAD_MULT_WALK: float = 2.00
const SPREAD_MULT_SPRINT: float = 4.50
const SPREAD_MULT_AIRBORNE: float = 3.00
const SPREAD_RECOVERY_TIME: float = 0.40
const SPREAD_BLOOM_TIME: float = 0.15

## 0..1 backward share of a (normalized) move input; +y is back (S). Pure S = 1, back-diagonal ~0.71, strafe 0.
static func backpedal_amount(input_vec: Vector2) -> float:
	if input_vec.length_squared() < 0.0001:
		return 0.0
	return clampf(input_vec.normalized().y, 0.0, 1.0)

## Speed multiplier for the backward share of the input (1.0 forward/strafe -> BACKPEDAL_SPEED_MULT pure back).
static func backpedal_speed_factor(input_vec: Vector2) -> float:
	return lerpf(1.0, BACKPEDAL_SPEED_MULT, backpedal_amount(input_vec))

## Ground-gait target speed before breakout multipliers (sprint only boosts the non-backward share of the input).
static func gait_target_speed(input_vec: Vector2, sprinting: bool, cur_stance: int) -> float:
	var back := backpedal_amount(input_vec)
	var base: float = WALK_SPEED
	if sprinting:
		base = lerpf(SPRINT_SPEED, WALK_SPEED, back)
	elif cur_stance == STANCE_CROUCHING:
		base = CROUCH_SPEED
	elif cur_stance == STANCE_PRONE:
		base = PRONE_SPEED
	return base * backpedal_speed_factor(input_vec)

## One step of the ground-speed ramp (walk-up fast, sprint-up slower, crisp stop).
static func step_ground_speed(ground_speed: float, target_speed: float, speed_mult: float, delta: float) -> float:
	var accel: float = GROUND_DECEL
	if target_speed > ground_speed:
		accel = SPRINT_ACCEL if ground_speed >= WALK_SPEED * speed_mult - 0.01 else GROUND_ACCEL
	return move_toward(ground_speed, target_speed, accel * delta)

## Planar speed of a knee-slide with slide_timer left (decays to 20%).
static func slide_speed(slide_timer: float) -> float:
	return SLIDE_INITIAL_SPEED * clampf(slide_timer / SLIDE_DURATION, 0.2, 1.0)

## Planar speed of a Superman dive with dive_timer left (decays to 15%).
static func dive_speed(dive_timer: float) -> float:
	return DIVE_INITIAL_SPEED * clampf(dive_timer / DIVE_DURATION, 0.15, 1.0)

## True for the whole slide / dive and the MOVEMENT_FIRE_RECOVERY window after.
static func is_fire_locked(slide_timer: float, dive_timer: float, recovery_timer: float) -> bool:
	return slide_timer > 0.0 or dive_timer > 0.0 or recovery_timer > 0.0

## Movement capsule / torso hitbox height for a stance (shared table with ProPaintballRig3D).
static func stance_capsule_target(slide_timer: float, dive_timer: float, cur_stance: int) -> float:
	if dive_timer > 0.0:
		return StanceRigScript.STANCE_CAPSULE_DIVE
	if slide_timer > 0.0:
		return StanceRigScript.STANCE_CAPSULE_SLIDE
	if cur_stance == STANCE_CROUCHING:
		return StanceRigScript.STANCE_CAPSULE_CROUCH
	if cur_stance == STANCE_PRONE:
		return StanceRigScript.STANCE_CAPSULE_PRONE
	return StanceRigScript.STANCE_CAPSULE_STANDING

## Eye height for a stance (slide / dive override).
static func eye_height(slide_timer: float, dive_timer: float, cur_stance: int) -> float:
	if dive_timer > 0.0:
		return HEIGHT_DIVE
	if slide_timer > 0.0:
		return HEIGHT_SLIDE
	if cur_stance == STANCE_CROUCHING:
		return HEIGHT_CROUCH
	if cur_stance == STANCE_PRONE:
		return HEIGHT_PRONE
	return HEIGHT_STANDING

## Spread multiplier the cone heads toward: posture floor, opened up by ground speed; sprint while sliding/diving.
static func target_spread_mult(in_pocket: bool, cur_stance: int, ground_speed: float, sliding_or_diving: bool, airborne: bool) -> float:
	var posture: float = SPREAD_MULT_STANDING
	if in_pocket:
		posture = SPREAD_MULT_POCKET
	elif cur_stance == STANCE_PRONE:
		posture = SPREAD_MULT_PRONE
	elif cur_stance == STANCE_CROUCHING:
		posture = SPREAD_MULT_CROUCH
	var m: float
	if ground_speed <= WALK_SPEED:
		m = lerpf(posture, SPREAD_MULT_WALK, clampf(ground_speed / WALK_SPEED, 0.0, 1.0))
	else:
		m = lerpf(SPREAD_MULT_WALK, SPREAD_MULT_SPRINT, clampf((ground_speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0))
	if sliding_or_diving:
		m = SPREAD_MULT_SPRINT
	elif airborne:
		m = maxf(m, SPREAD_MULT_AIRBORNE)
	return m

## One step of the smoothed spread multiplier (blooms in SPREAD_BLOOM_TIME, recovers in SPREAD_RECOVERY_TIME).
static func step_spread_mult(current: float, target: float, delta: float) -> float:
	var span: float = SPREAD_MULT_SPRINT - SPREAD_MULT_STANDING
	var rate: float = span / (SPREAD_BLOOM_TIME if target > current else SPREAD_RECOVERY_TIME)
	return move_toward(current, target, rate * delta)

## Bracket base cone half-angle (deg) from a GearBracketData trigger mode (0 ramp, 1 semi one-pull, 2 pump).
static func bracket_base_spread_deg_for_mode(trigger_mode: int) -> float:
	match trigger_mode:
		2:
			return SPREAD_BASE_DEG_PUMP
		1:
			return SPREAD_BASE_DEG_WOODSBALL
	return SPREAD_BASE_DEG_SPEEDBALL

## Random direction inside a circular cone of half-angle spread_deg around base_dir (uniform over the disc).
static func apply_spread_cone(base_dir: Vector3, right_dir: Vector3, up_dir: Vector3, spread_deg: float) -> Vector3:
	var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
	var th: float = randf() * TAU
	return (base_dir + right_dir * (r * cos(th)) + up_dir * (r * sin(th))).normalized()
