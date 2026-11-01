extends SceneTree
## v0.7 batched snapshots: drives the NetworkLobby autoload as a dedicated server with synthetic peers sending
## srv_player_state at 20 Hz, then checks (1) one cl_snapshot per room at ~20 Hz, even with uneven server frames,
## (2) room isolation (only that room's peers, only that room's players, solo rooms get nothing, no per-player
## relay), (3) the entry contents (pose, age, velocity, eliminated), (4) client interpolation ~100 ms behind is
## smooth under 100 ms of delivery jitter, extrapolates through a short gap and snaps (never glides) on a respawn,
## and (5) the lag-comp rewind uses the same 100 ms delay.
## Run: godot --headless --path . -s res://scripts/systems/test_snapshot_sync.gd
const PORT := 19298
const Interp = preload("res://scripts/systems/snapshot_interpolator.gd")
var L: Node
var f := 0
var fails: Array[String] = []
var clock := 7000000
var rng := RandomNumberGenerator.new()

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	rng.seed = 7
	L = root.get_node("NetworkLobby")
	L.start_dedicated_server(PORT)
	L.break_countdown_ms = 0
	L.match_countdown_ms = 0
	L.rules_clock_override_ms = clock
	L._net_ping_last_ms = clock + 100000000 # no pings in the captures
	_test_constants()
	_test_rate_and_isolation()
	_test_entry_contents()
	_test_interpolation_jitter(0, "no jitter")
	_test_interpolation_jitter(100, "100 ms jitter")
	_test_gap_extrapolation()
	_test_teleport_snaps()
	print("=== [PASS] v0.7 batched snapshots ===" if fails.is_empty() else "=== [FAIL] batched snapshots: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true

func _clock_to(ms: int) -> void:
	clock = ms
	L.rules_clock_override_ms = ms

func _state(pid: int, pos: Vector3, yaw: float = 0.0, stance: int = 0, elim: bool = false) -> void:
	L._server_on_player_state(pid, pos, yaw, 0.1, 0.0, stance, elim)

## Runs the server for ms of rules clock: each pid in movers sends a state every 50 ms (pos from path_fn(pid, t)),
## server frames are frame_ms long (+ up to frame_jitter ms). Returns nothing; read L.outbound_capture.
func _run(pids: Array, ms: int, path_fn: Callable, frame_ms: int = 16, frame_jitter: int = 0) -> void:
	var start := clock
	var next := {}
	for i in pids.size():
		next[pids[i]] = start + (i * 13) % 50
	while clock < start + ms:
		_clock_to(clock + frame_ms + (rng.randi_range(0, frame_jitter) if frame_jitter > 0 else 0))
		for p in pids:
			while int(next[p]) <= clock:
				_set_tmp(int(next[p]))
				_state(p, path_fn.call(p, int(next[p])))
				_set_tmp(clock)
				next[p] = int(next[p]) + 50
		L._server_tick(float(frame_ms) / 1000.0)

func _set_tmp(ms: int) -> void:
	L.rules_clock_override_ms = ms

func _snaps_to(pid: int) -> Array:
	var out: Array = []
	for m in L.outbound_capture:
		if int(m["peer"]) == pid and m["method"] == "cl_snapshot":
			out.append(m["args"])
	return out

func _ids(args: Array) -> Array:
	var ints: PackedInt32Array = args[2]
	var r: Array = []
	for i in ints.size() / L.SNAP_INTS:
		r.append(ints[i * L.SNAP_INTS])
	r.sort()
	return r

## ---------------------------------------------------------------------------------------------------------------
func _test_constants() -> void:
	print("constants")
	_check(L.REMOTE_INTERP_DELAY_MS == 100 and Interp.INTERP_DELAY_MS == L.REMOTE_INTERP_DELAY_MS, "client interpolation delay = lag-comp delay = 100 ms")
	_check(int(L.rewind_window({"rtt_ms": 120})["rewind_ms"]) == 220, "rewind = rtt + 100 ms interp (120 -> 220)")
	_check(int(L.rewind_window({"rtt_ms": 400})["rewind_ms"]) == 250, "rewind still capped at 250 ms")
	_check(L.SNAPSHOT_INTERVAL_MS == 50, "snapshot interval 50 ms (20 Hz)")

func _test_rate_and_isolation() -> void:
	print("rate + room isolation")
	for p in [201, 202, 203]:
		L._server_register_peer(p, "A%d" % p, "", "speedball", true, "lobby_01")
	for p in [211, 212]:
		L._server_register_peer(p, "B%d" % p, "", "speedball", true, "lobby_02")
	L._server_register_peer(221, "SOLO", "", "speedball", true, "lobby_03")
	var all := [201, 202, 203, 211, 212, 221]
	var circle := func(p: int, t: int) -> Vector3:
		var a := float(t) / 1000.0 + p
		return Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0)
	_run(all, 500, circle) # warm up: everyone has a state
	for variant in [[16, 0, "60 fps server"], [10, 40, "uneven 10-50 ms server frames"]]:
		L.outbound_capture = []
		var t0 := clock
		_run(all, 4000, circle, int(variant[0]), int(variant[1]))
		var secs := float(clock - t0) / 1000.0
		var a := _snaps_to(201)
		var b := _snaps_to(211)
		var hz_a := a.size() / secs
		var hz_b := b.size() / secs
		_check(hz_a >= 19.0 and hz_a <= 21.0 and hz_b >= 19.0 and hz_b <= 21.0, "%s: %.2f Hz to room A, %.2f Hz to room B (~20)" % [variant[2], hz_a, hz_b])
		var ticks_ok := true
		var gaps: Array = []
		for i in range(1, a.size()):
			ticks_ok = ticks_ok and int(a[i][0]) == int(a[i - 1][0]) + 1
			gaps.append(int(a[i][1]) - int(a[i - 1][1]))
		var mean_gap := 0.0
		for g in gaps:
			mean_gap += g
		mean_gap /= maxf(1.0, gaps.size())
		_check(ticks_ok and absf(mean_gap - 50.0) < 1.5, "%s: ticks consecutive, mean server_ms spacing %.1f ms" % [variant[2], mean_gap])
		var per_state := 0
		var iso_ok := true
		var one_per_tick := true
		for m in L.outbound_capture:
			if m["method"] == "rpc_sync_player_state":
				per_state += 1
			if m["method"] != "cl_snapshot":
				continue
			var to := int(m["peer"])
			var ids := _ids(m["args"])
			if to in [201, 202, 203]:
				iso_ok = iso_ok and ids == [201, 202, 203]
			elif to in [211, 212]:
				iso_ok = iso_ok and ids == [211, 212]
			else:
				iso_ok = false
		for p in [202, 203]:
			one_per_tick = one_per_tick and _snaps_to(p).size() == a.size()
		_check(per_state == 0, "%s: no per-player rpc_sync_player_state relay any more" % variant[2])
		_check(iso_ok, "%s: each room's snapshot goes only to its peers and holds only its players" % variant[2])
		_check(_snaps_to(221).is_empty(), "%s: a solo room gets no snapshots" % variant[2])
		_check(one_per_tick and a[0] == _snaps_to(202)[0], "%s: one shared snapshot per room tick (same packet to each peer)" % variant[2])
	# A peer that moves rooms leaves the old room's snapshot at once.
	L._server_register_peer(203, "A203", "", "speedball", true, "lobby_02")
	L.outbound_capture = []
	_run(all, 300, circle)
	var last_a: Array = _snaps_to(201)
	var last_b: Array = _snaps_to(212)
	_check(not last_a.is_empty() and _ids(last_a[last_a.size() - 1]) == [201, 202] and _ids(last_b[last_b.size() - 1]) == [203, 211, 212], "room switch: the mover leaves room A's snapshot and joins room B's")
	for p in all:
		L._server_remove_peer(p)

