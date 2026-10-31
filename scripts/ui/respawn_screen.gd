class_name RespawnScreen
extends CanvasLayer
## v0.6 (Ren): Gritty 2000s tournament "you've been hit" + respawn picker. Short words, one clear map.
## Shows: who hit you, a top-down mini map of the whole field (drawn the way you face it: your base at the bottom,
## enemy base at the top), five big numbered spawn spots you click or pick with 1-5, and optionally the shooter and
## where you went down. Emits zone_picked(index) - the arena does the respawn.
##   var rs := RespawnScreen.new(); add_child(rs)
##   rs.zone_picked.connect(func(i): ...)
##   rs.open("Viper", "ALPHA", arena._get_team_respawn_zones("ALPHA"), deaths, max_deaths, shooter_pos, death_pos)
##   (shooter_pos / death_pos are world positions; pass NO_POS or leave them out to hide them)

signal zone_picked(index: int)

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
## Woodsball Heli Crash (gritty_art_theme.gd build_woodsball_crash_site_map): mirrored per-half cover, then
## pieces that sit at fixed WORLD positions (towers, heli, 50-line). Rects are x, z, size x, size z.
const WOODS_HALF := [
	[0, 48, 3.8, 1.2], [0, 38, 3.2, 1.4], [-2.6, 41.8, 1.7, 1.7], [-1.8, 36.2, 1.7, 1.7], [-0.3, 35, 1.0, 3.4],
	[-11, 31, 2.8, 1.5], [11, 31, 2.8, 1.5], [-22, 31, 1.7, 1.7], [22, 31, 1.7, 1.7], [0, 19, 3.0, 1.6],
	[-8.5, 17.5, 1.7, 1.7], [8.5, 17.5, 1.7, 1.7], [-18.5, 16.5, 2.6, 1.8], [18.5, 16.5, 2.6, 1.8],
	[-6.2, 9.2, 1.9, 1.9], [6.2, 9.2, 1.9, 1.9], [-14.5, 9.5, 1.7, 1.7], [14.5, 9.5, 1.7, 1.7],
	[32, 35, 2.6, 2.2], [34.5, 23, 1.7, 1.7], [36.5, 11.5, 2.5, 2.2], [-33, 35, 2.8, 2.0], [-28.5, 24.5, 1.7, 1.7]]
const WOODS_WORLD := [
	[-11, 0, 1.7, 1.7], [11, 0, 1.7, 1.7], [-17.5, 0, 2.4, 1.8], [17.5, 0, 2.4, 1.8], [38, 0, 1.7, 1.7],
	[-35, 15, 1.1, 9.5], [-37.2, 5.5, 1.1, 9.5], [-37.2, -5.5, 1.1, 9.5], [-35, -15, 1.1, 9.5],
	[-35, 20, 2.6, 1.3], [-36.1, 10.2, 2.8, 1.3], [-37.2, 0, 3.0, 1.5], [-36.1, -10.2, 2.8, 1.3], [-35, -20, 2.6, 1.3]]
## Towers (4.8 m decks) and the crashed fuselage, drawn darker so they read as the big landmarks.
const WOODS_LANDMARKS := [[-25, 0, 4.8, 4.8], [25, 0, 4.8, 4.8], [-11.5, 24, 4.8, 4.8], [11.5, -24, 4.8, 4.8], [-2, -0.35, 16, 3.2]]
const FIELD_HALF_W := 42.0
const FIELD_DEPTH := 50.0
const MAP_SIZE := Vector2(440, 520)
const NO_POS := Vector3(INF, INF, INF)
const SPOT_HIT := 70.0

var handle_keys := true
var _team := "ALPHA"
var _zones: Array = []
var _hit_label: Label
var _by_label: Label
var _deaths_label: Label
var _map: Control
var _spots: Array[Button] = []
var _shooter_pos := NO_POS
var _death_pos := NO_POS
var _killer := ""
var _dots: Array = []
var _map_id := "speedball"
var _root: Control

func _init() -> void:
	name = "RespawnScreen"
	layer = 12
	visible = false

func _ready() -> void:
	_build()

func open(killer: String, team: String, zones: Array, deaths: int = -1, max_deaths: int = -1,
		shooter_pos: Vector3 = NO_POS, death_pos: Vector3 = NO_POS, map_id: String = "") -> void:
	if _root == null:
		_build()
	_team = team
	_zones = zones
	_killer = short_name(killer)
	_map_id = map_id if map_id != "" else _current_map()
	_shooter_pos = shooter_pos
	_death_pos = death_pos
	_by_label.text = ("by " + _killer) if _killer != "" else ""
	_by_label.visible = _killer != ""
	_deaths_label.text = ("DEATHS %d / %d" % [deaths, max_deaths]) if deaths >= 0 and max_deaths > 0 else ""
	_layout_spots()
	_map.queue_redraw()
	visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)

