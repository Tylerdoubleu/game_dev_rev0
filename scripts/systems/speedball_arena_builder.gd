extends Node3D

## Full-scale 3x Speedball Arena (108m x 132m) for v0.2 Gritty 2000s Tournament Art Overhaul.
## Features overcast stadium lighting, floodlight towers, perimeter black safety netting,
## tournament scoreboard backdrop, muddy turf with slick puddles, scuffed vinyl inflatable bunkers,
## stacked wooden cable spools, and 5 OpFor bots.

const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")

var player: Node3D
var hud_label: Label
var status_label: Label
var intel_label: Label
var round_label: Label

# Gritty 2000s Tournament Lobby Overlay Nodes
var lobby_canvas: CanvasLayer
var lobby_panel: PanelContainer
var lobby_status_label: Label
var lobby_roster_label: Label
var callsign_input: LineEdit
var room_input: LineEdit
var server_url_input: LineEdit
var team_alpha_btn: Button
var team_bravo_btn: Button
var bracket_speedball_btn: Button
var bracket_woodsball_btn: Button
var bracket_pump_btn: Button
var fill_bots_check: CheckBox
var copy_link_btn: Button
var npc_presence_on_btn: Button
var npc_presence_off_btn: Button
var scoreboard_canvas: CanvasLayer
var scoreboard_body_label: Label

func _ready() -> void:
	_build_environment_and_turf()
	_build_speedball_bunkers()
	_spawn_opfor_bots()
	if not NetworkLobby.is_dedicated_server:
		_spawn_player()
		_build_hud()
		_build_tournament_lobby_overlay()
		_build_scoreboard_overlay()
	GameManager.round_updated.connect(_on_round_updated)
	GameManager.round_won.connect(_on_round_won)
	GameManager.scoreboard_updated.connect(_on_scoreboard_updated)
	GameManager.match_over.connect(_on_match_over)
	IntelBus.intel_feed_updated.connect(_on_intel_feed)
	NetworkLobby.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkLobby.connection_status_changed.connect(_on_lobby_connection_status)
	NetworkLobby.match_started_signal.connect(_on_network_match_started)
	GameManager.register_round_start(5)

func _build_environment_and_turf() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = GrittyArtThemeScript.create_overcast_stadium_environment()
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "OvercastStadiumSun"
	sun.rotation_degrees = Vector3(-54.0, -32.0, 0.0)
	sun.shadow_enabled = true
	sun.light_color = Color(0.84, 0.87, 0.92)
	sun.light_energy = 0.92
	add_child(sun)

	# 3x Turf Floor (108m wide x 132m long) with worn muddy turf & normal/roughness maps
	var floor_body := StaticBody3D.new()
	floor_body.name = "TurfFloor"
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(108.0, 0.4, 132.0)
	fcol.shape = fbox
	fcol.position = Vector3(0, -0.2, 0)
	floor_body.add_child(fcol)

	var fmesh := MeshInstance3D.new()
	fmesh.name = "TurfFloorMesh"
	var fbm := BoxMesh.new()
	fbm.size = Vector3(108.0, 0.4, 132.0)
	fmesh.mesh = fbm
	fmesh.position = Vector3(0, -0.2, 0)
	fmesh.material_override = GrittyArtThemeScript.create_muddy_turf_material()
	floor_body.add_child(fmesh)
	add_child(floor_body)

	# Mud-stained 50-yard center line stripe on turf
	var line_mesh := MeshInstance3D.new()
	line_mesh.name = "Center50Line"
	var lbm := BoxMesh.new()
	lbm.size = Vector3(88.0, 0.015, 0.32)
	line_mesh.mesh = lbm
	line_mesh.position = Vector3(0, 0.006, 0)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.62, 0.60, 0.54)
	line_mat.roughness = 0.88
	line_mesh.material_override = line_mat
	add_child(line_mesh)

	# Stadium floodlight towers, perimeter safety netting, scoreboards, puddles, and wooden cable spools
	GrittyArtThemeScript.build_stadium_props(self)

