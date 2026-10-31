extends Node3D

## Full-scale 3x Speedball Arena (108m x 132m) for v0.2 Gritty 2000s Tournament Art Overhaul.
## Features overcast stadium lighting, floodlight towers, perimeter black safety netting,
## tournament scoreboard backdrop, muddy turf with slick puddles, scuffed vinyl inflatable bunkers,
## stacked wooden cable spools, and 5 OpFor bots.

const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")
const MatchHudClientScript = preload("res://scripts/ui/match_hud_client.gd")
const BunkerCalloutsScript = preload("res://scripts/systems/bunker_callouts.gd")
const MouseCaptureGuardScript = preload("res://scripts/systems/mouse_capture_guard.gd")
const BuildStampScript = preload("res://scripts/systems/build_stamp.gd")
const SoloFfaMatchScript = preload("res://scripts/bots/solo_ffa_match.gd")

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
## v0.6.3: Ren's RespawnScreen ("SPLATTED by X" + full-field map, 5 numbered spots, click or 1-5). Kept under the
## old name so MouseCaptureGuard / tests that read death_respawn_canvas.visible still work.
var death_respawn_canvas: CanvasLayer
var center_flag_node: Node3D
var center_flag_cloth: MeshInstance3D
var center_flag_label_3d: Label3D
var breakout_horn_label: Label
var _flag_wave_time: float = 0.0
## v0.5 client presentation of Tim's server match rules (HUD, banners, spectate camera, CTF base flags).
var match_client: Node = null
var bunker_callouts: Node = null # v0.6 [F] / mouse-thumb bunker callouts
## v0.7 solo FFA deathmatch vs BotPlayers (offline). null = not running.
var ffa_match: Node = null
var ffa_tier: String = "amateur"
var ffa_tier_btn: Button = null
var _ffa_zones: Array[Dictionary] = []
## Survives [T] rematch (scene reload) so a rematch restarts the same FFA setup; cleared by any other start.
static var ffa_rematch_opts: Dictionary = {}
var build_stamp: CanvasLayer = null # v0.6.3 "v0.6.3 · <commit>" corner label (HUD + lobby)
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
		build_stamp = BuildStampScript.new()
		add_child(build_stamp)
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
	if not NetworkLobby.is_dedicated_server:
		var url_opts := _ffa_opts_from_url()
		if not url_opts.is_empty():
			_start_ffa_when_lobby_ready.call_deferred(url_opts)
		elif not ffa_rematch_opts.is_empty():
			start_solo_ffa.call_deferred(ffa_rematch_opts)

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
				if not ("bot_name" in child): # practice bots are Bot_* now; never mistake one for a bunker
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

## v0.6.3: practice bot node names. They used to be OpFor_<stem>, but the speedball bunkers OpFor_CenterAztec and
## OpFor_BackCenter already held two of those names, so get_node_or_null() found the bunker, the bot was skipped (only 3
## of 5 spawned) and turning bots off deleted those two bunkers. The Bot_ prefix keeps bot and bunker names apart.
const OPFOR_BOT_NAMES := ["Bot_Snake50", "Bot_SnakeCorner", "Bot_CenterAztec", "Bot_Dorito2", "Bot_BackCenter"]

## The practice bot called bname, or null (a bunker or anything else with that name never counts).
func get_opfor_bot(bname: String) -> Node3D:
	var n := get_node_or_null(bname)
	if n is Node3D and "bot_name" in n and not n.is_queued_for_deletion():
		return n as Node3D
	return null

## Every practice bot currently in the arena.
func get_opfor_bots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for bname in OPFOR_BOT_NAMES:
		var b := get_opfor_bot(bname)
		if b != null:
			out.append(b)
	return out

