extends Node3D

## Full-scale 3x Speedball Arena (108m x 132m) for v0.2 Gritty 2000s Tournament Art Overhaul.
## Features overcast stadium lighting, floodlight towers, perimeter black safety netting,
## tournament scoreboard backdrop, muddy turf with slick puddles, scuffed vinyl inflatable bunkers,
## stacked wooden cable spools, and 5 OpFor bots.

const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")
const MatchHudClientScript = preload("res://scripts/ui/match_hud_client.gd")
const BunkerCalloutsScript = preload("res://scripts/systems/bunker_callouts.gd")
const MouseCaptureGuardScript = preload("res://scripts/systems/mouse_capture_guard.gd")

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
var map_speedball_btn: Button
var map_woodsball_btn: Button
var speedball_bunkers_root: Node3D
var woodsball_map_root: Node3D
var scoreboard_canvas: CanvasLayer
var scoreboard_body_label: Label
var death_respawn_canvas: CanvasLayer
var death_splat_flash_rect: ColorRect
var death_killer_label: Label
var death_sub_label: Label
var respawn_map_container: Control
var respawn_zone_buttons: Array[Button] = []
var center_flag_node: Node3D
var center_flag_cloth: MeshInstance3D
var center_flag_label_3d: Label3D
var breakout_horn_label: Label
var _flag_wave_time: float = 0.0
## v0.5 client presentation of Tim's server match rules (HUD, banners, spectate camera, CTF base flags).
var match_client: Node = null
var bunker_callouts: Node = null # v0.6 [F] / mouse-thumb bunker callouts
var mouse_guard: Node = null # v0.6.1 single authority for the gameplay mouse capture (CLICK TO RESUME)
var legacy_center_flag_hidden: bool = false
## Online start button pressed: menu stays up (waiting room) until notify_match_start.
var awaiting_online_start: bool = false
var online_start_requests: int = 0

func _ready() -> void:
	_build_environment_and_turf()
	_build_speedball_bunkers()
	_build_center_50_flag_station()
	_set_opfor_bots_enabled(NetworkLobby.fill_bots_enabled)
	if not NetworkLobby.is_dedicated_server:
		_spawn_player()
		_build_hud()
		_build_tournament_lobby_overlay()
		_build_scoreboard_overlay()
		_build_death_and_respawn_map_overlay()
		match_client = MatchHudClientScript.new()
		match_client.name = "MatchHudClient"
		add_child(match_client)
		match_client.call("setup", self, player)
		bunker_callouts = BunkerCalloutsScript.new()
		bunker_callouts.name = "BunkerCallouts"
		add_child(bunker_callouts)
		bunker_callouts.call("setup", self, player)
		mouse_guard = MouseCaptureGuardScript.new()
		mouse_guard.name = "MouseCaptureGuard"
		mouse_guard.call("setup", self, player)
		add_child(mouse_guard)
	GameManager.round_updated.connect(_on_round_updated)
	GameManager.round_won.connect(_on_round_won)
	GameManager.scoreboard_updated.connect(_on_scoreboard_updated)
	GameManager.match_over.connect(_on_match_over)
	IntelBus.intel_feed_updated.connect(_on_intel_feed)
	NetworkLobby.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkLobby.connection_status_changed.connect(_on_lobby_connection_status)
	NetworkLobby.match_started_signal.connect(_on_network_match_started)
	if NetworkLobby.has_signal("flag_event_received"):
		NetworkLobby.flag_event_received.connect(_on_network_flag_event)
	if NetworkLobby.has_signal("map_changed"):
		NetworkLobby.map_changed.connect(switch_arena_map)
	if NetworkLobby.selected_map == "woodsball_crash":
		switch_arena_map("woodsball_crash")
	if GameManager.has_signal("breakout_countdown_updated"):
		GameManager.breakout_countdown_updated.connect(_on_breakout_countdown_updated)
	GameManager.register_round_start(5)

func _build_environment_and_turf() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = GrittyArtThemeScript.create_overcast_stadium_environment()
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "OvercastStadiumSun"
	sun.rotation_degrees = Vector3(-54.0, -32.0, 0.0)
	sun.shadow_enabled = not OS.has_feature("web")
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

func _clear_speedball_bunkers() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is StaticBody3D:
			var cname := String(child.name)
			if cname.begins_with("Bunker_") or cname.begins_with("Home_") or cname.begins_with("OpFor_") or cname.begins_with("Snake_") or cname.begins_with("WoodSpool_"):
				if not (cname in ["OpFor_Snake50", "OpFor_SnakeCorner", "OpFor_CenterAztec", "OpFor_Dorito2", "OpFor_BackCenter"]):
					to_remove.append(child)
	for n in to_remove:
		remove_child(n)
		n.queue_free()

