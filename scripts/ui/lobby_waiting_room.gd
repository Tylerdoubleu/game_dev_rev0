class_name LobbyWaitingRoom
extends Control
## v0.5 (Ren): the lobby waiting room. JOIN on the Tournament Board connects to the room in place (no page reload)
## and shows this panel: both team rosters, the room's map and game type (any player can change them while the room
## is waiting), your own gun class, then START MATCH. LEAVE drops back to the lobby list.
## Talks only to NetworkLobby's public API: select_map / select_mode / update_local_player_choices /
## request_start_match / disconnect_from_lobby and the lobby_state_changed / connection_status_changed signals.

signal leave_requested
signal start_requested

const MAPS := [["speedball", "NPPL SPEEDBALL"], ["woodsball_crash", "WOODSBALL HELI CRASH"]]
const MODES := [["deathmatch", "10-KILL DEATHMATCH"], ["ctf", "1-LIFE CTF  BO5"], ["bots_test", "TEST VS BOTS"]]
const GUNS := [["speedball", "SPEEDBALL ELECTRO"], ["woodsball", "WOODSBALL A-5"], ["pump", "STOCK PUMP"]]
const NEON := LobbyBrowser.NEON
const RED_TEAM := LobbyBrowser.RED_TEAM
const BLUE_TEAM := LobbyBrowser.BLUE_TEAM

var lobby_name: String = "LOBBY"
var state: Dictionary = {}
var _title: Label
var _status: Label
var _red_list: VBoxContainer
var _blue_list: VBoxContainer
var _red_head: Label
var _blue_head: Label
var _map_btns := {}
var _mode_btns := {}
var _gun_btns := {}
var _start_btn: Button
var _lock_note: Label
var _online := false
var _ready_btn: Button
var _countdown: Label
var counting_down: bool = false
var countdown_left: int = 0

func _ready() -> void:
	_build_ui()
	if get_node_or_null("/root/NetworkLobby") != null:
		var nl := get_node("/root/NetworkLobby")
		nl.lobby_state_changed.connect(apply_state)
		nl.connection_status_changed.connect(_on_conn)
		if nl.has_signal("match_countdown"):
			nl.match_countdown.connect(_on_countdown)
		if nl.has_signal("room_event"):
			nl.room_event.connect(_on_room_event)
		_online = nl.is_online_client()
		apply_state(nl.get_lobby_state_snapshot())

func _nl() -> Node:
	return get_node_or_null("/root/NetworkLobby")

func set_lobby(entry: Dictionary) -> void:
	lobby_name = String(entry.get("name", entry.get("id", "LOBBY"))).to_upper()
	if _title:
		_title.text = "%s  -  WAITING ROOM" % lobby_name

func _on_conn(text: String, online: bool) -> void:
	_online = online
	_status.text = text
	_status.add_theme_color_override("font_color", Color(0.45, 0.95, 0.35) if online else Color(1.0, 0.72, 0.3))
	_refresh_controls()

func _on_countdown(seconds_left: int, _data: Dictionary = {}) -> void:
	counting_down = seconds_left > 0
	countdown_left = seconds_left
	_countdown.text = "MATCH STARTS IN %d" % seconds_left if counting_down else "GO GO GO!"
	_countdown.visible = true
	_refresh_controls()

func _on_room_event(event_name: String, _data: Dictionary) -> void:
	if event_name == "start_rejected":
		_lock_note.text = "CAN'T START YET: each team needs at least one player (or pick TEST VS BOTS)." if String(_data.get("reason", "")) == "team_empty" else "START WAS REFUSED (%s)." % String(_data.get("reason", "?"))
		_lock_note.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
		return
	if event_name in ["match_start_cancelled", "match_ended", "round_started"]:
		counting_down = false
		_countdown.visible = false
		_refresh_controls()