func _spawn_opfor_bots() -> void:
	var bot_script := load("res://scripts/systems/snap_target_bot.gd")

	var placements := [
		{"name": "Bot_Snake50", "label": "OpFor Snake-1", "pos": Vector3(-35.0, 0.0, -11.5), "peek": Vector3(1.3, 0.0, 0.0)},
		{"name": "Bot_SnakeCorner", "label": "OpFor Snake-Corner", "pos": Vector3(-28.5, 0.0, -25.8), "peek": Vector3(1.25, 0.0, 0.0)},
		{"name": "Bot_CenterAztec", "label": "OpFor Center-Aztec", "pos": Vector3(0.0, 0.0, -20.2), "peek": Vector3(1.55, 0.0, 0.0)},
		{"name": "Bot_Dorito2", "label": "OpFor Dorito-2", "pos": Vector3(36.5, 0.0, -12.8), "peek": Vector3(-1.4, 0.0, 0.0)},
		{"name": "Bot_BackCenter", "label": "OpFor Back-Center", "pos": Vector3(0.0, 0.0, -39.2), "peek": Vector3(1.6, 0.0, 0.0)}
	]

	for p in placements:
		if get_opfor_bot(p["name"]) != null:
			continue
		var stale := get_node_or_null(p["name"]) # a bot freed this frame still holds the name: release it first
		if stale != null:
			remove_child(stale)
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
	if ffa_match != null:
		round_label.text = ffa_round_text(ffa_match.call("standings"), int(ffa_match.get("kills_to_win")), time_left)
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

## v0.7 Solo FFA HUD line (no flag / death-limit text): your eliminations, the leader, first to N.
static func ffa_round_text(rows: Array, kills_to_win: int, time_left: float) -> String:
	var mine := 0
	var leader := "-"
	var lead_kills := 0
	for r in rows:
		if bool(r.get("is_player", false)):
			mine = int(r.get("kills", 0))
	if not rows.is_empty():
		lead_kills = int(rows[0].get("kills", 0))
		leader = "YOU" if bool(rows[0].get("is_player", false)) else String(rows[0].get("name", "-"))
	return (
		"SOLO FFA DEATHMATCH  |  YOUR ELIMS: %d  |  LEADER: %s (%d)  |  FIRST TO %d  |  %.0fs\n" % [mine, leader, lead_kills, kills_to_win, time_left] +
		"Move: WASD + Shift Break Out | E Peek (Active Hand, X Swap) | Q Crouch (Shift+Q Slide) | C Prone (Shift+C Dive)\n" +
		"1 Speedball (Walk LMB/RMB) | 2 Woodsball (Hold LMB+RMB) | 3 Pump (LMB->RMB)\n" +
		"R Pod Reload | F Callout Bunker | [M] Scoreboard | [TAB] Menu"
	)

func _on_ffa_standings_changed(_rows: Array) -> void:
	_refresh_scoreboard_text()
	_refresh_ffa_round_label()

func _refresh_ffa_round_label() -> void:
	if ffa_match != null and round_label != null:
		round_label.text = ffa_round_text(ffa_match.call("standings"), int(ffa_match.get("kills_to_win")), GameManager.round_time_left)

func _on_status_banner(msg: String, color: Color) -> void:
	if ffa_match != null and msg.contains("Go Get Center Flag"):
		msg = msg.replace(" — Go Get Center Flag!", "")
	if status_label:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)

func _on_intel_feed(msg: String) -> void:
	if intel_label:
		intel_label.text = msg

