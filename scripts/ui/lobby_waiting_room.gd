class_name LobbyWaitingRoom
extends Control
## v0.5 (Ren): the lobby waiting room. JOIN on the Tournament Board connects to the room in place (no page reload)
## and shows this panel: both team rosters, the room's map and game type (any player can change them while the room
## is waiting), your own gun class, then START MATCH. LEAVE drops back to the lobby list.
## Talks only to NetworkLobby's public API: select_map / select_mode / update_local_player_choices /
## request_start_match / disconnect_from_lobby and the lobby_state_changed / connection_status_changed signals.
##
## v0.6.4 team colors: a row of swatches under each team roster. You pick only for YOUR team, only while the room is
## waiting; the other team's color is crossed out (no two teams share a color). Headers + names take the team color.
## A pick shows at once (optimistic) and reverts if the server says no. Palette + names come from Tim's TeamColors
## (scripts/systems/team_colors.gd: names(), color_of(name), for_team(team, team_colors)).
## NetworkLobby seam (all optional, checked with has_method / has_signal, so nothing breaks before Tim's side lands):
##   lobby state  "team_colors": {"ALPHA": "red", "BRAVO": "blue"}   -> apply_team_colors()
##   nl.request_team_color(color_name)                                <- your own team only
##   signal team_colors_changed(team_colors: Dictionary)              -> apply_team_colors()
##   signal team_color_rejected(reason: String)  round_active | taken | invalid | rate_limited -> revert + LED note
## Tests / other callers: team_color_requested(team, color_name) fires on every pick; call apply_team_colors(dict)
## and on_team_color_rejected(reason) directly.

signal leave_requested
signal start_requested
signal team_color_requested(team: String, color_name: String)

const MAPS := [["speedball", "NPPL SPEEDBALL"], ["woodsball_crash", "WOODSBALL HELI CRASH"]]
const MODES := [["deathmatch", "10-KILL DEATHMATCH"], ["ctf", "1-LIFE CTF  BO5"], ["bots_test", "TEST VS BOTS"]]
const GUNS := [["speedball", "SPEEDBALL ELECTRO"], ["woodsball", "WOODSBALL A-5"], ["pump", "STOCK PUMP"]]
const NEON := LobbyBrowser.NEON
const DEFAULT_TEAM_COLORS := TeamColors.DEFAULTS  # Tim's shared palette (scripts/systems/team_colors.gd)
const REJECT_TEXT := {"round_active": "MATCH IS LIVE - COLORS LOCKED", "taken": "TAKEN BY THE OTHER TEAM",
	"invalid": "NOT A TEAM COLOR", "rate_limited": "SLOW DOWN - TRY AGAIN"}

var lobby_name: String = "LOBBY"
var state: Dictionary = {}
var _title: Label
var _status: Label
var _red_list: VBoxContainer
var _blue_list: VBoxContainer
var _red_head: Label
var _blue_head: Label
var _bench_list: VBoxContainer
var _bench_head: Label
var _map_btns := {}
var _mode_btns := {}
var _gun_btns := {}
var _start_btn: Button
var _lock_note: Label
var _online := false
var _red_count := 0
var _blue_count := 0
var _ready_btn: Button
var _countdown: Label
var counting_down: bool = false
var countdown_left: int = 0
## Server-confirmed colors per team (lowercase names). _optimistic holds your pick until the server answers.
var team_colors: Dictionary = DEFAULT_TEAM_COLORS.duplicate()
var _optimistic: Dictionary = {}
var _red_panel: PanelContainer
var _blue_panel: PanelContainer
var _swatches := {"ALPHA": {}, "BRAVO": {}}  # team -> name -> Swatch
var _color_note := {}  # team -> Label

