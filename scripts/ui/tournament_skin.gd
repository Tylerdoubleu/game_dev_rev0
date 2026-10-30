class_name TournamentSkin
extends RefCounted
## v0.6 (Ren): shared Gritty 2000s Tournament skin for the lobby browser and waiting room.
## Field netting backdrop, painted plywood scoreboard, scuffed vinyl cards, masking tape, paint splats,
## a stencil headline font, a Sharpie roster font and an amber LED font. Textures come from
## scripts/tools/gen_lobby_ui_textures.py; fonts are OFL / Apache (licenses in assets/fonts/).

const STENCIL := preload("res://assets/fonts/BlackOpsOne-Regular.ttf")
const MARKER := preload("res://assets/fonts/PermanentMarker-Regular.ttf")
const LED := preload("res://assets/fonts/ShareTechMono-Regular.ttf")
const NETTING := preload("res://assets/textures/ui/ui_netting_bg.png")
const PLYWOOD := preload("res://assets/textures/ui/ui_plywood_board.png")
const VINYL := preload("res://assets/textures/ui/ui_vinyl_card.png")
const TAPE := preload("res://assets/textures/ui/ui_tape_strip.png")
const SPLAT := preload("res://assets/textures/paint_splat_mask.png")

const NEON := Color(0.95, 1.0, 0.15)
const PINK := Color(1.0, 0.28, 0.62)
const AMBER := Color(1.0, 0.68, 0.18)
const CHALK := Color(0.86, 0.87, 0.8)
const MUTED := Color(0.6, 0.62, 0.55)

## Full-screen backdrop: tiled field netting with a dark vignette. Add as the first child.
static func backdrop() -> Control:
	var root := Control.new()
	root.name = "TournamentBackdrop"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var net := TextureRect.new()
	net.texture = NETTING
	net.stretch_mode = TextureRect.STRETCH_TILE
	net.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	net.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(net)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	return root

static func _tex_box(tex: Texture2D, tint: Color, margin: int, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.modulate_color = tint
	sb.set_texture_margin_all(margin)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = pad_x; sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y; sb.content_margin_bottom = pad_y
	return sb

## The big painted-plywood scoreboard the whole menu sits on.
static func board_style() -> StyleBox:
	return _tex_box(PLYWOOD, Color(1, 1, 1), 8, 26, 20)

## Scuffed vinyl card tinted to a color (rows, team panels, buttons).
static func card(tint: Color, pad_x := 12, pad_y := 6) -> StyleBox:
	return _tex_box(VINYL, tint, 10, pad_x, pad_y)

static func label(text: String, size: int, color: Color, font: Font = STENCIL, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## Amber LED readout (status lines, counts, countdown) with a soft glow.
static func led(text: String, size: int, color: Color = AMBER) -> Label:
	var l := label(text, size, color, LED, 0)
	l.add_theme_color_override("font_shadow_color", Color(color, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", maxi(4, size / 5))
	return l

## Sharpie-on-tape roster name.
static func marker(text: String, size: int, color: Color) -> Label:
	return label(text, size, color, MARKER, 3)

## Spray-painted vinyl button. accent = paint color for the face.
static func style_button(b: Button, accent: Color, size := 18, dark_text := true) -> Button:
	b.add_theme_font_override("font", STENCIL)
	b.add_theme_font_size_override("font_size", size)
	var ink := Color(0.06, 0.06, 0.05) if dark_text else CHALK
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(0.38, 0.38, 0.35))
	b.add_theme_stylebox_override("normal", card(accent))
	b.add_theme_stylebox_override("hover", card(accent.lightened(0.3)))
	b.add_theme_stylebox_override("pressed", card(accent.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", card(Color(0.42, 0.42, 0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

## Toggle chip for the field / game / gun pickers: grey vinyl, neon when picked.
static func style_toggle(b: Button, size := 16) -> Button:
	b.add_theme_font_override("font", STENCIL)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", CHALK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.38))
	b.add_theme_stylebox_override("normal", card(Color(0.62, 0.63, 0.6)))
	b.add_theme_stylebox_override("hover", card(Color(0.8, 0.82, 0.6)))
	b.add_theme_stylebox_override("pressed", card(NEON))
	b.add_theme_stylebox_override("hover_pressed", card(NEON.lightened(0.25)))
	b.add_theme_stylebox_override("disabled", card(Color(0.4, 0.4, 0.38)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

## A strip of masking tape stuck across a corner of `host` (purely decorative, ignores mouse).
static func tape(host: Control, at: Vector2, angle_deg: float, length := 120.0) -> void:
	var t := TextureRect.new()
	t.texture = TAPE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = Vector2(length, 30)
	t.pivot_offset = t.size * 0.5
	t.position = at - t.size * 0.5
	t.rotation_degrees = angle_deg
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 2
	host.add_child(t)

## A paint splat decal (decorative).
static func splat(host: Control, at: Vector2, size: float, color: Color, angle_deg := 0.0) -> void:
	var s := TextureRect.new()
	s.texture = SPLAT
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_SCALE
	s.size = Vector2(size, size)
	s.pivot_offset = s.size * 0.5
	s.position = at - s.size * 0.5
	s.rotation_degrees = angle_deg
	s.modulate = color
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(s)

## Tape the four corners of `board` and spray paint hits onto it (under its text).
## splats: [[Vector2 at as a 0..1 fraction of the board size, size px, color, angle], ...]
static func dress_board(owner: Control, board: PanelContainer, splats: Array) -> void:
	var paint := Control.new()  # top_level so the PanelContainer doesn't fit it; drawn before the content
	paint.name = "BoardPaint"
	paint.top_level = true
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(paint)
	board.move_child(paint, 0)
	var deco := Control.new()
	deco.name = "BoardDecals"
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(deco)
	var redo := func() -> void:
		for c in deco.get_children() + paint.get_children():
			c.queue_free()
		deco.position = board.global_position - owner.global_position
		paint.global_position = board.global_position
		var w := board.size.x
		var h := board.size.y
		tape(deco, Vector2(14, 10), -38, 110)
		tape(deco, Vector2(w - 14, 10), 38, 110)
		tape(deco, Vector2(14, h - 10), 38, 110)
		tape(deco, Vector2(w - 14, h - 10), -38, 110)
		for sp in splats:
			splat(paint, Vector2(sp[0].x * w, sp[0].y * h), sp[1], sp[2], sp[3])
	board.item_rect_changed.connect(redo)
