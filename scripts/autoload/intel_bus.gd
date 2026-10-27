extends Node

## Shared team communication bus for spotting enemies and flagging pinned bunkers.
## TODO(PB-04 / Issue #4): Upgrade basic 3D ping boxes to bunker callout zones, line-of-sight silhouettes, and Pinned suppression HUD.

signal enemy_spotted(target_name: String, world_position: Vector3, duration: float)
signal bunker_pinned(bunker_name: String, world_position: Vector3, intensity: float)
signal intel_feed_updated(message: String)

var active_pings: Array[Dictionary] = []

func _process(delta: float) -> void:
	for i in range(active_pings.size() - 1, -1, -1):
		active_pings[i]["time_left"] -= delta
		if active_pings[i]["time_left"] <= 0.0:
			active_pings.remove_at(i)

func report_spot(target_name: String, world_pos: Vector3, duration: float = 2.5) -> void:
	active_pings.append({
		"label": target_name,
		"position": world_pos,
		"time_left": duration
	})
	enemy_spotted.emit(target_name, world_pos, duration)
	intel_feed_updated.emit("INTEL: Spotted %s (%.1fs)" % [target_name, duration])

func report_bunker_hit(bunker_name: String, world_pos: Vector3) -> void:
	bunker_pinned.emit(bunker_name, world_pos, 1.0)
