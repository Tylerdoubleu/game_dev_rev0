extends StaticBody3D

## Attached to RemotePlayer_<peer_id> nodes spawned by NetworkLobby.
## Powered by the 22-joint ProPaintballRig3D (PB-14) with bone-synced sub-hitboxes
## (Hitbox_HopperMarker, Hitbox_Mask, Hitbox_PodPack, Hitbox_Torso).

var last_hit_zone: String = "TORSO / JERSEY"

func classify_hit_zone(hit_pos: Vector3) -> String:
	var sub := resolve_hit_subzone(hit_pos)
	return String(sub.get("zone", "TORSO / JERSEY"))

func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	var h_col := get_node_or_null("Hitbox_HopperMarker") as Node3D
	if h_col != null and world_hit_pos.distance_to(h_col.global_position) <= 0.30:
		last_hit_zone = "HOPPER / MARKER"
		return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	var m_col := get_node_or_null("Hitbox_Mask") as Node3D
	if m_col != null and world_hit_pos.distance_to(m_col.global_position) <= 0.26:
		last_hit_zone = "MASK / GOGGLES"
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.28}
	var p_col := get_node_or_null("Hitbox_PodPack") as Node3D
	if p_col != null and world_hit_pos.distance_to(p_col.global_position) <= 0.28:
		last_hit_zone = "POD PACK"
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.32}
	last_hit_zone = "TORSO / JERSEY"
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	resolve_hit_subzone(hit_pos)
	if has_meta("remote_peer_id"):
		if shooter == null or shooter.name == "Player3D":
			NetworkLobby.notify_remote_player_hit(int(get_meta("remote_peer_id")))

func on_paintball_bounce(hit_pos: Vector3) -> void:
	resolve_hit_subzone(hit_pos)
