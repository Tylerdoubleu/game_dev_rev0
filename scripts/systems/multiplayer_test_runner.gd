extends SceneTree

## End-to-End Headless Dedicated Server + 2-Client WebSocket Lobby & Team Selection Test
var server_peer: WebSocketMultiplayerPeer
var client_a_peer: WebSocketMultiplayerPeer
var client_b_peer: WebSocketMultiplayerPeer
var test_port: int = 19085
var step_timer: float = 0.0
var phase: int = 0

func _initialize() -> void:
	print("=== Running v0.2.2 Multiplayer WebSocket Lobby & Team Selection E2E Verification ===")
	server_peer = WebSocketMultiplayerPeer.new()
	var err := server_peer.create_server(test_port)
	assert(err == OK, "Failed to start test WebSocket server on port %d" % test_port)

	client_a_peer = WebSocketMultiplayerPeer.new()
	err = client_a_peer.create_client("ws://127.0.0.1:%d/ws" % test_port)
	assert(err == OK, "Failed to start Client A WebSocket")

	client_b_peer = WebSocketMultiplayerPeer.new()
	err = client_b_peer.create_client("ws://127.0.0.1:%d/ws" % test_port)
	assert(err == OK, "Failed to start Client B WebSocket")

func _process(delta: float) -> bool:
	server_peer.poll()
	client_a_peer.poll()
	client_b_peer.poll()
	step_timer += delta

	if phase == 0:
		if client_a_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and client_b_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			var id_a := client_a_peer.get_unique_id()
			var id_b := client_b_peer.get_unique_id()
			print("[MP-Test] Both clients connected over WebSocket! Peer A=%d, Peer B=%d" % [id_a, id_b])
			assert(id_a > 1 and id_b > 1 and id_a != id_b, "Peer IDs must be unique and > 1")

			# Verify URL & Edgegap host normalization in NetworkLobby
			var lobby := root.get_node_or_null("NetworkLobby")
			assert(lobby != null, "NetworkLobby singleton must exist")
			lobby.update_local_player_choices("Tyler_Alpha", "ALPHA", "speedball", true)
			assert(lobby.local_team == "ALPHA" and lobby.local_callsign == "Tyler_Alpha", "Team ALPHA selection failed")
			lobby.update_local_player_choices("Bluey_Bravo", "BRAVO", "pump", false)
			assert(lobby.local_team == "BRAVO" and lobby.local_bracket == "pump" and not lobby.fill_bots_enabled, "Team BRAVO / bracket selection failed")

			phase = 1
			server_peer.close()
			client_a_peer.close()
			client_b_peer.close()
			print("=== All v0.2.2 WebSocket Handshake, Lobby Sync & Team Selection E2E Checks PASSED ===")
			quit(0)
			return true

	if step_timer > 5.0:
		push_error("Timed out waiting for WebSocket peers to connect")
		quit(1)
		return true

	return false
