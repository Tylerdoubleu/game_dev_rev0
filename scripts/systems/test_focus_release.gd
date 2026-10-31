extends SceneTree
## v0.6.3 alt-tab fix: Tyler "when I alt tab out and back to the game my player is stuck to the ground".
## Alt is bound to prone_dive; Alt+Tab delivers the Alt key-down, the window loses focus and the key-up never comes, so
## prone stayed held. Covers: holding Alt / Ctrl / C / Q, then a window focus-out + focus-in -> player stands (capsule
## back to standing height) and walks normally; an Alt key-down that arrives AFTER the blur (web key queue race) is
## released too; the browser dropping Pointer Lock releases held keys; a superman dive in progress during the blur
## finishes normally and then stands; real presses after refocus still work (hold C -> prone).
## Run: godot --headless --path . -s scripts/systems/test_focus_release.gd

const STANDING := 0
const CROUCHING := 1
const PRONE := 2

var arena: Node
var player: Node
var g: Node
var failures: Array[String] = []
var started := false
var start_pos := Vector3.ZERO

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
		await physics_frame
		await process_frame

func _key_event(k: Key, pressed: bool, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	e.shift_pressed = shift
	if k == KEY_ALT:
		e.alt_pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _stance() -> int:
	return int(player.get("stance"))

func _focus_out() -> void:
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

func _focus_in() -> void:
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)

func _stands_and_walks(label: String) -> void:
	await _frames(30)
	_check(_stance() == STANDING, "%s: stance back to standing (stance %d)" % [label, _stance()])
	_check(not Input.is_action_pressed("prone_dive") and not Input.is_action_pressed("crouch_slide"), "%s: prone/crouch actions released" % label)
	var cap: float = float(player.get("torso_capsule_height"))
	var target: float = float(player.call("get_stance_capsule_target"))
	_check(absf(cap - target) < 0.01, "%s: capsule back to standing height (%.2f vs %.2f)" % [label, cap, target])
	player.global_position = start_pos # walk the same open lane every time (no wall ahead)
	player.velocity = Vector3.ZERO
	await _frames(5)
	var p0: Vector3 = player.global_position
	_key_event(KEY_W, true)
	await _frames(30)
	_key_event(KEY_W, false)
	var moved: float = Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	_check(moved > 1.5, "%s: walks normally afterwards (moved %.2f m in 0.5 s)" % [label, moved])
	await _frames(15)

func _hold_then_alt_tab(label: String, k: Key, expect: int) -> void:
	_key_event(k, true)
	await _frames(20)
	_check(_stance() == expect, "%s: held -> stance %d (got %d)" % [label, expect, _stance()])
	_focus_out()
	await _frames(5)
	_check(not Input.is_action_pressed("prone_dive") and not Input.is_action_pressed("crouch_slide"), "%s: focus out released the held key" % label)
	await _frames(10)
	_focus_in() # the key-up went to the OS window switcher: never delivered
	await _stands_and_walks(label)

func _run() -> void:
	await _frames(3)
	var gm := root.get_node("GameManager")
	gm.set("breakout_horn_sounded", true)
	player = arena.get("player")
	g = arena.get("mouse_guard")
	_check(player != null and g != null, "arena has a player and a MouseCaptureGuard")
	if player == null:
		_finish()
		return
	root.get_node("LobbyEntryFlow").call("close_browser")
	arena.call("_set_lobby_overlay_visible", false)
	player.call("clear_input_blocks", "test", false)
	await _frames(40) # settle on the floor
	start_pos = player.global_position
	_check(_stance() == STANDING and bool(player.get("window_focused")), "starts standing, window focused")

	print("[1] Alt+Tab: Alt (prone_dive) down, focus lost, Alt up never arrives")
	await _hold_then_alt_tab("Alt", KEY_ALT, PRONE)

	print("[2] Ctrl (prone), C (prone), Q (crouch) held through alt-tab")
	await _hold_then_alt_tab("Ctrl", KEY_CTRL, PRONE)
	await _hold_then_alt_tab("C", KEY_C, PRONE)
	await _hold_then_alt_tab("Q", KEY_Q, CROUCHING)

	print("[3] web key-queue race: the Alt key-down lands after the blur")
	_focus_out()
	await _frames(1)
	_key_event(KEY_ALT, true)
	await _frames(10)
	_check(not Input.is_action_pressed("prone_dive") and _stance() == STANDING, "late Alt key-down while unfocused is released (stance %d)" % _stance())
	_focus_in()
	await _stands_and_walks("late Alt")

	print("[4] browser drops Pointer Lock (alt-tab) while C is held")
	g.set("simulate", true)
	g.set("sim_mode", Input.MOUSE_MODE_CAPTURED)
	_key_event(KEY_C, true)
	await _frames(20)
	_check(_stance() == PRONE, "C held -> prone")
	var rel0 := int(g.get("input_releases"))
	g.call("simulate_browser_unlock")
	await _frames(2)
	_check(int(g.get("input_releases")) > rel0 and not Input.is_action_pressed("prone_dive"), "lost Pointer Lock released held keys")
	await _stands_and_walks("pointer lock lost")
	g.set("simulate", false)

	print("[5] Shift+Alt superman dive in progress during alt-tab finishes normally")
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	await _frames(5)
	_key_event(KEY_SHIFT, true)
	_key_event(KEY_W, true, true)
	await _frames(10)
	_key_event(KEY_ALT, true, true)
	await _frames(2)
	_check(float(player.get("dive_timer")) > 0.0, "Shift+Alt started a dive")
	_focus_out()
	await _frames(2)
	_check(float(player.get("dive_timer")) > 0.0 and _stance() == PRONE, "dive keeps going through the blur")
	_focus_in()
	await _frames(90)
	_check(float(player.get("dive_timer")) <= 0.0, "dive finished")
	await _stands_and_walks("after dive")

	print("[6] real presses still work after refocus")
	_key_event(KEY_C, true)
	await _frames(20)
	_check(_stance() == PRONE, "hold C after refocus -> prone")
	_key_event(KEY_C, false)
	await _frames(20)
	_check(_stance() == STANDING, "release C -> stands")
	_key_event(KEY_ALT, true)
	await _frames(20)
	_check(_stance() == PRONE, "hold Alt (no tab) -> prone, binding still works")
	_key_event(KEY_ALT, false)
	await _frames(20)
	_check(_stance() == STANDING, "release Alt -> stands")
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("FOCUS RELEASE TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("FOCUS RELEASE TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
