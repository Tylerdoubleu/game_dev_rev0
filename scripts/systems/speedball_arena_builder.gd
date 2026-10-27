extends Node3D

## Full-scale 3x Speedball Arena (108m x 132m) for v0.1.1-playtest.
## Features dense symmetrical bunkers (Home/Back, Cakes, Cans, Temples, Dorito Highway, Center 50 W-Wall,
## and an authentic multi-knuckle Snake with cross-blockers on the far-left 50s) plus 5 OpFor bots.

var player: Node3D
var hud_label: Label
var status_label: Label
var intel_label: Label
var round_label: Label

func _ready() -> void:
	_build_environment_and_turf()
	_build_speedball_bunkers()
	_spawn_opfor_bots()
	_spawn_player()
	_build_hud()
	GameManager.round_updated.connect(_on_round_updated)
	GameManager.round_won.connect(_on_round_won)
	IntelBus.intel_feed_updated.connect(_on_intel_feed)
	GameManager.register_round_start(5)

func _build_environment_and_turf() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.73, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.82, 0.9)
	env.ambient_light_energy = 0.65
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	add_child(sun)

	# 3x Turf Floor (108m wide x 132m long)
	var floor_body := StaticBody3D.new()
	floor_body.name = "TurfFloor"
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(108.0, 0.4, 132.0)
	fcol.shape = fbox
	fcol.position = Vector3(0, -0.2, 0)
	floor_body.add_child(fcol)

	var fmesh := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(108.0, 0.4, 132.0)
	fmesh.mesh = fbm
	fmesh.position = Vector3(0, -0.2, 0)
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color(0.14, 0.46, 0.22)
	turf_mat.roughness = 0.85
	fmesh.material_override = turf_mat
	floor_body.add_child(fmesh)
	add_child(floor_body)

	# 50-yard center line stripe on turf
	var line_mesh := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(106.0, 0.02, 0.35)
	line_mesh.mesh = lbm
	line_mesh.position = Vector3(0, 0.01, 0)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.95)
	line_mesh.material_override = line_mat
	add_child(line_mesh)

func _build_speedball_bunkers() -> void:
	var blue_vinyl := Color(0.12, 0.38, 0.82)
	var yellow_vinyl := Color(0.92, 0.76, 0.12)
	var red_vinyl := Color(0.86, 0.22, 0.18)
	var dark_vinyl := Color(0.18, 0.2, 0.25)

	# --- 1. CENTER 50-YARD LINE CLUSTER ---
	_spawn_bunker("Bunker_Center50_W", Vector3(0.0, 0.0, 0.0), Vector3(4.5, 2.4, 1.8), yellow_vinyl)
	_spawn_bunker("Bunker_50_MiniWin_Left", Vector3(-9.5, 0.0, 0.0), Vector3(2.4, 2.1, 1.4), yellow_vinyl)
	_spawn_bunker("Bunker_50_MiniWin_Right", Vector3(9.5, 0.0, 0.0), Vector3(2.4, 2.1, 1.4), yellow_vinyl)
	_spawn_bunker("Bunker_50_Insert_Left", Vector3(-19.0, 0.0, 0.0), Vector3(2.2, 2.2, 1.6), yellow_vinyl)
	_spawn_bunker("Bunker_50_Insert_Right", Vector3(19.0, 0.0, 0.0), Vector3(2.2, 2.2, 1.6), yellow_vinyl)

	# --- 2. SYMMETRICAL HALF-FIELD BUNKERS (Mirrored for Player +Z and OpFor -Z) ---
	for side in [-1.0, 1.0]:
		var team_color: Color = blue_vinyl if side > 0.0 else dark_vinyl
		var prefix: String = "Home_" if side > 0.0 else "OpFor_"

		# Breakout Start Gate & Back Center (Home Stone)
		_spawn_bunker(prefix + "BreakoutGate", Vector3(0.0, 0.0, 48.0 * side), Vector3(3.6, 2.3, 1.2), team_color)
		_spawn_bunker(prefix + "BackCenter", Vector3(0.0, 0.0, 38.0 * side), Vector3(3.2, 2.2, 1.4), team_color)

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
	# Low 0.90m crawl beams + upright knuckle blockers at S1, S2, S50, OpFor S2, OpFor S1 for prone/dive/crouch play!
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
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35
	mesh.material_override = mat
	body.add_child(mesh)
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

func _on_round_updated(round_num: int, remaining: int, time_left: float) -> void:
	if round_label == null:
		return
	round_label.text = (
		"ROUND %d  |  OPFOR ALIVE: %d  |  TIME: %.0fs\n" % [round_num, remaining, time_left] +
		"Move: WASD + Shift Sprint | C Crouch | Shift+C Knee-Slide\n" +
		"Ctrl Prone | Shift+Ctrl Superman Dive | Q/E Lean + Hand Swap\n" +
		"1 Speedball (Walk LMB/RMB) | 2 Woodsball (Hold LMB+RMB) | 3 Pump (LMB->RMB)\n" +
		"R Animated Pod Reload (Scarce Paint!) | F Ping | T Reset Round"
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
