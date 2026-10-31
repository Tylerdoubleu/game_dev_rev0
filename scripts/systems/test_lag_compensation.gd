extends SceneTree
## v0.6.4 server lag compensation (PB-13 rewind): drives the NetworkLobby autoload as a dedicated server with
## synthetic peers, a measured ping/pong RTT and a 20 Hz moving victim, then checks that hits are validated against
## the victim's rewound pose (capped at REWIND_CAP_MS) and that bounced balls are traced.
## Run: godot --headless --path . -s res://scripts/systems/test_lag_compensation.gd
const PORT := 19292
var L: Node
var f := 0
var fails: Array[String] = []
var clock_ms: int = 5000000

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	L = root.get_node("NetworkLobby")
	L.start_dedicated_server(PORT)
	L.outbound_capture = []
	L.break_countdown_ms = 0
	L.match_countdown_ms = 0
	_check(L.ensure_collision_worlds() == 2, "collision worlds for both maps")
	_test_rtt_measurement()
	_test_history_buffer()
	_test_moving_target(100, "lobby_02")
	_test_moving_target(150, "lobby_03")
	_test_over_cap("lobby_04")
	_test_impossible_hits("lobby_05")
	_test_bounced_ball("lobby_06")
	print("=== [PASS] v0.6.4 lag compensation ===" if fails.is_empty() else "=== [FAIL] lag compensation: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true

## ---------------------------------------------------------------------------------------------------------------
func _set_clock(ms: int) -> void:
	clock_ms = ms
	L.rules_clock_override_ms = clock_ms

func _reg(pid: int, room: String) -> void:
	L._server_register_peer(pid, "P%d" % pid, "", "speedball", true, room)
	L._server_set_room_settings(pid, "speedball", "deathmatch") # geometry below is on the speedball map

func _state(pid: int, pos: Vector3, stance: int = 0) -> void:
	L._server_on_player_state(pid, pos, 0.0, 0.0, 0.0, stance, false)

func _alive(pid: int) -> bool:
	return bool(L.players[pid].get("alive", true))

func _rej(reason: String) -> int:
	return int(L.rejected_hits.get(reason, 0))

## One ping/pong round trip of rtt ms through the real server path (cl_net_ping out, srv_net_pong back).
func _ping(pid: int, rtt: int) -> void:
	L._net_ping_last_ms = -10000000
	L._tick_net_pings()
	var pend: Array = L.players[pid].get("ping_pending", [])
	var stamp := int(pend.back())
	_set_clock(clock_ms + rtt)
	L._server_on_net_pong(pid, stamp)

## Victim runs +x along z=-4 at 6 m/s (clear lane, see test_lobby_rooms) for 1 s, states at 20 Hz.
const RUN_FROM := Vector3(2, 0, -4)
const RUN_SPEED := 6.0
func _run(pid: int, t0: int) -> void:
	for i in 21:
		_set_clock(t0 + i * 50)
		_state(pid, RUN_FROM + Vector3(RUN_SPEED * i * 0.05, 0, 0))

func _pos_at(t0: int, t: int) -> Vector3:
	return RUN_FROM + Vector3(RUN_SPEED * clampf(float(t - t0) / 1000.0, 0.0, 1.0), 0, 0)

func _test_rtt_measurement() -> void:
	print("--- RTT ping/pong ---")
	_set_clock(clock_ms + 100000)
	_reg(1, "lobby_01")
	_check(int(L.rewind_window(L.players[1])["rtt_ms"]) == L.DEFAULT_RTT_MS, "default RTT before the first pong")
	(L.outbound_capture as Array).clear()
	L._net_ping_last_ms = -10000000
	L._tick_net_pings()
	var sent := (L.outbound_capture as Array).filter(func(m): return int(m["peer"]) == 1 and m["method"] == &"cl_net_ping")
	_check(sent.size() == 1, "cl_net_ping sent to the peer")
	_set_clock(clock_ms + 140)
	L._server_on_net_pong(1, int(sent[0]["args"][0]))
	_check(int(L.players[1]["rtt_ms"]) == 140, "first pong sets RTT (%s)" % L.players[1].get("rtt_ms"))
	L._server_on_net_pong(1, clock_ms - 1500)
	_check(int(L.players[1]["rtt_ms"]) == 140, "forged/unsent pong stamp ignored")
	L._server_on_net_pong(1, int(sent[0]["args"][0]))
	_check(int(L.players[1]["rtt_ms"]) == 140, "replayed pong stamp ignored")
	_ping(1, 60)
	_check(int(L.players[1]["rtt_ms"]) == 120, "EWMA smoothing 140 -> 120 after a 60 ms sample (%s)" % L.players[1]["rtt_ms"])
	_check(int(L.rewind_window({"rtt_ms": 120})["rewind_ms"]) == 195, "rewind = rtt + 75 ms interp")
	_check(int(L.rewind_window({"rtt_ms": 900})["rewind_ms"]) == L.REWIND_CAP_MS and L.REWIND_CAP_MS == 250, "rewind capped at 250 ms")

func _test_history_buffer() -> void:
	print("--- hitbox history ---")
	var h: Array = []
	for i in 40:
		h = L.append_hit_history(h, 1000 + i * 50, Vector3(i * 0.3, 0, 0), 0)
	_check(int(h.back()[0]) - int(h[0][0]) <= L.HIT_HISTORY_MS and int(h.back()[0]) - int(h[0][0]) >= 1000, "about 1 s of history kept (%d ms)" % (int(h.back()[0]) - int(h[0][0])))
	var poses: Array = L.history_poses_at(h, int(h.back()[0]) - 25)
	_check(poses[0][0].distance_to(Vector3(38.5 * 0.3, 0, 0)) < 0.001, "pose interpolated between samples")
	h = L.append_hit_history(h, int(h.back()[0]) + 50, Vector3(100, 0, 100), 0)
	_check(h.size() == 1, "teleport (respawn) clears the history")

func _test_moving_target(rtt: int, room: String) -> void:
	print("--- moving target, %d ms RTT ---" % rtt)
	var s := 10 + rtt
	var v := s + 1
	_set_clock(clock_ms + 100000)
	_reg(s, room)
	_reg(v, room)
	var spos := Vector3(5, 0, 8)
	_state(s, spos)
	_ping(s, rtt)
	var t0 := clock_ms + 10
	_run(v, t0)
	var now := t0 + 1000
	# The shooter's screen showed the victim rtt + 75 ms in the past; the client fires at that pose.
	var seen := _pos_at(t0, now - rtt - L.REMOTE_INTERP_DELAY_MS)
	var hit := seen + Vector3(0, 1.2, 0)
	_check(not L.point_in_stance_box(hit, _pos_at(t0, now), 0), "hit is %.2f m behind the victim's latest pose (unrewound check would reject)" % (_pos_at(t0, now).x - seen.x))
	_set_clock(now - 40)
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (hit - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	_set_clock(now)
	var verdict: Dictionary = L._server_validate_hit(s, v, hit)
	_check(bool(verdict.get("ok")) and int(verdict["rewind_ms"]) == rtt + 75 and verdict["los"] == "clear", "rewound hit accepted (%s)" % [verdict])
	L._server_on_hit_report(s, v, hit)
	_check(not _alive(v), "victim eliminated")

func _test_over_cap(room: String) -> void:
	print("--- over-cap latency ---")
	var s := 401
	var v := 402
	_set_clock(clock_ms + 100000)
	_reg(s, room)
	_reg(v, room)
	var spos := Vector3(5, 0, 8)
	_state(s, spos)
	_ping(s, 600)
	_check(int(L.players[s]["rtt_ms"]) == 600 and int(L.rewind_window(L.players[s])["rewind_ms"]) == 250, "600 ms RTT measured, rewind capped at 250")
	var t0 := clock_ms + 10
	_run(v, t0)
	var now := t0 + 1000
	var hit := _pos_at(t0, now - 600 - 75) + Vector3(0, 1.2, 0)
	_set_clock(now - 40)
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (hit - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	_set_clock(now)
	var before := _rej("outside_hitbox")
	L._server_on_hit_report(s, v, hit)
	_check(_alive(v) and _rej("outside_hitbox") == before + 1, "hit on the 675 ms-old pose rejected (outside_hitbox)")
	# Inside the cap the same high-ping shooter still gets the full 250 ms.
	var ok_hit := _pos_at(t0, now - 250) + Vector3(0, 1.2, 0)
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (ok_hit - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	L._server_on_hit_report(s, v, ok_hit)
	_check(not _alive(v), "hit on the 250 ms-old pose accepted for the capped shooter (%s)" % [L.rejected_hits])

func _test_impossible_hits(room: String) -> void:
	print("--- impossible hits ---")
	var s := 501
	var v := 502
	_set_clock(clock_ms + 100000)
	_reg(s, room)
	_reg(v, room)
	var spos := Vector3(5, 0, 8)
	_state(s, spos)
	_ping(s, 20)
	var t0 := clock_ms + 10
	_run(v, t0)
	var now := t0 + 1000
	# A 20 ms player claiming a pose from 600 ms ago (rewind is 95 ms): rejected.
	var stale := _pos_at(t0, now - 600) + Vector3(0, 1.2, 0)
	_set_clock(now - 40)
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (stale - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	_set_clock(now)
	var before := _rej("outside_hitbox")
	L._server_on_hit_report(s, v, stale)
	_check(_alive(v) and _rej("outside_hitbox") == before + 1, "low-ping shooter can't claim a 600 ms-old pose")
	# A point the victim never occupied (2 m off the run line).
	var off := _pos_at(t0, now - 95) + Vector3(0, 1.2, 2.0)
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (off - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	L._server_on_hit_report(s, v, off)
	_check(_alive(v) and _rej("outside_hitbox") == before + 2, "hit where the victim never was rejected")
	# Shot fired nowhere near the victim, not explainable by a bounce either.
	var real := _pos_at(t0, now - 95) + Vector3(0, 1.2, 0)
	var aim_before := _rej("aim_mismatch")
	L.players[s]["shots"] = []
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), Vector3(1, 0, 0), 290.0)
	L._server_on_hit_report(s, v, real)
	_check(_alive(v) and _rej("aim_mismatch") == aim_before + 1, "hit 90 deg off the only shot rejected (aim_mismatch)")
	# The same pose with a proper shot is fine (sanity: the victim is hittable).
	L._server_on_fire(s, spos + Vector3(0, 1.4, 0), (real - spos - Vector3(0, 1.4, 0)).normalized(), 290.0)
	L._server_on_hit_report(s, v, real)
	_check(not _alive(v), "proper rewound hit on the same victim accepted (%s)" % [L.rejected_hits])

## Shooter aims at the turf 4 m ahead; the ball skips (|cos| 0.34 < 0.42) and rises through ~1.5 m at z = -0.4.
func _test_bounced_ball(room: String) -> void:
	print("--- bounced ball ---")
	var s := 601
	var v := 602
	_set_clock(clock_ms + 100000)
	_reg(s, room)
	_reg(v, room)
	var spos := Vector3(5, 0, 8)
	var muzzle := spos + Vector3(0, 1.4, 0)
	var dir := (Vector3(5, 0, 4) - muzzle).normalized()
	_state(s, spos)
	_ping(s, 80)
	var hit := Vector3(5, 1.48, -0.38)
	var vpos := Vector3(5, 0, -0.38)
	_state(v, vpos)
	_check(L.rooms[room]["settings"]["map"] == "speedball", "room on the speedball map")
	_check(rad_to_deg(dir.angle_to((hit - muzzle).normalized())) > 12.0, "hit is outside the 12 deg direct-aim cone")
	var status: String = L.bounce_path_status("speedball", muzzle, dir, 290.0, hit)
	_check(status == "bounce", "server trace finds the skip (%s)" % status)
	var miss: String = L.bounce_path_status("speedball", muzzle, dir, 290.0, Vector3(7.5, 1.48, -0.38))
	_check(miss == "none", "point 2.5 m off the skip path not on the bounce (%s)" % miss)
	var steep: String = L.bounce_path_status("speedball", muzzle, (Vector3(5, 0, 7) - muzzle).normalized(), 290.0, hit)
	_check(steep != "bounce", "steep shot into the turf doesn't skip (%s)" % steep)
	_set_clock(clock_ms + 60)
	L._server_on_fire(s, muzzle, dir, 290.0)
	_set_clock(clock_ms + 40)
	# A hit 2.5 m to the side of the skip is still rejected.
	var verdict: Dictionary = L._server_validate_hit(s, v, Vector3(7.5, 1.48, -0.38))
	_check(not bool(verdict.get("ok")) and verdict.get("reason") == "aim_mismatch", "off-path hit rejected (%s)" % [verdict])
	verdict = L._server_validate_hit(s, v, hit)
	_check(bool(verdict.get("ok")) and verdict["los"] == "bounce", "bounced hit accepted (%s)" % [verdict])
	L._server_on_hit_report(s, v, hit)
	_check(not _alive(v), "victim eliminated by the bounced ball")
