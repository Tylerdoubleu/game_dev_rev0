class_name GearBracketData
extends Resource

enum TriggerMode {
	RAMP_10_5,
	SEMI_ONE_PULL,
	PUMP_MANUAL
}

@export var bracket_id: String = "speedball"
@export var display_name: String = "Tournament Speedball"
@export var trigger_mode: TriggerMode = TriggerMode.RAMP_10_5
@export var max_bps: float = 10.5
@export var hopper_capacity: int = 200
@export var pod_count: int = 4
@export var pod_capacity: int = 140
@export var muzzle_fps: float = 285.0
