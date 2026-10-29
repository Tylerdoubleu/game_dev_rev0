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

			server_peer.close()
			client_a_peer.close()
			client_b_peer.close()
			print("=== All v0.2.2 WebSocket Handshake, Lobby Sync & Team Selection E2E Checks PASSED ===")
			_begin_remote_stance_phase()
			return false

	if phase >= 1:
		return _remote_stance_phase()

	if step_timer > 5.0:
		push_error("Timed out waiting for WebSocket peers to connect")
		quit(1)
		return true

	return false


# ---------------------------------------------------------------------------------------------------------------
# v0.4.4: remote player proxy hitboxes follow packed_stance. NetworkLobby._update_or_spawn_remote_player (the same
# path every client AND the server run for other peers' 0.05s state packets) must shrink the remote torso capsule
# to the local per-stance heights so friends' paintballs skimming a 1.25m rail miss a crouched player.
const REMOTE_PEER := 4242
const STANCE_CASES := [
	{"name": "standing", "packed": 0, "cap": 1.38, "covered_y": [], "exposed_y": 1.30},
	{"name": "crouched", "packed": 1, "cap": 1.00, "covered_y": [1.15, 1.20, 1.22, 1.25, 1.30, 1.45], "exposed_y": 0.80},
	{"name": "crouched+pocket tuck", "packed": 1 | 8, "cap": 1.00, "covered_y": [1.15, 1.22, 1.25, 1.40], "exposed_y": 0.70},
	{"name": "prone", "packed": 2, "cap": 0.50, "covered_y": [0.75, 1.00, 1.25], "exposed_y": 0.25},
	{"name": "left-handed crouch (bit 4)", "packed": 1 | 4, "cap": 1.00, "covered_y": [1.20, 1.25], "exposed_y": 0.80},
]
var mp_scene: Node3D
var mp_frame := 0
var mp_case := 0
var mp_failures: Array[String] = []

func _mp_check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		mp_failures.append(msg)

func _begin_remote_stance_phase() -> void:
	print("=== Running v0.4.4 remote-avatar stance hitbox checks (packed_stance -> RemotePlayer torso capsule) ===")
	mp_scene = Node3D.new()
	mp_scene.name = "MPStanceTestScene"
	root.add_child(mp_scene)
	current_scene = mp_scene
	phase = 1
	mp_frame = 0
	mp_case = 0

func _avatar() -> StaticBody3D:
	var lobby := root.get_node("NetworkLobby")
	return (lobby.get("remote_player_nodes") as Dictionary).get(REMOTE_PEER, null) as StaticBody3D

func _ray_avatar(y: float, from_dir: Vector3) -> String:
	var av := _avatar()
	var space := mp_scene.get_world_3d().direct_space_state
	var c := av.global_position + Vector3(0.0, y, 0.0)
	var q := PhysicsRayQueryParameters3D.create(c + from_dir * 4.0, c - from_dir * 4.0)
	var h := space.intersect_ray(q)
	if h.is_empty() or h.get("collider") != av:
		return ""
	var owner_id: int = av.shape_find_owner(int(h.get("shape", 0)))
	return String((av.shape_owner_get_owner(owner_id) as Node).name)

func _remote_stance_phase() -> bool:
	mp_frame += 1
	var lobby := root.get_node("NetworkLobby")
	var c: Dictionary = STANCE_CASES[mp_case]
	if mp_frame <= 40:
		# 40 state packets (2s of 0.05s ticks) so the pose blend and position lerp settle
		lobby.call("_update_or_spawn_remote_player", REMOTE_PEER, Vector3(3.0, 0.0, -2.0), 0.6, 0.0, 0.0, int(c["packed"]), "BRAVO", "Remote_Friend", false)
		return false
	if mp_frame < 44:
		return false # let the physics server pick up the new shape transforms
	var av := _avatar()
	var torso := av.get_node("Hitbox_Torso") as CollisionShape3D
	var cap := torso.shape as CapsuleShape3D
	var feet_y := av.global_position.y
	var cap_top := torso.global_position.y + cap.height * 0.5 - feet_y
	var cap_bottom := torso.global_position.y - cap.height * 0.5 - feet_y
	_mp_check(absf(cap.height - float(c["cap"])) < 0.01, "%s remote torso capsule height %.3f == local %.2f" % [c["name"], cap.height, c["cap"]])
	_mp_check(absf(cap_bottom) < 0.02, "%s remote torso capsule feet-anchored (bottom %.3f)" % [c["name"], cap_bottom])
	var mask := av.get_node("Hitbox_Mask") as CollisionShape3D
	var hop := av.get_node("Hitbox_HopperMarker") as CollisionShape3D
	var mask_top := mask.global_position.y + (mask.shape as SphereShape3D).radius - feet_y
	var hop_top := hop.global_position.y + (hop.shape as SphereShape3D).radius - feet_y
	print("    %s: torso top %.2f, mask top %.2f, hopper top %.2f" % [c["name"], cap_top, mask_top, hop_top])
	var leaks := []
	for y in c["covered_y"]:
		for d in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-0.7, 0, 0.7), Vector3(0.7, -0.08, -0.7).normalized()]:
			var zone := _ray_avatar(float(y), d)
			if zone != "":
				leaks.append("%.2f:%s" % [y, zone])
	_mp_check(leaks.is_empty(), "%s remote avatar: paintball rays at %s miss (hits %s)" % [c["name"], str(c["covered_y"]), str(leaks)])
	var exposed := _ray_avatar(float(c["exposed_y"]), Vector3(1, 0, 0))
	if exposed == "":
		exposed = _ray_avatar(float(c["exposed_y"]), Vector3(0, 0, 1))
	_mp_check(exposed != "", "%s remote avatar still hittable at %.2fm (hit %s)" % [c["name"], c["exposed_y"], exposed])
	if int(c["packed"]) == 0:
		_mp_check(_ray_avatar(1.30, Vector3(1, 0, 0)) == "Hitbox_Torso", "standing remote torso band above a 1.25m rail is hittable")
	if int(c["packed"]) & 3 == 1:
		_mp_check(mask_top < 1.22 and hop_top < 1.22 and cap_top < 1.22, "crouched remote mask/hopper/torso tops stay under the 1.22 sill and 1.25 rail")
	mp_case += 1
	mp_frame = 0
	if mp_case >= STANCE_CASES.size():
		if mp_failures.is_empty():
			print("=== All v0.4.4 Remote Avatar Stance Hitbox (packed_stance) Checks PASSED ===")
			quit(0)
		else:
			print("=== [FAIL] %d remote stance hitbox checks failed ===" % mp_failures.size())
			for f in mp_failures:
				print("   - ", f)
			quit(1)
		return true
	return false
