class_name CallsignEntry
extends Control
## v0.7 (Ren): Gritty 2000s tournament callsign picker. A Sharpie-on-tape text field + SAVE, checked here first with the
## server's rule (3-16 letters, numbers, _ or -), then reserved through Tim's ProfileApi (scripts/systems/profile_api.gd,
## read-only here), so no two players hold the same name. States: idle, saving, saved, invalid (400),
## taken (409 callsign_taken), offline (no server: the name is kept and re-sent every RETRY_SECONDS while open).
##
## Hookup (one line):  var ce := CallsignEntry.new(); add_child(ce); ce.open("Viper")
##   ce.callsign_saved.connect(func(n): ...)   # n = the name the server reserved (display case kept)
##   ce.profile_loaded.connect(func(p): ...)   # p = the 200 profile dict from PUT /api/profile/callsign
## It makes its own ProfileApi unless you hand it one first with bind_api(api) (CareerScreen shares its own).
## No saved profile yet or a stale token (401) -> ProfileApi makes a fresh one and retries once. Enter = SAVE, Esc = close.

signal callsign_saved(callsign: String)
signal profile_loaded(profile: Dictionary)
signal closed

enum State { IDLE, SAVING, SAVED, INVALID, TAKEN, OFFLINE, ERROR }
const CALLSIGN_MIN := 3
const CALLSIGN_MAX := 16
const RETRY_SECONDS := 15.0
const RULE_TEXT := "3-16  //  A-Z  0-9  _  -"
const STATE_TEXT := {
	State.IDLE: "PICK YOUR NAME", State.SAVING: "SAVING...", State.SAVED: "SAVED",
	State.INVALID: "BAD NAME", State.TAKEN: "CALLSIGN TAKEN", State.OFFLINE: "NO SERVER  -  WILL RETRY",
	State.ERROR: "SAVE FAILED  -  TRY AGAIN",
}
const STATE_COLOR := {
	State.IDLE: TournamentSkin.AMBER, State.SAVING: TournamentSkin.AMBER, State.SAVED: Color(0.45, 0.95, 0.35),
	State.INVALID: TournamentSkin.PINK, State.TAKEN: TournamentSkin.PINK, State.OFFLINE: TournamentSkin.AMBER,
	State.ERROR: TournamentSkin.PINK,
}
const BOARD_SIZE := Vector2(640, 0)

var api: ProfileApi
var state: int = State.IDLE
var close_on_save: bool = true
## The name being saved (kept while offline so the retry can re-send it).
var pending: String = ""
var _field: LineEdit
var _save_btn: Button
var _status: Label
var _rule: Label
var _board: PanelContainer
var _retry: Timer

func _ready() -> void:
	_build_ui()
	if api == null:
		var a := ProfileApi.new()
		bind_api(a)
		add_child(a)
	_retry = Timer.new()
	_retry.wait_time = RETRY_SECONDS
	_retry.one_shot = true
	_retry.timeout.connect(func() -> void:
		if state == State.OFFLINE and pending != "": _send(pending))
	add_child(_retry)
	visible = false