func switch_arena_map(map_id: String) -> void:
	var is_woods := (map_id == "woodsball_crash" or map_id == "woods" or map_id == "woodsball" or map_id == "crash_site")
	_clear_speedball_bunkers()
	if woodsball_map_root != null and is_instance_valid(woodsball_map_root):
		remove_child(woodsball_map_root)
		woodsball_map_root.queue_free()
		woodsball_map_root = null
	var props_root := get_node_or_null("GrittyStadiumProps") as Node3D
	if props_root != null:
		for c in props_root.get_children():
			if String(c.name).begins_with("WoodSpool_") and c is Node3D:
				(c as Node3D).visible = not is_woods
				for sub in c.get_children():
					if sub is CollisionShape3D:
						(sub as CollisionShape3D).disabled = is_woods
	if is_woods:
		woodsball_map_root = GrittyArtThemeScript.build_woodsball_crash_site_map(self)
		if center_flag_node != null and GameManager.flag_state == "CENTER_50":
			center_flag_node.position = Vector3(0.0, 0.0, 1.85)
	else:
		_build_speedball_bunkers()
		GrittyArtThemeScript._build_wooden_cable_spools(self)
		if center_flag_node != null and GameManager.flag_state == "CENTER_50":
			center_flag_node.position = Vector3(0.0, 0.0, 1.35)
	_refresh_lobby_button_highlights()
	if player != null and player.has_method("respawn_at_team_gate"):
		player.call("respawn_at_team_gate", NetworkLobby.local_team)

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
		if get_node_or_null(p["name"]) != null:
			continue
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
	player.connect("player_eliminated", _on_local_player_eliminated)
	if player.has_signal("respawned"):
		player.connect("respawned", _on_local_player_respawned)
	if player.has_method("respawn_at_team_gate"):
		player.call("respawn_at_team_gate", NetworkLobby.local_team)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PlaytestHUD"
	add_child(canvas)

	var crosshair := Label.new()
	crosshair.name = "SpreadCrosshair" # v0.5.0: PlayerController3D grows/fades it with the live shot spread
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

	breakout_horn_label = Label.new()
	breakout_horn_label.name = "BreakoutHornBanner"
	breakout_horn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breakout_horn_label.position = Vector2(360, 125)
	breakout_horn_label.custom_minimum_size = Vector2(880, 56)
	breakout_horn_label.add_theme_font_size_override("font_size", 28)
	breakout_horn_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.16))
	canvas.add_child(breakout_horn_label)

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

	var flag_carry_text := "  |  [!! CARRYING CENTER FLAG -> HANG AT ENEMY GATE !!]" if state.get("carrying_flag", false) else ""
	hud_label.text = (
		"BRACKET: %s%s\n" % [state["bracket_name"], flag_carry_text] +
		"HOPPER: %d / %d  |  PODS: %d (%d rnds)%s\n" % [state["hopper"], state["hopper_max"], state["pods"], state["pod_cap"], pump_text] +
		"STANCE: %s  |  SHOULDER: %s%s" % [state["stance"], state["hand"], reload_text]
	)

