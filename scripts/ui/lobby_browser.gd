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
const BuildInfo = preload("res://scripts/systems/build_info.gd")  # v0.7: SERVER_URL stamped per build (test vs live)
const DEFAULT_SERVER_URL := "wss://play.jeetball.com/ws"  # Grok Bot's always-on DigitalOcean server
const MAP_LABELS := {"speedball": "NPPL SPEEDBALL", "woodsball_crash": "WOODSBALL HELI CRASH"}
const MODE_LABELS := {"deathmatch": "10-KILL DEATHMATCH", "deathmatch_10": "10-KILL DEATHMATCH", "ctf": "1-LIFE CTF  BO5", "ctf_bo5": "1-LIFE CTF  BO5", "bots_test": "TEST VS BOTS", "bot_test": "TEST VS BOTS", "test": "TEST VS BOTS"}
const STATUS_COLORS := {"waiting": Color(0.45, 0.95, 0.35), "in_match": Color(1.0, 0.72, 0.2), "full": Color(1.0, 0.3, 0.25)}
const NEON := Color(0.95, 1.0, 0.15)
const RED_TEAM := Color(1.0, 0.32, 0.25)
const BLUE_TEAM := Color(0.3, 0.6, 1.0)

@export var api_base: String = ""
## When false, JOIN only emits lobby_join_requested (the in-place waiting room); true keeps the old page navigation.
var navigate_on_join: bool = true
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
		url = String(BuildInfo.SERVER_URL).strip_edges()
	if url == "":
		url = DEFAULT_SERVER_URL
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
		_status_label.add_theme_color_override("font_color", TournamentSkin.AMBER)
	_quick_btn.disabled = pick_quick_join(list).is_empty()
	lobbies_updated.emit(list.size())

func join(entry: Dictionary) -> void:
	lobby_join_requested.emit(entry)
	var url := String(entry.get("join_url", ""))
	if navigate_on_join and url != "" and OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = %s" % JSON.stringify(url))

func quick_join() -> void:
	var e := pick_quick_join(lobbies)
	if not e.is_empty():
		join(e)

# ---------------------------------------------------------------- UI ----------

func _panel_style(bg: Color, _border: Color = Color.BLACK, _bw: int = 2) -> StyleBox:
	return TournamentSkin.card(bg)

func _label(text: String, size: int, color: Color) -> Label:
	return TournamentSkin.label(text, size, color)

func _button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	return TournamentSkin.style_button(b, accent, 18)

## v0.6 (Ren): Gritty 2000s tournament reskin: netting backdrop, plywood scoreboard, stencil title with
## a paint hit, masking-taped vinyl lobby cards, amber LED counts.
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(TournamentSkin.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var board := PanelContainer.new()
	board.name = "Board"
	board.custom_minimum_size = Vector2(1100, 0)
	board.add_theme_stylebox_override("panel", TournamentSkin.board_style())
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := TournamentSkin.label("TOURNAMENT BOARD", 48, TournamentSkin.NEON, TournamentSkin.STENCIL, 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status_label = TournamentSkin.led("CONNECTING...", 20)
	header.add_child(_status_label)
	col.add_child(TournamentSkin.label("PICK A FIELD  //  5 V 5  //  TEAMS AUTO-SPLIT ON JOIN", 15, TournamentSkin.MUTED))

	var cols := HBoxContainer.new()
	for spec in [["", 10], ["LOBBY", 150], ["FIELD", 270], ["GAME", 210], ["RED", 90], ["BLUE", 90], ["STATUS", 120], ["", 110]]:
		var h := TournamentSkin.label(spec[0], 14, TournamentSkin.MUTED, TournamentSkin.STENCIL, 2)
		h.custom_minimum_size.x = spec[1]
		cols.add_child(h)
	col.add_child(cols)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
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
	_quick_btn.custom_minimum_size = Vector2(260, 56)
	_quick_btn.add_theme_font_size_override("font_size", 22)
	_quick_btn.pressed.connect(quick_join)
	footer.add_child(_quick_btn)
	var solo := _button("SOLO TEST VS BOTS", Color(0.62, 0.7, 0.55))
	solo.custom_minimum_size = Vector2(260, 56)
	solo.pressed.connect(func(): solo_requested.emit())
	footer.add_child(solo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var refresh_btn := _button("REFRESH", Color(0.55, 0.56, 0.52))
	refresh_btn.custom_minimum_size = Vector2(150, 56)
	refresh_btn.pressed.connect(refresh)
	footer.add_child(refresh_btn)
	TournamentSkin.dress_board(self, board, [[Vector2(0.555, 0.08), 120.0, Color(TournamentSkin.PINK, 0.9), 20.0], [Vector2(0.62, 0.92), 110.0, Color(TournamentSkin.NEON, 0.65), -40.0]])

func _make_row(e: Dictionary) -> Control:
	var status := String(e.get("status", "waiting"))
	var sc: Color = STATUS_COLORS.get(status, Color.GRAY)
	var row := PanelContainer.new()
	row.name = "Row_" + String(e.get("id", "lobby"))
	row.add_theme_stylebox_override("panel", TournamentSkin.card(Color(0.3, 0.31, 0.28), 8, 5))
	var h := HBoxContainer.new()
	row.add_child(h)
	var stripe := ColorRect.new()  # spray-painted status stripe down the card edge
	stripe.color = sc
	stripe.custom_minimum_size = Vector2(6, 0)
	h.add_child(stripe)
	var gap := Control.new()
	gap.custom_minimum_size.x = 4
	h.add_child(gap)
	var maxp := int(e.get("max_per_team", 5))
	var p: Dictionary = e.get("players", {})
	var mode_key := String(e.get("mode", ""))
	var cells := [
		[String(e.get("name", e.get("id", "LOBBY"))).to_upper(), 150, TournamentSkin.CHALK, TournamentSkin.STENCIL],
		[MAP_LABELS.get(String(e.get("map", "")), String(e.get("map", "")).to_upper()), 270, Color(0.85, 0.86, 0.8), TournamentSkin.STENCIL],
		[MODE_LABELS.get(mode_key, "ANY  (LOBBY PICKS)" if mode_key == "" else mode_key.to_upper()), 210, Color(0.78, 0.8, 0.72), TournamentSkin.STENCIL],
		["%d/%d" % [int(p.get("red", 0)), maxp], 90, RED_TEAM.lightened(0.15), TournamentSkin.LED],
		["%d/%d" % [int(p.get("blue", 0)), maxp], 90, BLUE_TEAM.lightened(0.15), TournamentSkin.LED],
		[status.replace("_", " ").to_upper(), 120, sc, TournamentSkin.LED],
	]
	for c in cells:
		var l: Label
		if c[3] == TournamentSkin.LED:
			l = TournamentSkin.led(c[0], 22, c[2])
		else:
			l = TournamentSkin.label(c[0], 18, c[2])
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
