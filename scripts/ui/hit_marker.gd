class_name HitMarker
extends CanvasLayer
## v0.6 (Ren): shooter hit marker. A gritty white X that pops over the crosshair, turns tournament red, and fades,
## plus a crisp tick - only for hits that actually counted:
## - online: NetworkLobby.player_eliminated room event where shooter == me (server-validated, PB-13)
## - offline bots: GameManager.npc_deaths going up (only the local player shoots bots offline)
## Lives under MovementAudioDirector, so no shared HUD / player files are touched.

const TICK := preload("res://assets/audio/paint/hit_marker_tick.wav")
const TICK_DB := -6.0
const SHOW_TIME := 0.42
const POP_TIME := 0.08
const HOLD_TIME := 0.12
const ARM_GAP := 7.0      # px from centre to where each arm starts
const ARM_LEN := 11.0
const ARM_W := 3.0
const HIT_RED := Color(0.96, 0.24, 0.18)

var show_count := 0
var _left := 0.0
var _canvas: Control
var _tick: AudioStreamPlayer
var _last_npc_deaths := -1

func _ready() -> void:
	layer = 60
	_canvas = Control.new()
	_canvas.name = "HitMarkerCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_marker)
	add_child(_canvas)
	_tick = AudioStreamPlayer.new()
	_tick.stream = TICK
	_tick.volume_db = TICK_DB
	add_child(_tick)
	_hook.call_deferred()

func _hook() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and nl.has_signal("room_event") and not nl.is_connected("room_event", _on_room_event):
		nl.connect("room_event", _on_room_event)

func _on_room_event(event_name: String, data: Dictionary) -> void:
	if event_name != "player_eliminated" or not bool(data.get("scored", true)):
		return
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl == null or not nl.has_method("_my_peer_id"):
		return
	var me := int(nl.call("_my_peer_id"))
	if int(data.get("shooter", 0)) == me and int(data.get("victim", 0)) != me:
		show_hit()

func show_hit() -> void:
	show_count += 1
	_left = SHOW_TIME
	_canvas.queue_redraw()
	if _tick.is_inside_tree():
		_tick.play()

func _process(delta: float) -> void:
	_watch_offline_bots()
	if _left > 0.0:
		_left = maxf(0.0, _left - delta)
		_canvas.queue_redraw()

func _watch_offline_bots() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not ("npc_deaths" in gm):
		return
	var d := int(gm.npc_deaths)
	var nl := get_node_or_null("/root/NetworkLobby")
	var online: bool = nl != null and nl.has_method("is_online_client") and bool(nl.call("is_online_client"))
	if _last_npc_deaths >= 0 and d > _last_npc_deaths and not online:
		show_hit()
	_last_npc_deaths = d

func _draw_marker() -> void:
	if _left <= 0.0:
		return
	var age := SHOW_TIME - _left
	var pop := 1.0 + 0.45 * (1.0 - clampf(age / POP_TIME, 0.0, 1.0))
	var fade := 1.0 if age < HOLD_TIME else clampf(_left / (SHOW_TIME - HOLD_TIME), 0.0, 1.0)
	var col := Color.WHITE.lerp(HIT_RED, clampf((age - 0.03) / 0.12, 0.0, 1.0))
	col.a = fade
	var shadow := Color(0, 0, 0, 0.75 * fade)
	var c := _canvas.size * 0.5
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var u: Vector2 = dir.normalized()
		var a: Vector2 = c + u * ARM_GAP * pop
		var b: Vector2 = c + u * (ARM_GAP + ARM_LEN) * pop
		_canvas.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), shadow, ARM_W + 2.0, true)
		_canvas.draw_line(a, b, col, ARM_W, true)