func _on_round_updated(round_num: int, _remaining: int, time_left: float) -> void:
	if round_label == null:
		return
	var net_tag := "ONLINE [%s]" % NetworkLobby.active_room.to_upper() if NetworkLobby.is_online_client() else ("SOLO+NPCs" if NetworkLobby.fill_bots_enabled else "PVP ONLY")
	var flag_hud_status := "AT 50"
	if GameManager.flag_state == "CARRIED":
		flag_hud_status = "CARRIED (%s)" % GameManager.flag_carrier_name
	elif GameManager.flag_state == "DROPPED":
		flag_hud_status = "DROPPED"
	round_label.text = (
		"ROUND %d  |  FLAG: %s (A:%d B:%d)  |  KILLS: %d  |  DEATHS: %d/%d  |  %.0fs  |  %s\n" % [round_num, flag_hud_status, GameManager.alpha_flag_hangs, GameManager.bravo_flag_hangs, GameManager.local_kills, GameManager.local_deaths, GameManager.MAX_DEATHS_TO_LOSE, time_left, net_tag] +
		"Move: WASD + Shift Break Out | E Peek (Active Hand, X Swap) | Q Crouch (Shift+Q Slide) | C Prone (Shift+C Dive)\n" +
		"1 Speedball (Walk LMB/RMB) | 2 Woodsball (Hold LMB+RMB) | 3 Pump (LMB->RMB)\n" +
		"Center-50 Flag Pull & Hang | R Pod Reload | F Callout Bunker | [M] Scoreboard | [TAB] Menu"
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
	if death_respawn_canvas != null and death_respawn_canvas.visible and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_5:
			_on_respawn_zone_selected(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_lobby") or event.is_action_pressed("ui_cancel"):
		_set_lobby_overlay_visible(not lobby_canvas.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_scoreboard"):
		if scoreboard_canvas != null:
			scoreboard_canvas.visible = not scoreboard_canvas.visible
			_refresh_scoreboard_text()
			_sync_mouse_capture()
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

	# Row 4.5: Arena Map Selector (Speedball Inflatable Turf vs. Woodsball Blackhawk Crash Site)
	var row_map := HBoxContainer.new()
	row_map.add_theme_constant_override("separation", 10)
	vbox.add_child(row_map)

	var lbl_map := Label.new()
	lbl_map.text = "ARENA MAP:"
	lbl_map.custom_minimum_size = Vector2(95, 0)
	row_map.add_child(lbl_map)

	map_speedball_btn = Button.new()
	map_speedball_btn.name = "MapSpeedballButton"
	map_speedball_btn.text = "MAP 1: NPPL SPEEDBALL (INFLATABLE)"
	map_speedball_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_speedball_btn.pressed.connect(func() -> void: _select_arena_map("speedball"))
	row_map.add_child(map_speedball_btn)

	map_woodsball_btn = Button.new()
	map_woodsball_btn.name = "MapWoodsballButton"
	map_woodsball_btn.text = "MAP 2: WOODSBALL HELI CRASH (TOWERS & RAMPS)"
	map_woodsball_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_woodsball_btn.pressed.connect(func() -> void: _select_arena_map("woodsball_crash"))
	row_map.add_child(map_woodsball_btn)

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

func _sync_mouse_capture() -> void:
	if mouse_guard != null and is_instance_valid(mouse_guard):
		mouse_guard.call("sync_capture")

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
	if map_speedball_btn != null and map_woodsball_btn != null:
		var is_woods := (NetworkLobby.selected_map == "woodsball_crash")
		map_speedball_btn.modulate = Color(0.35, 1.0, 0.55) if not is_woods else Color(0.72, 0.72, 0.72)
		map_woodsball_btn.modulate = Color(0.35, 1.0, 0.55) if is_woods else Color(0.72, 0.72, 0.72)

func _select_arena_map(map_id: String) -> void:
	NetworkLobby.select_map(map_id)
	var map_label := "WOODSBALL HELI CRASH (TOWERS & SPOOLS)" if NetworkLobby.selected_map == "woodsball_crash" else "NPPL SPEEDBALL STADIUM"
	_on_status_banner("ARENA MAP SELECTED: %s" % map_label, Color(0.45, 1.0, 0.60))

func _on_connect_ws_pressed() -> void:
	NetworkLobby.active_room = room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.local_callsign = callsign_input.text.strip_edges() if not callsign_input.text.strip_edges().is_empty() else NetworkLobby.local_callsign
	NetworkLobby.connect_to_lobby(server_url_input.text)
	server_url_input.text = NetworkLobby.current_ws_url

func _on_drop_in_pressed() -> void:
	var chosen_room := room_input.text.strip_edges() if not room_input.text.strip_edges().is_empty() else "alpha"
	NetworkLobby.active_room = chosen_room
	NetworkLobby.update_local_player_choices(callsign_input.text, NetworkLobby.local_team, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	if NetworkLobby.is_online_client():
		_request_online_start_via_waiting_room(chosen_room)
		return
	# Offline solo / bots: direct drop-in, as before.
	NetworkLobby.request_start_match(chosen_room, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	_set_lobby_overlay_visible(false)

## v0.5 online: the start button goes through Tim's room start (request_start_match -> 5 s match_starting/countdown ->
## notify_match_start) and Ren's waiting room instead of hiding the menu, so nobody sits in practice mode during the
## countdown. The menu stays up (player input locked) until notify_match_start drops everyone in together.
func _request_online_start_via_waiting_room(chosen_room: String) -> void:
	awaiting_online_start = true
	online_start_requests += 1
	NetworkLobby.request_start_match(chosen_room, NetworkLobby.local_bracket, fill_bots_check.button_pressed)
	var flow := get_tree().root.get_node_or_null("LobbyEntryFlow")
	if flow != null and flow.has_method("open_waiting_room"):
		flow.call("open_waiting_room", {"id": NetworkLobby.active_room, "name": NetworkLobby.active_room, "map": NetworkLobby.selected_map, "mode": NetworkLobby.selected_mode})
	_on_status_banner("MATCH START REQUESTED - Room [%s]: waiting for the countdown (everyone drops in together)" % NetworkLobby.active_room.to_upper(), Color(1.0, 0.85, 0.3))

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
	var fill_bots_val := NetworkLobby.fill_bots_enabled
	if player != null and lobby_canvas != null and lobby_canvas.visible:
		var expected_z := 45.5 if NetworkLobby.local_team == "ALPHA" else -45.5
		if absf(player.global_position.z - expected_z) > 20.0 and player.has_method("respawn_at_team_gate"):
			player.call("respawn_at_team_gate", NetworkLobby.local_team)
	if fill_bots_check != null:
		fill_bots_check.button_pressed = fill_bots_val
	_set_opfor_bots_enabled(fill_bots_val)
	_refresh_lobby_button_highlights()
	if lobby_roster_label == null:
		return
	var p_dict: Dictionary = state.get("players", {})
	var lines: Array[String] = []
	lines.append("STAGING ROSTER — ROOM [%s] (%d Human Player%s + %s):" % [
		String(state.get("room", "alpha")).to_upper(),
		p_dict.size(),
		"" if p_dict.size() == 1 else "s",
		"5 OpFor Bots" if NetworkLobby.fill_bots_enabled else "No Bots"
	])
	if NetworkLobby.is_online_client():
		lines.append("YOU: TEAM %s (%s) - auto-assigned by the server" % [NetworkLobby.team_label(NetworkLobby.local_team).to_upper(), NetworkLobby.local_team])
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
	if awaiting_online_start:
		awaiting_online_start = false
		_set_lobby_overlay_visible(false)
	# v0.6.2: a match started from the waiting room must not inherit a respawn map / spectate / stale lobby flag
	clear_gameplay_input_blocks("match_started")
	_set_opfor_bots_enabled(fill_bots)
	_refresh_lobby_button_highlights()
	_on_status_banner("MATCH LIVE — Room [%s] | Bracket: %s | Press [TAB] for Lobby" % [NetworkLobby.active_room.to_upper(), bracket_id.to_upper()], Color(0.35, 1.0, 0.55))

func _set_opfor_bots_enabled(enabled: bool) -> void:
	var bot_names := ["OpFor_Snake50", "OpFor_SnakeCorner", "OpFor_CenterAztec", "OpFor_Dorito2", "OpFor_BackCenter"]
	if enabled:
		var any_missing := false
		for bname in bot_names:
			if get_node_or_null(bname) == null:
				any_missing = true
				break
		if any_missing:
			_spawn_opfor_bots()
		for bname in bot_names:
			var b := get_node_or_null(bname) as Node3D
			if b != null and b.has_method("set_bot_enabled"):
				b.call("set_bot_enabled", true)
	else:
		for bname in bot_names:
			var b := get_node_or_null(bname) as Node3D
			if b != null:
				if b.has_method("set_bot_enabled"):
					b.call("set_bot_enabled", false)
				remove_child(b)
				b.queue_free()

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
	# v0.5 server matches (online): MatchHudClient shows the congrats + recap from match_results and the server's
	# returned_to_lobby opens the waiting room, so no offline "10 Deaths / Press [T] for Rematch" screen here.
	if match_client != null and bool(match_client.call("owns_match_end")):
		return
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


func _get_team_respawn_zones(team: String) -> Array[Dictionary]:
	var side := 1.0 if team == "ALPHA" else -1.0
	var base_yaw := 0.0 if side > 0.0 else PI
	return [
		{
			"id": "snake_corner",
			"title": "[1] SNAKE CORNER TAPE",
			"desc": "Far Left Tape Entry (X = -31m)",
			"pos": Vector3(-31.0, 0.1, 38.5 * side),
			"yaw": base_yaw,
			"map_uv": Vector2(0.14, 0.80 if side > 0.0 else 0.20)
		},
		{
			"id": "left_brick",
			"title": "[2] LEFT BACK BRICK",
			"desc": "Left-Center Bunker Pocket (X = -13m)",
			"pos": Vector3(-13.0, 0.1, 33.5 * side),
			"yaw": base_yaw,
			"map_uv": Vector2(0.33, 0.75 if side > 0.0 else 0.25)
		},
		{
			"id": "home_gate",
			"title": "[3] CENTER BREAKOUT GATE",
			"desc": "Home Stone Start Box (X = 0m)",
			"pos": Vector3(0.0, 0.1, 45.5 * side),
			"yaw": base_yaw,
			"map_uv": Vector2(0.50, 0.87 if side > 0.0 else 0.13)
		},
		{
			"id": "right_brick",
			"title": "[4] RIGHT BACK BRICK",
			"desc": "Right-Center Bunker Pocket (X = +13m)",
			"pos": Vector3(13.0, 0.1, 33.5 * side),
			"yaw": base_yaw,
			"map_uv": Vector2(0.67, 0.75 if side > 0.0 else 0.25)
		},
		{
			"id": "dorito_corner",
			"title": "[5] DORITO CORNER TAPE",
			"desc": "Far Right Dorito Highway (X = +30m)",
			"pos": Vector3(30.0, 0.1, 38.5 * side),
			"yaw": base_yaw,
			"map_uv": Vector2(0.86, 0.80 if side > 0.0 else 0.20)
		}
	]

func _build_death_and_respawn_map_overlay() -> void:
	death_respawn_canvas = CanvasLayer.new()
	death_respawn_canvas.name = "DeathRespawnMapOverlay"
	death_respawn_canvas.layer = 12
	death_respawn_canvas.visible = false
	add_child(death_respawn_canvas)

	# Full-screen goggle paint-splat shock backdrop
	death_splat_flash_rect = ColorRect.new()
	death_splat_flash_rect.name = "GoggleSplatShockBackdrop"
	death_splat_flash_rect.color = Color(0.96, 0.12, 0.52, 0.86)
	death_splat_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_respawn_canvas.add_child(death_splat_flash_rect)

	# Decorative oily neon yellow/pink goggle lens paint blobs (Gritty 2000s aesthetic)
	var blob_specs := [
		{"pos": Vector2(80, 40), "size": Vector2(420, 260), "col": Color(0.98, 0.86, 0.08, 0.42)},
		{"pos": Vector2(1050, 60), "size": Vector2(460, 290), "col": Color(0.96, 0.14, 0.56, 0.48)},
		{"pos": Vector2(140, 580), "size": Vector2(390, 240), "col": Color(0.96, 0.14, 0.56, 0.40)},
		{"pos": Vector2(1080, 560), "size": Vector2(410, 260), "col": Color(0.98, 0.86, 0.08, 0.44)}
	]
	for bspec in blob_specs:
		var blob := Panel.new()
		blob.position = bspec["pos"]
		blob.size = bspec["size"]
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bstyle := StyleBoxFlat.new()
		bstyle.bg_color = bspec["col"]
		bstyle.corner_radius_top_left = 120
		bstyle.corner_radius_top_right = 95
		bstyle.corner_radius_bottom_left = 110
		bstyle.corner_radius_bottom_right = 130
		blob.add_theme_stylebox_override("panel", bstyle)
		death_respawn_canvas.add_child(blob)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_respawn_canvas.add_child(center)

	var main_panel := PanelContainer.new()
	main_panel.name = "TacticalRespawnPanel"
	main_panel.custom_minimum_size = Vector2(860, 620)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	pstyle.border_width_left = 4
	pstyle.border_width_top = 4
	pstyle.border_width_right = 4
	pstyle.border_width_bottom = 4
	pstyle.border_color = Color(0.98, 0.84, 0.10, 1.0)
	pstyle.corner_radius_top_left = 8
	pstyle.corner_radius_top_right = 8
	pstyle.corner_radius_bottom_left = 8
	pstyle.corner_radius_bottom_right = 8
	pstyle.content_margin_left = 26
	pstyle.content_margin_right = 26
	pstyle.content_margin_top = 20
	pstyle.content_margin_bottom = 20
	main_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(main_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(vbox)

	death_killer_label = Label.new()
	death_killer_label.name = "YouveBeenHitBanner"
	death_killer_label.text = "!! YOU'VE BEEN HIT !!"
	death_killer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_killer_label.add_theme_font_size_override("font_size", 36)
	death_killer_label.add_theme_color_override("font_color", Color(0.99, 0.90, 0.12))
	vbox.add_child(death_killer_label)

	death_sub_label = Label.new()
	death_sub_label.name = "DeathSubLabel"
	death_sub_label.text = "GOGGLE LENS SPLATTED — CHOOSE YOUR RE-ENTRY DROP ZONE BELOW (OR PRESS [1]–[5])"
	death_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_sub_label.add_theme_font_size_override("font_size", 15)
	death_sub_label.add_theme_color_override("font_color", Color(0.98, 0.45, 0.72))
	vbox.add_child(death_sub_label)

	# Tactical Top-Down Speedball Arena Map Schematic
	respawn_map_container = Panel.new()
	respawn_map_container.name = "TacticalArenaMap"
	respawn_map_container.custom_minimum_size = Vector2(800, 390)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.14, 0.19, 0.13, 0.98)
	mstyle.border_width_left = 3
	mstyle.border_width_top = 3
	mstyle.border_width_right = 3
	mstyle.border_width_bottom = 3
	mstyle.border_color = Color(0.45, 0.50, 0.42)
	respawn_map_container.add_theme_stylebox_override("panel", mstyle)
	vbox.add_child(respawn_map_container)

	# 50-Yard Center Line on Tactical Map
	var center_line := ColorRect.new()
	center_line.color = Color(0.85, 0.82, 0.70, 0.55)
	center_line.position = Vector2(10, 193)
	center_line.size = Vector2(780, 4)
	center_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_map_container.add_child(center_line)

	var lbl_north := Label.new()
	lbl_north.text = "NORTH END — TEAM BRAVO (-Z)   |   SNAKE SIDE (LEFT)   <--- 50 YD LINE --->   DORITO SIDE (RIGHT)"
	lbl_north.position = Vector2(18, 10)
	lbl_north.add_theme_font_size_override("font_size", 13)
	lbl_north.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 0.9))
	respawn_map_container.add_child(lbl_north)

	var lbl_south := Label.new()
	lbl_south.text = "SOUTH END — TEAM ALPHA (+Z)   |   CLICK ANY HIGHLIGHTED SPAWN ZONE OR PRESS KEYS [1] - [5]"
	lbl_south.position = Vector2(18, 362)
	lbl_south.add_theme_font_size_override("font_size", 13)
	lbl_south.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0, 0.9))
	respawn_map_container.add_child(lbl_south)

	# Visual schematic bunker blocks on the tactical map
	var map_bunkers := [
		Vector2(385, 182), Vector2(280, 184), Vector2(490, 184),
		Vector2(95, 130), Vector2(95, 235), Vector2(685, 130), Vector2(685, 235),
		Vector2(385, 110), Vector2(385, 255), Vector2(240, 115), Vector2(530, 115),
		Vector2(240, 250), Vector2(530, 250)
	]
	for bpos in map_bunkers:
		var brect := ColorRect.new()
		brect.size = Vector2(28, 16)
		brect.position = bpos
		brect.color = Color(0.84, 0.70, 0.16, 0.45)
		brect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		respawn_map_container.add_child(brect)

	respawn_zone_buttons.clear()
	for i in range(5):
		var btn := Button.new()
		btn.name = "RespawnZoneBtn_%d" % i
		btn.custom_minimum_size = Vector2(148, 54)
		var bstyle := StyleBoxFlat.new()
		bstyle.bg_color = Color(0.12, 0.34, 0.22, 0.96)
		bstyle.border_width_left = 2
		bstyle.border_width_top = 2
		bstyle.border_width_right = 2
		bstyle.border_width_bottom = 2
		bstyle.border_color = Color(0.35, 1.0, 0.55)
		bstyle.corner_radius_top_left = 6
		bstyle.corner_radius_top_right = 6
		bstyle.corner_radius_bottom_left = 6
		bstyle.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", bstyle)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color(0.95, 1.0, 0.95))
		var zone_idx := i
		btn.pressed.connect(func() -> void: _on_respawn_zone_selected(zone_idx))
		respawn_map_container.add_child(btn)
		respawn_zone_buttons.append(btn)

	# Quick bottom bar of 5 spawn buttons as well for fast clicking
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	vbox.add_child(quick_row)
	var quick_labels := ["[1] SNAKE CORNER", "[2] LEFT BRICK", "[3] CENTER GATE", "[4] RIGHT BRICK", "[5] DORITO CORNER"]
	for i in range(5):
		var qbtn := Button.new()
		qbtn.text = quick_labels[i]
		qbtn.custom_minimum_size = Vector2(0, 42)
		qbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qbtn.add_theme_font_size_override("font_size", 14)
		qbtn.add_theme_color_override("font_color", Color(0.98, 0.90, 0.20))
		var z_idx := i
		qbtn.pressed.connect(func() -> void: _on_respawn_zone_selected(z_idx))
		quick_row.add_child(qbtn)

func _on_local_player_eliminated(killer_name: String) -> void:
	# v0.5 one-life CTF: no respawn map - the MatchHudClient spectate camera takes over until round_started.
	if player != null and bool(player.get("spectating")):
		return
	if NetworkLobby.is_dedicated_server or DisplayServer.get_name() == "headless":
		return
	if GameManager.match_ended or death_respawn_canvas == null:
		return
	if lobby_canvas != null and lobby_canvas.visible:
		_set_lobby_overlay_visible(false)

	player.set("awaiting_respawn_choice", true)

	var zones := _get_team_respawn_zones(NetworkLobby.local_team)
	for i in range(min(zones.size(), respawn_zone_buttons.size())):
		var z: Dictionary = zones[i]
		var btn: Button = respawn_zone_buttons[i]
		btn.text = "%s\n%s" % [z["title"], z["desc"]]
		var uv: Vector2 = z["map_uv"]
		btn.position = Vector2(uv.x * 800.0 - 74.0, uv.y * 390.0 - 27.0)

	death_killer_label.text = "!! YOU'VE BEEN HIT BY %s !!" % killer_name.to_upper()
	death_sub_label.text = "TEAM %s — PODS REFILLED & 2.8s SPAWN PROTECTION READY! CLICK A MAP ZONE OR PRESS [1]–[5] (DEATHS: %d / %d)" % [
		NetworkLobby.local_team,
		GameManager.local_deaths,
		GameManager.MAX_DEATHS_TO_LOSE
	]
	death_splat_flash_rect.color = Color(0.98, 0.14, 0.56, 0.94)
	death_respawn_canvas.visible = true
	_sync_mouse_capture()

	# Jump-scare goggle paint-splat flash that settles into the tactical map background
	var tw := create_tween()
	tw.tween_property(death_splat_flash_rect, "color", Color(0.14, 0.04, 0.09, 0.84), 0.48)

## v0.6.2: any respawn (map pick, server team-gate reset on round_started, starting spot) drops the respawn map, so it
## can never stay up over a live round with awaiting_respawn_choice already cleared.
func _on_local_player_respawned(_zone_label: String = "") -> void:
	if death_respawn_canvas != null and death_respawn_canvas.visible:
		death_respawn_canvas.visible = false

## v0.6.2: clears every player input block that is not backed by a menu on screen (respawn map, spectate, stale
## lobby_open) and re-syncs the mouse. Called on round_started, returned_to_lobby and network match start.
func clear_gameplay_input_blocks(reason: String = "") -> void:
	_on_local_player_respawned()
	if player != null and is_instance_valid(player) and player.has_method("clear_input_blocks"):
		player.call("clear_input_blocks", reason)

func _on_respawn_zone_selected(zone_index: int) -> void:
	var zones := _get_team_respawn_zones(NetworkLobby.local_team)
	if zone_index < 0 or zone_index >= zones.size():
		zone_index = 2
	var chosen: Dictionary = zones[zone_index]
	if death_respawn_canvas != null:
		death_respawn_canvas.visible = false
	if player != null and player.has_method("respawn_at_map_zone"):
		player.call("respawn_at_map_zone", chosen["pos"], chosen["yaw"], chosen["title"])

func _build_center_50_flag_station() -> void:
	center_flag_node = Node3D.new()
	center_flag_node.name = "Center50FlagStation"
	center_flag_node.position = Vector3(0.0, 0.0, 1.35)
	add_child(center_flag_node)

	var base_mesh := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 0.42
	base_cyl.bottom_radius = 0.50
	base_cyl.height = 0.08
	base_mesh.mesh = base_cyl
	base_mesh.position = Vector3(0, 0.04, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.18, 0.19, 0.21)
	bmat.roughness = 0.7
	base_mesh.material_override = bmat
	center_flag_node.add_child(base_mesh)

	var pole_mesh := MeshInstance3D.new()
	var pole_cyl := CylinderMesh.new()
	pole_cyl.top_radius = 0.032
	pole_cyl.bottom_radius = 0.038
	pole_cyl.height = 2.65
	pole_mesh.mesh = pole_cyl
	pole_mesh.position = Vector3(0, 1.325, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.88, 0.90, 0.94)
	pmat.metallic = 0.65
	pmat.roughness = 0.25
	pole_mesh.material_override = pmat
	center_flag_node.add_child(pole_mesh)

	center_flag_cloth = MeshInstance3D.new()
	center_flag_cloth.name = "FlagBannerCloth"
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.95, 0.58, 0.035)
	center_flag_cloth.mesh = fbox
	center_flag_cloth.position = Vector3(0.48, 2.25, 0.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.80, 0.06)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.68, 0.04)
	fmat.emission_energy_multiplier = 0.65
	fmat.roughness = 0.42
	center_flag_cloth.material_override = fmat
	center_flag_node.add_child(center_flag_cloth)

	center_flag_label_3d = Label3D.new()
	center_flag_label_3d.name = "CenterFlagLabel3D"
	center_flag_label_3d.text = "[CENTER-50 FLAG — SPRINT THROUGH TO PULL]"
	center_flag_label_3d.font_size = 44
	center_flag_label_3d.pixel_size = 0.005
	center_flag_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	center_flag_label_3d.position = Vector3(0, 2.95, 0)
	center_flag_label_3d.modulate = Color(1.0, 0.92, 0.18)
	center_flag_node.add_child(center_flag_label_3d)

