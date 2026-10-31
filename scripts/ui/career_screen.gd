class_name CareerScreen
extends Control
## v0.7 (Ren): Gritty 2000s tournament career screen. Big callsign (EDIT opens CallsignEntry), clout from Tim's
## ProfileApi (read-only: one server total), Bluey's career progress and the tier's challenge cards.
## Short words, big numbers.
##
## Hookup (one line):  var cs := CareerScreen.new(); add_child(cs); cs.show_career(career_dict)
##   cs.back_pressed.connect(...)   cs.play_pressed.connect(func(challenge_id: String) -> void: ...)
## It loads the profile by itself (ensure_profile on its own ProfileApi, or bind_api(api) before add_child to share one).
##
## Career data (Bluey's career runner owns it; it saves in the browser for now and later through
## ProfileApi.save_career). Every key is optional; missing ones fall back to ProfileApi.profile stats or a blank:
##   tier: String          current level, e.g. "ROOKIE", "AMATEUR", "D2", "PRO"
##   next_tier: String     the level after it ("" at the top)
##   progress: float       0..1 toward next_tier  (or xp: int + xp_next: int, used when progress is missing)
##   team: String          your team name          sponsor: String   current sponsor ("" = none)
##   season: int           season number           event: String     next event name, e.g. "MIDWEST OPEN"
##   wins, losses, matches, eliminations, flags: int   career totals (else profile.stats)
##   stars: int            total stars earned (shown next to the tier)
##   clout: int            local clout, shown only when the server profile has no clout
##   challenges: Array     this tier's challenges, in order:
##       [{id: String, name: String, mode: String, best_stars: int 0..3, locked: bool}, ...]
##     Shown as cards (4 per row, scrolls past 2 rows). Click an unlocked card to select it; the first unlocked
##     one is selected by default. Locked cards are dimmed, taped + padlocked, and can't be selected.
##     NEXT MATCH emits play_pressed(selected id) - "" when there are no challenges; it is disabled when
##     there are challenges but none are unlocked.

signal back_pressed
signal play_pressed(challenge_id: String)
signal edit_callsign_pressed

const SCREEN := Vector2(1280, 720)
const BOARD_WIDTH := 1100.0
const GREEN := Color(0.45, 0.95, 0.35)
const CARD_COLUMNS := 4
const CARD_HEIGHT := 88.0
const CARD_GAP := 10
const CARD_ROWS_VISIBLE := 2

var api: ProfileApi
var profile: Dictionary = {}
var career: Dictionary = {}
var entry: CallsignEntry
var _board: PanelContainer
var _callsign: Label
var _tier: Label
var _next: Label
var _bar: ProgressBar
var _team: Label
var _status: Label
var _nums: Dictionary = {}  # key -> Label
var selected_challenge: String = ""
var challenge_cards: Dictionary = {}  # id -> Button
var _stars_total: Label
var _stars_box: HBoxContainer
var _cards_scroll: ScrollContainer
var _cards_grid: GridContainer
var _play: Button

## A row of `slots` stars, `filled` of them lit (drawn, so no font glyph needed).
class Stars extends Control:
	var slots := 3
	var filled := 0
	var star_size := 22.0
	var on_color := TournamentSkin.NEON
	func _init(n_slots := 3, n_filled := 0, px := 22.0) -> void:
		slots = n_slots; filled = n_filled; star_size = px
		custom_minimum_size = Vector2(slots * (px + 4) - 4, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for i in slots:
			var c := Vector2(i * (star_size + 4) + star_size * 0.5, star_size * 0.52)
			var pts := PackedVector2Array()
			for k in 10:
				var r := star_size * (0.5 if k % 2 == 0 else 0.22)
				var a := -PI / 2.0 + k * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			var lit := i < filled
			draw_colored_polygon(pts, on_color if lit else Color(0.08, 0.08, 0.07, 0.85))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.9) if lit else Color(TournamentSkin.MUTED, 0.7), 1.5, true)

