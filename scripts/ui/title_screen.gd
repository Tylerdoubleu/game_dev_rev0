class_name TitleScreen
extends Control
## v0.6.4 (Ren): the first screen on boot - just SINGLE PLAYER or MULTIPLAYER over a full-screen hero shot: a player in
## a red jersey peeking around a vinyl can with the marker up at you. The backdrop is Bluey's live loop scene
## (title_hero_loop.tscn) when it is in the build, else the still title_hero.jpg (rendered in-engine from the bot PEEK
## pose). A vignette keeps the title / board readable without covering the player. Gritty 2000s TournamentSkin.
##   SINGLE PLAYER -> the same path as the lobby browser's button: LobbyBrowser.launch_single_player(self, tier)
##                    (SoloLauncher.start_ffa(tier), else ?solo=ffa&tier= on the web). Small ROOKIE / AMATEUR pick.
##   MULTIPLAYER   -> /root/LobbyEntryFlow.open_browser() (the lobby browser the bare link used to open).
##   PLAYER TAG    -> a compact callsign field on the board (CallsignEntry's rule + states, Tim's ProfileApi reserves it).
##                    Prefilled from the profile's callsign, else the last tag used on this device. The tag becomes
##                    NetworkLobby's callsign through its public update_local_player_choices(), so the waiting room
##                    bench, nametags and kill feed show it. MULTIPLAYER needs a tag (gentle amber nudge when empty,
##                    stops on CALLSIGN TAKEN / BAD NAME, goes on when the profile server is offline); SINGLE PLAYER
##                    never waits: an empty or bad tag is swapped for a suggestion (the lobby's Player_123).
## Either way the title screen removes itself. Deep links (?room=, ?solo=ffa, quickjoin, ...) never show it: that
## bypass lives in LobbyEntryFlow (Tim), which is also what puts this screen up on boot.

signal single_player_requested(difficulty: String)
signal multiplayer_requested
## The tag NetworkLobby now plays under.
signal tag_applied(tag: String)

const TITLE := "JEET-BALL"
const TAGLINE := "2000s TOURNAMENT SERIES  //  SPEEDBALL  -  WOODSBALL  -  PUMP"
## Bluey's live hero loop scene (scenes/ui/title_hero_loop.tscn, 1414296 + fa2dcac). The first path that exists wins.
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
## The last tag used on this device (IndexedDB on the web), so the field is filled even before the profile answers.
const TAG_CFG := "user://player_tag.cfg"
const TAG_EMPTY_TEXT := "SET YOUR TAG"
const TAG_NEEDED_TEXT := "TAG NEEDED FOR ONLINE"
## MULTIPLAYER waits this long for the profile server before going on with the tag anyway (never blocks play).
const TAG_SAVE_WAIT := 5.0

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
## Player tag
var api: ProfileApi
var tag_cfg_path: String = TAG_CFG  # tests point this elsewhere
var tag_field: LineEdit
var tag_status: Label
var tag_state: int = CallsignEntry.State.IDLE
## The callsign the server's profile holds ("" until known) and the one NetworkLobby plays under.
var reserved_tag: String = ""
var applied_tag: String = ""
## How the last MULTIPLAYER press went: "opened", "need_tag", "bad_tag", "taken", "saving" (tests / logs).
var last_multi_result: String = ""
var _tag_touched := false
var _go_multi := false
var _pending_tag := ""
var _save_wait: Timer
var _pulse: Tween

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
	_save_wait = Timer.new()
	_save_wait.one_shot = true
	_save_wait.wait_time = TAG_SAVE_WAIT
	_save_wait.timeout.connect(_on_save_wait_timeout)
	add_child(_save_wait)
	_setup_tag()
	if current_tag().is_empty():
		tag_field.grab_focus.call_deferred()
	else:
		single_btn.grab_focus.call_deferred()

# ------------------------------------------------------------- actions --------

