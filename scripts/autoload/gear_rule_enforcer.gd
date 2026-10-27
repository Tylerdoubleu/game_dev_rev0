extends Node

## Enforces map-locked horizontal gear brackets (Speedball, Woodsball, Pump) with 40% reduced scarce paint counts.
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
	speedball.display_name = "Tournament Speedball (Dual-Trigger Walk, 10.5 BPS Cap)"
	speedball.trigger_mode = GearBracketDataScript.TriggerMode.RAMP_10_5
	speedball.max_bps = 10.5
	speedball.hopper_capacity = 30
	speedball.pod_count = 2
	speedball.pod_capacity = 30
	speedball.muzzle_fps = 290.0
	brackets["speedball"] = speedball

	var woodsball: Resource = GearBracketDataScript.new()
	woodsball.bracket_id = "woodsball"
	woodsball.display_name = "Tactical Woodsball (1-Pull: Hold LMB+RMB Together)"
	woodsball.trigger_mode = GearBracketDataScript.TriggerMode.SEMI_ONE_PULL
	woodsball.max_bps = 6.5
	woodsball.hopper_capacity = 18
	woodsball.pod_count = 2
	woodsball.pod_capacity = 18
	woodsball.muzzle_fps = 285.0
	brackets["woodsball"] = woodsball

	var pump: Resource = GearBracketDataScript.new()
	pump.bracket_id = "pump"
	pump.display_name = "Stock & Pump Classic (LMB Shoot -> RMB Rack)"
	pump.trigger_mode = GearBracketDataScript.TriggerMode.PUMP_MANUAL
	pump.max_bps = 2.5
	pump.hopper_capacity = 6
	pump.pod_count = 3
	pump.pod_capacity = 6
	pump.muzzle_fps = 280.0
	brackets["pump"] = pump

func set_active_bracket(bracket_id: String) -> void:
	if brackets.has(bracket_id):
		active_bracket = brackets[bracket_id]
		bracket_changed.emit(active_bracket)

func get_min_shot_interval() -> float:
	if active_bracket == null or active_bracket.max_bps <= 0.0:
		return 0.095
	return 1.0 / float(active_bracket.max_bps)