## Little padlock for locked cards.
class Padlock extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(22, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_arc(Vector2(11, 11), 6.5, PI, TAU, 12, TournamentSkin.CHALK, 3.0, true)
		draw_line(Vector2(4.5, 11), Vector2(4.5, 13), TournamentSkin.CHALK, 3.0)
		draw_line(Vector2(17.5, 11), Vector2(17.5, 13), TournamentSkin.CHALK, 3.0)
		draw_rect(Rect2(2, 12, 18, 13), TournamentSkin.CHALK)
		draw_rect(Rect2(9.5, 16, 3, 5), Color(0.1, 0.1, 0.09))

func _ready() -> void:
	_build_ui()
	if api == null:
		api = ProfileApi.new()
		add_child(api)
	api.completed.connect(_on_api)
	entry = CallsignEntry.new()
	entry.bind_api(api)
	entry.z_index = 10  # above the board's tape (z 2)
	add_child(entry)
	entry.callsign_saved.connect(func(n: String) -> void:
		profile["callsign"] = n
		_refresh())
	if not api.profile.is_empty():
		set_profile(api.profile)
	_refresh()
	api.ensure_profile.call_deferred()

func bind_api(a: ProfileApi) -> void:
	api = a

func _on_api(action: String, status: int, d: Dictionary) -> void:
	if status == 200 and action in ["get", "set_callsign", "save_career"]:
		set_profile(d)
	elif action == "create" and status == 201:
		api.fetch_profile()
	elif action == "get" and status == 401:
		api.create_profile()  # ProfileApi forgot the stale token; make a fresh profile
	elif action in ["get", "create"] and _status:
		_status.text = "OFFLINE" if CallsignEntry._offline(status) else "SERVER ERROR"

func show_career(data: Dictionary) -> void:
	career = data.duplicate(true)
	visible = true
	_refresh()

func set_profile(p: Dictionary) -> void:
	profile = p.duplicate(true)
	if _status:
		_status.text = "ONLINE"
	_refresh()

func edit_callsign() -> void:
	edit_callsign_pressed.emit()
	if entry:
		entry.open(String(profile.get("callsign", "")) if profile.get("callsign") != null else "")

## Career value, else the profile's stats, else 0.
func stat(key: String) -> int:
	if career.has(key):
		return int(career[key])
	var s = profile.get("stats", {})
	return int(s.get(key, 0)) if s is Dictionary else 0

func progress() -> float:
	if career.has("progress"):
		return clampf(float(career["progress"]), 0.0, 1.0)
	if int(career.get("xp_next", 0)) > 0:
		return clampf(float(career.get("xp", 0)) / float(career["xp_next"]), 0.0, 1.0)
	return 0.0

## Server clout when the profile has it, else the career's local clout, else 0.
func clout() -> int:
	if profile.get("clout") != null:
		return int(profile["clout"])
	return int(career.get("clout", 0)) if career.get("clout") != null else 0

func challenges() -> Array:
	var c = career.get("challenges", [])
	return c if c is Array else []

## Select an unlocked challenge by id. Returns false (and changes nothing) for locked or unknown ids.
func select_challenge(id: String) -> bool:
	for c in challenges():
		if c is Dictionary and String(c.get("id", "")) == id:
			if bool(c.get("locked", false)):
				return false
			selected_challenge = id
			_mark_selected()
			return true
	return false

## Same as pressing NEXT MATCH (no-op while it is disabled).
func play() -> void:
	if _play and _play.disabled:
		return
	play_pressed.emit(selected_challenge)

func _first_unlocked() -> String:
	for c in challenges():
		if c is Dictionary and not bool(c.get("locked", false)):
			return String(c.get("id", ""))
	return ""

func _build_cards() -> void:
	for c in _cards_grid.get_children():
		_cards_grid.remove_child(c)
		c.queue_free()
	challenge_cards.clear()
	var list := challenges()
	var keep := false
	for c in list:
		if c is Dictionary and String(c.get("id", "")) == selected_challenge and not bool(c.get("locked", false)):
			keep = true
	if not keep:
		selected_challenge = _first_unlocked()
	for c in list:
		if c is Dictionary:
			_challenge_card(c)
	var rows := ceili(float(list.size()) / CARD_COLUMNS)
	var shown := mini(rows, CARD_ROWS_VISIBLE)
	_cards_scroll.visible = rows > 0
	_cards_scroll.custom_minimum_size.y = shown * CARD_HEIGHT + maxi(0, shown - 1) * CARD_GAP
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if rows > CARD_ROWS_VISIBLE else ScrollContainer.SCROLL_MODE_DISABLED
	_play.disabled = not list.is_empty() and selected_challenge == ""
	_mark_selected()

func _mark_selected() -> void:
	for id in challenge_cards:
		challenge_cards[id].get_node("Outline").visible = id == selected_challenge

func _challenge_card(c: Dictionary) -> void:
	var id := String(c.get("id", ""))
	var locked := bool(c.get("locked", false))
	var b := Button.new()
	b.name = "Challenge_" + id.validate_node_name()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	var tint := Color(0.2, 0.21, 0.19) if not locked else Color(0.13, 0.13, 0.12)
	for st in ["normal", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, TournamentSkin.card(tint, 12, 6))
	b.add_theme_stylebox_override("hover", TournamentSkin.card(Color(0.27, 0.28, 0.24), 12, 6))
	b.disabled = locked
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	b.set_meta("challenge_id", id)
	b.set_meta("locked", locked)
	b.pressed.connect(func() -> void: select_challenge(id))
	_cards_grid.add_child(b)
	challenge_cards[id] = b
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14; v.offset_right = -14; v.offset_top = 8; v.offset_bottom = -8
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		v.modulate = Color(1, 1, 1, 0.45)
		v.offset_right = -40  # room for the padlock
	b.add_child(v)
	var n := TournamentSkin.label(String(c.get("name", id)).to_upper(), 20, TournamentSkin.CHALK, TournamentSkin.STENCIL, 3)
	n.name = "Name"
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(n)
	var m := TournamentSkin.label(String(c.get("mode", "")).to_upper(), 15, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2)
	m.name = "Mode"
	m.clip_text = true
	m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(m)
	var stars := Stars.new(3, clampi(int(c.get("best_stars", 0)), 0, 3), 20.0)
	stars.name = "Stars"
	v.add_child(stars)
	if locked:
		var lock := Padlock.new()
		lock.name = "Padlock"
		lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lock.position = Vector2(-34, 8)
		b.add_child(lock)
		var t := TextureRect.new()  # a strip of tape across the card
		t.name = "LockTape"
		t.texture = TournamentSkin.TAPE
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.set_anchors_preset(Control.PRESET_CENTER)
		t.size = Vector2(170, 24)
		t.position = -t.size * 0.5
		t.pivot_offset = t.size * 0.5
		t.rotation_degrees = -8.0
		t.modulate = Color(1, 1, 1, 0.8)
		b.add_child(t)
		var tl := TournamentSkin.label("LOCKED", 16, Color(0.15, 0.14, 0.12), TournamentSkin.STENCIL, 0)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(tl)
	var o := Panel.new()
	o.name = "Outline"
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(4)
	sb.border_color = TournamentSkin.NEON
	sb.shadow_color = Color(TournamentSkin.NEON, 0.35)
	sb.shadow_size = 6
	o.add_theme_stylebox_override("panel", sb)
	o.visible = false
	b.add_child(o)

static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

func _refresh() -> void:
	if _board == null:
		return
	var cs = profile.get("callsign")
	var pend := entry.pending if entry else ""
	_callsign.text = String(cs) if cs != null and String(cs) != "" else (pend if pend != "" else "NO CALLSIGN")
	_nums["clout"].text = fmt(clout())
	_nums["wins"].text = fmt(stat("wins"))
	_nums["losses"].text = fmt(stat("losses") if career.has("losses") else maxi(0, stat("matches") - stat("wins")))
	_nums["eliminations"].text = fmt(stat("eliminations"))
	_nums["flags"].text = fmt(stat("flags"))
	_tier.text = String(career.get("tier", "ROOKIE")).to_upper()
	var nt := String(career.get("next_tier", "")).to_upper()
	_next.text = ("NEXT  " + nt) if nt != "" else "TOP TIER"
	_bar.value = progress() * 100.0
	var bits: Array = []
	for k in ["team", "sponsor", "event"]:
		if String(career.get(k, "")) != "":
			bits.append(String(career[k]).to_upper())
	if career.has("season"):
		bits.push_front("SEASON %d" % int(career["season"]))
	_team.text = "  //  ".join(bits) if not bits.is_empty() else "FREE AGENT"
	_stars_total.text = fmt(int(career.get("stars", 0)))
	_stars_box.visible = career.has("stars") or not challenges().is_empty()
	_build_cards()

func _num_card(parent: Control, key: String, title: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.name = "Card_" + key
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", TournamentSkin.card(Color(0.2, 0.21, 0.19), 14, 8))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var t := TournamentSkin.label(title, 18, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := TournamentSkin.led("0", 58, color)
	n.name = "Num"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	_nums[key] = n

func _build_ui() -> void:
	if _board != null:
		return
	name = "CareerScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(TournamentSkin.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_board = PanelContainer.new()
	_board.name = "Board"
	_board.custom_minimum_size = Vector2(BOARD_WIDTH, 0)
	_board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	center.add_child(_board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_board.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := TournamentSkin.label("CAREER", 48, TournamentSkin.NEON, TournamentSkin.STENCIL, 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status = TournamentSkin.led("LOADING...", 20)
	header.add_child(_status)

	# Callsign on a strip of tape + EDIT
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	col.add_child(name_row)
	var tag := PanelContainer.new()
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.add_theme_stylebox_override("panel", TournamentSkin.card(TournamentSkin.CHALK, 20, 4))
	name_row.add_child(tag)
	_callsign = TournamentSkin.marker("NO CALLSIGN", 52, Color(0.08, 0.08, 0.07))
	_callsign.name = "Callsign"
	_callsign.remove_theme_constant_override("outline_size")
	_callsign.add_theme_constant_override("outline_size", 0)
	_callsign.clip_text = true
	tag.add_child(_callsign)
	var edit := TournamentSkin.style_button(Button.new(), TournamentSkin.PINK, 22)
	edit.name = "EditButton"
	edit.text = "EDIT"
	edit.custom_minimum_size = Vector2(130, 0)
	edit.pressed.connect(edit_callsign)
	name_row.add_child(edit)

	# Big numbers
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 12)
	col.add_child(nums)
	_num_card(nums, "clout", "CLOUT", TournamentSkin.NEON)
	_num_card(nums, "wins", "WINS", GREEN)
	_num_card(nums, "losses", "LOSSES", TournamentSkin.PINK)
	_num_card(nums, "eliminations", "ELIMS", TournamentSkin.AMBER)
	_num_card(nums, "flags", "FLAGS", TournamentSkin.CHALK)

	# Tier + progress
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 16)
	col.add_child(tier_row)
	_tier = TournamentSkin.label("ROOKIE", 44, TournamentSkin.AMBER, TournamentSkin.STENCIL, 6)
	_tier.name = "Tier"
	tier_row.add_child(_tier)
	_stars_box = HBoxContainer.new()
	_stars_box.name = "StarsTotal"
	_stars_box.add_theme_constant_override("separation", 6)
	_stars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_child(_stars_box)
	var big_star := Stars.new(1, 1, 30.0)
	big_star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stars_box.add_child(big_star)
	_stars_total = TournamentSkin.led("0", 36, TournamentSkin.NEON)
	_stars_total.name = "Num"
	_stars_box.add_child(_stars_total)
	var pcol := VBoxContainer.new()
	pcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_child(pcol)
	_next = TournamentSkin.label("NEXT  AMATEUR", 18, TournamentSkin.CHALK, TournamentSkin.STENCIL, 3)
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pcol.add_child(_next)
	_bar = ProgressBar.new()
	_bar.name = "TierBar"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.add_theme_stylebox_override("background", TournamentSkin.card(Color(0.18, 0.18, 0.16), 4, 4))
	_bar.add_theme_stylebox_override("fill", TournamentSkin.card(TournamentSkin.NEON, 4, 4))
	pcol.add_child(_bar)
	_team = TournamentSkin.label("FREE AGENT", 20, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2)
	_team.name = "TeamLine"
	_team.clip_text = true
	col.add_child(_team)

	# Challenge cards (this tier)
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.name = "Challenges"
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards_scroll.visible = false
	col.add_child(_cards_scroll)
	_cards_grid = GridContainer.new()
	_cards_grid.columns = CARD_COLUMNS
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_cards_grid.add_theme_constant_override("v_separation", CARD_GAP)
	_cards_scroll.add_child(_cards_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	var back := TournamentSkin.style_button(Button.new(), Color(0.55, 0.56, 0.52), 20)
	back.text = "BACK"
	back.custom_minimum_size = Vector2(140, 54)
	back.pressed.connect(func() -> void: back_pressed.emit())
	footer.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	var play_btn := TournamentSkin.style_button(Button.new(), TournamentSkin.NEON, 26)
	play_btn.name = "PlayButton"
	play_btn.text = "NEXT MATCH"
	play_btn.custom_minimum_size = Vector2(240, 54)
	play_btn.pressed.connect(play)
	_play = play_btn
	footer.add_child(play_btn)
	TournamentSkin.dress_board(self, _board, [[Vector2(0.5, 0.08), 120.0, Color(TournamentSkin.PINK, 0.45), 15.0], [Vector2(0.3, 0.93), 110.0, Color(TournamentSkin.NEON, 0.3), -25.0], [Vector2(0.55, 0.95), 100.0, Color(0.3, 0.6, 1.0, 0.35), 60.0]])
