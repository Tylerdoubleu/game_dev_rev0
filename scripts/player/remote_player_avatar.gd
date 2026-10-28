extends StaticBody3D

## Attached to RemotePlayer_<peer_id> nodes spawned by NetworkLobby.
## Supports sub-hitbox classification (HOPPER / MARKER, MASK / GOGGLES, POD PACK, TORSO / JERSEY)
## and articulated 3P marker/hopper tilts when tucked vs. snap-peeking (#16 + #20).

var last_hit_zone: String = "TORSO / JERSEY"

func classify_hit_zone(hit_pos: Vector3) -> String:
	var sub := resolve_hit_subzone(hit_pos)
	return String(sub.get("zone", "TORSO / JERSEY"))

func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	var marker_piv := get_node_or_null("MarkerPivot3D") as Node3D
	if marker_piv != null:
		var hopper_piv := marker_piv.get_node_or_null("HopperPivot3D") as Node3D
		var hopper_world := hopper_piv.global_position if hopper_piv != null else (marker_piv.global_position + Vector3(0.0, 0.12, 0.0))
		if world_hit_pos.distance_to(hopper_world) <= 0.28 or world_hit_pos.distance_to(marker_piv.global_position) <= 0.28:
			last_hit_zone = "HOPPER / MARKER"
			return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	var local_hit := to_local(world_hit_pos)
	if local_hit.y >= 1.32:
		last_hit_zone = "MASK / GOGGLES"
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.26}
	if local_hit.z >= 0.12 and local_hit.y >= 0.65 and local_hit.y <= 1.18:
		last_hit_zone = "POD PACK"
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.36}
	last_hit_zone = "TORSO / JERSEY"
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	resolve_hit_subzone(hit_pos)
	if has_meta("remote_peer_id"):
		if shooter == null or shooter.name == "Player3D":
			NetworkLobby.notify_remote_player_hit(int(get_meta("remote_peer_id")))

func on_paintball_bounce(hit_pos: Vector3) -> void:
	resolve_hit_subzone(hit_pos)
