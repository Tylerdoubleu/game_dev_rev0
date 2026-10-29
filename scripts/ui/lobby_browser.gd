class_name LobbyBrowser
extends Control
## v0.5 (Ren): Gritty 2000s tournament-board lobby browser. Lists the permanent lobbies from Tim's
## GET /api/lobbies ({"lobbies":[{id,name,map,mode?,players:{red,blue},max_per_team,status,bots,join_url}]}),
## with per-row JOIN, a QUICK-JOIN (fullest "waiting" lobby that still has room) and a SOLO TEST VS BOTS button.
## Standalone: emits signals, and on the web build JOIN navigates to the lobby's join_url.

signal lobby_join_requested(entry: Dictionary)
signal solo_requested
signal lobbies_updated(count: int)

const REFRESH_SECONDS: float = 4.0
const MAP_LABELS := {"speedball": "NPPL SPEEDBALL", "woodsball_crash": "WOODSBALL HELI CRASH"}
const MODE_LABELS := {"deathmatch": "10-KILL DEATHMATCH", "deathmatch_10": "10-KILL DEATHMATCH", "ctf": "1-LIFE CTF  BO5", "ctf_bo5": "1-LIFE CTF  BO5", "bot_test": "TEST VS BOTS", "test": "TEST VS BOTS"}
const STATUS_COLORS := {"waiting": Color(0.45, 0.95, 0.35), "in_match": Color(1.0, 0.72, 0.2), "full": Color(1.0, 0.3, 0.25)}
const NEON := Color(0.95, 1.0, 0.15)
const RED_TEAM := Color(1.0, 0.32, 0.25)
const BLUE_TEAM := Color(0.3, 0.6, 1.0)

@export var api_base: String = ""
var lobbies: Array = []
var last_error: String = ""
var _http: HTTPRequest
var _rows: VBoxContainer
var _status_label: Label
var _quick_btn: Button
var _refresh_timer: Timer

func _ready() -> void:
	_build_ui()
	if api_base == "":
		api_base = derive_api_base()
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(refresh)
	add_child(_refresh_timer)
	refresh()

## wss://host:port/ws -> https://host:port (and ws:// -> http://). Reads ?server= on the web build.
static func derive_api_base(server_url: String = "") -> String:
	var url := server_url
	if url == "" and OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		url = str(q) if q != null else ""
	if url == "":
		return ""
	url = url.replace("wss://", "https://").replace("ws://", "http://")
	if url.ends_with("/ws"):
		url = url.substr(0, url.length() - 3)
	return url.trim_suffix("/")

static func parse_lobbies(body: String) -> Array:
	var data = JSON.parse_string(body)
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("lobbies")) == TYPE_ARRAY:
		return data["lobbies"]
	return []

static func player_total(entry: Dictionary) -> int:
	var p: Dictionary = entry.get("players", {})
	return int(p.get("red", 0)) + int(p.get("blue", 0))

static func has_room(entry: Dictionary) -> bool:
	return player_total(entry) < int(entry.get("max_per_team", 5)) * 2

## Tim's rule: the "waiting" lobby with the most players that still has room (ties -> lowest id).
static func pick_quick_join(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for e in list:
		if typeof(e) != TYPE_DICTIONARY or String(e.get("status", "")) != "waiting" or not has_room(e):
			continue
		if best.is_empty() or player_total(e) > player_total(best) or (player_total(e) == player_total(best) and String(e.get("id", "")) < String(best.get("id", ""))):
			best = e
	return best

func refresh() -> void:
	if api_base == "" or _http == null:
		set_lobbies([], "NO SERVER IN LINK  -  SOLO TEST STILL WORKS")
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request(api_base + "/api/lobbies")

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		set_lobbies([], "SERVER OFFLINE  -  RETRYING...")
		return
	set_lobbies(parse_lobbies(body.get_string_from_utf8()))

func set_lobbies(list: Array, error_text: String = "") -> void:
	lobbies = list
	last_error = error_text
	if _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	for e in list:
		if typeof(e) == TYPE_DICTIONARY:
			_rows.add_child(_make_row(e))
	var open := 0
	for e in list:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("status", "")) == "waiting" and has_room(e):
			open += 1
	if error_text != "":
		_status_label.text = error_text
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	else:
		_status_label.text = "%d LOBBIES  -  %d OPEN" % [list.size(), open]
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.78))
	_quick_btn.disabled = pick_quick_join(list).is_empty()
	lobbies_updated.emit(list.size())

