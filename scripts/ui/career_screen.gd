class_name CareerScreen
extends Control
## v0.7 (Ren): Gritty 2000s tournament career screen. Big callsign (EDIT opens CallsignEntry), clout from Tim's
## /api/profile (read-only, server-awarded), and Bluey's career progress. Short words, big numbers.
##
## Hookup (one line):  var cs := CareerScreen.new(); add_child(cs); cs.show_career(career_dict)
##   cs.back_pressed.connect(...)   cs.play_pressed.connect(...)
## It loads the profile by itself (ensure_profile on its own ProfileApi, or bind_api(api) before add_child to share one).
##
## Career data (Bluey's career runner owns it; it saves in the browser for now and later through
## ProfileApi.save_career). Every key is optional; missing ones fall back to /api/profile stats or a blank:
##   tier: String          current level, e.g. "ROOKIE", "AMATEUR", "D2", "PRO"
##   next_tier: String     the level after it ("" at the top)
##   progress: float       0..1 toward next_tier  (or xp: int + xp_next: int, used when progress is missing)
##   team: String          your team name          sponsor: String   current sponsor ("" = none)
##   season: int           season number           event: String     next event name, e.g. "MIDWEST OPEN"
##   wins, losses, matches, eliminations, flags: int   career totals (else profile.stats)

signal back_pressed
signal play_pressed
signal edit_callsign_pressed

const SCREEN := Vector2(1280, 720)
const BOARD_WIDTH := 1100.0
const GREEN := Color(0.45, 0.95, 0.35)

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
	_nums["clout"].text = fmt(int(profile.get("clout", 0)))
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
	var play := TournamentSkin.style_button(Button.new(), TournamentSkin.NEON, 26)
	play.name = "PlayButton"
	play.text = "NEXT MATCH"
	play.custom_minimum_size = Vector2(240, 54)
	play.pressed.connect(func() -> void: play_pressed.emit())
	footer.add_child(play)
	TournamentSkin.dress_board(self, _board, [[Vector2(0.5, 0.08), 120.0, Color(TournamentSkin.PINK, 0.45), 15.0], [Vector2(0.03, 0.6), 120.0, Color(TournamentSkin.NEON, 0.35), -25.0], [Vector2(0.55, 0.95), 100.0, Color(0.3, 0.6, 1.0, 0.35), 60.0]])
