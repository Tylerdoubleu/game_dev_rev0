class_name RespawnScreen
extends CanvasLayer
## v0.6 (Ren): Gritty 2000s tournament "you've been hit" + respawn picker. Short words, one clear map.
## Shows: who hit you, a top-down view of YOUR half of the field (drawn the way you face it, enemy at the top),
## and five big numbered spawn spots you click or pick with 1-5. Emits zone_picked(index) - the arena does the respawn.
##   var rs := RespawnScreen.new(); add_child(rs)
##   rs.zone_picked.connect(func(i): ...)
##   rs.open("Viper", "ALPHA", arena._get_team_respawn_zones("ALPHA"), deaths, max_deaths)

signal zone_picked(index: int)

const SHORT_NAMES := {"snake_corner": "SNAKE CORNER", "left_brick": "SNAKE BRICK", "home_gate": "HOME",
	"right_brick": "DORITO BRICK", "dorito_corner": "DORITO CORNER"}
const DEFAULT_ZONE := 2
const RED := Color(0.86, 0.2, 0.17)
const BLUE := Color(0.2, 0.45, 0.95)
## Your half of the Speedball field (speedball_arena_builder.gd positions, |z| from the 50 line): x, z, size x, size z.
const HALF_BUNKERS := [
	[0, 48, 3.6, 1.2], [0, 38, 3.2, 1.4], [-2.6, 41.8, 1.5, 1.5], [-1.8, 36.2, 1.5, 1.5], [-0.3, 35, 1.0, 3.4],
	[-11, 29, 2.6, 1.6], [11, 29, 2.6, 1.6], [-22, 31, 2.2, 2.2], [22, 31, 2.2, 2.2], [0, 19, 2.8, 1.8],
	[-8.5, 17.5, 2, 2], [8.5, 17.5, 2, 2], [-18.5, 18.5, 2.4, 2], [18.5, 18.5, 2.4, 2], [-5.5, 9, 1.8, 1.8],
	[5.5, 9, 1.8, 1.8], [-14.5, 9.5, 2.2, 2.2], [14.5, 9.5, 2.2, 2.2], [32, 35, 2.6, 2.6], [34.5, 23, 2.5, 2.5],
	[36.5, 11.5, 2.5, 2.5], [-33, 35, 2.8, 2.2], [-28.5, 24.5, 2.2, 2.2],
	[0, 0, 4.5, 1.8], [-9.5, 0, 2.4, 1.4], [9.5, 0, 2.4, 1.4], [-19, 0, 2.2, 1.6], [19, 0, 2.2, 1.6], [38, 0, 3, 3],
	[-35, 15, 1.1, 9.5], [-37.2, 5.5, 1.1, 9.5], [-35, 20, 2.6, 1.3], [-36.1, 10.2, 2.8, 1.3], [-37.2, 0, 3.0, 1.3]]
const FIELD_HALF_W := 42.0
const FIELD_DEPTH := 50.0
const MAP_SIZE := Vector2(880, 440)

var handle_keys := true
var _team := "ALPHA"
var _zones: Array = []
var _hit_label: Label
var _by_label: Label
var _deaths_label: Label
var _map: Control
var _spots: Array[Button] = []
var _root: Control

func _init() -> void:
	name = "RespawnScreen"
	layer = 12
	visible = false

func _ready() -> void:
	_build()

func open(killer: String, team: String, zones: Array, deaths: int = -1, max_deaths: int = -1) -> void:
	if _root == null:
		_build()
	_team = team
	_zones = zones
	_by_label.text = ("by " + killer) if killer != "" else ""
	_by_label.visible = killer != ""
	_deaths_label.text = ("DEATHS %d / %d" % [deaths, max_deaths]) if deaths >= 0 and max_deaths > 0 else ""
	_layout_spots()
	_map.queue_redraw()
	visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)

func close() -> void:
	visible = false