func _unhandled_input(event: InputEvent) -> void:
	if NetworkLobby.is_dedicated_server or lobby_canvas == null:
		return
	# v0.6.3: 1-5 on the respawn map are read by RespawnScreen itself (mirrored for BRAVO).
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

	# v0.7 solo FFA deathmatch vs BotPlayers (offline): first to 10 eliminations, everyone for themselves.
	var row_ffa := HBoxContainer.new()
	row_ffa.add_theme_constant_override("separation", 14)
	vbox.add_child(row_ffa)
	var ffa_btn := Button.new()
	ffa_btn.name = "SoloFfaButton"
	ffa_btn.text = "SOLO FFA DEATHMATCH (%d BOTS, FIRST TO %d)" % [SoloFfaMatchScript.DEFAULT_BOTS, SoloFfaMatchScript.KILLS_TO_WIN]
	ffa_btn.custom_minimum_size = Vector2(0, 40)
	ffa_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ffa_btn.add_theme_font_size_override("font_size", 16)
	ffa_btn.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	ffa_btn.pressed.connect(func(): start_solo_ffa({"bots": SoloFfaMatchScript.DEFAULT_BOTS, "tier": ffa_tier}))
	row_ffa.add_child(ffa_btn)
	ffa_tier_btn = Button.new()
	ffa_tier_btn.name = "SoloFfaTierButton"
	ffa_tier_btn.custom_minimum_size = Vector2(210, 40)
	ffa_tier_btn.add_theme_font_size_override("font_size", 15)
	ffa_tier_btn.pressed.connect(_cycle_ffa_tier)
	row_ffa.add_child(ffa_tier_btn)
	_cycle_ffa_tier(false)

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
	stop_solo_ffa()
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
	if enabled:
		if get_opfor_bots().size() < OPFOR_BOT_NAMES.size():
			_spawn_opfor_bots()
		for b in get_opfor_bots():
			if b.has_method("set_bot_enabled"):
				b.call("set_bot_enabled", true)
	else:
		for b in get_opfor_bots():
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
	_close_respawn_screen_for_match_end()
	# v0.5 server matches (online): MatchHudClient shows the congrats + recap from match_results and the server's
	# returned_to_lobby opens the waiting room, so no offline "10 Deaths / Press [T] for Rematch" screen here.
	if match_client != null and bool(match_client.call("owns_match_end")):
		return
	if scoreboard_canvas != null:
		scoreboard_canvas.visible = true
	_refresh_scoreboard_text()
	if ffa_match != null:
		_on_status_banner("FFA OVER! %s WINS (first to %d) — Press [T] for Rematch" % [String(ffa_match.get("winner")), int(ffa_match.get("kills_to_win"))], Color(1.0, 0.88, 0.22))
		return
	_on_status_banner("MATCH OVER! %s hit 10 Deaths — %s WINS! Press [T] for Rematch" % [loser_name, winner_label], Color(1.0, 0.88, 0.22))

func _refresh_scoreboard_text() -> void:
	if scoreboard_body_label == null:
		return
	var lines: Array[String] = []
	if ffa_match != null:
		lines.append_array(ffa_match.call("scoreboard_lines"))
		lines.append("----------------------------------------------------------------------")
		if GameManager.match_ended:
			lines.append(">> FFA OVER — %s WINS — PRESS [T] FOR A REMATCH <<" % String(ffa_match.get("winner")))
		else:
			lines.append("Press [M] to Close Scoreboard   |   Press [TAB] for the Menu")
		scoreboard_body_label.text = "\n".join(lines)
		return
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
	var rs := RespawnScreen.new()
	death_respawn_canvas = rs
	add_child(rs)
	rs.zone_picked.connect(_on_respawn_zone_selected)
	if not NetworkLobby.room_event.is_connected(_on_room_event_close_respawn):
		NetworkLobby.room_event.connect(_on_room_event_close_respawn)

func _on_local_player_eliminated(killer_name: String) -> void:
	# v0.5 one-life CTF: no respawn map - the MatchHudClient spectate camera takes over until round_started.
	if player != null and bool(player.get("spectating")):
		return
	if NetworkLobby.is_dedicated_server or DisplayServer.get_name() == "headless":
		return
	_open_respawn_screen(killer_name)

## Opens Ren's RespawnScreen for the local team (split out of _on_local_player_eliminated so headless tests and the
## screenshot tool drive the exact same path; the headless guard above stays in the signal handler).
func _open_respawn_screen(killer_name: String) -> void:
	if GameManager.match_ended or death_respawn_canvas == null:
		return
	if lobby_canvas != null and lobby_canvas.visible:
		_set_lobby_overlay_visible(false)
	player.set("awaiting_respawn_choice", true)
	var team := NetworkLobby.local_team
	var shooter_pos: Vector3 = RespawnScreen.NO_POS
	var death_pos: Vector3 = RespawnScreen.NO_POS
	if player != null and is_instance_valid(player):
		death_pos = player.get("last_death_position")
		if bool(player.get("has_last_shooter_position")):
			shooter_pos = player.get("last_shooter_position")
	death_respawn_canvas.call("open", killer_name, team, _respawn_zones_for_local(true),
		GameManager.local_deaths, GameManager.MAX_DEATHS_TO_LOSE, shooter_pos, death_pos)
	_refresh_respawn_map_dots()
	_sync_mouse_capture()