func _test_entry_contents() -> void:
	print("entry contents")
	L._server_register_peer(301, "VIC", "", "speedball", true, "lobby_04")
	L._server_register_peer(302, "OBS", "", "speedball", true, "lobby_04")
	var line := func(p: int, t: int) -> Vector3:
		return Vector3(6.0 * float(t - 7000000) / 1000.0, 0.0, 3.0) if p == 301 else Vector3(0, 0, -5)
	_run([301, 302], 600, line)
	L.outbound_capture = []
	_run([301, 302], 60, line)
	var s: Array = _snaps_to(302)
	var args: Array = s[s.size() - 1]
	var ints: PackedInt32Array = args[2]
	var fl: PackedFloat32Array = args[3]
	var i: int = ints.find(301) / L.SNAP_INTS if ints.find(301) % L.SNAP_INTS == 0 else 0
	var st: Dictionary = L.players[301]["state"]
	var o: int = i * L.SNAP_FLOATS
	_check(Vector3(fl[o], fl[o + 1], fl[o + 2]).distance_to(st["pos"]) < 0.001 and absf(fl[o + 4] - 0.1) < 0.001, "entry = the latest received pose (pos, pitch)")
	_check(int(args[1]) - ints[i * L.SNAP_INTS + 1] == int(st["t"]), "server_ms - age_ms = the state's receive stamp (the hit-history clock)")
	_check(absf(fl[o + 6] - 6.0) < 0.05 and absf(fl[o + 8]) < 0.05, "velocity from history: (%.2f, %.2f, %.2f) for a 6 m/s run along x" % [fl[o + 6], fl[o + 7], fl[o + 8]])
	_check(ints[i * L.SNAP_INTS + 3] == 0, "alive: eliminated flag clear")
	L.players[301]["alive"] = false
	L.players[301]["dead_since_ms"] = clock # practice respawn is 1 s away
	L.outbound_capture = []
	_run([302], 60, line)
	s = _snaps_to(302)
	ints = s[s.size() - 1][2]
	i = ints.find(301) / L.SNAP_INTS
	_check(ints[i * L.SNAP_INTS + 3] & L.SNAP_FLAG_ELIMINATED != 0, "server-side elimination is flagged even without a new state")
	_check(L.history_velocity([[0, Vector3.ZERO, 0], [400, Vector3(1, 0, 0), 0]]) == Vector3.ZERO, "no velocity across a >250 ms gap")

