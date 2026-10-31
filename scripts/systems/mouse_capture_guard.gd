extends Node
## v0.6.1 single authority for the gameplay mouse capture (web Pointer Lock).
##
## Why: on the web build the browser drops Pointer Lock on Esc / alt-tab / focus loss and REFUSES
## requestPointerLock unless it comes from a user gesture. The old code only called
## Input.set_mouse_mode(CAPTURED) from non-gesture places (match start from a websocket message,
## set_lobby_open_state, respawn_at_map_zone at round_started), never re-captured after the browser let go, and
## aim only follows MOUSE_MODE_CAPTURED motion, so the mouse came "disconnected" from the player while clicks
## still fired paint.
##
## capture_policy():
##   "release" -> a cursor UI is up: the TAB/Esc menu, the lobby browser, the waiting room, the respawn map or the
##                match-end screen. These are the ONLY states that free the cursor without the card.
##   "capture" -> everything else in a match: live round, break + countdown banners, the 8 s round recap, dead
##                with a respawn timer, spectating (Q/E, A/D, arrows, LMB/RMB cycle; a locked mouse is fine) and the
##                [M] scoreboard. Lock lost here -> CLICK TO RESUME card.
##   "keep"    -> not in a match at all (no player in the tree yet): the guard does nothing.
## While "capture" but not captured: a small CLICK TO RESUME overlay shows; the next mouse button press re-captures
## inside that input event (a user gesture) and is swallowed (no shot); any other key re-captures and passes through.
## Re-tries (non-gesture, may be refused on web -> overlay) when the policy turns "capture" (any overlay closing,
## round start), on window/app focus-in and whenever sync_capture() is called (PlayerController3D routes
## set_lobby_open_state and respawn_at_map_zone here).
## v0.6.3: on web, Input.mouse_mode is not trusted alone for "captured": document.pointerLockElement is polled every
## LOCK_POLL_S via JavaScriptBridge.eval (plus the pointerlockchange / pointerlockerror callbacks). Policy "capture"
## with no browser lock = lost -> CLICK TO RESUME, even while Input.mouse_mode still reports CAPTURED; the resume
## gesture then forces a fresh lock request (VISIBLE -> CAPTURED + canvas.requestPointerLock()).

const GROUP := "mouse_capture_guard"
const MENU_ACTIONS := ["ui_cancel", "toggle_lobby", "toggle_scoreboard"]

var builder: Node = null
var player: Node = null

## tests: simulated mouse backend that behaves like a browser (refuses a capture outside a user gesture)
var simulate: bool = false
var sim_mode: int = Input.MOUSE_MODE_VISIBLE
var sim_refuse_outside_gesture: bool = true

var overlay: CanvasLayer
var overlay_panel: PanelContainer
var policy: String = "keep"
var capture_attempts: int = 0
var gesture_captures: int = 0
var swallowed_clicks: int = 0
var lock_losses: int = 0
var focus_ins: int = 0
var focus_outs: int = 0
var browser_lock_changes: int = 0
var _swallow_release_button: int = -1
var _was_captured: bool = false
var _js_cb: Variant = null # pointerlockchange callback; must stay referenced or the JS side calls a freed object
var _js_err_cb: Variant = null # pointerlockerror callback (same reason)

## v0.6.3 browser-side lock state: -1 unknown (not web / never polled), 0 no pointerLockElement, 1 locked
const LOCK_POLL_S := 0.25
const LOCK_GRANT_GRACE_MS := 1000 # requestPointerLock resolves asynchronously; don't call it "lost" meanwhile
var browser_lock: int = -1
var lock_polls: int = 0
var lock_desyncs: int = 0 # times Input said CAPTURED but the browser had no lock
var _poll_left: float = 0.0
var _grant_pending_until_ms: int = 0
## tests: simulated document.pointerLockElement (-1 = follows sim_mode, 0 = null, 1 = set)
var sim_dom_lock: int = -1

func setup(p_builder: Node, p_player: Node) -> void:
	builder = p_builder
	player = p_player

func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	if OS.has_feature("web"):
		# Know the moment the browser drops the lock (Esc, alt-tab) instead of waiting for the next frame's poll.
		_js_cb = JavaScriptBridge.create_callback(_on_js_pointerlockchange)
		_js_err_cb = JavaScriptBridge.create_callback(_on_js_pointerlockerror)
		var doc: Variant = JavaScriptBridge.get_interface("document")
		if doc != null:
			doc.addEventListener("pointerlockchange", _js_cb)
			doc.addEventListener("pointerlockerror", _js_err_cb)
	poll_pointer_lock()
	policy = capture_policy()
	_was_captured = is_captured()