func pick(index: int) -> void:
	if not visible or index < 0 or index >= _zones.size():
		return
	close()
	zone_picked.emit(index)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not handle_keys:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_5:
			pick(_index_for_slot(k - KEY_1))
			get_viewport().set_input_as_handled()

## Numbers always run 1-5 left to right as you see the map (BRAVO's view is mirrored, so its zones count backwards).
func _index_for_slot(slot: int) -> int:
	return slot if _team == "ALPHA" else _zones.size() - 1 - slot

func _slot_for_index(index: int) -> int:
	return _index_for_slot(index)

func _team_color() -> Color:
	return RED if _team == "ALPHA" else BLUE

## Map coordinates: you look toward the enemy, so the 50 line is at the top and your back line at the bottom.
## ALPHA faces -Z (+X on the right); BRAVO faces +Z, so its view is mirrored.
func _to_map(x: float, z_abs: float) -> Vector2:
	var m := 1.0 if _team == "ALPHA" else -1.0
	return Vector2((x * m + FIELD_HALF_W) / (FIELD_HALF_W * 2.0) * MAP_SIZE.x, (z_abs + 2.0) / (FIELD_DEPTH + 2.0) * MAP_SIZE.y)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.02, 0.04, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var paint := Control.new()
	paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(paint)
	paint.resized.connect(func() -> void:
		for c in paint.get_children():
			c.queue_free()
		var s := paint.size
		TournamentSkin.splat(paint, Vector2(s.x * 0.08, s.y * 0.12), 360, Color(TournamentSkin.PINK, 0.55), 20)
		TournamentSkin.splat(paint, Vector2(s.x * 0.93, s.y * 0.85), 300, Color(TournamentSkin.PINK, 0.4), -35)
		TournamentSkin.splat(paint, Vector2(s.x * 0.9, s.y * 0.1), 160, Color(TournamentSkin.NEON, 0.25), 70))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	_hit_label = TournamentSkin.label("SPLATTED", 64, TournamentSkin.PINK, TournamentSkin.STENCIL, 8)
	head.add_child(_hit_label)
	_by_label = TournamentSkin.marker("", 34, TournamentSkin.CHALK)
	head.add_child(_by_label)

	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	col.add_child(board)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	board.add_child(inner)
	var title := TournamentSkin.label("PICK YOUR SPAWN", 26, TournamentSkin.NEON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(title)
	_map = Control.new()
	_map.custom_minimum_size = MAP_SIZE
	_map.clip_contents = true
	_map.draw.connect(_draw_map)
	inner.add_child(_map)
	for i in 5:
		var b := Button.new()
		b.name = "Spot%d" % (i + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.custom_minimum_size = Vector2(150, 92)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func() -> void: pick(idx))
		b.mouse_entered.connect(func() -> void: _map.queue_redraw())
		b.mouse_exited.connect(func() -> void: _map.queue_redraw())
		_map.add_child(b)
		_spots.append(b)

	var foot := HBoxContainer.new()
	col.add_child(foot)
	var keys := TournamentSkin.led("CLICK A SPOT  OR  PRESS 1-5", 20, TournamentSkin.AMBER)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(keys)
	_deaths_label = TournamentSkin.led("", 20, TournamentSkin.CHALK)
	foot.add_child(_deaths_label)

func _layout_spots() -> void:
	for i in _spots.size():
		var b := _spots[i]
		b.visible = i < _zones.size()
		if not b.visible:
			continue
		var p: Vector3 = _zones[i]["pos"]
		b.position = _to_map(p.x, absf(p.z)) - Vector2(75, 64)
		b.tooltip_text = ""

func _spot_name(i: int) -> String:
	var z: Dictionary = _zones[i]
	return SHORT_NAMES.get(z.get("id", ""), String(z.get("title", "")).get_slice("] ", 1))

func _draw_map() -> void:
	var tc := _team_color()
	var font: Font = TournamentSkin.STENCIL
	var mfont: Font = TournamentSkin.MARKER
	# turf + half-field
	_map.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.11, 0.16, 0.1, 0.96))
	var a := _to_map(-FIELD_HALF_W + 2.0, 0.0)
	var b := _to_map(FIELD_HALF_W - 2.0, FIELD_DEPTH)
	var field := Rect2(Vector2(minf(a.x, b.x), a.y), Vector2(absf(b.x - a.x), b.y - a.y))
	_map.draw_rect(field, Color(0.15, 0.22, 0.13))
	_map.draw_rect(field, Color(1, 1, 1, 0.18), false, 2.0)
	# 50 line (enemy beyond) + your back line
	var y50 := _to_map(0, 0).y
	_map.draw_line(Vector2(field.position.x, y50), Vector2(field.end.x, y50), Color(TournamentSkin.CHALK, 0.6), 3.0)
	_map.draw_rect(Rect2(0, 0, MAP_SIZE.x, y50), Color(0.3, 0.05, 0.05, 0.35) if _team != "ALPHA" else Color(0.05, 0.1, 0.3, 0.35))
	_map.draw_string(font, Vector2(0, y50 + 26), "ENEMY  ▲", HORIZONTAL_ALIGNMENT_CENTER, MAP_SIZE.x, 18, Color(TournamentSkin.CHALK, 0.55))
	var yb := _to_map(0, 45.5).y
	_map.draw_dashed_line(Vector2(field.position.x, yb), Vector2(field.end.x, yb), Color(tc, 0.55), 2.0, 10.0)
	# side names (snake / dorito) on the edges, mirrored for BRAVO
	var snake_x := _to_map(-38, 0).x
	var dorito_x := _to_map(38, 0).x
	_map.draw_string(mfont, Vector2(snake_x - 30, MAP_SIZE.y * 0.32), "SNAKE", HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color(TournamentSkin.CHALK, 0.5))
	_map.draw_string(mfont, Vector2(dorito_x - 30, MAP_SIZE.y * 0.32), "DORITO", HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color(TournamentSkin.CHALK, 0.5))
	# bunkers (muted, just for orientation)
	var px := MAP_SIZE.x / (FIELD_HALF_W * 2.0)
	var pz := MAP_SIZE.y / (FIELD_DEPTH + 2.0)
	for bk in HALF_BUNKERS:
		var c := _to_map(bk[0], bk[1])
		var s := Vector2(bk[2] * px, bk[3] * pz) * 1.15
		_map.draw_rect(Rect2(c - s * 0.5, s), Color(0.55, 0.55, 0.48, 0.5))
	# spawn spots
	for i in mini(_zones.size(), _spots.size()):
		var btn := _spots[i]
		var cpos := btn.position + Vector2(75, 64)
		var hot := btn.is_hovered()
		var r := 28.0 if not hot else 32.0
		_map.draw_circle(cpos, r + 6.0, Color(0, 0, 0, 0.55))
		_map.draw_circle(cpos, r, TournamentSkin.NEON if hot else tc)
		_map.draw_arc(cpos, r, 0, TAU, 40, TournamentSkin.NEON, 3.0 if i == DEFAULT_ZONE or hot else 2.0)
		var num := str(_slot_for_index(i) + 1)
		var ink := Color(0.06, 0.06, 0.05) if hot else Color.WHITE
		_map.draw_string(font, cpos + Vector2(-20, 11), num, HORIZONTAL_ALIGNMENT_CENTER, 40, 30, ink)
		var nm := _spot_name(i)
		var nc := TournamentSkin.NEON if hot else TournamentSkin.CHALK
		var lx := clampf(cpos.x - 85.0, 4.0, MAP_SIZE.x - 174.0)
		_map.draw_string_outline(font, Vector2(lx, cpos.y - r - 12), nm, HORIZONTAL_ALIGNMENT_CENTER, 170, 18, 5, Color(0, 0, 0, 0.9))
		_map.draw_string(font, Vector2(lx, cpos.y - r - 12), nm, HORIZONTAL_ALIGNMENT_CENTER, 170, 18, nc)
