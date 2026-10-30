extends SceneTree
## v0.6.1/v0.6.2 mouse capture (web Pointer Lock): MouseCaptureGuard is the one authority.
## v0.6.2: spectating and the [M] scoreboard want capture (lock lost -> CLICK TO RESUME, the click neither fires nor
## cycles spectate); spectate -> next round keeps the lock; only the TAB/Esc menu, lobby browser, waiting room, respawn
## map and match end free the cursor; lobby_open / awaiting_respawn_choice / spectating are cleared on respawn,
## round_started, returned_to_lobby and a waiting-room match start (mouse look works afterwards).
## Covers: capture_policy() / wants_capture() per state, a capture outside a user gesture being refused (browser-like
## simulated backend) -> CLICK TO RESUME overlay, the resume click re-capturing without firing, any key re-capturing,
## menu keys not re-capturing, focus out/in, the browser dropping the lock, and every overlay (TAB/Esc menu, lobby
## browser + waiting room, respawn map, scoreboard, match end, spectate, recap intermission, break) restoring capture
## when it closes; set_lobby_open_state / respawn_at_map_zone routed through the guard.
## Run: godot --headless --path . -s scripts/systems/test_mouse_capture.gd

var arena: Node
var player: Node
var g: Node
var mc: Node
var lef: Node
var failures: Array[String] = []
var started := false

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

const CAP := Input.MOUSE_MODE_CAPTURED

