class_name MovementFoley
extends Node
## v0.6 (Ren): subtle movement foley + effort sounds for a player body. Reads the body's state each physics
## frame (velocity, is_on_floor, stance, slide_timer, dive_timer) without touching the controller:
## - turf footsteps paced by distance travelled (quieter crouched, harder plants when sprinting)
## - masked sprint exhales once you've been sprinting a couple of seconds
## - knee-slide: turf scrape + a short "hnh" effort
## - Superman dive: a "hup!" effort on take-off and a chest-pad thud when you hit the ground
## - a soft landing after a real fall
## Sounds are synthesized by scripts/tools/gen_movement_audio.py into res://assets/audio/movement/.

const STREAMS := {
	"step": [preload("res://assets/audio/movement/step_turf_1.wav"), preload("res://assets/audio/movement/step_turf_2.wav"),
		preload("res://assets/audio/movement/step_turf_3.wav"), preload("res://assets/audio/movement/step_turf_4.wav")],
	"step_sprint": [preload("res://assets/audio/movement/step_sprint_1.wav"), preload("res://assets/audio/movement/step_sprint_2.wav")],
	"breath": [preload("res://assets/audio/movement/breath_sprint_1.wav"), preload("res://assets/audio/movement/breath_sprint_2.wav")],
	## v0.6: Tyler's recorded slide/dive efforts rotate for both moves; the synthesized scrape/effort/thud are retired.
	"slide": [preload("res://assets/audio/movement/slide_dive_1.wav"), preload("res://assets/audio/movement/slide_dive_2.wav"),
		preload("res://assets/audio/movement/slide_dive_3.wav"), preload("res://assets/audio/movement/slide_dive_4.wav")],
	"effort_slide": [],
	"effort_dive": [preload("res://assets/audio/movement/slide_dive_1.wav"), preload("res://assets/audio/movement/slide_dive_2.wav"),
		preload("res://assets/audio/movement/slide_dive_3.wav"), preload("res://assets/audio/movement/slide_dive_4.wav")],
	"dive_land": [],
	"land": [preload("res://assets/audio/movement/land_soft.wav")],
}
## Kept deliberately low so paint, markers and the horn stay on top.
const VOLUME_DB := {"step": -29.0, "step_sprint": -26.0, "breath": -21.0, "slide": -11.0, "effort_slide": -15.0,
	"effort_dive": -12.0, "dive_land": -9.0, "land": -14.0}
## Tyler: footsteps "way down, subtle and muffled" - they go through their own bus with a low-pass filter.
const STEP_BUS := "Footsteps"
const STEP_LOWPASS_HZ := 1800.0
const STEP_KINDS := ["step", "step_sprint"]
const WALK_STRIDE := 1.5        # metres between footsteps when walking
const SPRINT_STRIDE := 2.1      # longer strides at sprint pace
const SPRINT_SPEED_MIN := 6.6   # above WALK_SPEED 5.6, below SPRINT_SPEED 8.4
const BREATH_AFTER := 2.0       # seconds of sprinting before exhales start
const FALL_MIN_AIR := 0.35      # airborne this long before a landing sound

static var play_counts: Dictionary = {}

var target: Node3D
## Tests can set this to drive the foley without a physics body: {speed, on_floor, stance, slide, dive}.
var debug_state: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _stride_acc := 0.0
var _sprint_time := 0.0
var _breath_timer := 0.0
var _air_time := 0.0
var _was_sliding := false
var _was_diving := false
var _dive_airborne := false
var _dive_landed := false
var _last_pick: Dictionary = {}

func _init(body: Node3D = null) -> void:
	target = body
	name = "MovementFoley"

static func ensure_step_bus() -> String:
	var idx := AudioServer.get_bus_index(STEP_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, STEP_BUS)
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = STEP_LOWPASS_HZ
		lp.resonance = 0.4
		AudioServer.add_bus_effect(idx, lp)
	return STEP_BUS

func _ready() -> void:
	ensure_step_bus()
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 30.0
		p.attenuation_filter_cutoff_hz = 7000.0
		add_child(p)
		_players.append(p)

func _physics_process(delta: float) -> void:
	step(delta)

func _read_state() -> Dictionary:
	if not debug_state.is_empty() or target == null:
		return debug_state
	var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
	return {
		"speed": Vector2(v.x, v.z).length(),
		"on_floor": target.is_on_floor() if target.has_method("is_on_floor") else true,
		"stance": int(target.get("stance")) if "stance" in target else 0,
		"slide": float(target.get("slide_timer")) > 0.0 if "slide_timer" in target else false,
		"dive": float(target.get("dive_timer")) > 0.0 if "dive_timer" in target else false,
	}

func step(delta: float) -> void:
	var s := _read_state()
	if s.is_empty():
		return
	var speed := float(s.get("speed", 0.0))
	var on_floor := bool(s.get("on_floor", true))
	var stance := int(s.get("stance", 0))  # 0 standing, 1 crouching, 2 prone
	var sliding := bool(s.get("slide", false))
	var diving := bool(s.get("dive", false))

	# Knee-slide start
	if sliding and not _was_sliding:
		play("slide"); play("effort_slide")
		_stride_acc = 0.0
	# Superman dive: effort on take-off, thud on first ground contact after leaving it (or when it ends)
	if diving and not _was_diving:
		play("effort_dive")
		_dive_airborne = false; _dive_landed = false
	if diving:
		if not on_floor:
			_dive_airborne = true
		elif _dive_airborne and not _dive_landed:
			play("dive_land"); _dive_landed = true
	elif _was_diving and not _dive_landed:
		play("dive_land")
	_was_sliding = sliding
	_was_diving = diving

	# Landing after a real fall
	if not on_floor:
		_air_time += delta
	else:
		if _air_time >= FALL_MIN_AIR and not diving:
			play("land")
		_air_time = 0.0

	# Footsteps + sprint breathing
	var sprinting := on_floor and stance == 0 and speed >= SPRINT_SPEED_MIN and not sliding and not diving
	if on_floor and not sliding and not diving and stance != 2 and speed > 0.8:
		_stride_acc += speed * delta
		var stride := SPRINT_STRIDE if sprinting else WALK_STRIDE
		if _stride_acc >= stride:
			_stride_acc -= stride
			play("step_sprint" if sprinting else "step", -5.0 if stance == 1 else 0.0)
	else:
		_stride_acc = minf(_stride_acc, WALK_STRIDE * 0.6)
	if sprinting:
		_sprint_time += delta
		if _sprint_time >= BREATH_AFTER:
			_breath_timer -= delta
			if _breath_timer <= 0.0:
				play("breath")
				_breath_timer = randf_range(1.5, 1.9)
	else:
		_sprint_time = maxf(0.0, _sprint_time - delta * 2.0)
		_breath_timer = 0.0

func play(kind: String, extra_db := 0.0) -> void:
	play_counts[kind] = int(play_counts.get(kind, 0)) + 1
	if _players.is_empty() or not is_inside_tree():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	var list: Array = STREAMS[kind]
	if list.is_empty():
		return
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_pick.get(kind, -1)):
		i = (i + 1 + randi() % (list.size() - 1)) % list.size()
	_last_pick[kind] = i
	p.stream = list[i]
	p.bus = STEP_BUS if kind in STEP_KINDS else "Master"
	p.volume_db = float(VOLUME_DB.get(kind, -15.0)) + extra_db + randf_range(-1.5, 1.0)
	p.pitch_scale = randf_range(0.97, 1.03)
	if target != null and target.is_inside_tree():
		p.global_position = target.global_position
	p.play()
