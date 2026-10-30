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
##   "release" -> a cursor UI is up (TAB/Esc menu, lobby browser / waiting room, respawn map, match end): free it.
##   "keep"    -> no cursor UI, but not playing either (spectating, scoreboard [M]): leave the mouse alone, no overlay.
##   "capture" -> live gameplay (break, round, recap intermission): want Pointer Lock.
## While "capture" but not captured: a small CLICK TO RESUME overlay shows; the next mouse button press re-captures
## inside that input event (a user gesture) and is swallowed (no shot); any other key re-captures and passes through.
## Re-tries (non-gesture, may be refused on web -> overlay) when the policy turns "capture" (any overlay closing,
## round start), on window/app focus-in and whenever sync_capture() is called (PlayerController3D routes
## set_lobby_open_state and respawn_at_map_zone here).

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
var _js_cb: Variant = null

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
		var doc: Variant = JavaScriptBridge.get_interface("document")
		if doc != null:
			doc.addEventListener("pointerlockchange", _js_cb)
	policy = capture_policy()
	_was_captured = is_captured()

func is_active() -> bool:
	return simulate or (DisplayServer.get_name() != "headless" and not NetworkLobby.is_dedicated_server)

func mouse_mode() -> int:
	return sim_mode if simulate else Input.get_mouse_mode()

func is_captured() -> bool:
	return mouse_mode() == Input.MOUSE_MODE_CAPTURED

func _set_mode(m: int, gesture: bool) -> void:
	if simulate:
		if m == Input.MOUSE_MODE_CAPTURED and sim_refuse_outside_gesture and not gesture:
			return # browser: "requestPointerLock() needs a user gesture" - silently refused
		sim_mode = m
	else:
		Input.set_mouse_mode(m)

## Tests: the browser dropped the lock (Esc / alt-tab).
func simulate_browser_unlock() -> void:
	sim_mode = Input.MOUSE_MODE_VISIBLE
	_on_js_pointerlockchange([])

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
	# not playing, no cursor needed
	if bool(player.get("spectating")) or (mc is Node and bool(mc.get("spectating"))):
		return "keep"
	if _vis(_prop(builder, "scoreboard_canvas")):
		return "keep"
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

func _process(_delta: float) -> void:
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
		_show_overlay(is_active() and capture_policy() == "capture" and not is_captured())
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		focus_ins += 1
		if is_inside_tree():
			sync_capture()

func _on_js_pointerlockchange(_args: Array) -> void:
	browser_lock_changes += 1
	if is_inside_tree():
		policy = capture_policy()
		_apply(false)

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