## Fills rosters and highlights from a NetworkLobby.get_lobby_state_snapshot() dict. Static-friendly for tests.
func apply_state(s: Dictionary) -> void:
	state = s
	if _red_list == null:
		return
	for c in _red_list.get_children(): c.queue_free()
	for c in _blue_list.get_children(): c.queue_free()
	var room := String(s.get("room", ""))
	var red := 0
	var blue := 0
	var players: Dictionary = s.get("players", {})
	var me := _my_id()
	for pid in players:
		var p: Dictionary = players[pid]
		if room != "" and p.has("room") and String(p["room"]) != room:
			continue
		var is_red := String(p.get("team", "ALPHA")).to_upper() in ["ALPHA", "RED"]
		var gun := String(p.get("bracket", "speedball")).to_upper()
		var ready_mark := "[READY]  " if bool(p.get("ready", false)) else "[ - ]  "
		var line := "%s%s%s   (%s)" % [ready_mark, String(p.get("name", "PLAYER")).to_upper(), "  (YOU)" if int(pid) == me else "", gun]
		if int(pid) == me and _ready_btn != null:
			_ready_btn.set_pressed_no_signal(bool(p.get("ready", false)))
		var l := _label(line, 17, (RED_TEAM if is_red else BLUE_TEAM).lightened(0.35))
		if is_red:
			_red_list.add_child(l); red += 1
		else:
			_blue_list.add_child(l); blue += 1
	_red_head.text = "RED  %d / 5" % red
	_blue_head.text = "BLUE  %d / 5" % blue
	_highlight(_map_btns, String(s.get("selected_map", s.get("map", ""))))
	_highlight(_mode_btns, String(s.get("mode", "")))
	_highlight(_gun_btns, String(s.get("bracket", "")))
	_refresh_controls()

func is_locked() -> bool:
	var m: Dictionary = state.get("match", {})
	return String(m.get("phase", "waiting")) != "waiting" or String(state.get("status", "waiting")) == "in_match"

func _refresh_controls() -> void:
	var locked := is_locked()
	for k in _map_btns: _map_btns[k].disabled = locked
	for k in _mode_btns: _mode_btns[k].disabled = locked
	var can_cancel := counting_down and _nl() != null and _nl().has_method("cancel_start")
	_start_btn.disabled = (locked and not can_cancel) or not _online or (counting_down and not can_cancel)
	if counting_down:
		_start_btn.text = "CANCEL START" if can_cancel else "STARTING..."
	else:
		_start_btn.text = "MATCH IN PROGRESS" if locked else ("START MATCH" if _online else "CONNECTING...")
	if _ready_btn != null:
		_ready_btn.text = "READY  [X]" if _ready_btn.button_pressed else "READY  [ ]"
	_lock_note.remove_theme_color_override("font_color")
	_lock_note.add_theme_color_override("font_color", Color(0.55, 0.56, 0.5))
	_lock_note.text = "Settings are locked while a match is running." if locked else "Anyone in the lobby can change the field and game type until the match starts."

func _my_id() -> int:
	var nl := _nl()
	if nl != null and nl.is_online_client():
		return nl.multiplayer.get_unique_id()
	return 1

func _highlight(btns: Dictionary, current: String) -> void:
	for k in btns:
		var b: Button = btns[k]
		b.button_pressed = k == current

func _pick_map(id: String) -> void:
	var nl := _nl()
	if nl: nl.select_map(id)

func _pick_mode(id: String) -> void:
	var nl := _nl()
	if nl: nl.select_mode(id)

func _pick_gun(id: String) -> void:
	var nl := _nl()
	if nl:
		nl.update_local_player_choices(nl.local_callsign, nl.local_team, id, nl.fill_bots_enabled)
	_highlight(_gun_btns, id)

func _press_start() -> void:
	var nl := _nl()
	if counting_down:
		if nl and nl.has_method("cancel_start"):
			nl.cancel_start()
		return
	start_requested.emit()
	if nl:
		nl.request_start_match(nl.active_room, nl.local_bracket, String(state.get("mode", "")) == "bots_test")

func _press_ready(on: bool) -> void:
	var nl := _nl()
	if nl and nl.has_method("set_ready"):
		nl.set_ready(on)
	_refresh_controls()

func _press_leave() -> void:
	var nl := _nl()
	if nl and nl.has_method("leave_room"):
		nl.leave_room()  # Tim: leaves the room server-side and emits left_room
	elif nl and nl.has_method("disconnect_from_lobby"):
		nl.disconnect_from_lobby()
	leave_requested.emit()

# ---------------------------------------------------------------- UI ----------

