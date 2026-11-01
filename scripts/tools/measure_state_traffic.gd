extends SceneTree
## v0.7 traffic probe: drives the NetworkLobby autoload as a dedicated server with synthetic peers that each send
## srv_player_state at 20 Hz (the client rate, PlayerController3D._net_sync_timer 0.05 s) for SIM_MS of rules clock,
## ticking the server at ~60 fps, then prints the server -> client messages/s and an estimated bandwidth per client.
## Bytes are an upper-bound estimate: var_to_bytes(args) + 4 B RPC header + 2-4 B WebSocket frame header.
## Run: godot --headless --path . -s res://scripts/tools/measure_state_traffic.gd
const PORT := 19297
const SIM_MS := 5000
const ROOMS := {"lobby_01": 10, "lobby_02": 4}
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var L: Node = root.get_node("NetworkLobby")
	L.start_dedicated_server(PORT)
	L.break_countdown_ms = 0
	L.match_countdown_ms = 0
	var clock := 9000000
	L.rules_clock_override_ms = clock
	var pid := 100
	var pids: Array = []
	for rid in ROOMS.keys():
		for i in int(ROOMS[rid]):
			pid += 1
			L._server_register_peer(pid, "P%d" % pid, "ALPHA" if i % 2 == 0 else "BRAVO", "speedball", true, rid)
			pids.append(pid)
	L._net_ping_last_ms = clock + 100000 # keep pings out of the window
	L.outbound_capture = []
	var next_state := {}
	for i in pids.size():
		next_state[pids[i]] = clock + (i * 7) % 50
	var t := clock
	var end := clock + SIM_MS
	var step := 0
	while t < end:
		step += 1
		t = clock + int(step * 1000.0 / 60.0)
		L.rules_clock_override_ms = t
		for p in pids:
			while int(next_state[p]) <= t:
				var a := float(int(next_state[p]) - clock) / 1000.0
				L._server_on_player_state(p, Vector3(sin(a + p) * 10.0, 0.0, cos(a + p) * 10.0), a, 0.0, 0.0, 0, false)
				next_state[p] = int(next_state[p]) + 50
		L._server_tick(1.0 / 60.0)
	var per_peer := {}
	for m in L.outbound_capture:
		var key := int(m["peer"])
		var e: Dictionary = per_peer.get(key, {"msgs": 0, "bytes": 0, "methods": {}})
		var b := 4
		for a in m["args"]:
			b += var_to_bytes(a).size()
		b += 2 if b < 126 else 4
		e["msgs"] += 1
		e["bytes"] += b
		e["methods"][m["method"]] = int(e["methods"].get(m["method"], 0)) + 1
		per_peer[key] = e
	var secs := SIM_MS / 1000.0
	for rid in ROOMS.keys():
		var sample_pid := 0
		for p in pids:
			if String(L.peer_room.get(p, "")) == rid:
				sample_pid = p
				break
		var e: Dictionary = per_peer.get(sample_pid, {"msgs": 0, "bytes": 0, "methods": {}})
		print("TRAFFIC room=%s players=%d  per client: %.1f msg/s, %.0f B/s (%.1f kbit/s)  methods=%s" % [rid, int(ROOMS[rid]), e["msgs"] / secs, e["bytes"] / secs, e["bytes"] * 8.0 / secs / 1000.0, e["methods"]])
	quit(0)
	return true