func _process(delta: float) -> void:
	if NetworkLobby.is_dedicated_server:
		return
	_flag_wave_time += delta
	_apply_legacy_center_flag_policy()
	if center_flag_cloth != null and center_flag_node != null and center_flag_node.visible:
		center_flag_cloth.rotation.y = sin(_flag_wave_time * 4.5) * 0.18
	if not legacy_center_flag_hidden:
		_update_center_flag_pickup_and_hang()

## Used by PlayerController3D: a live one-life CTF round (server state via the MatchHudClient) means no local respawn.
func is_one_life_round_live() -> bool:
	return match_client != null and bool(match_client.call("is_one_life_round_live"))

## v0.5: the legacy single Center-50 flag (and its local pickup/hang) only exists in offline non-CTF play. In CTF and
## on every online client it is hidden and inert; CTF shows one server-driven flag per base (MatchHudClient).
func _apply_legacy_center_flag_policy() -> void:
	var enabled := match_client == null or bool(match_client.call("legacy_center_flag_enabled"))
	if enabled == (not legacy_center_flag_hidden):
		return
	legacy_center_flag_hidden = not enabled
	if center_flag_node != null:
		center_flag_node.visible = enabled and GameManager.flag_state != "CARRIED"
	if not enabled and player != null and bool(player.get("carrying_center_flag")):
		player.call("set_carrying_center_flag", false)

