extends Node

## Shared team communication bus for Named Bunker Callouts ('Dorito 2', 'Snake 50'),
## Lane Suppression Intensity ('PINNED!'), and 3D Field Pings (PB-17 / Issue #21).

signal enemy_spotted(target_name: String, world_position: Vector3, duration: float)
signal bunker_pinned(bunker_name: String, world_position: Vector3, intensity: float)
signal suppression_updated(level: float, pinned_bunker: String)
signal intel_feed_updated(message: String)

var active_pings: Array[Dictionary] = []
var suppression_level: float = 0.0
var last_pinned_bunker: String = ""

const BUNKER_CALLOUT_MAP := {
	"Bunker_Center50_W": "CENTER 50 W",
	"Bunker_50_MiniWin_Left": "SNAKE-SIDE 50 MINI-W",
	"Bunker_50_MiniWin_Right": "DORITO-SIDE 50 MINI-W",
	"Bunker_50_Insert_Left": "SNAKE-SIDE 50 INSERT",
	"Bunker_50_Insert_Right": "DORITO-SIDE 50 INSERT",
	"Bunker_50_GiantDorito": "GIANT DORITO 50",
	"Snake_Beam_Home1": "SNAKE 1 (HOME)",
	"Snake_Beam_Home2": "SNAKE 2 (HOME)",
	"Snake_Beam_OpFor2": "SNAKE 2 (OPFOR)",
	"Snake_Beam_OpFor1": "SNAKE 1 (OPFOR)",
	"Snake_Knuckle_HomeEntry": "SNAKE ENTRY KNUCKLE",
	"Snake_Knuckle_HomeMid": "SNAKE GOD POCKET",
	"Snake_Knuckle_Center50": "SNAKE 50 KNUCKLE",
	"Snake_Knuckle_OpForMid": "OPFOR SNAKE POCKET",
	"Snake_Knuckle_OpForEntry": "OPFOR SNAKE ENTRY",
	"Heli_CrashFuselage_Center50": "HELI CRASH FUSELAGE (50)",
	"Heli_CockpitNose": "HELI COCKPIT NOSE (50)",
	"Heli_BrokenTailBoom": "HELI TAIL BOOM (50)",
	"Heli_TailRotorPylon": "HELI TAIL ROTOR PYLON",
	"Tower_WestFlank_Parapet_Front": "WEST WATCHTOWER (NORTH RAIL)",
	"Tower_WestFlank_Parapet_Back": "WEST WATCHTOWER (SOUTH RAIL)",
	"Tower_EastFlank_Parapet_Front": "EAST WATCHTOWER (SOUTH RAIL)",
	"Tower_EastFlank_Parapet_Back": "EAST WATCHTOWER (NORTH RAIL)",
	"Tower_WestFlank_Parapet_Left": "WEST WATCHTOWER (SNAKE RAIL)",
	"Tower_WestFlank_Parapet_Right": "WEST WATCHTOWER (CENTER RAIL)",
	"Tower_EastFlank_Parapet_Left": "EAST WATCHTOWER (DORITO RAIL)",
	"Tower_EastFlank_Parapet_Right": "EAST WATCHTOWER (CENTER RAIL)",
	"Tower_SouthRidge_Parapet_Right": "HOME RIDGE TOWER DECK",
	"Tower_NorthRidge_Parapet_Right": "OPFOR RIDGE TOWER DECK",
	"Tower_SouthRidge_Parapet_Front": "HOME RIDGE TOWER DECK",
	"Tower_SouthRidge_Parapet_Back": "HOME RIDGE TOWER DECK",
	"Tower_SouthRidge_Parapet_Left": "HOME RIDGE TOWER DECK",
	"Tower_NorthRidge_Parapet_Front": "OPFOR RIDGE TOWER DECK",
	"Tower_NorthRidge_Parapet_Back": "OPFOR RIDGE TOWER DECK",
	"Tower_NorthRidge_Parapet_Left": "OPFOR RIDGE TOWER DECK"
}

func format_bunker_callout(raw_name: String, world_pos: Vector3 = Vector3.ZERO) -> String:
	if BUNKER_CALLOUT_MAP.has(raw_name):
		return BUNKER_CALLOUT_MAP[raw_name]
	var side_tag := ""
	var clean := raw_name
	if clean.begins_with("Home_"):
		side_tag = "HOME "
		clean = clean.trim_prefix("Home_")
	elif clean.begins_with("OpFor_"):
		side_tag = "OPFOR "
		clean = clean.trim_prefix("OpFor_")
	elif clean.begins_with("Bunker_"):
		clean = clean.trim_prefix("Bunker_")

	match clean:
		"Dorito_Corner":
			return side_tag + "DORITO CORNER (D1)"
		"Dorito_1":
			return side_tag + "DORITO 1"
		"Dorito_2":
			return side_tag + "DORITO 2"
		"Snake_Corner":
			return side_tag + "SNAKE CORNER"
		"Snake_GodCan":
			return side_tag + "GOD CAN (SNAKE)"
		"CenterAztec":
			return side_tag + "CENTER AZTEC"
		"BackCenter":
			return side_tag + "HOME STONE"
		"BreakoutGate":
			return side_tag + "BREAKOUT GATE"
		"40_Pin_L":
			return side_tag + "SNAKE-SIDE 40 PIN"
		"40_Pin_R":
			return side_tag + "DORITO-SIDE 40 PIN"
		"40_Wedge_L":
			return side_tag + "SNAKE-SIDE 40 WEDGE"
		"40_Wedge_R":
			return side_tag + "DORITO-SIDE 40 WEDGE"
		_:
			if raw_name == "TurfFloor":
				if absf(world_pos.z) < 6.0:
					return "50-YARD LINE TURF"
				elif world_pos.x > 22.0:
					return "DORITO TAPE LANE"
				elif world_pos.x < -22.0:
					return "SNAKE TAPE LANE"
				return "MIDFIELD TURF (%.0fm, %.0fm)" % [world_pos.x, world_pos.z]
			return (side_tag + clean.replace("_", " ")).to_upper()

func _process(delta: float) -> void:
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i]["time_left"] -= delta
		if active_pings[i]["time_left"] <= 0.0:
			active_pings.remove_at(i)
	if suppression_level > 0.0:
		suppression_level = maxf(0.0, suppression_level - delta * 0.45)
		suppression_updated.emit(suppression_level, last_pinned_bunker)

func report_spot(target_name: String, world_pos: Vector3, duration: float = 3.5) -> void:
	var callout := format_bunker_callout(target_name, world_pos)
	active_pings.append({
		"label": callout,
		"position": world_pos,
		"time_left": duration
	})
	enemy_spotted.emit(callout, world_pos, duration)
	intel_feed_updated.emit("CALLOUT: [%s] @ (%.0fm, %.0fm)" % [callout, world_pos.x, world_pos.z])

func report_bunker_hit(bunker_name: String, world_pos: Vector3) -> void:
	var callout := format_bunker_callout(bunker_name, world_pos)
	last_pinned_bunker = callout
	suppression_level = clampf(suppression_level + 0.28, 0.0, 1.0)
	bunker_pinned.emit(callout, world_pos, suppression_level)
	suppression_updated.emit(suppression_level, callout)
