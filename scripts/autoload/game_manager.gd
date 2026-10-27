extends Node

## Manages 3v3 round loop, target elimination counts, and round resets.
## TODO(PB-05 / Issue #5): Add Center Flag / CTF objectives, tactical bot AI, and multiplayer lobbies.

signal round_updated(round_num: int, remaining_enemies: int, round_time_left: float)
signal round_won(round_num: int)

var current_round: int = 1
var remaining_enemies: int = 0
var round_time_left: float = 180.0
var round_active: bool = false

func _ready() -> void:
	_setup_input_map()

func _process(delta: float) -> void:
	if round_active:
		round_time_left = max(0.0, round_time_left - delta)
		round_updated.emit(current_round, remaining_enemies, round_time_left)

func register_round_start(enemy_count: int) -> void:
	remaining_enemies = enemy_count
	round_time_left = 180.0
	round_active = true
	round_updated.emit(current_round, remaining_enemies, round_time_left)

func notify_enemy_eliminated() -> void:
	remaining_enemies = max(0, remaining_enemies - 1)
	round_updated.emit(current_round, remaining_enemies, round_time_left)
	if remaining_enemies == 0 and round_active:
		round_active = false
		round_won.emit(current_round)

func reset_round() -> void:
	current_round += 1
	PaintBallistics.clear_all()
	get_tree().reload_current_scene()

func _setup_input_map() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("crouch_slide", KEY_CTRL)
	_bind_key("crouch_slide", KEY_C)
	_bind_key("lean_left", KEY_Q)
	_bind_key("lean_right", KEY_E)
	_bind_key("swap_shoulder", KEY_X)
	_bind_key("reload_pod", KEY_R)
	_bind_key("ping_intel", KEY_F)
	_bind_key("bracket_speedball", KEY_1)
	_bind_key("bracket_woodsball", KEY_2)
	_bind_key("bracket_pump", KEY_3)
	_bind_key("reset_round", KEY_T)
	_bind_mouse("fire_primary", MOUSE_BUTTON_LEFT)
	_bind_mouse("fire_secondary_walk", MOUSE_BUTTON_RIGHT)
	_bind_mouse("swap_shoulder", MOUSE_BUTTON_MIDDLE)

func _bind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