func _build_speedball_bunkers() -> void:
	var blue_vinyl := Color(0.22, 0.36, 0.64)
	var yellow_vinyl := Color(0.84, 0.70, 0.16)
	var red_vinyl := Color(0.72, 0.22, 0.20)
	var dark_vinyl := Color(0.42, 0.43, 0.45)

	# --- 1. CENTER 50-YARD LINE CLUSTER ---
	_spawn_bunker("Bunker_Center50_W", Vector3(0.0, 0.0, 0.0), Vector3(4.5, 2.4, 1.8), yellow_vinyl)
	_spawn_bunker("Bunker_50_MiniWin_Left", Vector3(-9.5, 0.0, 0.0), Vector3(2.4, 2.1, 1.4), yellow_vinyl)
	_spawn_bunker("Bunker_50_MiniWin_Right", Vector3(9.5, 0.0, 0.0), Vector3(2.4, 2.1, 1.4), yellow_vinyl)
	_spawn_bunker("Bunker_50_Insert_Left", Vector3(-19.0, 0.0, 0.0), Vector3(2.2, 2.2, 1.6), yellow_vinyl)
	_spawn_bunker("Bunker_50_Insert_Right", Vector3(19.0, 0.0, 0.0), Vector3(2.2, 2.2, 1.6), yellow_vinyl)

	# --- 2. SYMMETRICAL HALF-FIELD BUNKERS (Mirrored for Player +Z and OpFor -Z) ---
	for side in [-1.0, 1.0]:
		var team_color: Color = dark_vinyl if side > 0.0 else blue_vinyl
		var prefix: String = "Home_" if side > 0.0 else "OpFor_"

		# Breakout Start Gate & Back Center (Home Stone)
		_spawn_bunker(prefix + "BreakoutGate", Vector3(0.0, 0.0, 48.0 * side), Vector3(3.6, 2.3, 1.2), team_color)
		_spawn_bunker(prefix + "BackCenter", Vector3(0.0, 0.0, 38.0 * side), Vector3(3.2, 2.2, 1.4), team_color)

		# Near-Breakout Tournament Cans & Horizontal Bolster (gives classic 2000s tournament density)
		_spawn_bunker(prefix + "BreakoutCan_L", Vector3(-2.6, 0.0, 41.8 * side), Vector3(1.5, 2.2, 1.5), dark_vinyl)
		_spawn_bunker(prefix + "BreakoutCan_R", Vector3(-1.8, 0.0, 36.2 * side), Vector3(1.5, 2.1, 1.5), dark_vinyl)
		_spawn_bunker(prefix + "BreakoutBolster", Vector3(-0.3, 0.0, 35.0 * side), Vector3(1.0, 1.0, 3.4), dark_vinyl)

		# Mid-Back Bricks & Cakes (Z = 28m)
		_spawn_bunker(prefix + "BackBrick_L", Vector3(-11.0, 0.0, 29.0 * side), Vector3(2.6, 2.0, 1.6), team_color)
		_spawn_bunker(prefix + "BackBrick_R", Vector3(11.0, 0.0, 29.0 * side), Vector3(2.6, 2.0, 1.6), team_color)
		_spawn_bunker(prefix + "OuterTower_L", Vector3(-22.0, 0.0, 31.0 * side), Vector3(2.2, 2.4, 2.2), team_color)
		_spawn_bunker(prefix + "OuterTower_R", Vector3(22.0, 0.0, 31.0 * side), Vector3(2.2, 2.4, 2.2), team_color)

		# Midfield Temples, Aztecs & Tall Cans (Z = 18m)
		_spawn_bunker(prefix + "CenterAztec", Vector3(0.0, 0.0, 19.0 * side), Vector3(2.8, 2.3, 1.8), team_color)
		_spawn_bunker(prefix + "MidCan_L", Vector3(-8.5, 0.0, 17.5 * side), Vector3(2.0, 2.3, 2.0), yellow_vinyl)
		_spawn_bunker(prefix + "MidCan_R", Vector3(8.5, 0.0, 17.5 * side), Vector3(2.0, 2.3, 2.0), yellow_vinyl)
		_spawn_bunker(prefix + "WideTemple_L", Vector3(-18.5, 0.0, 18.5 * side), Vector3(2.4, 2.1, 2.0), team_color)
		_spawn_bunker(prefix + "WideTemple_R", Vector3(18.5, 0.0, 18.5 * side), Vector3(2.4, 2.1, 2.0), team_color)

		# 40-Yard Attacking Pins & Wedges (Z = 9m)
		_spawn_bunker(prefix + "40_Pin_L", Vector3(-5.5, 0.0, 9.0 * side), Vector3(1.8, 1.9, 1.8), team_color)
		_spawn_bunker(prefix + "40_Pin_R", Vector3(5.5, 0.0, 9.0 * side), Vector3(1.8, 1.9, 1.8), team_color)
		_spawn_bunker(prefix + "40_Wedge_L", Vector3(-14.5, 0.0, 9.5 * side), Vector3(2.2, 1.6, 2.2), team_color)
		_spawn_bunker(prefix + "40_Wedge_R", Vector3(14.5, 0.0, 9.5 * side), Vector3(2.2, 1.6, 2.2), team_color)

		# --- 3. DORITO HIGHWAY (Far Right Edge: X = +28m to +38m) ---
		_spawn_bunker(prefix + "Dorito_Corner", Vector3(32.0, 0.0, 35.0 * side), Vector3(2.6, 2.2, 2.6), team_color)
		_spawn_bunker(prefix + "Dorito_1", Vector3(34.5, 0.0, 23.0 * side), Vector3(2.5, 2.1, 2.5), yellow_vinyl)
		_spawn_bunker(prefix + "Dorito_2", Vector3(36.5, 0.0, 11.5 * side), Vector3(2.5, 2.1, 2.5), team_color)

		# --- 4. SNAKE CORNER & GOD-BUNKERS (Far Left Edge Entry: X = -28m to -38m) ---
		_spawn_bunker(prefix + "Snake_Corner", Vector3(-33.0, 0.0, 35.0 * side), Vector3(2.8, 2.2, 2.2), team_color)
		_spawn_bunker(prefix + "Snake_GodCan", Vector3(-28.5, 0.0, 24.5 * side), Vector3(2.2, 2.2, 2.2), team_color)

	# 50-Yard Giant Dorito on Far Right (+X = 38m)
	_spawn_bunker("Bunker_50_GiantDorito", Vector3(38.0, 0.0, 0.0), Vector3(3.0, 2.4, 3.0), yellow_vinyl)

	# --- 5. ACTUAL MULTI-KNUCKLE SNAKE ON THE FAR LEFT EDGE 50s (X = -34m to -39m, Z = -20m to +20m) ---
	_spawn_bunker("Snake_Beam_Home1", Vector3(-35.0, 0.0, 15.0), Vector3(1.1, 0.92, 9.5), red_vinyl)
	_spawn_bunker("Snake_Beam_Home2", Vector3(-37.2, 0.0, 5.5), Vector3(1.1, 0.92, 9.5), yellow_vinyl)
	_spawn_bunker("Snake_Beam_OpFor2", Vector3(-37.2, 0.0, -5.5), Vector3(1.1, 0.92, 9.5), yellow_vinyl)
	_spawn_bunker("Snake_Beam_OpFor1", Vector3(-35.0, 0.0, -15.0), Vector3(1.1, 0.92, 9.5), red_vinyl)

	# Snake Knuckle Cross-Pillars (Stand-up/Crouch pockets along the snake)
	_spawn_bunker("Snake_Knuckle_HomeEntry", Vector3(-35.0, 0.0, 20.0), Vector3(2.6, 1.45, 1.3), blue_vinyl)
	_spawn_bunker("Snake_Knuckle_HomeMid", Vector3(-36.1, 0.0, 10.2), Vector3(2.8, 1.45, 1.3), yellow_vinyl)
	_spawn_bunker("Snake_Knuckle_Center50", Vector3(-37.2, 0.0, 0.0), Vector3(3.0, 1.65, 1.5), red_vinyl)
	_spawn_bunker("Snake_Knuckle_OpForMid", Vector3(-36.1, 0.0, -10.2), Vector3(2.8, 1.45, 1.3), yellow_vinyl)
	_spawn_bunker("Snake_Knuckle_OpForEntry", Vector3(-35.0, 0.0, -20.0), Vector3(2.6, 1.45, 1.3), dark_vinyl)