## A paint-chip color swatch: ringed when it is that team's color, crossed out when the other team holds it.
class Swatch extends Button:
	var chip := Color.WHITE
	var ringed := false
	var crossed := false
	func _init(c: Color) -> void:
		chip = c
		custom_minimum_size = Vector2(30, 30)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var dim := 0.45 if disabled and not ringed else 1.0
		draw_rect(r.grow(2), Color(0, 0, 0, 0.85))
		draw_rect(r, Color(chip, dim))
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.3)), Color(1, 1, 1, 0.14 * dim))  # vinyl shine
		if ringed:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), TournamentSkin.NEON, false, 3.0)
		if crossed:
			draw_line(r.position, r.end, Color(0, 0, 0, 0.95), 5.0)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(0, 0, 0, 0.95), 5.0)
			draw_line(r.position, r.end, TournamentSkin.CHALK, 2.0)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), TournamentSkin.CHALK, 2.0)

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
		if nl.has_signal("team_colors_changed"):
			nl.team_colors_changed.connect(apply_team_colors)
		if nl.has_signal("team_color_rejected"):
			nl.team_color_rejected.connect(on_team_color_rejected)
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
	for c in _bench_list.get_children(): c.queue_free()
	var bench := 0
	var room := String(s.get("room", ""))
	var red := 0
	var blue := 0
	var players: Dictionary = s.get("players", {})
	var me := _my_id()
	for pid in players:
		var p: Dictionary = players[pid]
		if room != "" and p.has("room") and String(p["room"]) != room:
			continue
		var is_red := TeamColors.team_key(String(p.get("team", "ALPHA"))) == "ALPHA"
		var gun := String(p.get("bracket", "speedball")).to_upper()
		var is_ready := bool(p.get("ready", false))
		var line := "%s%s   (%s)" % [String(p.get("name", "PLAYER")).to_upper(), "  (YOU)" if int(pid) == me else "", gun]
		if int(pid) == me and _ready_btn != null:
			_ready_btn.set_pressed_no_signal(is_ready)
		# Tyler v0.5: you only take your (auto-assigned) team spot once you press READY.
		if not is_ready:
			_bench_list.add_child(TournamentSkin.marker(line, 17, Color(0.8, 0.81, 0.76)))
			bench += 1
			continue
		var l := TournamentSkin.marker(line, 18, team_color("ALPHA" if is_red else "BRAVO").lightened(0.45))
		if is_red:
			_red_list.add_child(l); red += 1
		else:
			_blue_list.add_child(l); blue += 1
	_red_head.text = "%s  %d / 5" % [shown_color("ALPHA").to_upper(), red]
	_blue_head.text = "%s  %d / 5" % [shown_color("BRAVO").to_upper(), blue]
	_bench_head.text = "NOT READY  %d" % bench
	_red_count = red
	_blue_count = blue
	if s.get("team_colors") is Dictionary:
		apply_team_colors(s["team_colors"])
	else:
		_refresh_colors()
	_highlight(_map_btns, String(s.get("selected_map", s.get("map", ""))))
	_highlight(_mode_btns, String(s.get("mode", "")))
	_highlight(_gun_btns, String(s.get("bracket", "")))
	_refresh_controls()

# ------------------------------------------------------- team colors ----------

## The palette's color names in picker order (TeamColors.NAMES).
static func color_names() -> Array:
	return TeamColors.names()

## Color for a color name (TeamColors.color_of; unknown -> red).
static func color_of_name(color_name: String) -> Color:
	return TeamColors.color_of(color_name)

static func _team_key(t: String) -> String:
	return TeamColors.team_key(t)

## The color name a team shows right now (your pending pick first, then the server's).
func shown_color(team: String) -> String:
	var t := _team_key(team)
	return String(_optimistic.get(t, team_colors.get(t, DEFAULT_TEAM_COLORS[t]))).to_lower()

func team_color(team: String) -> Color:
	return color_of_name(shown_color(team))

## Your team: your row in the room state, else NetworkLobby.local_team, else ALPHA.
func my_team() -> String:
	var players: Dictionary = state.get("players", {})
	var me := _my_id()
	for pid in players:
		if int(pid) == me and players[pid] is Dictionary and players[pid].has("team"):
			return _team_key(String(players[pid]["team"]))
	var nl := _nl()
	if nl != null and nl.get("local_team") != null:
		return _team_key(String(nl.get("local_team")))
	return "ALPHA"

func can_pick_color(team: String, color_name: String) -> bool:
	var t := _team_key(team)
	var other := "BRAVO" if t == "ALPHA" else "ALPHA"
	return not is_locked() and t == my_team() and color_name.to_lower() in color_names() \
		and color_name.to_lower() != shown_color(other)

## A swatch click: shows it now, asks the server (nl.request_team_color), reverts on team_color_rejected.
func pick_team_color(color_name: String) -> bool:
	var t := my_team()
	var n := color_name.to_lower()
	if not can_pick_color(t, n) or n == shown_color(t):
		return false
	_optimistic[t] = n
	_set_note(t, "", TournamentSkin.MUTED)
	_refresh_colors()
	team_color_requested.emit(t, n)
	var nl := _nl()
	if nl != null and nl.has_method("request_team_color"):
		nl.call("request_team_color", n)
	return true

## Server-confirmed colors, e.g. {"ALPHA": "red", "BRAVO": "blue"} (from lobby state or team_colors_changed).
func apply_team_colors(colors: Dictionary) -> void:
	for k in colors:
		team_colors[_team_key(String(k))] = String(colors[k]).to_lower()
	for t in _optimistic.keys():
		if team_colors.get(t) == _optimistic[t]:
			_optimistic.erase(t)
			_set_note(t, "", TournamentSkin.MUTED)
	_refresh_colors()

## The server refused your pick: back to the confirmed color and say why.
func on_team_color_rejected(reason: String) -> void:
	var t := my_team()
	_optimistic.erase(t)
	_set_note(t, REJECT_TEXT.get(reason, "COLOR REFUSED (%s)" % reason.to_upper()), Color(1.0, 0.45, 0.3))
	_refresh_colors()

func _set_note(team: String, text: String, c: Color) -> void:
	var l: Label = _color_note.get(team)
	if l != null:
		l.text = text
		l.add_theme_color_override("font_color", c)