func set_solo_difficulty(d: String) -> void:
	if d.to_lower() in LobbyBrowser.SOLO_DIFFICULTIES:
		solo_difficulty = d.to_lower()
	for k in _diff_btns:
		_diff_btns[k].set_pressed_no_signal(k == solo_difficulty)

func start_single_player(difficulty: String = "") -> void:
	var t := current_tag()
	if not CallsignEntry.is_valid_callsign(t):
		t = suggest_tag()
		if tag_field != null:
			tag_field.text = t
	apply_tag(t)
	var d := difficulty.to_lower() if difficulty.to_lower() in LobbyBrowser.SOLO_DIFFICULTIES else solo_difficulty
	single_player_requested.emit(d)
	last_solo_route = LobbyBrowser.launch_single_player(self, d)
	if last_solo_route != "web_link":  # the web link reloads the page; keep the title up until it does
		dismiss()

## The MULTIPLAYER button: needs a valid tag, reserves it on the profile server, then opens the lobby browser.
func request_multiplayer() -> void:
	var t := current_tag()
	if t.is_empty():
		last_multi_result = "need_tag"
		nudge_tag(TAG_NEEDED_TEXT)
		return
	if not CallsignEntry.is_valid_callsign(t):
		last_multi_result = "bad_tag"
		_set_tag_state(CallsignEntry.State.INVALID)
		nudge_tag()
		return
	apply_tag(t)
	if not reserved_tag.is_empty() and t.to_lower() == reserved_tag.to_lower():
		last_multi_result = "opened"
		open_multiplayer()
		return
	last_multi_result = "saving"
	_go_multi = true
	reserve_tag(t)

func open_multiplayer() -> void:
	multiplayer_requested.emit()
	var flow := get_node_or_null("/root/LobbyEntryFlow") if is_inside_tree() else null
	if flow != null and flow.has_method("open_browser"):
		flow.call("open_browser")
	dismiss()

func dismiss() -> void:
	visible = false
	queue_free()

# ----------------------------------------------------------- player tag --------

func current_tag() -> String:
	return tag_field.text.strip_edges() if tag_field != null else applied_tag

## A ready-made tag for SINGLE PLAYER: the lobby's random Player_123 when it passes the rule, else a fresh one.
func suggest_tag() -> String:
	var nl := _lobby()
	var cur := String(nl.get("local_callsign")) if nl != null else ""
	if CallsignEntry.is_valid_callsign(cur):
		return cur
	return "Player_%03d" % randi_range(100, 999)

## NetworkLobby plays under the tag from now on (waiting room bench, nametags, kill feed) and this device remembers it.
## Uses only NetworkLobby's public update_local_player_choices (re-registers with the server when online).
func apply_tag(t: String) -> bool:
	t = t.strip_edges()
	if not CallsignEntry.is_valid_callsign(t):
		return false
	applied_tag = t
	save_tag(t, tag_cfg_path)
	var nl := _lobby()
	if nl != null:
		if nl.has_method("update_local_player_choices"):
			nl.call("update_local_player_choices", t, String(nl.get("local_team")), String(nl.get("local_bracket")), bool(nl.get("fill_bots_enabled")))
		else:
			nl.set("local_callsign", t)
	tag_applied.emit(t)
	return true

## Reserve the tag on the profile server (ProfileApi makes a profile first if there is none).
func reserve_tag(t: String) -> void:
	_pending_tag = t
	_set_tag_state(CallsignEntry.State.SAVING)
	if api == null:
		_on_api("set_callsign", 0, {})
		return
	if _go_multi and _save_wait != null and _save_wait.is_inside_tree():
		_save_wait.start()
	api.set_callsign(t)

## Enter in the field: check, apply and reserve without leaving the title.
func commit_tag() -> void:
	var t := current_tag()
	if t.is_empty():
		nudge_tag()
	elif not CallsignEntry.is_valid_callsign(t):
		_set_tag_state(CallsignEntry.State.INVALID)
		nudge_tag()
	elif apply_tag(t) and t.to_lower() != reserved_tag.to_lower():
		reserve_tag(t)
	else:
		_set_tag_state(CallsignEntry.State.SAVED)