func _spawn_bunker(bunker_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = bunker_name
	body.position = pos + Vector3(0, size.y * 0.5, 0)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "BunkerMesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	body.add_child(mesh)
	GrittyArtThemeScript.decorate_bunker_mesh(body, mesh, size, color)
	add_child(body)

func _spawn_opfor_bots() -> void:
	var bot_script := load("res://scripts/systems/snap_target_bot.gd")

	var placements := [
		{"name": "OpFor_Snake50", "label": "OpFor Snake-1", "pos": Vector3(-35.0, 0.0, -11.5), "peek": Vector3(1.3, 0.0, 0.0)},
		{"name": "OpFor_SnakeCorner", "label": "OpFor Snake-Corner", "pos": Vector3(-28.5, 0.0, -25.8), "peek": Vector3(1.25, 0.0, 0.0)},
		{"name": "OpFor_CenterAztec", "label": "OpFor Center-Aztec", "pos": Vector3(0.0, 0.0, -20.2), "peek": Vector3(1.55, 0.0, 0.0)},
		{"name": "OpFor_Dorito2", "label": "OpFor Dorito-2", "pos": Vector3(36.5, 0.0, -12.8), "peek": Vector3(-1.4, 0.0, 0.0)},
		{"name": "OpFor_BackCenter", "label": "OpFor Back-Center", "pos": Vector3(0.0, 0.0, -39.2), "peek": Vector3(1.6, 0.0, 0.0)}
	]

	for p in placements:
		var b := StaticBody3D.new()
		b.set_script(bot_script)
		b.name = p["name"]
		b.set("bot_name", p["label"])
		b.position = p["pos"]
		b.set("peek_offset", p["peek"])
		add_child(b)

func _spawn_player() -> void:
	var player_script := load("res://scripts/player/player_controller_3d.gd")
	player = CharacterBody3D.new()
	player.name = "Player3D"
	player.set_script(player_script)
	player.position = Vector3(0.0, 0.1, 45.5)
	add_child(player)
	player.connect("hud_state_changed", _on_hud_state_changed)
	player.connect("status_banner_sent", _on_status_banner)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PlaytestHUD"
	add_child(canvas)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.9))
	canvas.add_child(crosshair)

	hud_label = Label.new()
	hud_label.position = Vector2(20, 16)
	hud_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hud_label)

	round_label = Label.new()
	round_label.position = Vector2(930, 16)
	round_label.add_theme_font_size_override("font_size", 15)
	canvas.add_child(round_label)

	status_label = Label.new()
	status_label.position = Vector2(20, 815)
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	canvas.add_child(status_label)

	intel_label = Label.new()
	intel_label.position = Vector2(20, 775)
	intel_label.add_theme_font_size_override("font_size", 17)
	intel_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	canvas.add_child(intel_label)

	player.call("_emit_hud")