func _update_center_flag_pickup_and_hang() -> void:
	if player == null or GameManager.match_ended:
		return
	if bool(player.get("awaiting_respawn_choice")) or bool(player.get("lobby_open")):
		return
	var p_pos: Vector3 = player.global_position
	var is_carrying: bool = bool(player.get("carrying_center_flag"))

	if not is_carrying and center_flag_node != null and center_flag_node.visible and GameManager.flag_state != "CARRIED":
		var f_pos: Vector3 = center_flag_node.global_position
		if Vector2(p_pos.x - f_pos.x, p_pos.z - f_pos.z).length() <= 2.35:
			pickup_center_flag_for_local_player()
	elif is_carrying:
		var enemy_gate_z: float = -45.5 if NetworkLobby.local_team == "ALPHA" else 45.5
		var enemy_gate_pos := Vector3(0.0, 0.1, enemy_gate_z)
		if Vector2(p_pos.x - enemy_gate_pos.x, p_pos.z - enemy_gate_pos.z).length() <= 4.2:
			hang_center_flag_for_local_player()

func pickup_center_flag_for_local_player() -> void:
	if player == null:
		return
	player.call("set_carrying_center_flag", true)
	if center_flag_node != null:
		center_flag_node.visible = false
	GameManager.notify_flag_picked_up(NetworkLobby.local_callsign, NetworkLobby.local_team, player.global_position)
	_on_status_banner("FLAG PULLED BY %s! Sprint to Enemy Breakout Gate (%s End) to HANG IT!" % [
		NetworkLobby.local_callsign.to_upper(),
		"NORTH -Z" if NetworkLobby.local_team == "ALPHA" else "SOUTH +Z"
	], Color(1.0, 0.88, 0.14))
	IntelBus.intel_feed_updated.emit("CENTER-50 FLAG PULLED BY %s (%s)!" % [NetworkLobby.local_callsign, NetworkLobby.local_team])
	NetworkLobby.broadcast_flag_event("PICKUP", NetworkLobby.local_callsign, NetworkLobby.local_team, player.global_position)