## Live player dots: [{"team": "ALPHA"/"BRAVO", "pos": Vector3}, ...]. Call as often as you like while open.
## Only players standing on YOUR half are drawn (Tyler 10/31: no calling out enemies on the far half).
func set_players(dots: Array) -> void:
	_dots = dots.filter(func(d) -> bool: return d.has("pos") and on_my_half(d["pos"]))
	if _map != null:
		_map.queue_redraw()

## "Viper [MASK / GOGGLES]" -> "Viper": the screen only ever shows the name.
static func short_name(n: String) -> String:
	var i := n.find(" [")
	return (n.substr(0, i) if i >= 0 else n).strip_edges()

static func is_woods(map_id: String) -> bool:
	return map_id in ["woodsball_crash", "woods", "woodsball", "crash_site"]

func _current_map() -> String:
	var nl: Node = Engine.get_main_loop().root.get_node_or_null("NetworkLobby") if Engine.get_main_loop() is SceneTree else null
	return String(nl.get("selected_map")) if nl != null and nl.get("selected_map") != null else "speedball"

func on_my_half(p: Vector3) -> bool:
	return p.z * _side() > 0.0

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

## Map coordinates: you look toward the enemy, so your base is at the bottom and theirs at the top.
## ALPHA's base is +Z and it faces -Z (+X on the right); BRAVO's base is -Z and it faces +Z, so its view is mirrored.
func _side() -> float:
	return 1.0 if _team == "ALPHA" else -1.0

func _to_map(x: float, z: float) -> Vector2:
	var s := _side()
	var depth := FIELD_DEPTH + 2.0
	return Vector2((x * s + FIELD_HALF_W) / (FIELD_HALF_W * 2.0) * MAP_SIZE.x, (z * s + depth) / (depth * 2.0) * MAP_SIZE.y)

## Your-side coordinates (z_own > 0 = your half) for the static bunker table.
func _own_to_map(x: float, z_own: float) -> Vector2:
	return _to_map(x, z_own * _side())

static func _has(p: Vector3) -> bool:
	return is_finite(p.x)

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
	_hit_label = TournamentSkin.label("SPLATTED", 52, TournamentSkin.PINK, TournamentSkin.STENCIL, 8)
	head.add_child(_hit_label)
	_by_label = TournamentSkin.marker("", 30, TournamentSkin.CHALK)
	head.add_child(_by_label)

	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(board)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	board.add_child(inner)
	var title := TournamentSkin.label("PICK YOUR SPAWN", 22, TournamentSkin.NEON)
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
		b.custom_minimum_size = Vector2(SPOT_HIT, SPOT_HIT)
		b.size = Vector2(SPOT_HIT, SPOT_HIT)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		b.pressed.connect(func() -> void: pick(idx))
		b.mouse_entered.connect(func() -> void: _map.queue_redraw())
		b.mouse_exited.connect(func() -> void: _map.queue_redraw())
		_map.add_child(b)
		_spots.append(b)

	var foot := HBoxContainer.new()
	foot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	foot.custom_minimum_size.x = MAP_SIZE.x + 24.0
	col.add_child(foot)
	var keys := TournamentSkin.led("CLICK A SPOT  OR  PRESS 1-5", 18, TournamentSkin.AMBER)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(keys)
	_deaths_label = TournamentSkin.led("", 18, TournamentSkin.CHALK)
	foot.add_child(_deaths_label)

func _layout_spots() -> void:
	for i in _spots.size():
		var b := _spots[i]
		b.visible = i < _zones.size()
		if not b.visible:
			continue
		var p: Vector3 = _zones[i]["pos"]
		b.position = _to_map(p.x, p.z) - Vector2(SPOT_HIT, SPOT_HIT) * 0.5
		b.tooltip_text = ""