## --- v0.6.3 respawn minimap player dots (Tyler/Tim rule) -------------------------------------------------------------
## Team modes: everyone alive (teammate or enemy) standing on YOUR half - ALPHA half z > 0, BRAVO half z < 0, midfield
## z = 0 - is shown; the enemy half is never shown. Deathmatch has no sides: no dots at all (open() already gets the
## shooter + your death spot). Refreshed every RESPAWN_DOTS_INTERVAL while the screen is up.
## respawn_map_dots holds the latest list [{"team": "ALPHA"|"BRAVO", "pos": Vector3 (world), "name": String,
## "teammate": bool}] and goes to RespawnScreen.set_players() on open and on every refresh (the screen filters to your
## half again itself; deathmatch always sends []).
const RESPAWN_DOTS_INTERVAL := 0.25
var respawn_map_dots: Array = []
var respawn_map_show_all: bool = false # the show_all flag of the last set_players(dots, show_all) call (true in bot matches)
var _respawn_dots_timer: float = 0.0

static func is_on_team_half(team: String, world_pos: Vector3) -> bool:
	return world_pos.z > 0.0 if team == "ALPHA" else world_pos.z < 0.0

## Pure filter (tested): candidates [{team, pos, ...}] -> only those on my_team's half; [] in deathmatch.
static func filter_dots_to_half(candidates: Array, my_team: String, match_mode: String) -> Array:
	var out: Array = []
	if match_mode == "deathmatch":
		return out
	for c in candidates:
		if c is Dictionary and (c as Dictionary).has("pos") and is_on_team_half(my_team, (c as Dictionary)["pos"]):
			out.append(c)
	return out

## Match mode for the dots rule: the server's mode online (MatchHudClient, else the lobby's selected mode);
## offline solo vs the OpFor bots is a two-sided practice game.
var respawn_map_mode_override: String = "" # tests / preview renders only

func respawn_map_mode() -> String:
	if not respawn_map_mode_override.is_empty():
		return respawn_map_mode_override
	if ffa_match != null:
		return "deathmatch"
	if not NetworkLobby.is_online_client():
		return "practice"
	var m := String(match_client.get("mode")) if match_client != null else ""
	return m if not m.is_empty() else String(NetworkLobby.selected_mode)

## Live players from the client snapshots: remote avatars (NetworkLobby.players team/name/alive + the avatar's
## interpolated position, falling back to players[pid].state.pos) online, plus every live local bot (practice OpFor bots,
## fill-bots, Solo FFA bots) tagged "bot": true. Excludes me.
func respawn_map_candidates() -> Array:
	var me := NetworkLobby.local_team
	var out: Array = []
	if NetworkLobby.is_online_client():
		var my_id := multiplayer.get_unique_id()
		for pid in NetworkLobby.players.keys():
			if int(pid) == my_id:
				continue
			var info: Dictionary = NetworkLobby.players[pid]
			if not bool(info.get("alive", true)):
				continue
			var pos: Variant = null
			var n: Variant = NetworkLobby.remote_player_nodes.get(pid, null)
			if n is Node3D and is_instance_valid(n):
				pos = (n as Node3D).global_position
			elif info.get("state", {}) is Dictionary and (info.get("state", {}) as Dictionary).has("pos"):
				pos = info["state"]["pos"]
			if pos is Vector3:
				var t := String(info.get("team", "ALPHA"))
				out.append({"team": t, "pos": pos, "name": String(info.get("name", "")), "teammate": t == me})
	out.append_array(respawn_map_bot_candidates())
	return out

## v0.7 (Tyler): every live local bot - practice OpFor bots, fill-bots online and the Solo FFA bots. Practice / fill
## bots fight for the other side; FFA bots have team "FFA" (never a teammate).
func respawn_map_bot_candidates() -> Array:
	var me := NetworkLobby.local_team
	var enemy := "BRAVO" if me == "ALPHA" else "ALPHA"
	var out: Array = []
	for c in get_children():
		if c is Node3D and "bot_name" in c and not bool(c.get("is_eliminated")) and (c as Node3D).visible:
			var t := enemy
			if "ffa" in c and bool(c.get("ffa")):
				t = "FFA"
			elif "team" in c and String(c.get("team")) in ["ALPHA", "BRAVO"]:
				t = String(c.get("team"))
			out.append({"team": t, "pos": (c as Node3D).global_position, "name": String(c.get("bot_name")), "teammate": t == me, "bot": true})
	return out