func _style(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _toggle(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.82, 0.83, 0.78))
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_stylebox_override("normal", _style(Color(0.2, 0.205, 0.19), Color(0.33, 0.33, 0.3)))
	b.add_theme_stylebox_override("hover", _style(Color(0.26, 0.27, 0.24), NEON.darkened(0.3)))
	b.add_theme_stylebox_override("pressed", _style(NEON, NEON.darkened(0.45)))
	b.add_theme_stylebox_override("hover_pressed", _style(NEON.lightened(0.15), Color.WHITE))
	b.add_theme_stylebox_override("disabled", _style(Color(0.15, 0.15, 0.14), Color(0.1, 0.1, 0.1)))
	return b

func _picker_row(col: VBoxContainer, title: String, options: Array, store: Dictionary, cb: Callable) -> void:
	col.add_child(_label(title, 14, Color(0.6, 0.62, 0.56)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	col.add_child(h)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for o in options:
		var b := _toggle(o[1])
		b.name = "Pick_" + o[0]
		b.button_group = group
		b.pressed.connect(cb.bind(o[0]))
		store[o[0]] = b
		h.add_child(b)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.07, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var board := PanelContainer.new()
	board.custom_minimum_size = Vector2(1080, 0)
	board.add_theme_stylebox_override("panel", _style(Color(0.13, 0.135, 0.12), Color(0.32, 0.3, 0.25), 3))
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = _label("%s  -  WAITING ROOM" % lobby_name, 36, NEON)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_status = _label("CONNECTING...", 15, Color(1.0, 0.72, 0.3))
	head.add_child(_status)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	col.add_child(teams)
	for side in [[RED_TEAM, true], [BLUE_TEAM, false]]:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 230)
		p.add_theme_stylebox_override("panel", _style(Color(0.16, 0.165, 0.15), side[0].darkened(0.35), 2))
		teams.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		var h := _label("", 22, side[0])
		v.add_child(h)
		var list := VBoxContainer.new()
		v.add_child(list)
		if side[1]:
			_red_head = h; _red_list = list
		else:
			_blue_head = h; _blue_list = list
	col.add_child(_label("TEAMS AUTO-BALANCE WHEN PLAYERS JOIN AND AT MATCH START", 13, Color(0.55, 0.56, 0.5)))

	_picker_row(col, "FIELD", MAPS, _map_btns, _pick_map)
	_picker_row(col, "GAME TYPE", MODES, _mode_btns, _pick_mode)
	_picker_row(col, "YOUR GUN", GUNS, _gun_btns, _pick_gun)
	_lock_note = _label("", 13, Color(0.55, 0.56, 0.5))
	col.add_child(_lock_note)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	var leave := Button.new()
	leave.name = "LeaveButton"
	leave.text = "LEAVE LOBBY"
	leave.custom_minimum_size = Vector2(200, 54)
	leave.add_theme_font_size_override("font_size", 18)
	leave.add_theme_stylebox_override("normal", _style(Color(0.35, 0.36, 0.33), Color(0.2, 0.2, 0.2)))
	leave.pressed.connect(_press_leave)
	foot.add_child(leave)
	_ready_btn = _toggle("READY  [ ]")
	_ready_btn.name = "ReadyButton"
	_ready_btn.custom_minimum_size = Vector2(200, 54)
	_ready_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ready_btn.toggled.connect(_press_ready)
	foot.add_child(_ready_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_start_btn = Button.new()
	_start_btn.name = "StartMatchButton"
	_start_btn.custom_minimum_size = Vector2(340, 54)
	_start_btn.add_theme_font_size_override("font_size", 22)
	_start_btn.add_theme_color_override("font_color", Color(0.06, 0.06, 0.05))
	_start_btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.38))
	_start_btn.add_theme_stylebox_override("normal", _style(Color(0.45, 0.95, 0.35), Color(0.2, 0.45, 0.15)))
	_start_btn.add_theme_stylebox_override("hover", _style(Color(0.6, 1.0, 0.5), Color.WHITE))
	_start_btn.add_theme_stylebox_override("disabled", _style(Color(0.18, 0.18, 0.17), Color(0.1, 0.1, 0.1)))
	_start_btn.pressed.connect(_press_start)
	foot.add_child(_start_btn)
	_countdown = _label("", 64, NEON)
	_countdown.name = "CountdownLabel"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_countdown.position = Vector2(-300, 24)
	_countdown.custom_minimum_size = Vector2(600, 80)
	_countdown.add_theme_constant_override("outline_size", 10)
	_countdown.visible = false
	add_child(_countdown)
	_refresh_controls()