func is_active() -> bool:
	return simulate or (DisplayServer.get_name() != "headless" and not NetworkLobby.is_dedicated_server)

func mouse_mode() -> int:
	return sim_mode if simulate else Input.get_mouse_mode()

func uses_dom_lock() -> bool:
	return simulate or OS.has_feature("web")

## document.pointerLockElement != null ? 1 : 0 (-1 where there is no DOM).
func _dom_lock_now() -> int:
	if simulate:
		if sim_dom_lock < 0:
			return 1 if sim_mode == Input.MOUSE_MODE_CAPTURED else 0
		return sim_dom_lock
	if not OS.has_feature("web"):
		return -1
	var v: Variant = JavaScriptBridge.eval("document.pointerLockElement !== null", true)
	return 1 if bool(v) else 0

func poll_pointer_lock() -> void:
	lock_polls += 1
	browser_lock = _dom_lock_now()
	if browser_lock == 1:
		_grant_pending_until_ms = 0

## Input says CAPTURED but the browser holds no lock (and no lock request is still resolving).
func lock_desynced() -> bool:
	if not uses_dom_lock() or browser_lock != 0 or mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	return Time.get_ticks_msec() >= _grant_pending_until_ms

func is_captured() -> bool:
	return mouse_mode() == Input.MOUSE_MODE_CAPTURED and not lock_desynced()

func _set_mode(m: int, gesture: bool) -> void:
	if simulate:
		if m == Input.MOUSE_MODE_CAPTURED and sim_refuse_outside_gesture and not gesture:
			return # browser: "requestPointerLock() needs a user gesture" - silently refused
		sim_mode = m
		if m == Input.MOUSE_MODE_CAPTURED and gesture:
			sim_dom_lock = -1 # the browser grants a lock requested from a gesture
		poll_pointer_lock()
		return
	if m == Input.MOUSE_MODE_CAPTURED and OS.has_feature("web"):
		if gesture and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			# desync: Godot already thinks it is captured and would no-op; force a real request
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		Input.set_mouse_mode(m)
		if gesture:
			JavaScriptBridge.eval("(function(){var c=document.querySelector('canvas');if(c&&!document.pointerLockElement&&c.requestPointerLock){try{var p=c.requestPointerLock();if(p&&p.catch)p.catch(function(){});}catch(e){}}})()", true)
		_grant_pending_until_ms = Time.get_ticks_msec() + LOCK_GRANT_GRACE_MS
		return
	Input.set_mouse_mode(m)
	if OS.has_feature("web"):
		poll_pointer_lock()

## Tests: the browser dropped the lock (Esc / alt-tab).
func simulate_browser_unlock() -> void:
	sim_mode = Input.MOUSE_MODE_VISIBLE
	_on_js_pointerlockchange([])

## Tests: the browser dropped the lock but Input.mouse_mode still says CAPTURED (no pointerlockchange delivered).
func simulate_silent_dom_unlock() -> void:
	sim_dom_lock = 0

func _vis(o: Variant) -> bool:
	if not (o is Object) or not is_instance_valid(o):
		return false
	if o is CanvasLayer:
		return (o as CanvasLayer).visible
	if o is CanvasItem:
		return (o as CanvasItem).is_visible_in_tree()
	return false

func _prop(o: Object, prop: String) -> Variant:
	return o.get(prop) if o != null and is_instance_valid(o) else null

func capture_policy() -> String:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return "keep"
	var mc: Variant = _prop(builder, "match_client")
	# cursor UIs
	if bool(player.get("lobby_open")) or _vis(_prop(builder, "lobby_canvas")):
		return "release"
	var lef: Node = get_node_or_null("/root/LobbyEntryFlow")
	if lef != null and _vis(lef.get("_layer")):
		return "release"
	if bool(player.get("awaiting_respawn_choice")) or _vis(_prop(builder, "death_respawn_canvas")):
		return "release"
	if GameManager.match_ended or (mc is Node and String(mc.get("phase")) == "ended"):
		return "release"
	# v0.6.2: spectating, the [M] scoreboard, dead/respawn timers, recap, break and countdown banners all keep wanting
	# the lock (no cursor UI there), so a dropped lock shows the card instead of silently leaving the next round free.
	return "capture"