## A match with bots in it: Solo FFA, the offline practice range, an online bots_test room or fill-bots with live bots.
func is_bot_match() -> bool:
	if ffa_match != null:
		return true
	if not NetworkLobby.is_online_client():
		return true # offline is always you vs the practice / FFA bots
	var m := respawn_map_mode()
	if m == "bots_test":
		return true
	return NetworkLobby.fill_bots_enabled and not respawn_map_bot_candidates().is_empty()

## v0.7 respawn minimap (Tyler): in any bot match every live bot is shown wherever it stands (deathmatch / FFA
## included); humans keep the v0.6.3 rule (your half only, none in deathmatch). Pure (tested).
static func respawn_dots_for(candidates: Array, my_team: String, match_mode: String, bot_match: bool) -> Array:
	var humans: Array = []
	var bots: Array = []
	for c in candidates:
		if c is Dictionary and bool((c as Dictionary).get("bot", false)):
			bots.append(c)
		else:
			humans.append(c)
	var out := filter_dots_to_half(humans, my_team, match_mode)
	if bot_match:
		out.append_array(bots.filter(func(d) -> bool: return (d as Dictionary).has("pos")))
	else:
		out.append_array(filter_dots_to_half(bots, my_team, match_mode))
	return out

func _refresh_respawn_map_dots() -> void:
	_respawn_dots_timer = RESPAWN_DOTS_INTERVAL
	var bot_match := is_bot_match()
	respawn_map_dots = respawn_dots_for(respawn_map_candidates(), NetworkLobby.local_team, respawn_map_mode(), bot_match)
	# Ren's RespawnScreen.set_players(dots, show_all): show_all in a bot match draws every dot anywhere (bots in orange);
	# humans were already filtered to your half above, so the screen's own-half filter is only skipped for bot matches.
	if death_respawn_canvas != null and death_respawn_canvas.has_method("set_players"):
		respawn_map_show_all = bot_match
		death_respawn_canvas.call("set_players", respawn_map_dots, bot_match)

func _process_respawn_map_dots(delta: float) -> void:
	if death_respawn_canvas == null or not death_respawn_canvas.visible:
		return
	_respawn_dots_timer -= delta
	if _respawn_dots_timer <= 0.0:
		_refresh_respawn_map_dots()

## v0.6.3: a match ending while you sit on the respawn map closes it (the recap / waiting room takes over).
func _on_room_event_close_respawn(event_name: String, _data: Variant = {}) -> void:
	if event_name == "match_ended":
		_close_respawn_screen_for_match_end()

func _close_respawn_screen_for_match_end() -> void:
	if death_respawn_canvas != null and death_respawn_canvas.visible:
		death_respawn_canvas.visible = false
		if player != null and is_instance_valid(player) and player.has_method("clear_input_blocks"):
			player.call("clear_input_blocks", "match_ended")

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
	var zones := _respawn_zones_for_local(false)
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
	_process_respawn_map_dots(delta)
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


## ===== v0.7 solo FFA deathmatch vs BotPlayers (Bluey) ===============================================================
## Respawn choices: team zones normally; in FFA the 5 spawn spots farthest from the live bots (fixed when the map opens).
func _respawn_zones_for_local(refresh: bool) -> Array[Dictionary]:
	if ffa_match == null:
		return _get_team_respawn_zones(NetworkLobby.local_team)
	if refresh or _ffa_zones.is_empty():
		_ffa_zones = []
		var i := 1
		for z in ffa_match.call("player_respawn_zones"):
			var d: Dictionary = z
			var p: Vector3 = d["pos"]
			d["id"] = "ffa_%d" % i
			d["title"] = "[%d] %s" % [i, String(d["title"]).to_upper()]
			d["map_uv"] = Vector2(clampf(0.5 + p.x / 84.7, 0.03, 0.97), clampf(0.5 + p.z / 100.0, 0.03, 0.97))
			_ffa_zones.append(d)
			i += 1
	return _ffa_zones