func drop_center_flag_at(drop_pos: Vector3, carrier_name: String) -> void:
	var clamped_drop := Vector3(clampf(drop_pos.x, -48.0, 48.0), 0.0, clampf(drop_pos.z, -44.0, 44.0))
	if center_flag_node != null:
		center_flag_node.global_position = clamped_drop
		center_flag_node.visible = true
	if center_flag_label_3d != null:
		center_flag_label_3d.text = "[DROPPED FLAG — SPRINT THROUGH TO RECOVER]"
	GameManager.notify_flag_dropped(clamped_drop, carrier_name)
	_on_status_banner("FLAG DROPPED BY %s AT (%.0fm, %.0fm)!" % [carrier_name.to_upper(), clamped_drop.x, clamped_drop.z], Color(1.0, 0.52, 0.18))
	IntelBus.intel_feed_updated.emit("FLAG DROPPED @ (%.0fm, %.0fm)!" % [clamped_drop.x, clamped_drop.z])
	NetworkLobby.broadcast_flag_event("DROP", carrier_name, NetworkLobby.local_team, clamped_drop)

func hang_center_flag_for_local_player() -> void:
	if player == null:
		return
	player.call("set_carrying_center_flag", false)
	player.call("award_kill_bonus_pod", "Center-50 Flag Hang (+2 Bonus Pods)")
	player.call("award_kill_bonus_pod", "Center-50 Flag Hang")
	if center_flag_node != null:
		center_flag_node.global_position = Vector3(0.0, 0.0, 1.35)
		center_flag_node.visible = true
	if center_flag_label_3d != null:
		center_flag_label_3d.text = "[CENTER-50 FLAG — SPRINT THROUGH TO PULL]"
	GameManager.notify_flag_hung(NetworkLobby.local_callsign, NetworkLobby.local_team)
	_on_status_banner("FLAG HUNG BY %s (%s)! ROUND POINT SCORED (+2 PODS & -3 TEAM DEATHS)!" % [
		NetworkLobby.local_callsign.to_upper(),
		NetworkLobby.local_team
	], Color(0.28, 1.0, 0.48))
	IntelBus.intel_feed_updated.emit("FLAG HUNG ON ENEMY GATE BY %s (%s)!" % [NetworkLobby.local_callsign, NetworkLobby.local_team])
	NetworkLobby.broadcast_flag_event("HANG", NetworkLobby.local_callsign, NetworkLobby.local_team, Vector3(0.0, 0.0, 1.35))