## ---------------------------------------------------------------------------------------------------------------
## Client side. Builds real snapshots from the server for a victim running a curve at 6 m/s, delivers them in order
## with 30 + [0, jitter] ms latency to L.client_apply_snapshot (local clock = server clock + 12345), and renders at
## 60 fps. Returns {"max_step", "nominal", "max_err", "extrap_frames", "frames", "rendered": [[local, pos]...]}.
func _client_run(rid: String, victim: int, path_fn: Callable, ms: int, jitter: int, drop: Callable = Callable()) -> Dictionary:
	L._server_register_peer(victim, "RUN", "", "speedball", true, rid)
	L._server_register_peer(victim + 1, "ME", "", "speedball", true, rid)
	L.remote_snapshots.clear()
	L.outbound_capture = []
	var t0 := clock
	_run([victim, victim + 1], ms, path_fn)
	var deliveries: Array = []
	var last_arrival := 0
	for args in _snaps_to(victim + 1):
		if drop.is_valid() and drop.call(int(args[1]) - t0):
			continue
		var arrival := maxi(last_arrival, int(args[1]) + 30 + (rng.randi_range(0, jitter) if jitter > 0 else 0))
		last_arrival = arrival
		deliveries.append([arrival + 12345, args])
	var di := 0
	var res := {"max_step": 0.0, "max_err": 0.0, "extrap_frames": 0, "frames": 0, "rendered": []}
	var prev := Vector3.INF
	var lt := t0 + 12345 + 300
	var dt := 1.0 / 60.0
	while lt < t0 + 12345 + ms - 50:
		lt = t0 + 12345 + 300 + int(res["frames"] * 1000.0 / 60.0)
		while di < deliveries.size() and int(deliveries[di][0]) <= lt:
			var a: Array = deliveries[di][1]
			L.client_apply_snapshot(int(a[0]), int(a[1]), a[2], a[3], int(deliveries[di][0]))
			di += 1
		res["frames"] += 1
		var s: Dictionary = L.remote_snapshots.sample(victim, lt, dt)
		if s.is_empty():
			continue
		var p: Vector3 = s["pos"]
		if bool(s["extrapolated"]):
			res["extrap_frames"] += 1
		if prev != Vector3.INF:
			res["max_step"] = maxf(res["max_step"], p.distance_to(prev))
		prev = p
		# Truth at the render time (server clock = local - 12345, 100 ms behind), as the server history has it.
		var truth: Vector3 = path_fn.call(victim, int(L.remote_snapshots.render_time(lt)))
		res["max_err"] = maxf(res["max_err"], p.distance_to(truth))
		res["rendered"].append([lt, p])
	res["nominal"] = 6.0 * dt
	L._server_remove_peer(victim)
	L._server_remove_peer(victim + 1)
	return res

