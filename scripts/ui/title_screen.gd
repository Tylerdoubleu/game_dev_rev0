class_name TitleScreen
extends Control
## v0.6.4 (Ren): the first screen on boot - just SINGLE PLAYER or MULTIPLAYER over a full-screen hero shot: a player in
## a red jersey peeking around a vinyl can with the marker up at you. The backdrop is Bluey's live loop scene
## (title_hero_loop.tscn) when it is in the build, else the still title_hero.jpg (rendered in-engine from the bot PEEK
## pose). A vignette keeps the title / board readable without covering the player. Gritty 2000s TournamentSkin.
##   SINGLE PLAYER -> the same path as the lobby browser's button: LobbyBrowser.launch_single_player(self, tier)
##                    (SoloLauncher.start_ffa(tier), else ?solo=ffa&tier= on the web). Small ROOKIE / AMATEUR pick.
##   MULTIPLAYER   -> /root/LobbyEntryFlow.open_browser() (the lobby browser the bare link used to open).
## Either way the title screen removes itself. Deep links (?room=, ?solo=ffa, quickjoin, ...) never show it: that
## bypass lives in LobbyEntryFlow (Tim), which is also what puts this screen up on boot.

signal single_player_requested(difficulty: String)
signal multiplayer_requested

const TITLE := "JEET-BALL"
const TAGLINE := "2000s TOURNAMENT SERIES  //  SPEEDBALL  -  WOODSBALL  -  PUMP"
## Bluey's live hero loop scene (not on origin/test yet). The first path that exists wins.
const HERO_LOOP_PATHS := ["res://scenes/ui/title_hero_loop.tscn", "res://scenes/title_hero_loop.tscn"]
## Poster / fallback: the same shot as a still (1920x1080 JPG).
const HERO_STILL_PATH := "res://assets/ui/title/title_hero.jpg"
## Where the player's mask sits in the hero shot (0..1 of the image); the title and board must stay off it.
const HERO_FOCUS := Vector2(0.36, 0.39)
## Two small caption-less prints in the corner: [texture, tilt degrees]
const PHOTOS := [
	[preload("res://assets/ui/title/title_speedball.jpg"), -6.0],
	[preload("res://assets/ui/title/title_woods_crash.jpg"), 5.0],
]
const PHOTO_SIZE := Vector2(208, 117)
const PHOTO_BORDER := 8
const SPOTLIGHT_SECONDS := 3.5
const PHOTO_PAPER := Color(0.93, 0.91, 0.85)

var solo_difficulty: String = "amateur"
## How the last SINGLE PLAYER went: "solo_launcher", "web_link" or "signal_only" (tests / logs).
var last_solo_route: String = ""
## What the backdrop shows: "loop" (Bluey's live scene) or "still" (title_hero.jpg).
var hero_source: String = ""
var hero_node: Control
var single_btn: Button
var multi_btn: Button
var photo_cards: Array[Control] = []
var _diff_btns := {}
var _spot := 0
var _spot_timer: Timer

func _init() -> void:
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spot_timer = Timer.new()
	_spot_timer.wait_time = SPOTLIGHT_SECONDS
	_spot_timer.autostart = true
	_spot_timer.timeout.connect(_next_spotlight)
	add_child(_spot_timer)
	single_btn.grab_focus.call_deferred()

# ------------------------------------------------------------- actions --------

func set_solo_difficulty(d: String) -> void:
	if d.to_lower() in LobbyBrowser.SOLO_DIFFICULTIES:
		solo_difficulty = d.to_lower()
	for k in _diff_btns:
		_diff_btns[k].set_pressed_no_signal(k == solo_difficulty)

func start_single_player(difficulty: String = "") -> void:
	var d := difficulty.to_lower() if difficulty.to_lower() in LobbyBrowser.SOLO_DIFFICULTIES else solo_difficulty
	single_player_requested.emit(d)
	last_solo_route = LobbyBrowser.launch_single_player(self, d)
	if last_solo_route != "web_link":  # the web link reloads the page; keep the title up until it does
		dismiss()

