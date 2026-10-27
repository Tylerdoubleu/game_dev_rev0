extends Node

## Enforces map-locked horizontal gear brackets (Speedball, Woodsball, Pump).
## TODO(PB-06 / Issue #6): Load bracket definitions from .tres files in res://data/brackets/ and validate custom player loadouts.

const GearBracketDataScript = preload("res://scripts/resources/gear_bracket_data.gd")

signal bracket_changed(bracket_data: Resource)

var brackets: Dictionary = {}
var active_bracket: Resource

func _ready() -> void:
	_init_default_brackets()
	set_active_bracket("speedball")

func _init_default_brackets() -> void:
	var speedball: Resource = GearBracketDataScript.new()
	speedball.bracket_id = "speedball"
	speedball.display_name = "Tournament Speedball (10.5 BPS Ramp)"
	speedball.trigger_mode = GearBracketDataScript.TriggerMode.RAMP_10_5
	speedball.max_bps = 10.5
	speedball.hopper_capacity = 200
	speedball.pod_count = 4
	speedball.pod_capacity = 140
	speedball.muzzle_fps = 285.0
	brackets["speedball"] = speedball

	var woodsball: Resource = GearBracketDataScript.new()
	woodsball.bracket_id = "woodsball"
	woodsball.display_name = "Tactical Woodsball (Semi 1-Pull)"
	woodsball.trigger_mode = GearBracketDataScript.TriggerMode.SEMI_ONE_PULL
	woodsball.max_bps = 6.5
	woodsball.hopper_capacity = 150
	woodsball.pod_count = 3
	woodsball.pod_capacity = 140
	woodsball.muzzle_fps = 280.0
	brackets["woodsball"] = woodsball

	var pump: Resource = GearBracketDataScript.new()
	pump.bracket_id = "pump"
	pump.display_name = "Stock & Pump Classic (Manual Rack)"
	pump.trigger_mode = GearBracketDataScript.TriggerMode.PUMP_MANUAL
	pump.max_bps = 2.2
	pump.hopper_capacity = 50
	pump.pod_count = 5
	pump.pod_capacity = 10
	pump.muzzle_fps = 275.0
	brackets["pump"] = pump

func set_active_bracket(bracket_id: String) -> void:
	if brackets.has(bracket_id):
		active_bracket = brackets[bracket_id]
		bracket_changed.emit(active_bracket)

func get_min_shot_interval() -> float:
	if active_bracket == null or active_bracket.max_bps <= 0.0:
		return 0.1
	return 1.0 / float(active_bracket.max_bps)