## Mirrors the server's /^[A-Za-z0-9_-]{3,16}$/.
static func is_valid_callsign(s: String) -> bool:
	if s.length() < CALLSIGN_MIN or s.length() > CALLSIGN_MAX:
		return false
	for c in s:
		var u := c.unicode_at(0)
		if not ((u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or c == "_" or c == "-"):
			return false
	return true

func bind_api(a: ProfileApi) -> void:
	if api != null and api.completed.is_connected(_on_completed):
		api.completed.disconnect(_on_completed)
	api = a
	api.completed.connect(_on_completed)

func open(current: String = "") -> void:
	if _field == null:
		_build_ui()
	_field.text = current
	set_state(State.IDLE)
	_on_text_changed(current)
	visible = true
	_field.grab_focus.call_deferred()
	_field.caret_column = current.length()

func close() -> void:
	visible = false
	closed.emit()

func submit() -> void:
	var name := _field.text.strip_edges()
	if not is_valid_callsign(name):
		set_state(State.INVALID)
		return
	_send(name)

func _send(name: String) -> void:
	pending = name
	set_state(State.SAVING)
	if api == null:
		set_state(State.OFFLINE)
		return
	api.set_callsign(name)  # ProfileApi creates a profile first if needed and handles a stale-token 401 once

static func _offline(status: int) -> bool:
	return status == 0 or status == 404 or status >= 500

func set_state(s: int, _name: String = "") -> void:
	state = s
	if _status == null:
		return
	_status.text = STATE_TEXT[s]
	_status.add_theme_color_override("font_color", STATE_COLOR[s])
	_status.add_theme_color_override("font_shadow_color", Color(STATE_COLOR[s], 0.45))
	_save_btn.disabled = s == State.SAVING or not is_valid_callsign(_field.text.strip_edges())
	_field.editable = s != State.SAVING
	var bad := s == State.INVALID or s == State.TAKEN
	_field.add_theme_stylebox_override("normal", TournamentSkin.card(TournamentSkin.PINK if bad else TournamentSkin.CHALK, 16, 8))
	_rule.add_theme_color_override("font_color", TournamentSkin.PINK if s == State.INVALID else TournamentSkin.MUTED)

func _on_completed(action: String, status: int, d: Dictionary) -> void:
	if pending == "":
		return
	if action == "set_callsign":
		match status:
			200:
				var name := String(d.get("callsign", pending)) if d.get("callsign") != null else pending
				pending = ""
				set_state(State.SAVED)
				callsign_saved.emit(name)
				profile_loaded.emit(d)
				if close_on_save and is_inside_tree():
					get_tree().create_timer(0.6).timeout.connect(func() -> void:
						if state == State.SAVED: close())
			409: _fail(State.TAKEN)
			400: _fail(State.INVALID)
			_:
				_fail(State.OFFLINE if _offline(status) else State.ERROR)

func _fail(s: int) -> void:
	if s != State.OFFLINE:
		pending = ""
	set_state(s)
	if s == State.OFFLINE and _retry and _retry.is_inside_tree():
		_retry.start()

func _on_text_changed(t: String) -> void:
	if state != State.SAVING and state != State.IDLE:
		set_state(State.IDLE)
	_save_btn.disabled = state == State.SAVING or not is_valid_callsign(t.strip_edges())
	_rule.add_theme_color_override("font_color", TournamentSkin.MUTED if t == "" or is_valid_callsign(t.strip_edges()) else TournamentSkin.PINK)

func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	if _board != null:
		return
	name = "CallsignEntry"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_board = PanelContainer.new()
	_board.name = "Board"
	_board.custom_minimum_size = BOARD_SIZE
	_board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	center.add_child(_board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_board.add_child(col)
	col.add_child(TournamentSkin.label("CALLSIGN", 46, TournamentSkin.NEON, TournamentSkin.STENCIL, 8))
	_field = LineEdit.new()
	_field.name = "CallsignField"
	_field.max_length = CALLSIGN_MAX
	_field.placeholder_text = "VIPER"
	_field.custom_minimum_size = Vector2(0, 64)
	_field.add_theme_font_override("font", TournamentSkin.MARKER)
	_field.add_theme_font_size_override("font_size", 34)
	_field.add_theme_color_override("font_color", Color(0.08, 0.08, 0.07))
	_field.add_theme_color_override("font_placeholder_color", Color(0.08, 0.08, 0.07, 0.35))
	_field.add_theme_color_override("caret_color", Color(0.08, 0.08, 0.07))
	_field.add_theme_stylebox_override("normal", TournamentSkin.card(TournamentSkin.CHALK, 16, 8))
	_field.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_field.text_changed.connect(_on_text_changed)
	_field.text_submitted.connect(func(_t: String) -> void: submit())
	col.add_child(_field)
	_rule = TournamentSkin.label(RULE_TEXT, 16, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2)
	col.add_child(_rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_status = TournamentSkin.led("PICK YOUR NAME", 24)
	_status.name = "Status"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	row.add_child(_status)
	var cancel := TournamentSkin.style_button(Button.new(), Color(0.55, 0.56, 0.52), 20)
	cancel.text = "BACK"
	cancel.custom_minimum_size = Vector2(110, 52)
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_save_btn = TournamentSkin.style_button(Button.new(), TournamentSkin.NEON, 22)
	_save_btn.name = "SaveButton"
	_save_btn.text = "SAVE"
	_save_btn.custom_minimum_size = Vector2(130, 52)
	_save_btn.pressed.connect(submit)
	row.add_child(_save_btn)
	TournamentSkin.dress_board(self, _board, [[Vector2(0.92, 0.18), 120.0, Color(TournamentSkin.PINK, 0.55), 20.0], [Vector2(0.66, 0.1), 90.0, Color(TournamentSkin.NEON, 0.35), -30.0]])