func open_multiplayer() -> void:
	multiplayer_requested.emit()
	var flow := get_node_or_null("/root/LobbyEntryFlow") if is_inside_tree() else null
	if flow != null and flow.has_method("open_browser"):
		flow.call("open_browser")
	dismiss()

func dismiss() -> void:
	visible = false
	queue_free()

# ------------------------------------------------------------- backdrop --------

## The live loop scene's path if it is in this build, else "".
static func hero_loop_path() -> String:
	for p in HERO_LOOP_PATHS:
		if ResourceLoader.exists(p):
			return p
	return ""

## Full-screen hero backdrop: Bluey's loop scene (a Control is used as is; a 3D scene is put in a SubViewport) over the
## still as its poster, or just the still when the scene is not in the build or fails to load.
func _build_hero(path: String = hero_loop_path()) -> Control:
	var holder := Control.new()
	holder.name = "Hero"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var poster := TextureRect.new()
	poster.name = "HeroStill"
	poster.texture = load(HERO_STILL_PATH)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(poster)
	hero_source = "still"
	var packed := load(path) as PackedScene if not path.is_empty() else null
	var inst: Node = packed.instantiate() if packed != null else null
	if inst is Control:
		var c := inst as Control
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(c)
		hero_source = "loop"
	elif inst is Node3D:
		var box := SubViewportContainer.new()
		box.name = "HeroLoop"
		box.stretch = true
		box.stretch_shrink = 2 if OS.has_feature("web") else 1  # cheap on the web build
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.audio_listener_enable_3d = false  # the title is silent: no marker shots from the loop
		vp.add_child(inst)
		box.add_child(vp)
		holder.add_child(box)
		hero_source = "loop"
	elif inst != null:
		inst.free()
	return holder

## Darkened vignette: edges fall off to near-black, a band under the title, the player's spot (left of center) clear.
static func vignette() -> Control:
	var v := Control.new()
	v.name = "Vignette"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var radial := GradientTexture2D.new()
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.38, 0.5)
	radial.fill_to = Vector2(1.05, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.82))
	g.add_point(0.45, Color(0, 0, 0, 0.18))
	radial.gradient = g
	var top := GradientTexture2D.new()
	top.fill_from = Vector2(0, 0)
	top.fill_to = Vector2(0, 1)
	var tg := Gradient.new()
	tg.set_color(0, Color(0, 0, 0, 0.7))
	tg.set_color(1, Color(0, 0, 0, 0.0))
	tg.add_point(0.22, Color(0, 0, 0, 0.35))
	top.gradient = tg
	var right := GradientTexture2D.new()
	right.fill_from = Vector2(0.45, 0)
	right.fill_to = Vector2(1, 0)
	var rg := Gradient.new()
	rg.set_color(0, Color(0, 0, 0, 0.0))
	rg.set_color(1, Color(0, 0, 0, 0.55))
	right.gradient = rg
	for t in [[radial, "Edges"], [top, "TitleBand"], [right, "BoardShade"]]:
		var r := TextureRect.new()
		r.name = t[1]
		r.texture = t[0]
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(r)
	return v

## The player's mask on screen: HERO_FOCUS through the still's keep-aspect-covered fit of this screen's rect.
func hero_focus_point() -> Vector2:
	var r := get_global_rect()
	var img := Vector2(1920, 1080)
	var k := maxf(r.size.x / img.x, r.size.y / img.y)
	return r.position + (r.size - img * k) * 0.5 + HERO_FOCUS * img * k