func is_solo_ffa_active() -> bool:
	return ffa_match != null

func _cycle_ffa_tier(advance: bool = true) -> void:
	if advance:
		ffa_tier = "rookie" if ffa_tier == "amateur" else "amateur"
	if ffa_tier_btn != null:
		ffa_tier_btn.text = "BOTS: %s" % ffa_tier.to_upper()

## Offline only. opts: bots (default 4), tier ("rookie" / "amateur"), kills_to_win (default 10), seed.
func start_solo_ffa(opts: Dictionary = {}) -> Node:
	if NetworkLobby.is_online_client() or NetworkLobby.is_dedicated_server:
		_on_status_banner("Solo FFA is offline only — leave the room first", Color(1.0, 0.5, 0.3))
		return null
	stop_solo_ffa()
	ffa_rematch_opts = opts.duplicate()
	if woodsball_map_root != null and is_instance_valid(woodsball_map_root):
		switch_arena_map("speedball") # v1 bunker graph is speedball-only
	NetworkLobby.fill_bots_enabled = false
	if fill_bots_check != null:
		fill_bots_check.button_pressed = false
	_set_opfor_bots_enabled(false)
	if player != null and player.has_method("respawn_at_team_gate"):
		player.call("respawn_at_team_gate", NetworkLobby.local_team)
	ffa_match = SoloFfaMatchScript.new()
	ffa_match.name = "SoloFfaMatch"
	add_child(ffa_match)
	ffa_match.call("start", self, player, opts)
	ffa_match.connect("standings_changed", _on_ffa_standings_changed)
	_refresh_ffa_round_label()
	if lobby_canvas != null:
		_set_lobby_overlay_visible(false)
	if has_method("clear_gameplay_input_blocks"):
		call("clear_gameplay_input_blocks", "solo_ffa")
	_on_status_banner("SOLO FFA DEATHMATCH — %d %s bots, first to %d eliminations. Break on the horn!" % [
		int(opts.get("bots", SoloFfaMatchScript.DEFAULT_BOTS)), String(opts.get("tier", ffa_tier)).to_upper(), int(opts.get("kills_to_win", SoloFfaMatchScript.KILLS_TO_WIN))], Color(1.0, 0.62, 0.2))
	return ffa_match

func stop_solo_ffa() -> void:
	ffa_rematch_opts = {}
	if ffa_match == null:
		return
	ffa_match.call("stop")
	ffa_match.queue_free()
	ffa_match = null
	_ffa_zones = []
	GameManager.death_limit_enabled = true

## Web link: ?solo=ffa[&tier=rookie|amateur][&ffa_bots=N] auto-starts the FFA (skips the lobby browser).
func _ffa_opts_from_url() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var q := String(JavaScriptBridge.eval("window.location.search", true))
	return parse_ffa_query(q)

static func parse_ffa_query(q: String) -> Dictionary:
	var kv := {}
	for part in q.trim_prefix("?").split("&", false):
		var bits := part.split("=", true, 1)
		kv[bits[0].to_lower()] = bits[1].uri_decode() if bits.size() > 1 else ""
	if String(kv.get("solo", "")).to_lower() != "ffa":
		return {}
	var opts := {"bots": SoloFfaMatchScript.DEFAULT_BOTS, "tier": "amateur"}
	if kv.has("tier") and String(kv["tier"]).to_lower() in ["rookie", "amateur"]:
		opts["tier"] = String(kv["tier"]).to_lower()
	if kv.has("ffa_bots") and String(kv["ffa_bots"]).is_valid_int():
		opts["bots"] = clampi(int(kv["ffa_bots"]), 1, 7)
	return opts

func _start_ffa_when_lobby_ready(opts: Dictionary) -> void:
	# Tim's LobbyEntryFlow attaches within ~10 frames and may open the browser; close it, then start.
	for _i in 14:
		await get_tree().process_frame
	var lef := get_node_or_null("/root/LobbyEntryFlow")
	if lef != null and lef.has_method("close_browser"):
		lef.call("close_browser")
	start_solo_ffa(opts)
