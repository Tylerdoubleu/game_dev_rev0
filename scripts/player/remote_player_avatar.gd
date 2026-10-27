extends StaticBody3D

func on_paintball_break(_hit_pos: Vector3, _shooter: Node) -> void:
	if has_meta("remote_peer_id"):
		NetworkLobby.notify_remote_player_hit(int(get_meta("remote_peer_id")))