func _on_network_flag_event(event_type: String, p_name: String, team: String, world_pos: Vector3) -> void:
	if p_name == NetworkLobby.local_callsign or legacy_center_flag_hidden:
		return
	if event_type == "PICKUP":
		if center_flag_node != null:
			center_flag_node.visible = false
		GameManager.notify_flag_picked_up(p_name, team, world_pos)
		_on_status_banner("ALERT: %s (%s) PULLED THE CENTER-50 FLAG!" % [p_name.to_upper(), team], Color(1.0, 0.65, 0.16))
	elif event_type == "DROP":
		if center_flag_node != null:
			center_flag_node.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
			center_flag_node.visible = true
		if center_flag_label_3d != null:
			center_flag_label_3d.text = "[DROPPED FLAG — SPRINT THROUGH TO RECOVER]"
		GameManager.notify_flag_dropped(world_pos, p_name)
		_on_status_banner("FLAG DROPPED BY %s AT (%.0fm, %.0fm)!" % [p_name.to_upper(), world_pos.x, world_pos.z], Color(1.0, 0.85, 0.22))
	elif event_type == "HANG":
		if center_flag_node != null:
			center_flag_node.global_position = Vector3(0.0, 0.0, 1.35)
			center_flag_node.visible = true
		if center_flag_label_3d != null:
			center_flag_label_3d.text = "[CENTER-50 FLAG — SPRINT THROUGH TO PULL]"
		GameManager.notify_flag_hung(p_name, team)
		_on_status_banner("FLAG HUNG BY %s (%s)! Flag Reset to Center-50!" % [p_name.to_upper(), team], Color(1.0, 0.42, 0.42))

func _on_breakout_countdown_updated(seconds_left: float, horn_sounded: bool) -> void:
	if breakout_horn_label == null:
		return
	if not horn_sounded:
		breakout_horn_label.visible = true
		breakout_horn_label.text = "BARRELS ON THE GATE NET — BREAKOUT IN %.1fs..." % seconds_left
		breakout_horn_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.16))
	else:
		breakout_horn_label.text = "!! HORN SOUNDED — BREAKOUT !! GO GET THE CENTER-50 FLAG !!"
		breakout_horn_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.52))
		var tw := create_tween()
		tw.tween_interval(2.2)
		tw.tween_callback(func() -> void:
			if breakout_horn_label != null:
				breakout_horn_label.visible = false
		)