func wants_capture() -> bool:
	return capture_policy() == "capture"

func overlay_visible() -> bool:
	return overlay != null and overlay.visible

## Overlays closing / opening and PlayerController3D (set_lobby_open_state, respawn_at_map_zone) call this.
func sync_capture() -> void:
	policy = capture_policy()
	_apply(true)

func _apply(try_capture: bool) -> void:
	if not is_active():
		_show_overlay(false)
		return
	if policy == "release" and is_captured():
		_set_mode(Input.MOUSE_MODE_VISIBLE, false)
	elif policy == "capture" and not is_captured() and try_capture:
		capture_attempts += 1
		_set_mode(Input.MOUSE_MODE_CAPTURED, false)
	_show_overlay(policy == "capture" and not is_captured())

func _process(delta: float) -> void:
	if uses_dom_lock():
		_poll_left -= delta
		if _poll_left <= 0.0:
			_poll_left = LOCK_POLL_S
			poll_pointer_lock()
			if lock_desynced() and capture_policy() == "capture":
				lock_desyncs += 1
	var p := capture_policy()
	var turned := p != policy
	policy = p
	var cap := is_captured()
	if _was_captured and not cap and policy == "capture":
		lock_losses += 1
	_was_captured = cap
	_apply(turned and policy == "capture")

func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if _swallow_release_button >= 0 and event is InputEventMouseButton and not event.pressed and event.button_index == _swallow_release_button:
		_swallow_release_button = -1
		get_viewport().set_input_as_handled()
		return
	if is_captured() or capture_policy() != "capture":
		return
	if event is InputEventMouseButton and event.pressed:
		# user gesture: Pointer Lock is allowed now; the resume click must not fire paint
		_gesture_capture()
		swallowed_clicks += 1
		_swallow_release_button = event.button_index
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		for a in MENU_ACTIONS:
			if InputMap.has_action(a) and event.is_action_pressed(a):
				return
		_gesture_capture() # key passes through (W keeps walking)

func _gesture_capture() -> void:
	capture_attempts += 1
	_set_mode(Input.MOUSE_MODE_CAPTURED, true)
	if is_captured():
		gesture_captures += 1
	_was_captured = is_captured()
	_show_overlay(not is_captured())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		focus_outs += 1
		_release_player_inputs("focus_out")
		_show_overlay(is_active() and capture_policy() == "capture" and not is_captured())
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		focus_ins += 1
		if is_inside_tree():
			sync_capture()

func _on_js_pointerlockchange(_args: Array) -> void:
	browser_lock_changes += 1
	_grant_pending_until_ms = 0
	poll_pointer_lock()
	if browser_lock == 0:
		_release_player_inputs("pointer_lock_lost") # alt-tab / Esc: keys held at that moment never send a key-up
	if is_inside_tree():
		policy = capture_policy()
		_apply(false)

func _on_js_pointerlockerror(_args: Array) -> void:
	_grant_pending_until_ms = 0
	poll_pointer_lock()
	if is_inside_tree():
		policy = capture_policy()
		_apply(false)

## v0.6.3: the window blur / lost Pointer Lock (alt-tab) also releases every held key action on the player, so Alt
## (prone_dive) or Ctrl/C/Q pressed as the window lost focus doesn't leave the player stuck prone/crouched.
var input_releases: int = 0
func _release_player_inputs(reason: String) -> void:
	input_releases += 1
	if player != null and is_instance_valid(player) and player.has_method("release_held_inputs"):
		player.call("release_held_inputs", reason)
	else:
		for a in InputMap.get_actions():
			if Input.is_action_pressed(a):
				Input.action_release(a)

func _show_overlay(on: bool) -> void:
	if overlay != null and overlay.visible != on:
		overlay.visible = on

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "ClickToResumeOverlay"
	overlay.layer = 40
	overlay.visible = false
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	overlay_panel = PanelContainer.new()
	overlay_panel.name = "ResumeCard"
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.add_theme_stylebox_override("panel", TournamentSkin.card(Color(0.32, 0.27, 0.18, 0.94), 26, 12))
	center.add_child(overlay_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_panel.add_child(v)
	var title := TournamentSkin.led("CLICK TO RESUME", 30)
	title.name = "ResumeTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var sub := TournamentSkin.led("aim lock released - click (no shot) or press any key", 14, TournamentSkin.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