func _draw_map() -> void:
	var tc := _team_color()
	var ec := BLUE if _team == "ALPHA" else RED
	var font: Font = TournamentSkin.STENCIL
	var mfont: Font = TournamentSkin.MARKER
	_map.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.09, 0.13, 0.08, 0.97))
	var a := _own_to_map(-(FIELD_HALF_W - 2.0), -FIELD_DEPTH)
	var b := _own_to_map(FIELD_HALF_W - 2.0, FIELD_DEPTH)
	var field := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	var y50 := _own_to_map(0, 0).y
	# halves: enemy tint on top, yours on the bottom
	_map.draw_rect(Rect2(field.position, Vector2(field.size.x, y50 - field.position.y)), Color(ec.darkened(0.55), 0.85))
	_map.draw_rect(Rect2(Vector2(field.position.x, y50), Vector2(field.size.x, field.end.y - y50)), Color(tc.darkened(0.6), 0.85))
	_map.draw_rect(field, Color(1, 1, 1, 0.22), false, 2.0)
	_map.draw_line(Vector2(field.position.x, y50), Vector2(field.end.x, y50), Color(TournamentSkin.CHALK, 0.6), 2.0)
	for zz in [45.5, -45.5]:
		var yb := _own_to_map(0, zz).y
		_map.draw_dashed_line(Vector2(field.position.x, yb), Vector2(field.end.x, yb), Color(tc if zz > 0 else ec, 0.7), 2.0, 8.0)
	# bunkers on both halves
	var px := MAP_SIZE.x / (FIELD_HALF_W * 2.0)
	var pz := MAP_SIZE.y / ((FIELD_DEPTH + 2.0) * 2.0)
	var cover := Color(0.62, 0.62, 0.55, 0.6)
	if is_woods(_map_id):
		cover = Color(0.66, 0.52, 0.34, 0.7)
		for bk in WOODS_HALF:
			for half in [1.0, -1.0]:
				_draw_cover(_own_to_map(bk[0], float(bk[1]) * half), bk, px, pz, cover)
		for bk in WOODS_WORLD:
			_draw_cover(_to_map(bk[0], bk[1]), bk, px, pz, cover)
		for bk in WOODS_LANDMARKS:
			_draw_cover(_to_map(bk[0], bk[1]), bk, px, pz, Color(0.3, 0.36, 0.22, 0.95), true)
	else:
		for bk in HALF_BUNKERS:
			for half in ([1.0] if float(bk[1]) == 0.0 else [1.0, -1.0]):
				_draw_cover(_own_to_map(bk[0], float(bk[1]) * half), bk, px, pz, cover)
	# live players on your half only
	for d in _dots:
		var pp: Vector3 = d["pos"]
		var dc := RED if String(d.get("team", "")) == "ALPHA" else BLUE
		var mp := _to_map(pp.x, pp.z)
		_map.draw_circle(mp, 6.5, Color.BLACK)
		_map.draw_circle(mp, 5.0, dc.lightened(0.15))
	# shooter, where you went down, and the line between them
	var has_s := _has(_shooter_pos)
	var has_d := _has(_death_pos)
	var sp := _to_map(_shooter_pos.x, _shooter_pos.z) if has_s else Vector2.ZERO
	var dp := _to_map(_death_pos.x, _death_pos.z) if has_d else Vector2.ZERO
	if has_s and has_d:
		_map.draw_dashed_line(sp, dp, Color(TournamentSkin.PINK, 0.9), 2.0, 6.0)
	if has_d:
		var k := 7.0
		_map.draw_line(dp + Vector2(-k, -k), dp + Vector2(k, k), Color.BLACK, 6.0)
		_map.draw_line(dp + Vector2(-k, k), dp + Vector2(k, -k), Color.BLACK, 6.0)
		_map.draw_line(dp + Vector2(-k, -k), dp + Vector2(k, k), Color.WHITE, 3.0)
		_map.draw_line(dp + Vector2(-k, k), dp + Vector2(k, -k), Color.WHITE, 3.0)
		_label_at(dp + Vector2(12, 5), "YOU", Color.WHITE)
	if has_s:
		_map.draw_circle(sp, 9.0, Color.BLACK)
		_map.draw_circle(sp, 7.0, TournamentSkin.PINK)
		_label_at(sp + Vector2(12, 5), _killer.to_upper() if _killer != "" else "SHOOTER", TournamentSkin.PINK)
	# spawn spots: big numbers only
	for i in mini(_zones.size(), _spots.size()):
		var btn := _spots[i]
		var cpos := btn.position + Vector2(SPOT_HIT, SPOT_HIT) * 0.5
		var hot := btn.is_hovered()
		var r := 19.0 if not hot else 23.0
		_map.draw_circle(cpos, r + 4.0, Color(0, 0, 0, 0.6))
		_map.draw_circle(cpos, r, TournamentSkin.NEON if hot else Color(0.07, 0.07, 0.06))
		_map.draw_arc(cpos, r, 0, TAU, 40, TournamentSkin.NEON, 3.0)
		var ink := Color(0.06, 0.06, 0.05) if hot else TournamentSkin.NEON
		_map.draw_string(font, cpos + Vector2(-20, 9), str(_slot_for_index(i) + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 24, ink)

func _draw_cover(c: Vector2, bk: Array, px: float, pz: float, col: Color, outline := false) -> void:
	var sz := Vector2(bk[2] * px, bk[3] * pz) * 1.2
	_map.draw_rect(Rect2(c - sz * 0.5, sz), col)
	if outline:
		_map.draw_rect(Rect2(c - sz * 0.5, sz), Color(0, 0, 0, 0.7), false, 2.0)

## Keeps a marker label fully inside the map: flips left of the dot near the right edge, then clamps both edges.
func label_pos(at: Vector2, w: float) -> Vector2:
	if at.x + w > MAP_SIZE.x - 4.0:
		at.x -= w + 24.0
	at.x = clampf(at.x, 4.0, MAP_SIZE.x - 4.0 - w)
	at.y = clampf(at.y, 16.0, MAP_SIZE.y - 4.0)
	return at

func _label_at(at: Vector2, text: String, color: Color) -> void:
	var font: Font = TournamentSkin.STENCIL
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	at = label_pos(at, w)
	_map.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
	_map.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
