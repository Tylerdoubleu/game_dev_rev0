extends Resource
## v0.7 BotPlayer difficulty tier (plan "Smarter bots" > Difficulty tiers). Difficulty comes from decisions
## (reaction, peek habits, when to move, slide / dive, suppression) plus a bounded aim error. The spread cone itself is
## the player's MovementRules cone, so a sprinting bot misses exactly as much as a sprinting player.
## Rookie and Amateur are live in v0.7; Pro / Legend carry the plan's proposed numbers for the career runner later.

const TIER_ROOKIE := "rookie"
const TIER_AMATEUR := "amateur"
const TIER_PRO := "pro"
const TIER_LEGEND := "legend"

@export var tier: String = TIER_ROOKIE
@export var display_name: String = "Rookie"
## Seconds from first seeing a target (perception tick) to the first shot.
@export var reaction_s: float = 0.65
## Aim error (radius, metres) at 20 m; scales linearly with range. Sampled once per burst.
@export var aim_error_at_20m: float = 1.2
## 1.0 = the bracket's max BPS inside a burst; Rookie fires its bursts at half rate.
@export var fire_rate_scale: float = 0.5
@export var burst_min: int = 2
@export var burst_max: int = 3
@export var burst_pause_min: float = 0.55
@export var burst_pause_max: float = 1.1
## Chance per tuck to leave the bunker for the next one when the lane is safe ("rarely" vs "when safe").
@export var move_chance: float = 0.12
## Seconds without a visible threat before a move counts as safe.
@export var safe_after_s: float = 3.0
@export var can_slide: bool = false
@export var can_dive: bool = false
@export var suppresses: bool = false
@export var flanks: bool = false
## false = always peeks the same side of its bunker (Rookie habit); true = varies the side.
@export var varies_peek_side: bool = false
@export var peek_time_min: float = 1.4
@export var peek_time_max: float = 2.2
@export var tuck_time_min: float = 1.4
@export var tuck_time_max: float = 2.4
## Aim turn rate (deg/s, yaw and pitch) when swinging onto a target. A bot only fires once its body / marker is within
## BotPlayer.FIRE_CONE_DEG of the shot, so a slower turn = a later first ball (Rookie is visibly slower to swing).
@export var turn_rate_deg: float = 300.0

static func make(tier_id: String) -> Resource:
	var script: GDScript = load("res://scripts/bots/bot_difficulty.gd")
	var d: Resource = script.new()
	match tier_id.to_lower():
		TIER_AMATEUR:
			d.tier = TIER_AMATEUR
			d.turn_rate_deg = 480.0
			d.display_name = "Amateur"
			d.reaction_s = 0.45
			d.aim_error_at_20m = 0.7
			d.fire_rate_scale = 1.0
			d.burst_min = 3
			d.burst_max = 4
			d.burst_pause_min = 0.35
			d.burst_pause_max = 0.8
			d.move_chance = 0.55
			d.safe_after_s = 2.0
			d.can_slide = true
			d.can_dive = false # plan: Amateur slides; dive arrives with Pro
			d.suppresses = true
			d.varies_peek_side = true
			d.peek_time_min = 0.9
			d.peek_time_max = 1.8
			d.tuck_time_min = 0.8
			d.tuck_time_max = 1.6
		TIER_PRO:
			d.tier = TIER_PRO
			d.turn_rate_deg = 660.0
			d.display_name = "Pro"
			d.reaction_s = 0.30
			d.aim_error_at_20m = 0.4
			d.fire_rate_scale = 1.0
			d.burst_min = 4
			d.burst_max = 6
			d.burst_pause_min = 0.25
			d.burst_pause_max = 0.6
			d.move_chance = 0.75
			d.safe_after_s = 1.5
			d.can_slide = true
			d.can_dive = true
			d.suppresses = true
			d.flanks = true
			d.varies_peek_side = true
			d.peek_time_min = 0.6
			d.peek_time_max = 1.6
			d.tuck_time_min = 0.5
			d.tuck_time_max = 1.4
		TIER_LEGEND:
			d.tier = TIER_LEGEND
			d.turn_rate_deg = 840.0
			d.display_name = "Legend"
			d.reaction_s = 0.20
			d.aim_error_at_20m = 0.25
			d.fire_rate_scale = 1.0
			d.burst_min = 6
			d.burst_max = 9
			d.burst_pause_min = 0.15
			d.burst_pause_max = 0.4
			d.move_chance = 0.9
			d.safe_after_s = 1.0
			d.can_slide = true
			d.can_dive = true
			d.suppresses = true
			d.flanks = true
			d.varies_peek_side = true
			d.peek_time_min = 0.5
			d.peek_time_max = 1.4
			d.tuck_time_min = 0.4
			d.tuck_time_max = 1.1
		_:
			d.tier = TIER_ROOKIE # defaults above are Rookie
	return d

## Aim error radius (m) at a given range.
func aim_error_at(range_m: float) -> float:
	return aim_error_at_20m * maxf(range_m, 0.0) / 20.0

## Seconds between balls inside a burst for a bracket max BPS.
func shot_interval(max_bps: float) -> float:
	return 1.0 / maxf(max_bps * fire_rate_scale, 0.5)