func _click(button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = Vector2(800, 450)
	root.push_input(e)
	await _frames(1)
	var r := InputEventMouseButton.new()
	r.button_index = button
	r.pressed = false
	r.position = Vector2(800, 450)
	root.push_input(r)
	await _frames(1)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await _frames(1)
	var r := InputEventKey.new()
	r.keycode = k
	r.physical_keycode = k
	r.pressed = false
	root.push_input(r)
	await _frames(1)

func _hopper() -> int:
	return int(player.get("hopper_paint"))

## Lock lost while playing -> overlay; resume click re-captures, swallowed (no shot).
func _resume_by_click(label: String) -> void:
	await _frames(2)
	_check(not g.call("is_captured") and bool(g.call("overlay_visible")), "%s: capture refused outside a gesture -> CLICK TO RESUME shown" % label)
	var h := _hopper()
	var sw := int(g.get("swallowed_clicks"))
	await _click()
	await _frames(1)
	_check(bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "%s: click re-captured, overlay hidden" % label)
	_check(_hopper() == h and int(g.get("swallowed_clicks")) == sw + 1, "%s: the resume click fired no paint (hopper %d -> %d)" % [label, h, _hopper()])

func _run() -> void:
	await _frames(3)
	var gm := root.get_node("GameManager")
	gm.set("breakout_horn_sounded", true)
	player = arena.get("player")
	g = arena.get("mouse_guard")
	_check(g != null and player != null, "arena has a MouseCaptureGuard and a player")
	if g == null or player == null:
		_finish()
		return
	lef = root.get_node("LobbyEntryFlow")
	lef.call("close_browser")
	arena.call("_set_lobby_overlay_visible", false)
	g.set("simulate", true)
	g.set("sim_mode", Input.MOUSE_MODE_VISIBLE)
	g.set("sim_refuse_outside_gesture", true)
	await _frames(2)

	print("[1] policy")
	_check(String(g.call("capture_policy")) == "capture" and bool(g.call("wants_capture")), "live play -> capture")
	mc = arena.get("match_client")
	for ph in ["break", "intermission", "live", "waiting"]:
		mc.set("phase", ph)
		_check(String(g.call("capture_policy")) == "capture", "phase %s (break / 8 s recap) keeps wanting capture" % ph)
	mc.set("phase", "ended")
	_check(String(g.call("capture_policy")) == "release", "match end screen -> release")
	mc.set("phase", "live")
	player.set("lobby_open", true)
	_check(String(g.call("capture_policy")) == "release", "TAB/Esc menu (lobby_open) -> release")
	player.set("lobby_open", false)
	player.set("awaiting_respawn_choice", true)
	_check(String(g.call("capture_policy")) == "release", "respawn map -> release")
	player.set("awaiting_respawn_choice", false)
	player.set("spectating", true)
	_check(String(g.call("capture_policy")) == "capture" and bool(g.call("wants_capture")), "spectating -> capture")
	player.set("spectating", false)
	# every in-match state other than the five cursor UIs wants capture
	var states := {
		"dead, respawn timer running": func(on: bool): mc.set("respawn_left", 4.0 if on else 0.0),
		"8 s round recap (intermission)": func(on: bool): mc.set("phase", "intermission" if on else "live"),
		"break hold": func(on: bool): mc.set("phase", "break" if on else "live"),
		"match countdown banner": func(on: bool): mc.set("countdown_active", on),
		"round-end banner": func(on: bool): mc.set("awaiting_return_to_lobby", on),
		"scoreboard open": func(on: bool): arena.get("scoreboard_canvas").visible = on,
	}
	for st in states:
		(states[st] as Callable).call(true)
		_check(String(g.call("capture_policy")) == "capture", "%s -> capture" % st)
		(states[st] as Callable).call(false)
	_check(String(g.call("capture_policy")) == "capture", "state table restored -> capture")
	gm.set("match_ended", true)
	_check(String(g.call("capture_policy")) == "release", "GameManager.match_ended -> release")
	gm.set("match_ended", false)

	print("[2] resume click (web: capture needs a gesture)")
	await _resume_by_click("initial drop-in")
	var h := _hopper()
	await _click()
	await _frames(2)
	_check(_hopper() == h - 1, "once captured a click fires normally (hopper %d -> %d)" % [h, _hopper()])
	g.call("simulate_browser_unlock")
	await _frames(1)
	_check(bool(g.call("overlay_visible")), "browser dropped the lock (Esc / alt-tab, pointerlockchange) -> overlay")
	h = _hopper()
	await _click(MOUSE_BUTTON_RIGHT)
	_check(bool(g.call("is_captured")) and _hopper() == h, "right-click resume re-captures and is swallowed too")

	print("[3] keys")
	g.call("simulate_browser_unlock")
	await _frames(1)
	await _key(KEY_W)
	_check(bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "any key (W) re-captures")
	g.call("simulate_browser_unlock")
	await _frames(1)
	await _key(KEY_M)
	_check(not bool(g.call("is_captured")), "[M] scoreboard key does not grab the mouse")
	_check(String(g.call("capture_policy")) == "capture" and bool(g.call("overlay_visible")), "scoreboard open while unlocked -> capture policy, CLICK TO RESUME shown")
	await _resume_by_click("scoreboard open")
	await _key(KEY_M)
	_check(bool(g.call("is_captured")), "scoreboard closed: still locked")
	await _key(KEY_M)
	g.call("simulate_browser_unlock")
	await _frames(1)
	_check(bool(g.call("overlay_visible")), "lock lost with the scoreboard open -> CLICK TO RESUME")
	await _resume_by_click("lock lost on scoreboard")
	await _key(KEY_M)
	await _key(KEY_M)
	_check(bool(g.call("is_captured")), "scoreboard open while locked keeps the lock")
	await _key(KEY_M)
	_check(bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "scoreboard closed: still locked, no overlay")

	print("[4] focus")
	g.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	g.call("simulate_browser_unlock")
	await _frames(1)
	_check(bool(g.call("overlay_visible")), "focus out + lock lost -> overlay")
	var att := int(g.get("capture_attempts"))
	g.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(int(g.get("capture_attempts")) == att + 1 and bool(g.call("overlay_visible")), "focus in retries; web refuses -> overlay stays")
	g.set("sim_refuse_outside_gesture", false)
	g.call("_notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	_check(bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "desktop window focus in re-captures directly")
	g.set("sim_refuse_outside_gesture", true)

	print("[5] overlays release and restore")
	# TAB / Esc menu
	await _key(KEY_ESCAPE)
	await _frames(1)
	_check(bool(arena.get("lobby_canvas").visible) and not bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "Esc opens the menu and frees the cursor (no overlay)")
	await _key(KEY_ESCAPE)
	await _resume_by_click("menu closed")
	await _key(KEY_TAB)
	await _frames(1)
	_check(not bool(g.call("is_captured")), "TAB menu frees the cursor")
	g.set("sim_refuse_outside_gesture", false)
	arena.call("_set_lobby_overlay_visible", false) # DROP IN button = a click: capture works
	_check(bool(g.call("is_captured")), "menu closed by a click (gesture) -> captured at once via set_lobby_open_state")
	g.set("sim_refuse_outside_gesture", true)
	# lobby browser / waiting room (Ren's LobbyEntryFlow) -> match starts from a websocket message (no gesture)
	lef.call("open_waiting_room", {"id": "lobby_01", "name": "Lobby 01", "map": "speedball"})
	await _frames(2)
	_check(String(g.call("capture_policy")) == "release" and not bool(g.call("is_captured")), "waiting room open -> cursor free")
	lef.call("_on_match_started", "lobby_01", "speedball", false)
	await _resume_by_click("match started from the waiting room")
	# respawn map (offline)
	player.set("awaiting_respawn_choice", true)
	arena.get("death_respawn_canvas").visible = true
	arena.call("_sync_mouse_capture")
	_check(not bool(g.call("is_captured")), "respawn map frees the cursor")
	att = int(g.get("capture_attempts"))
	arena.call("_on_respawn_zone_selected", 0)
	_check(int(g.get("capture_attempts")) == att + 1, "respawn_at_map_zone routes through the guard")
	await _resume_by_click("respawn (key 1-5 / server round_started)")
	# match end
	gm.set("match_ended", true)
	await _frames(2)
	_check(not bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "match end frees the cursor, no overlay")
	gm.set("match_ended", false)
	await _resume_by_click("next match")
	# spectate (one-life CTF): wants capture; a lost lock shows the card, the click re-captures without cycling
	mc.call("enter_spectate")
	await _frames(2)
	_check(bool(player.get("spectating")) and bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "spectating keeps the lock, no card")
	g.call("simulate_browser_unlock")
	await _frames(1)
	_check(bool(g.call("overlay_visible")), "lock lost while spectating -> CLICK TO RESUME")
	var cyc := int(mc.get("spectate_cycles"))
	await _resume_by_click("spectating")
	_check(int(mc.get("spectate_cycles")) == cyc, "the resume click did not cycle the spectate target")
	await _key(KEY_E)
	await _key(KEY_Q)
	_check(int(mc.get("spectate_cycles")) == cyc + 2 and bool(g.call("is_captured")), "Q/E cycle spectate while captured")
	await _click()
	_check(int(mc.get("spectate_cycles")) == cyc + 3, "LMB cycles spectate while captured (no shot: spectating)")
	att = int(g.get("capture_attempts"))
	mc.call("_on_round_started", {"mode": String(mc.get("mode")), "round": 2})
	await _frames(2)
	_check(not bool(player.get("spectating")) and bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "spectate -> next round (round_started): still captured, no card")
	_check(int(g.get("capture_attempts")) == att, "spectate -> next round: no new capture request needed")
	mc.call("_end_break_hold")
	mc.set("phase", "live")
	# recap intermission / break never touch the mouse
	mc.set("phase", "intermission")
	await _frames(3)
	mc.set("phase", "break")
	await _frames(3)
	mc.set("phase", "live")
	_check(bool(g.call("is_captured")) and not bool(g.call("overlay_visible")), "8 s recap + break keep the lock")
	# respawn at round start with the lock held -> nothing changes
	att = int(g.get("capture_attempts"))
	player.call("respawn_at_team_gate", "ALPHA")
	_check(bool(g.call("is_captured")) and int(g.get("capture_attempts")) == att, "round_started respawn with the lock held: no re-request")
	player.call("set_lobby_open_state", false)
	_check(bool(g.call("is_captured")), "set_lobby_open_state(false) while locked stays locked")

	print("[6] stuck input-block flags (lobby_open / awaiting_respawn_choice / spectating)")
	await _stuck_case("respawn (team gate)", func(): player.call("respawn_at_team_gate", "ALPHA"))
	await _stuck_case("respawn (starting spot)", func(): player.call("respawn_at_starting_spot"))
	await _stuck_case("round_started (new CTF round)", func():
		mc.call("_on_round_started", {"mode": "ctf", "round": 3})
		mc.call("_end_break_hold")
		mc.set("phase", "live"))
	await _stuck_case("waiting room match start", func():
		lef.call("open_waiting_room", {"id": "lobby_01", "name": "Lobby 01", "map": "speedball"})
		NetworkLobby_emit_match_started())
	await _stuck_case("returned_to_lobby -> match start", func():
		root.get_node("NetworkLobby").emit_signal("returned_to_lobby", "lobby_01")
		_check(not bool(player.get("spectating")) and not bool(player.get("awaiting_respawn_choice")), "returned_to_lobby itself cleared spectate + respawn map")
		_check(String(g.call("capture_policy")) == "release", "returned_to_lobby -> waiting room frees the cursor")
		NetworkLobby_emit_match_started())
	# a menu that is really open keeps blocking input through a respawn
	arena.call("_set_lobby_overlay_visible", true)
	player.call("respawn_at_team_gate", "ALPHA")
	_check(bool(player.get("lobby_open")) and String(g.call("capture_policy")) == "release", "respawn with the TAB menu really open keeps lobby_open (menu still blocks input)")
	g.set("sim_refuse_outside_gesture", false)
	arena.call("_set_lobby_overlay_visible", false)
	g.set("sim_refuse_outside_gesture", true)
	_finish()

func NetworkLobby_emit_match_started() -> void:
	root.get_node("NetworkLobby").emit_signal("match_started_signal", "lobby_01", "speedball", false)

## All three flags stuck (respawn map up, spectating, lobby_open with no menu on screen) -> transition -> all cleared,
## respawn map hidden, the mouse captured and mouse look turning the player.
func _stuck_case(label: String, transition: Callable) -> void:
	player.set("awaiting_respawn_choice", true)
	arena.get("death_respawn_canvas").visible = true
	player.call("set_spectating", true)
	player.set("lobby_open", true) # stale: lobby canvas hidden
	await _frames(1)
	transition.call()
	await _frames(2)
	_check(not bool(player.get("lobby_open")) and not bool(player.get("awaiting_respawn_choice")) and not bool(player.get("spectating")),
		"%s: lobby_open / awaiting_respawn_choice / spectating all cleared" % label)
	_check(not bool(arena.get("death_respawn_canvas").visible), "%s: respawn map hidden" % label)
	if not bool(g.call("is_captured")):
		await _resume_by_click(label)
	var yaw0 := float(player.get("yaw"))
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40, 0)
	mm.position = Vector2(800, 450)
	root.push_input(mm)
	await _frames(1)
	_check(bool(g.call("is_captured")) and absf(float(player.get("yaw")) - yaw0) > 0.001, "%s: mouse look works (yaw %.3f -> %.3f)" % [label, yaw0, float(player.get("yaw"))])

func _finish() -> void:
	if failures.is_empty():
		print("MOUSE CAPTURE TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("MOUSE CAPTURE TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