var _base := 0
func _curve(_p: int, t: int) -> Vector3:
	var a := float(t - _base) / 1000.0 * 6.0 / 8.0 # 6 m/s on an 8 m radius
	return Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0)

func _test_interpolation_jitter(jitter: int, label: String) -> void:
	print("interpolation, %s" % label)
	_base = clock
	var r := _client_run("lobby_%02d" % (5 + jitter / 50), 401 + jitter, Callable(self, "_curve"), 6000, jitter)
	print("    frames=%d max_step=%.3f m (nominal %.3f) max_err=%.3f m extrapolated=%d" % [r["frames"], r["max_step"], r["nominal"], r["max_err"], r["extrap_frames"]])
	_check(float(r["max_step"]) <= float(r["nominal"]) * 1.6 + 0.01, "%s: no snapping (max per-frame step %.3f m vs %.3f m at 6 m/s)" % [label, r["max_step"], r["nominal"]])
	_check(float(r["max_err"]) <= (0.12 if jitter == 0 else 0.35), "%s: within %.2f m of the true path 100 ms back" % [label, r["max_err"]])
	_check(int(r["extrap_frames"]) <= int(r["frames"]) / 20, "%s: the 100 ms buffer covers the jitter (%d/%d frames extrapolated)" % [label, r["extrap_frames"], r["frames"]])

func _straight(_p: int, t: int) -> Vector3:
	var x := float(t - _base) / 1000.0 * 6.0
	if t - _base > 2500: # turns 90 degrees during the gap
		return Vector3(15.0, 0.0, float(t - _base - 2500) / 1000.0 * 6.0)
	return Vector3(x, 0.0, 0.0)

func _test_gap_extrapolation() -> void:
	print("short gap")
	_base = clock
	var gap := func(ms: int) -> bool: return ms >= 2300 and ms < 2550 # 5 snapshots lost (250 ms), the turn inside
	var r := _client_run("lobby_09", 501, Callable(self, "_straight"), 4500, 20, gap)
	print("    frames=%d max_step=%.3f m max_err=%.3f m extrapolated=%d" % [r["frames"], r["max_step"], r["max_err"], r["extrap_frames"]])
	_check(int(r["extrap_frames"]) >= 5, "gap: extrapolates along the velocity (%d frames)" % r["extrap_frames"])
	_check(float(r["max_step"]) <= float(r["nominal"]) * 3.0, "gap: recovery is blended, no snap (max step %.3f m)" % r["max_step"])
	# Long gap: extrapolation stops after EXTRAPOLATE_MAX_MS and holds.
	var it = Interp.new()
	it.note_server_time(1000, 1000)
	it.push(9, 900, {"pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "lean": 0.0, "stance": 0, "vel": Vector3(6, 0, 0), "elim": false})
	var far: Vector3 = it.pose_at(9, 900.0 + 600.0)["pos"]
	_check(absf(far.x - 6.0 * Interp.EXTRAPOLATE_MAX_MS / 1000.0) < 0.001, "long gap: extrapolation capped at %d ms then held (x=%.2f)" % [Interp.EXTRAPOLATE_MAX_MS, far.x])

func _respawn(_p: int, t: int) -> Vector3:
	return Vector3(float(t - _base) / 1000.0 * 3.0, 0.0, 0.0) if t - _base < 1500 else Vector3(0.0, 0.0, 40.0)

func _test_teleport_snaps() -> void:
	print("respawn")
	_base = clock
	var r := _client_run("lobby_10", 601, Callable(self, "_respawn"), 3000, 50)
	var mid := 0
	for e in r["rendered"]:
		var p: Vector3 = e[1]
		if p.z > 2.0 and p.z < 38.0:
			mid += 1
	_check(mid == 0, "respawn: snaps to the new spot, never glides across the field (%d mid-way frames)" % mid)