func _on_hud_state_changed(state: Dictionary) -> void:
	if hud_label == null:
		return
	var reload_text := ""
	if state["reloading"]:
		reload_text = "\n[POURING POD: %d%% — DO NOT SPRINT/SLIDE/DIVE!]" % int(state["reload_pct"] * 100.0)
	var pump_text := ""
	if state["pump_mode"]:
		pump_text = " | PUMP: %s" % ("RACKED (Ready)" if state["pump_racked"] else "NEEDS RACK [RMB]")

	hud_label.text = (
		"BRACKET: %s\n" % state["bracket_name"] +
		"HOPPER: %d / %d  |  PODS: %d (%d rnds)%s\n" % [state["hopper"], state["hopper_max"], state["pods"], state["pod_cap"], pump_text] +
		"STANCE: %s  |  SHOULDER: %s%s" % [state["stance"], state["hand"], reload_text]
	)

func _on_round_updated(round_num: int, _remaining: int, time_left: float) -> void:
	if round_label == null:
		return
	var net_tag := "ONLINE [%s]" % NetworkLobby.active_room.to_upper() if NetworkLobby.is_online_client() else ("SOLO+NPCs" if NetworkLobby.fill_bots_enabled else "PVP ONLY")
	round_label.text = (
		"ROUND %d  |  KILLS: %d (+1 Pod/Kill)  |  DEATHS: %d/%d  |  TIME: %.0fs  |  %s\n" % [round_num, GameManager.local_kills, GameManager.local_deaths, GameManager.MAX_DEATHS_TO_LOSE, time_left, net_tag] +
		"Move: WASD + Shift Sprint | C Crouch | Shift+C Knee-Slide | Ctrl Prone | Shift+Ctrl Dive\n" +
		"1 Speedball (Walk LMB/RMB) | 2 Woodsball (Hold LMB+RMB) | 3 Pump (LMB->RMB)\n" +
		"R Pod Reload | F Ping | [M] Scoreboard (K/D) | [TAB / ESC] Opening Menu | T Reset"
	)

func _on_round_won(round_num: int) -> void:
	_on_status_banner("ROUND %d WON! All 5 OpFor Eliminated — Press [T] for Next Round" % round_num, Color(0.3, 1.0, 0.45))

func _on_status_banner(msg: String, color: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)

func _on_intel_feed(msg: String) -> void:
	if intel_label:
		intel_label.text = msg

