extends SceneTree
## v0.6.1 mouse capture (web Pointer Lock): MouseCaptureGuard is the one authority.
## Covers: capture_policy() / wants_capture() per state, a capture outside a user gesture being refused (browser-like
## simulated backend) -> CLICK TO RESUME overlay, the resume click re-capturing without firing, any key re-capturing,
## menu keys not re-capturing, focus out/in, the browser dropping the lock, and every overlay (TAB/Esc menu, lobby
## browser + waiting room, respawn map, scoreboard, match end, spectate, recap intermission, break) restoring capture
## when it closes; set_lobby_open_state / respawn_at_map_zone routed through the guard.
## Run: godot --headless --path . -s scripts/systems/test_mouse_capture.gd

var arena: Node
var player: Node
var g: Node
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
	var lef := root.get_node("LobbyEntryFlow")
	lef.call("close_browser")
	arena.call("_set_lobby_overlay_visible", false)
	g.set("simulate", true)
	g.set("sim_mode", Input.MOUSE_MODE_VISIBLE)
	g.set("sim_refuse_outside_gesture", true)
	await _frames(2)

	print("[1] policy")
	_check(String(g.call("capture_policy")) == "capture" and bool(g.call("wants_capture")), "live play -> capture")
	var mc: Node = arena.get("match_client")
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
	_check(String(g.call("capture_policy")) == "keep" and not bool(g.call("wants_capture")), "spectating -> keep (no overlay, no release)")
	player.set("spectating", false)
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
	_check(String(g.call("capture_policy")) == "keep" and not bool(g.call("overlay_visible")), "scoreboard open -> keep, overlay hidden")
	await _key(KEY_M)
	await _frames(1)
	_check(bool(g.call("overlay_visible")), "scoreboard closed while unlocked -> CLICK TO RESUME")
	await _resume_by_click("after scoreboard")
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
	# spectate (one-life CTF): keep the lock if it is still there, ask for a click at round start if it was lost
	player.call("set_spectating", true)
	await _frames(2)
	_check(bool(g.call("is_captured")), "spectating does not free the mouse")
	g.call("simulate_browser_unlock")
	await _frames(1)
	_check(not bool(g.call("overlay_visible")), "lock lost while spectating -> no overlay yet")
	player.call("set_spectating", false) # round_started
	await _resume_by_click("next round after spectating")
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
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("MOUSE CAPTURE TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("MOUSE CAPTURE TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