## Gentle highlight: amber border, a short pulse and the caret in the field.
func nudge_tag(text: String = "") -> void:
	if tag_field == null:
		return
	if not text.is_empty():
		_set_tag_state(CallsignEntry.State.IDLE, text)
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	tag_field.modulate = Color.WHITE
	if is_inside_tree():
		_pulse = create_tween().set_trans(Tween.TRANS_SINE)
		for i in 2:
			_pulse.tween_property(tag_field, "modulate", Color(1.25, 1.1, 0.8), 0.18)
			_pulse.tween_property(tag_field, "modulate", Color.WHITE, 0.22)
		tag_field.grab_focus()

static func load_saved_tag(path: String = TAG_CFG) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var t := String(cfg.get_value("player", "tag", "")).strip_edges()
	return t if CallsignEntry.is_valid_callsign(t) else ""

static func save_tag(t: String, path: String = TAG_CFG) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "tag", t)
	cfg.save(path)

## Hand the title a ProfileApi before adding it (tests, or a screen that already has one).
func bind_api(a: ProfileApi) -> void:
	if api != null and api.completed.is_connected(_on_api):
		api.completed.disconnect(_on_api)
	api = a
	if api != null and not api.completed.is_connected(_on_api):
		api.completed.connect(_on_api)

func _lobby() -> Node:
	return get_node_or_null("/root/NetworkLobby") if is_inside_tree() else null

func _setup_tag() -> void:
	var saved := load_saved_tag(tag_cfg_path)
	if not saved.is_empty():
		tag_field.text = saved
		applied_tag = saved
		apply_tag(saved)
	_set_tag_state(CallsignEntry.State.IDLE)
	if api == null:
		bind_api(ProfileApi.new())
	if api.get_parent() == null:
		add_child(api)
	if api.has_profile():
		api.fetch_profile()  # the profile's callsign wins unless the player already typed

func _on_api(action: String, status: int, d: Dictionary) -> void:
	if action == "get" and status == 200:
		var cs := String(d.get("callsign")) if d.get("callsign") != null else ""
		if CallsignEntry.is_valid_callsign(cs):
			reserved_tag = cs
			if not _tag_touched or current_tag().is_empty():
				tag_field.text = cs
				apply_tag(cs)
				_set_tag_state(CallsignEntry.State.SAVED)
		return
	if action != "set_callsign" or _pending_tag.is_empty():
		return
	var t := _pending_tag
	_pending_tag = ""
	if _save_wait != null:
		_save_wait.stop()
	match status:
		200:
			reserved_tag = String(d.get("callsign")) if d.get("callsign") != null else t
			_set_tag_state(CallsignEntry.State.SAVED)
			_finish_multi(true)
		409:
			_set_tag_state(CallsignEntry.State.TAKEN)
			last_multi_result = "taken" if _go_multi else last_multi_result
			_finish_multi(false)
			nudge_tag()
		400:
			_set_tag_state(CallsignEntry.State.INVALID)
			last_multi_result = "bad_tag" if _go_multi else last_multi_result
			_finish_multi(false)
			nudge_tag()
		_:
			# no profile server (or it hiccuped): keep the tag and play under it anyway
			_set_tag_state(CallsignEntry.State.OFFLINE if CallsignEntry._offline(status) else CallsignEntry.State.ERROR)
			_finish_multi(true)

func _finish_multi(go: bool) -> void:
	if not _go_multi:
		return
	_go_multi = false
	if go:
		last_multi_result = "opened"
		open_multiplayer()

func _on_save_wait_timeout() -> void:
	if _go_multi and tag_state == CallsignEntry.State.SAVING:
		_pending_tag = ""
		_set_tag_state(CallsignEntry.State.OFFLINE)
		_finish_multi(true)