func _unhandled_input(event: InputEvent) -> void:
	if NetworkLobby.is_dedicated_server or lobby_canvas == null:
		return
	if event.is_action_pressed("toggle_lobby") or event.is_action_pressed("ui_cancel"):
		_set_lobby_overlay_visible(not lobby_canvas.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_scoreboard"):
		if scoreboard_canvas != null:
			scoreboard_canvas.visible = not scoreboard_canvas.visible
			_refresh_scoreboard_text()
		get_viewport().set_input_as_handled()

func _build_tournament_lobby_overlay() -> void:
	lobby_canvas = CanvasLayer.new()
	lobby_canvas.name = "TournamentLobbyOverlay"
	lobby_canvas.layer = 10
	add_child(lobby_canvas)

	var backdrop := ColorRect.new()
	backdrop.name = "LobbyBackdrop"
	backdrop.color = Color(0.05, 0.06, 0.08, 0.82)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_canvas.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_canvas.add_child(center)

	lobby_panel = PanelContainer.new()
	lobby_panel.name = "LobbyMainPanel"
	lobby_panel.custom_minimum_size = Vector2(760, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.15, 0.96)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.92, 0.76, 0.14, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	lobby_panel.add_theme_stylebox_override("panel", style)
	center.add_child(lobby_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	lobby_panel.add_child(vbox)

	var title := Label.new()
	title.text = "NPPL / PSP 2004 TOURNAMENT STAGING PITS — CLICK-TO-LOBBY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	lobby_status_label = Label.new()
	lobby_status_label.name = "LobbyStatusLabel"
	lobby_status_label.text = "LIVE LOBBY STATUS: Initializing WebSocket Staging..."
	lobby_status_label.add_theme_font_size_override("font_size", 15)
	lobby_status_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
	lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lobby_status_label)

	# Row 1: Callsign & Room Code
	var row_id := HBoxContainer.new()
	row_id.add_theme_constant_override("separation", 12)
	vbox.add_child(row_id)

	var lbl_callsign := Label.new()
	lbl_callsign.text = "CALLSIGN:"
	lbl_callsign.custom_minimum_size = Vector2(95, 0)
	row_id.add_child(lbl_callsign)

	callsign_input = LineEdit.new()
	callsign_input.name = "CallsignInput"
	callsign_input.text = NetworkLobby.local_callsign
	callsign_input.placeholder_text = "Enter player callsign..."
	callsign_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_id.add_child(callsign_input)

	var lbl_room := Label.new()
	lbl_room.text = "ROOM:"
	row_id.add_child(lbl_room)

	room_input = LineEdit.new()
	room_input.name = "RoomInput"
	room_input.text = NetworkLobby.active_room
	room_input.custom_minimum_size = Vector2(120, 0)
	row_id.add_child(room_input)

	# Row 2: Server WebSocket Endpoint (Edgegap Arbitrium / Local / Custom WS)
	var row_srv := HBoxContainer.new()
	row_srv.add_theme_constant_override("separation", 10)
	vbox.add_child(row_srv)

	var lbl_srv := Label.new()
	lbl_srv.text = "SERVER WS:"
	lbl_srv.custom_minimum_size = Vector2(95, 0)
	row_srv.add_child(lbl_srv)

	server_url_input = LineEdit.new()
	server_url_input.name = "ServerUrlInput"
	server_url_input.text = NetworkLobby.current_ws_url
	server_url_input.placeholder_text = "wss://... or ip:port (Edgegap Arbitrium / Custom)"
	server_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_srv.add_child(server_url_input)

	var connect_btn := Button.new()
	connect_btn.name = "ConnectServerButton"
	connect_btn.text = "CONNECT / SYNC WS"
	connect_btn.custom_minimum_size = Vector2(165, 34)
	connect_btn.pressed.connect(_on_connect_ws_pressed)
	row_srv.add_child(connect_btn)

	# Row 3: Team Selection (ALPHA vs BRAVO)
	var row_team := HBoxContainer.new()
	row_team.add_theme_constant_override("separation", 12)
	vbox.add_child(row_team)

	var lbl_team := Label.new()
	lbl_team.text = "TEAM SIDE:"
	lbl_team.custom_minimum_size = Vector2(95, 0)
	row_team.add_child(lbl_team)

	team_alpha_btn = Button.new()
	team_alpha_btn.text = "TEAM ALPHA (SOUTH GATE)"
	team_alpha_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_alpha_btn.pressed.connect(func() -> void: _select_team("ALPHA"))
	row_team.add_child(team_alpha_btn)

	team_bravo_btn = Button.new()
	team_bravo_btn.text = "TEAM BRAVO (NORTH GATE)"
	team_bravo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_bravo_btn.pressed.connect(func() -> void: _select_team("BRAVO"))
	row_team.add_child(team_bravo_btn)

	# Row 4: Gear Bracket Selection
	var row_bracket := HBoxContainer.new()
	row_bracket.add_theme_constant_override("separation", 10)
	vbox.add_child(row_bracket)

	var lbl_bracket := Label.new()
	lbl_bracket.text = "BRACKET:"
	lbl_bracket.custom_minimum_size = Vector2(95, 0)
	row_bracket.add_child(lbl_bracket)

	bracket_speedball_btn = Button.new()
	bracket_speedball_btn.text = "SPEEDBALL (10.5 BPS)"
	bracket_speedball_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bracket_speedball_btn.pressed.connect(func() -> void: _select_bracket("speedball"))
	row_bracket.add_child(bracket_speedball_btn)

	bracket_woodsball_btn = Button.new()
	bracket_woodsball_btn.text = "WOODSBALL (1-PULL)"
	bracket_woodsball_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bracket_woodsball_btn.pressed.connect(func() -> void: _select_bracket("woodsball"))
	row_bracket.add_child(bracket_woodsball_btn)

	bracket_pump_btn = Button.new()
	bracket_pump_btn.text = "STOCK PUMP"
	bracket_pump_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bracket_pump_btn.pressed.connect(func() -> void: _select_bracket("pump"))
	row_bracket.add_child(bracket_pump_btn)

	# Row 5: NPC Presence Selector (Selectable in Opening Menu)
	var row_npc := HBoxContainer.new()
	row_npc.add_theme_constant_override("separation", 10)
	vbox.add_child(row_npc)

	var lbl_npc := Label.new()
	lbl_npc.text = "NPC PRESENCE:"
	lbl_npc.custom_minimum_size = Vector2(95, 0)
	row_npc.add_child(lbl_npc)

	npc_presence_on_btn = Button.new()
	npc_presence_on_btn.name = "NpcPresenceOnButton"
	npc_presence_on_btn.text = "NPC PRESENCE: ON (5 OpFor Bots)"
	npc_presence_on_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_presence_on_btn.pressed.connect(func() -> void: _select_npc_presence(true))
	row_npc.add_child(npc_presence_on_btn)

	npc_presence_off_btn = Button.new()
	npc_presence_off_btn.name = "NpcPresenceOffButton"
	npc_presence_off_btn.text = "NPC PRESENCE: OFF (Players Only)"
	npc_presence_off_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_presence_off_btn.pressed.connect(func() -> void: _select_npc_presence(false))
	row_npc.add_child(npc_presence_off_btn)

	fill_bots_check = CheckBox.new()
	fill_bots_check.visible = false
	fill_bots_check.button_pressed = NetworkLobby.fill_bots_enabled
	vbox.add_child(fill_bots_check)

	# Roster Box
	var roster_panel := PanelContainer.new()
	roster_panel.custom_minimum_size = Vector2(0, 135)
	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0.07, 0.08, 0.10, 0.95)
	rstyle.border_width_left = 1
	rstyle.border_width_top = 1
	rstyle.border_width_right = 1
	rstyle.border_width_bottom = 1
	rstyle.border_color = Color(0.32, 0.36, 0.42)
	rstyle.content_margin_left = 14
	rstyle.content_margin_right = 14
	rstyle.content_margin_top = 10
	rstyle.content_margin_bottom = 10
	roster_panel.add_theme_stylebox_override("panel", rstyle)
	vbox.add_child(roster_panel)

	lobby_roster_label = Label.new()
	lobby_roster_label.name = "LobbyRosterLabel"
	lobby_roster_label.add_theme_font_size_override("font_size", 14)
	lobby_roster_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	roster_panel.add_child(lobby_roster_label)

	# Bottom Action Buttons: DROP IN TO ARENA & COPY INVITE LINK
	var row_actions := HBoxContainer.new()
	row_actions.add_theme_constant_override("separation", 14)
	vbox.add_child(row_actions)

	var drop_in_btn := Button.new()
	drop_in_btn.name = "DropInArenaButton"
	drop_in_btn.text = ">> DROP IN TO ARENA (PLAY NOW) <<"
	drop_in_btn.custom_minimum_size = Vector2(0, 48)
	drop_in_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_in_btn.add_theme_font_size_override("font_size", 18)
	drop_in_btn.add_theme_color_override("font_color", Color(0.15, 1.0, 0.45))
	drop_in_btn.pressed.connect(_on_drop_in_pressed)
	row_actions.add_child(drop_in_btn)

	copy_link_btn = Button.new()
	copy_link_btn.name = "CopyInviteLinkButton"
	copy_link_btn.text = "COPY INVITE LINK"
	copy_link_btn.custom_minimum_size = Vector2(210, 48)
	copy_link_btn.add_theme_font_size_override("font_size", 16)
	copy_link_btn.pressed.connect(_on_copy_invite_pressed)
	row_actions.add_child(copy_link_btn)

	_refresh_lobby_button_highlights()
	_on_lobby_state_changed(NetworkLobby.get_lobby_state_snapshot())

	# Show lobby overlay on interactive clients; keep hidden in headless smoke tests
	var is_headless := (DisplayServer.get_name() == "headless")
	_set_lobby_overlay_visible(not is_headless)