# ------------------------------------------------------------------ UI --------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	hero_node = _build_hero()
	add_child(hero_node)
	add_child(vignette())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title := TournamentSkin.label(TITLE, 76, TournamentSkin.NEON, TournamentSkin.STENCIL, 10)
	title.name = "Title"
	col.add_child(title)
	var tag := TournamentSkin.led(TAGLINE, 20, TournamentSkin.AMBER)
	tag.name = "Tagline"
	col.add_child(tag)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	col.add_child(body)

	# left of the board stays open for the player; two small prints sit in the bottom-left corner
	var left := Control.new()
	left.name = "HeroSpace"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var strip := Control.new()
	strip.name = "PhotoStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	left.add_child(strip)
	for i in PHOTOS.size():
		var card := _print(PHOTOS[i][0], PHOTOS[i][1])
		card.name = "Photo%d" % i
		card.position = Vector2(i * (PHOTO_SIZE.x * 0.92), -card.size.y - 6.0 - (1 - i) * 26.0)
		strip.add_child(card)
		photo_cards.append(card)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(right)
	var board := PanelContainer.new()
	board.name = "Board"
	board.custom_minimum_size = Vector2(420, 0)
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	right.add_child(board)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	board.add_child(menu)

	single_btn = TournamentSkin.style_button(Button.new(), TournamentSkin.NEON, 34)
	single_btn.name = "SinglePlayer"
	single_btn.text = "SINGLE PLAYER"
	single_btn.custom_minimum_size = Vector2(0, 86)
	single_btn.pressed.connect(func(): start_single_player())
	menu.add_child(single_btn)
	menu.add_child(TournamentSkin.led("FREE-FOR-ALL  //  ALL BOTS VS YOU  //  FIRST TO 10", 15, TournamentSkin.CHALK))
	var diff := HBoxContainer.new()
	diff.add_theme_constant_override("separation", 8)
	diff.add_child(TournamentSkin.label("BOTS", 16, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2))
	for d in LobbyBrowser.SOLO_DIFFICULTIES:
		var b := TournamentSkin.style_toggle(Button.new(), 15)
		b.name = "Diff_" + d
		b.text = d.to_upper()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 32)
		b.pressed.connect(set_solo_difficulty.bind(d))
		diff.add_child(b)
		_diff_btns[d] = b
	menu.add_child(diff)
	set_solo_difficulty(solo_difficulty)

	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	menu.add_child(gap)
	multi_btn = TournamentSkin.style_button(Button.new(), TournamentSkin.PINK, 34)
	multi_btn.name = "Multiplayer"
	multi_btn.text = "MULTIPLAYER"
	multi_btn.custom_minimum_size = Vector2(0, 86)
	multi_btn.pressed.connect(open_multiplayer)
	menu.add_child(multi_btn)
	menu.add_child(TournamentSkin.led("ONLINE LOBBIES  //  5 V 5  //  CTF + DEATHMATCH", 15, TournamentSkin.CHALK))

	TournamentSkin.dress_board(self, board, [[Vector2(0.88, 0.1), 110.0, Color(TournamentSkin.PINK, 0.85), 25.0]])

## A small taped print: paper border around the shot, no caption. Rotates around its center.
func _print(tex: Texture2D, tilt: float) -> Control:
	var holder := Control.new()  # plain Control so the tape sits on top without the frame stretching it
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.name = "Frame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = PHOTO_PAPER
	sb.set_content_margin_all(PHOTO_BORDER)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(4, 6)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.name = "Shot"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = PHOTO_SIZE
	card.add_child(pic)
	holder.add_child(card)
	holder.size = card_size()
	card.size = holder.size
	holder.pivot_offset = holder.size * 0.5
	holder.rotation_degrees = tilt
	holder.set_meta("tilt", tilt)
	TournamentSkin.tape(holder, Vector2(holder.size.x * 0.5, 0), tilt * -1.6, 80.0)
	return holder

static func card_size() -> Vector2:
	return PHOTO_SIZE + Vector2(PHOTO_BORDER * 2, PHOTO_BORDER * 2)

## Slow life in the corner: every few seconds the other print comes to the front and straightens a little.
func _next_spotlight() -> void:
	if photo_cards.is_empty():
		return
	var prev := photo_cards[_spot]
	_spot = (_spot + 1) % photo_cards.size()
	var cur := photo_cards[_spot]
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(prev, "scale", Vector2.ONE, 0.6)
	tw.tween_property(prev, "rotation_degrees", float(prev.get_meta("tilt")), 0.6)
	tw.tween_property(cur, "scale", Vector2.ONE * 1.06, 0.6)
	tw.tween_property(cur, "rotation_degrees", float(cur.get_meta("tilt")) * 0.4, 0.6)
	prev.z_index = 0
	cur.z_index = 5