func _refresh_colors() -> void:
	if _red_head == null:
		return
	var mine := my_team()
	for t in ["ALPHA", "BRAVO"]:
		var other := "BRAVO" if t == "ALPHA" else "ALPHA"
		var c := team_color(t)
		var head: Label = _red_head if t == "ALPHA" else _blue_head
		head.text = "%s  %d / 5" % [shown_color(t).to_upper(), _red_count if t == "ALPHA" else _blue_count]
		head.add_theme_color_override("font_color", c.lightened(0.2))
		var list: VBoxContainer = _red_list if t == "ALPHA" else _blue_list
		for l in list.get_children():
			if l is Label:
				l.add_theme_color_override("font_color", c.lightened(0.45))
		var panel: PanelContainer = _red_panel if t == "ALPHA" else _blue_panel
		panel.add_theme_stylebox_override("panel", TournamentSkin.card(c.darkened(0.62).lerp(Color(0.25, 0.25, 0.23), 0.35), 14, 10))
		for n in _swatches[t]:
			var sw: Swatch = _swatches[t][n]
			sw.ringed = n == shown_color(t)
			sw.crossed = n == shown_color(other)
			sw.disabled = t != mine or is_locked() or sw.crossed
			sw.mouse_default_cursor_shape = Control.CURSOR_ARROW if sw.disabled else Control.CURSOR_POINTING_HAND
			sw.tooltip_text = n.to_upper()
			sw.queue_redraw()

func is_locked() -> bool:
	var m: Dictionary = state.get("match", {})
	return String(m.get("phase", "waiting")) != "waiting" or String(state.get("status", "waiting")) == "in_match"

func _refresh_controls() -> void:
	var locked := is_locked()
	for k in _map_btns: _map_btns[k].disabled = locked
	for k in _mode_btns: _mode_btns[k].disabled = locked
	_refresh_colors()
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

func _style(bg: Color, _border: Color = Color.BLACK, _bw := 2) -> StyleBox:
	return TournamentSkin.card(bg)

func _label(t: String, size: int, c: Color) -> Label:
	return TournamentSkin.label(t, size, c)

func _toggle(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return TournamentSkin.style_toggle(b, 16)

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
	add_child(TournamentSkin.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var board := PanelContainer.new()
	board.name = "Board"
	board.custom_minimum_size = Vector2(1100, 0)
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = TournamentSkin.label("%s  -  WAITING ROOM" % lobby_name, 40, NEON, TournamentSkin.STENCIL, 8)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_status = TournamentSkin.led("CONNECTING...", 17)
	head.add_child(_status)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	col.add_child(teams)
	for side in [[TeamColors.for_team("ALPHA", team_colors), 0], [Color(0.5, 0.5, 0.46), 1], [TeamColors.for_team("BRAVO", team_colors), 2]]:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_stretch_ratio = 0.8 if side[1] == 1 else 1.0
		p.custom_minimum_size = Vector2(0, 230)
		p.add_theme_stylebox_override("panel", TournamentSkin.card(side[0].darkened(0.62).lerp(Color(0.25, 0.25, 0.23), 0.35), 14, 10))
		teams.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		var h := TournamentSkin.label("", 24, side[0].lightened(0.2), TournamentSkin.STENCIL, 5)
		v.add_child(h)
		var list := VBoxContainer.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(list)
		if side[1] != 1:
			var team := "ALPHA" if side[1] == 0 else "BRAVO"
			var row := HBoxContainer.new()
			row.name = "Swatches_" + team
			row.add_theme_constant_override("separation", 2)
			v.add_child(row)
			for n in color_names():
				var sw := Swatch.new(color_of_name(String(n)))
				sw.name = "Swatch_" + String(n)
				sw.pressed.connect(pick_team_color.bind(String(n)))
				row.add_child(sw)
				_swatches[team][String(n)] = sw
			var note := TournamentSkin.led("", 14, Color(1.0, 0.45, 0.3))
			note.name = "ColorNote"
			note.custom_minimum_size.y = 18
			v.add_child(note)
			_color_note[team] = note
		match side[1]:
			0: _red_head = h; _red_list = list; _red_panel = p
			1: _bench_head = h; _bench_list = list
			2: _blue_head = h; _blue_list = list; _blue_panel = p
	col.add_child(_label("PRESS READY TO TAKE YOUR SPOT. TEAMS ARE PICKED FOR YOU AND STAY EVEN.", 13, Color(0.55, 0.56, 0.5)))

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
	TournamentSkin.style_button(leave, Color(0.58, 0.58, 0.55), 18)
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
	TournamentSkin.style_button(_start_btn, Color(0.45, 0.95, 0.35), 24)
	_start_btn.pressed.connect(_press_start)
	foot.add_child(_start_btn)
	_countdown = TournamentSkin.led("", 72, TournamentSkin.AMBER)
	_countdown.name = "CountdownLabel"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_countdown.position = Vector2(-300, 24)
	_countdown.custom_minimum_size = Vector2(600, 80)
	_countdown.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_countdown.add_theme_constant_override("outline_size", 10)
	_countdown.visible = false
	add_child(_countdown)
	TournamentSkin.dress_board(self, board, [[Vector2(0.5, 0.93), 110.0, Color(TournamentSkin.PINK, 0.85), 15.0]])
	move_child(_countdown, -1)
	_refresh_controls()