func _set_lobby_overlay_visible(show_lobby: bool) -> void:
	if lobby_canvas == null:
		return
	lobby_canvas.visible = show_lobby
	if player and player.has_method("set_lobby_open_state"):
		player.call("set_lobby_open_state", show_lobby)

func _select_team(team: String) -> void:
	NetworkLobby.active_room = room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.update_local_player_choices(callsign_input.text, team, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	if player and player.has_method("respawn_at_team_gate"):
		player.call("respawn_at_team_gate", NetworkLobby.local_team)
	_refresh_lobby_button_highlights()

func _select_bracket(bracket_id: String) -> void:
	NetworkLobby.active_room = room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.update_local_player_choices(callsign_input.text, NetworkLobby.local_team, bracket_id, fill_bots_check.button_pressed)
	_refresh_lobby_button_highlights()

func _refresh_lobby_button_highlights() -> void:
	if team_alpha_btn == null:
		return
	team_alpha_btn.modulate = Color(0.4, 0.95, 1.0) if NetworkLobby.local_team == "ALPHA" else Color(0.75, 0.75, 0.75)
	team_bravo_btn.modulate = Color(1.0, 0.55, 0.55) if NetworkLobby.local_team == "BRAVO" else Color(0.75, 0.75, 0.75)
	bracket_speedball_btn.modulate = Color(1.0, 0.92, 0.3) if NetworkLobby.local_bracket == "speedball" else Color(0.75, 0.75, 0.75)
	bracket_woodsball_btn.modulate = Color(1.0, 0.92, 0.3) if NetworkLobby.local_bracket == "woodsball" else Color(0.75, 0.75, 0.75)
	bracket_pump_btn.modulate = Color(1.0, 0.92, 0.3) if NetworkLobby.local_bracket == "pump" else Color(0.75, 0.75, 0.75)
	if npc_presence_on_btn != null and npc_presence_off_btn != null:
		npc_presence_on_btn.modulate = Color(0.35, 1.0, 0.55) if NetworkLobby.fill_bots_enabled else Color(0.72, 0.72, 0.72)
		npc_presence_off_btn.modulate = Color(1.0, 0.75, 0.35) if not NetworkLobby.fill_bots_enabled else Color(0.72, 0.72, 0.72)

func _on_connect_ws_pressed() -> void:
	NetworkLobby.active_room = room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.local_callsign = callsign_input.text.strip_edges() if not callsign_input.text.strip_edges().is_empty() else NetworkLobby.local_callsign
	NetworkLobby.connect_to_lobby(server_url_input.text)
	server_url_input.text = NetworkLobby.current_ws_url

func _on_drop_in_pressed() -> void:
	var chosen_room := room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.active_room = chosen_room
	NetworkLobby.update_local_player_choices(callsign_input.text, NetworkLobby.local_team, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	NetworkLobby.request_start_match(chosen_room, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	_set_lobby_overlay_visible(false)

func _on_copy_invite_pressed() -> void:
	NetworkLobby.active_room = room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	var url := NetworkLobby.copy_invite_link()
	if copy_link_btn:
		copy_link_btn.text = "COPIED! (%s)" % NetworkLobby.active_room
	_on_status_banner("Copied Lobby Invite Link: %s" % url, Color(0.4, 1.0, 0.6))

func _on_lobby_connection_status(status_text: String, is_online: bool) -> void:
	if lobby_status_label:
		lobby_status_label.text = "LIVE LOBBY STATUS: %s" % status_text
		lobby_status_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55) if is_online else Color(1.0, 0.82, 0.35))

func _on_lobby_state_changed(state: Dictionary) -> void:
	if lobby_roster_label == null:
		return
	var p_dict: Dictionary = state.get("players", {})
	var lines: Array[String] = []
	lines.append("STAGING ROSTER — ROOM [%s] (%d Human Player%s + %s):" % [
		String(state.get("room", "alpha")).to_upper(),
		p_dict.size(),
		"" if p_dict.size() == 1 else "s",
		"5 OpFor Bots" if bool(state.get("fill_bots", true)) else "No Bots"
	])
	for pid in p_dict.keys():
		var info: Dictionary = p_dict[pid]
		lines.append("  • [%s] %s  —  Bracket: %s  (%s)" % [
			info.get("team", "ALPHA"),
			info.get("name", "Player"),
			String(info.get("bracket", "speedball")).to_upper(),
			"READY / ON TURF" if info.get("ready", true) else "STAGING"
		])
	lobby_roster_label.text = "\n".join(lines)

func _on_network_match_started(_room_id: String, bracket_id: String, fill_bots: bool) -> void:
	_set_opfor_bots_enabled(fill_bots)
	_refresh_lobby_button_highlights()
	_on_status_banner("MATCH LIVE — Room [%s] | Bracket: %s | Press [TAB] for Lobby" % [NetworkLobby.active_room.to_upper(), bracket_id.to_upper()], Color(0.35, 1.0, 0.55))

func _set_opfor_bots_enabled(enabled: bool) -> void:
	for bname in ["OpFor_Snake50", "OpFor_SnakeCorner", "OpFor_CenterAztec", "OpFor_Dorito2", "OpFor_BackCenter"]:
		var b := get_node_or_null(bname) as Node3D
		if b != null:
			b.visible = enabled
			b.set_process(enabled)
			b.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
			for child in b.get_children():
				if child is CollisionShape3D:
					child.disabled = not enabled

func _select_npc_presence(enabled: bool) -> void:
	NetworkLobby.fill_bots_enabled = enabled
	if fill_bots_check != null:
		fill_bots_check.button_pressed = enabled
	_set_opfor_bots_enabled(enabled)
	NetworkLobby.update_local_player_choices(callsign_input.text, NetworkLobby.local_team, NetworkLobby.local_bracket, enabled)
	_refresh_lobby_button_highlights()

func _build_scoreboard_overlay() -> void:
	scoreboard_canvas = CanvasLayer.new()
	scoreboard_canvas.name = "ScoreboardOverlay"
	scoreboard_canvas.layer = 9
	scoreboard_canvas.visible = false
	add_child(scoreboard_canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ScoreboardPanel"
	panel.custom_minimum_size = Vector2(640, 340)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	pstyle.border_width_left = 3
	pstyle.border_width_top = 3
	pstyle.border_width_right = 3
	pstyle.border_width_bottom = 3
	pstyle.border_color = Color(0.95, 0.80, 0.18, 0.95)
	pstyle.corner_radius_top_left = 6
	pstyle.corner_radius_top_right = 6
	pstyle.corner_radius_bottom_left = 6
	pstyle.corner_radius_bottom_right = 6
	pstyle.content_margin_left = 24
	pstyle.content_margin_right = 24
	pstyle.content_margin_top = 20
	pstyle.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "LIVE MATCH SCOREBOARD [M] — FIRST TO 10 DEATHS LOSES"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(0.98, 0.85, 0.18))
	vbox.add_child(hdr)

	var rules_sub := Label.new()
	rules_sub.text = "RULE: Respawn at Original Starting Gate on Hit  |  +1 Bonus Paint Pod per Kill  |  10 Deaths = Loss"
	rules_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_sub.add_theme_font_size_override("font_size", 13)
	rules_sub.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0))
	vbox.add_child(rules_sub)

	scoreboard_body_label = Label.new()
	scoreboard_body_label.name = "ScoreboardBodyLabel"
	scoreboard_body_label.add_theme_font_size_override("font_size", 16)
	scoreboard_body_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	vbox.add_child(scoreboard_body_label)

	_refresh_scoreboard_text()

