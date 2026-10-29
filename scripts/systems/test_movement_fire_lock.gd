extends SceneTree
## v0.4.5 movement fire lock: no shooting during the Shift+Q knee-slide or the Shift+C Superman dive, plus a 0.15s
## trigger recovery afterwards. Checks the local PlayerController3D (zero paintballs, zero paint, no rate state,
## one HUD hint, signal/progress API for the viewmodel) and the network receive path (NetworkLobby rejects
## rpc_fire_paintball from a peer whose packed_stance has bit 16 / bit 32 set, or that cleared it < 0.10s ago).
## Run: godot --headless --path . -s scripts/systems/test_movement_fire_lock.gd

var arena: Node
var player: CharacterBody3D
var lobby: Node
var balls: Node
var frame := 0
var phase := 0
var phase_start := 0
var failures: Array[String] = []
var banners: Array[String] = []
var lock_events: Array = []
# per-move bookkeeping
var move_name := ""
var snap := {}
var move_end_frame := -1
var unlock_frame := -1
var reasons_seen := {}
var progress_samples: Array[float] = []
var shots_while_locked := 0

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _find_player(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.has_method("is_fire_locked_by_movement"):
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p != null:
			return p
	return null

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _spawned() -> int:
	return int(balls.get("total_spawned"))

func _snapshot() -> Dictionary:
	return {"spawned": _spawned(), "hopper": int(player.get("hopper_paint")), "shots": int(player.get("_shot_counter")), "blocked": int(player.get("movement_blocked_trigger_pulls"))}

func _pull() -> void:
	player.call("_handle_trigger_press", false)

func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.set("yaw", yaw)
	player.velocity = Vector3.ZERO
	player.set("bunker_pocket_weight", 0.0)

func _release_all() -> void:
	for a in ["crouch_slide", "prone_dive", "move_forward", "sprint"]:
		Input.action_release(a)

func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		root.get_node("NetworkLobby").call("select_map", "woodsball_crash")
		player = _find_player(arena)
		lobby = root.get_node("NetworkLobby")
		balls = root.get_node("PaintBallistics")
		root.get_node("GearRuleEnforcer").call("set_active_bracket", "speedball")
		player.connect("status_banner_sent", func(m: String, _c: Color): banners.append(m))
		player.connect("movement_fire_lock_changed", func(l: bool, r: String): lock_events.append([l, r, frame]))
	elif frame == 10:
		_place(Vector3(-0.3, 0.1, 6.0), PI)
		player.set("hopper_paint", 120)
		player.set("time_since_last_shot", 10.0)
		var s0 := _snapshot()
		_pull()
		var s1 := _snapshot()
		_check(s1["spawned"] == s0["spawned"] + 1 and s1["hopper"] == s0["hopper"] - 1, "Baseline: standing trigger pull fires one paintball and uses one paint")
		_check(not bool(player.call("is_fire_locked_by_movement")) and String(player.call("get_fire_lock_reason")) == "", "Not locked while standing")
		_begin_move("slide")
	elif phase == 1:
		_run_move()
	elif phase == 2:
		if frame - phase_start == 20:
			_place(Vector3(-0.3, 0.1, 6.0), PI)
			_begin_move("dive")
	elif phase == 3:
		_network_checks()
	return false

func _begin_move(n: String) -> void:
	move_name = n
	phase = 1
	phase_start = frame
	move_end_frame = -1
	unlock_frame = -1
	reasons_seen = {}
	progress_samples.clear()
	shots_while_locked = 0
	banners.clear()
	lock_events.clear()
	player.set("time_since_last_shot", 10.0)
	Input.action_press("move_forward")
	Input.action_press("sprint")

func _run_move() -> void:
	var t := frame - phase_start
	if t == 12:
		snap = _snapshot()
		Input.action_press("crouch_slide" if move_name == "slide" else "prone_dive")
		return
	if t < 13:
		return
	var timer_name := "slide_timer" if move_name == "slide" else "dive_timer"
	var active: bool = float(player.get(timer_name)) > 0.0
	var locked: bool = bool(player.call("is_fire_locked_by_movement"))
	if t == 14:
		_check(active, "%s started (%s %.2f)" % [move_name, timer_name, float(player.get(timer_name))])
	if locked:
		reasons_seen[String(player.call("get_fire_lock_reason"))] = true
		progress_samples.append(float(player.call("get_movement_fire_lock_progress")))
		# hammer the trigger every frame, as a held/mashed trigger would
		var before := _spawned()
		_pull()
		player.set("time_since_last_shot", 10.0) # rate limiter can never be the reason a shot is blocked
		if _spawned() != before:
			shots_while_locked += 1
	if not active and move_end_frame < 0 and t > 14:
		move_end_frame = frame
	if not locked and t > 14 and unlock_frame < 0:
		unlock_frame = frame
		var s := _snapshot()
		_check(shots_while_locked == 0 and s["spawned"] == snap["spawned"], "%s: holding/mashing fire spawned %d paintballs (expected 0)" % [move_name, s["spawned"] - snap["spawned"]])
		_check(s["hopper"] == snap["hopper"], "%s: hopper paint unchanged (%d -> %d)" % [move_name, snap["hopper"], s["hopper"]])
		_check(s["shots"] == snap["shots"], "%s: shot counter / bolt & recoil state unchanged" % move_name)
		_check(s["blocked"] - snap["blocked"] >= 20, "%s: %d trigger pulls were blocked" % [move_name, s["blocked"] - snap["blocked"]])
		var rec_s := float(unlock_frame - move_end_frame) / float(Engine.physics_ticks_per_second)
		_check(rec_s >= 0.12 and rec_s <= 0.2, "%s: post-move recovery %.3fs (~0.15s)" % [move_name, rec_s])
		_check(reasons_seen.keys() == [move_name], "%s: get_fire_lock_reason() reported %s" % [move_name, str(reasons_seen.keys())])
		var mono := true
		for i in range(1, progress_samples.size()):
			if progress_samples[i] > progress_samples[i - 1] + 0.0001:
				mono = false
		_check(progress_samples.size() > 0 and progress_samples[0] == 1.0 and mono, "%s: lock progress holds 1.0 then decays monotonically" % move_name)
		var expect_banner := "SLIDING - CAN'T SHOOT" if move_name == "slide" else "DIVING - CAN'T SHOOT"
		_check(banners.count(expect_banner) == 1, "%s: one '%s' HUD hint (no spam), banners %s" % [move_name, expect_banner, str(banners)])
		var lock_on := lock_events.filter(func(e): return e[0] == true and e[1] == move_name).size()
		var lock_off := lock_events.filter(func(e): return e[0] == false).size()
		_check(lock_on == 1 and lock_off == 1, "%s: movement_fire_lock_changed emitted lock(%s)/unlock once each %s" % [move_name, move_name, str(lock_events)])
		# Trigger still physically held: no buffered/auto shot appears on unlock
		_check(_spawned() == s["spawned"], "%s: no buffered shot fires on unlock" % move_name)
		_release_all()
		# next trigger pull fires normally
		player.set("time_since_last_shot", 10.0)
		_pull()
		var s2 := _snapshot()
		_check(s2["spawned"] == s["spawned"] + 1 and s2["hopper"] == s["hopper"] - 1, "%s: next trigger pull after recovery fires normally" % move_name)
		if move_name == "slide":
			phase = 2
			phase_start = frame
		else:
			phase = 3
			phase_start = frame
	elif t > 400:
		_check(false, "%s: lock never released" % move_name)
		_finish()

const NET_PEER := 4243
func _net_update(stance_bits: int) -> void:
	lobby.call("_update_or_spawn_remote_player", NET_PEER, Vector3(4.0, 0.0, 12.0), 0.0, 0.0, 0.0, stance_bits, "BRAVO", "Cheaty_McSlide", false)

func _net_fire() -> bool:
	var before := _spawned()
	lobby.call("rpc_fire_paintball", Vector3(4.0, 1.4, 12.0), Vector3(0, 0, -1), 280.0, NET_PEER)
	return _spawned() > before

func _network_checks() -> void:
	var t := frame - phase_start
	if t == 1:
		_net_update(0)
		_check(_net_fire(), "Network: remote peer standing -> relayed shot accepted")
		var rej0 := int(lobby.get("rejected_movement_lock_shots"))
		_net_update(16 | 1)
		_check(not _net_fire(), "Network: packed_stance bit 16 (knee-slide) -> relayed shot rejected")
		_net_update(32 | 2)
		_check(not _net_fire(), "Network: packed_stance bit 32 (Superman dive) -> relayed shot rejected")
		_net_update(2)
		_check(not _net_fire(), "Network: shot right after the dive bit clears is rejected (recovery)")
		_check(int(lobby.get("rejected_movement_lock_shots")) - rej0 == 3, "Network: 3 rejected shots counted")
		_check(not bool(lobby.call("is_remote_fire_allowed", NET_PEER)), "Network: is_remote_fire_allowed false during recovery")
	elif t == 10:
		_check(_net_fire(), "Network: after the 0.10s remote recovery the peer can fire again")
		_net_update(1 | 8 | 4)
		_check(_net_fire(), "Network: crouched + tucked + left-handed bits do not block firing")
		var before := _spawned()
		lobby.call("rpc_fire_paintball", Vector3(4.0, 1.4, 12.0), Vector3(0, 0, -1), 280.0, 777777)
		_check(_spawned() == before + 1, "Network: unknown peer (no state yet) is not blocked")
		_finish()

func _finish() -> void:
	if failures.is_empty():
		print("=== [PASS] v0.4.5 knee-slide & Superman-dive fire lock (local + network receive) ===")
		quit(0)
	else:
		print("=== [FAIL] %d movement fire-lock checks failed ===" % failures.size())
		for f in failures:
			print("   - ", f)
		quit(1)