func join(entry: Dictionary) -> void:
	lobby_join_requested.emit(entry)
	var url := String(entry.get("join_url", ""))
	if url != "" and OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = %s" % JSON.stringify(url))

func quick_join() -> void:
	var e := pick_quick_join(lobbies)
	if not e.is_empty():
		join(e)

# ---------------------------------------------------------------- UI ----------

func _panel_style(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.06, 0.06, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.33))
	b.add_theme_stylebox_override("normal", _panel_style(accent, accent.darkened(0.45)))
	b.add_theme_stylebox_override("hover", _panel_style(accent.lightened(0.2), Color.WHITE))
	b.add_theme_stylebox_override("pressed", _panel_style(accent.darkened(0.2), accent.darkened(0.6)))
	b.add_theme_stylebox_override("disabled", _panel_style(Color(0.18, 0.18, 0.17), Color(0.1, 0.1, 0.1)))
	return b

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.07, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var board := PanelContainer.new()
	board.custom_minimum_size = Vector2(1080, 0)
	board.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.135, 0.12), Color(0.32, 0.3, 0.25), 3))
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := _label("TOURNAMENT BOARD", 40, NEON)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status_label = _label("CONNECTING...", 18, Color(0.8, 0.82, 0.78))
	header.add_child(_status_label)
	col.add_child(_label("PICK A FIELD  -  5 V 5  -  TEAMS AUTO-SPLIT ON JOIN", 16, Color(0.62, 0.64, 0.58)))

	var cols := HBoxContainer.new()
	for spec in [["LOBBY", 150], ["FIELD", 270], ["GAME", 210], ["RED", 90], ["BLUE", 90], ["STATUS", 120], ["", 110]]:
		var h := _label(spec[0], 14, Color(0.55, 0.56, 0.5))
		h.custom_minimum_size.x = spec[1]
		cols.add_child(h)
	col.add_child(cols)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	_quick_btn = _button("QUICK-JOIN", NEON)
	_quick_btn.custom_minimum_size = Vector2(260, 54)
	_quick_btn.pressed.connect(quick_join)
	footer.add_child(_quick_btn)
	var solo := _button("SOLO TEST VS BOTS", Color(0.55, 0.62, 0.5))
	solo.custom_minimum_size = Vector2(260, 54)
	solo.pressed.connect(func(): solo_requested.emit())
	footer.add_child(solo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var refresh_btn := _button("REFRESH", Color(0.4, 0.42, 0.38))
	refresh_btn.custom_minimum_size = Vector2(150, 54)
	refresh_btn.pressed.connect(refresh)
	footer.add_child(refresh_btn)

func _make_row(e: Dictionary) -> Control:
	var status := String(e.get("status", "waiting"))
	var sc: Color = STATUS_COLORS.get(status, Color.GRAY)
	var row := PanelContainer.new()
	row.name = "Row_" + String(e.get("id", "lobby"))
	row.add_theme_stylebox_override("panel", _panel_style(Color(0.17, 0.175, 0.16), sc.darkened(0.55), 2))
	var h := HBoxContainer.new()
	row.add_child(h)
	var maxp := int(e.get("max_per_team", 5))
	var p: Dictionary = e.get("players", {})
	var mode_key := String(e.get("mode", ""))
	var cells := [
		[String(e.get("name", e.get("id", "LOBBY"))).to_upper(), 150, Color(0.92, 0.93, 0.88)],
		[MAP_LABELS.get(String(e.get("map", "")), String(e.get("map", "")).to_upper()), 270, Color(0.85, 0.86, 0.8)],
		[MODE_LABELS.get(mode_key, "ANY  (LOBBY PICKS)" if mode_key == "" else mode_key.to_upper()), 210, Color(0.75, 0.77, 0.7)],
		["%d / %d" % [int(p.get("red", 0)), maxp], 90, RED_TEAM],
		["%d / %d" % [int(p.get("blue", 0)), maxp], 90, BLUE_TEAM],
		[status.replace("_", " ").to_upper(), 120, sc],
	]
	for c in cells:
		var l := _label(c[0], 18, c[2])
		l.custom_minimum_size.x = c[1]
		l.clip_text = true
		h.add_child(l)
	var btn := _button("JOIN" if status == "waiting" else ("WATCH" if status == "in_match" else "FULL"), sc)
	btn.name = "JoinButton"
	btn.custom_minimum_size = Vector2(110, 40)
	btn.disabled = status == "full" or not has_room(e)
	btn.pressed.connect(join.bind(e))
	h.add_child(btn)
	return row