func _on_scoreboard_updated(_stats: Dictionary) -> void:
	_refresh_scoreboard_text()

func _on_match_over(loser_name: String, winner_label: String) -> void:
	if scoreboard_canvas != null:
		scoreboard_canvas.visible = true
	_refresh_scoreboard_text()
	_on_status_banner("MATCH OVER! %s hit 10 Deaths — %s WINS! Press [T] for Rematch" % [loser_name, winner_label], Color(1.0, 0.88, 0.22))

func _refresh_scoreboard_text() -> void:
	if scoreboard_body_label == null:
		return
	var lines: Array[String] = []
	lines.append("----------------------------------------------------------------------")
	lines.append("PLAYER / SQUAD                  TEAM       KILLS (+PODS)     DEATHS (MAX 10)")
	lines.append("----------------------------------------------------------------------")
	lines.append("%-30s  %-9s  %-16d  %d / %d" % [
		NetworkLobby.local_callsign + " (YOU)",
		NetworkLobby.local_team,
		GameManager.local_kills,
		GameManager.local_deaths,
		GameManager.MAX_DEATHS_TO_LOSE
	])
	for pid in NetworkLobby.players.keys():
		var my_id := multiplayer.get_unique_id() if NetworkLobby.peer != null else 1
		if int(pid) == my_id:
			continue
		var pinfo: Dictionary = NetworkLobby.players[pid]
		lines.append("%-30s  %-9s  %-16d  %d / %d" % [
			String(pinfo.get("name", "Peer #%d" % int(pid))),
			String(pinfo.get("team", "BRAVO")),
			int(pinfo.get("kills", 0)),
			int(pinfo.get("deaths", 0)),
			GameManager.MAX_DEATHS_TO_LOSE
		])
	if NetworkLobby.fill_bots_enabled:
		lines.append("%-30s  %-9s  %-16d  %d / %d" % [
			"OpFor NPC Squad (5 Bots)",
			"OPFOR",
			GameManager.local_deaths,
			GameManager.npc_deaths,
			GameManager.MAX_DEATHS_TO_LOSE
		])
	lines.append("----------------------------------------------------------------------")
	if GameManager.match_ended:
		lines.append(">> MATCH ENDED (10 DEATH LIMIT REACHED) — PRESS [T] TO START NEXT MATCH <<")
	else:
		lines.append("Press [M] to Close Scoreboard   |   Press [TAB] for Opening Menu / NPC Toggle")
	scoreboard_body_label.text = "\n".join(lines)