func _on_tag_changed(t: String) -> void:
	_tag_touched = true
	if tag_state != CallsignEntry.State.SAVING:
		_set_tag_state(CallsignEntry.State.IDLE)

func _on_tag_focus_exited() -> void:
	var t := current_tag()
	if CallsignEntry.is_valid_callsign(t) and t != applied_tag:
		apply_tag(t)

func _set_tag_state(s: int, text: String = "") -> void:
	tag_state = s
	if tag_status == null:
		return
	var t := current_tag()
	var col: Color = CallsignEntry.STATE_COLOR[s]
	var msg := text
	if msg.is_empty():
		if s == CallsignEntry.State.IDLE:
			if t.is_empty():
				msg = TAG_EMPTY_TEXT
			elif CallsignEntry.is_valid_callsign(t):
				msg = CallsignEntry.RULE_TEXT
				col = TournamentSkin.MUTED
			else:
				msg = CallsignEntry.RULE_TEXT
				col = TournamentSkin.PINK
		elif s == CallsignEntry.State.OFFLINE:
			msg = "NO SERVER  -  KEPT"
		else:
			msg = CallsignEntry.STATE_TEXT[s]
	tag_status.text = msg
	tag_status.add_theme_color_override("font_color", col)
	tag_status.add_theme_color_override("font_shadow_color", Color(col, 0.45))
	var bad := s == CallsignEntry.State.INVALID or s == CallsignEntry.State.TAKEN
	var edge: Color = TournamentSkin.PINK if bad else (TournamentSkin.AMBER if t.is_empty() else TournamentSkin.CHALK)
	tag_field.add_theme_stylebox_override("normal", TournamentSkin.card(edge, 14, 6))
	tag_field.editable = s != CallsignEntry.State.SAVING

func _build_tag(menu: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.name = "PlayerTag"
	box.add_theme_constant_override("separation", 4)
	menu.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(TournamentSkin.label("PLAYER TAG", 18, TournamentSkin.NEON, TournamentSkin.STENCIL, 3))
	tag_status = TournamentSkin.led(TAG_EMPTY_TEXT, 16, TournamentSkin.AMBER)
	tag_status.name = "TagStatus"
	tag_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag_status.clip_text = true
	row.add_child(tag_status)
	tag_field = LineEdit.new()
	tag_field.name = "TagField"
	tag_field.max_length = CallsignEntry.CALLSIGN_MAX
	tag_field.placeholder_text = "YOUR TAG"
	tag_field.custom_minimum_size = Vector2(0, 52)
	tag_field.add_theme_font_override("font", TournamentSkin.MARKER)
	tag_field.add_theme_font_size_override("font_size", 28)
	tag_field.add_theme_color_override("font_color", Color(0.08, 0.08, 0.07))
	tag_field.add_theme_color_override("font_placeholder_color", Color(0.08, 0.08, 0.07, 0.35))
	tag_field.add_theme_color_override("caret_color", Color(0.08, 0.08, 0.07))
	tag_field.add_theme_stylebox_override("normal", TournamentSkin.card(TournamentSkin.AMBER, 14, 6))
	tag_field.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tag_field.text_changed.connect(_on_tag_changed)
	tag_field.text_submitted.connect(func(_t: String) -> void: commit_tag())
	tag_field.focus_exited.connect(_on_tag_focus_exited)
	box.add_child(tag_field)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	menu.add_child(gap)

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
	_build_tag(menu)

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
	multi_btn.pressed.connect(request_multiplayer)
	menu.add_child(multi_btn)
	menu.add_child(TournamentSkin.led("ONLINE LOBBIES  //  5 V 5  //  CTF + DEATHMATCH", 15, TournamentSkin.CHALK))

	TournamentSkin.dress_board(self, board, [[Vector2(0.9, 0.95), 110.0, Color(TournamentSkin.PINK, 0.85), 25.0]])  # bottom corner: the tag LED stays clear

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
