extends Node3D

## Greybox 3v3 Speedball Arena ("speedball_arena_01") for v0.1.0-playtest.
## Builds symmetrical inflatable bunkers (Center 50, Doritos, Snake, Cans, Home Back Center),
## spawns the First-Person Player + 3 Snap-Shooting OpFor bots, and wires the live tactical HUD.

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
	GameManager.register_round_start(3)

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

	# Turf floor (36m x 44m speedball field)
	var floor_body := StaticBody3D.new()
	floor_body.name = "TurfFloor"
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(36.0, 0.4, 44.0)
	fcol.shape = fbox
	fcol.position = Vector3(0, -0.2, 0)
	floor_body.add_child(fcol)

	var fmesh := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(36.0, 0.4, 44.0)
	fmesh.mesh = fbm
	fmesh.position = Vector3(0, -0.2, 0)
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color(0.14, 0.46, 0.22)
	turf_mat.roughness = 0.85
	fmesh.material_override = turf_mat
	floor_body.add_child(fmesh)
	add_child(floor_body)

func _build_speedball_bunkers() -> void:
	var blue_vinyl := Color(0.12, 0.38, 0.82)
	var yellow_vinyl := Color(0.92, 0.76, 0.12)
	var dark_vinyl := Color(0.18, 0.2, 0.25)

	# Center 50-yard X/Aztec bunker
	_spawn_bunker("Bunker_Center50", Vector3(0.0, 0.0, 0.0), Vector3(2.4, 2.2, 1.2), yellow_vinyl)

	# Home & OpFor Back Center (Home Stone)
	_spawn_bunker("Bunker_HomeBack", Vector3(0.0, 0.0, 14.0), Vector3(2.2, 2.1, 1.0), blue_vinyl)
	_spawn_bunker("Bunker_OpForBack", Vector3(0.0, 0.0, -14.0), Vector3(2.2, 2.1, 1.0), dark_vinyl)

	# Dorito Side (Right side from player breakout: +X)
	_spawn_bunker("Bunker_HomeDorito1", Vector3(6.5, 0.0, 8.0), Vector3(1.8, 2.0, 1.8), blue_vinyl)
	_spawn_bunker("Bunker_50Dorito", Vector3(8.5, 0.0, 0.0), Vector3(2.0, 2.1, 2.0), yellow_vinyl)
	_spawn_bunker("Bunker_OpForDorito1", Vector3(6.5, 0.0, -8.0), Vector3(1.8, 2.0, 1.8), dark_vinyl)

	# Snake Side (Left side from player breakout: -X, low beams for crouch/slide cover)
	_spawn_bunker("Bunker_HomeSnakeCorner", Vector3(-6.5, 0.0, 8.5), Vector3(1.8, 2.0, 1.4), blue_vinyl)
	_spawn_bunker("Bunker_SnakeBeam", Vector3(-8.5, 0.0, 0.0), Vector3(1.1, 1.05, 11.0), yellow_vinyl)
	_spawn_bunker("Bunker_OpForSnakeCorner", Vector3(-6.5, 0.0, -8.5), Vector3(1.8, 2.0, 1.4), dark_vinyl)

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

	var b1 := StaticBody3D.new()
	b1.set_script(bot_script)
	b1.name = "OpFor_BackCenter"
	b1.set("bot_name", "OpFor Back-Center")
	b1.position = Vector3(0.8, 0.0, -14.8)
	b1.set("peek_offset", Vector3(0.95, 0.0, 0.0))
	add_child(b1)

	var b2 := StaticBody3D.new()
	b2.set_script(bot_script)
	b2.name = "OpFor_Dorito"
	b2.set("bot_name", "OpFor Dorito-1")
	b2.position = Vector3(5.8, 0.0, -8.8)
	b2.set("peek_offset", Vector3(-0.9, 0.0, 0.0))
	add_child(b2)

	var b3 := StaticBody3D.new()
	b3.set_script(bot_script)
	b3.name = "OpFor_Snake"
	b3.set("bot_name", "OpFor Snake-Corner")
	b3.position = Vector3(-5.8, 0.0, -9.2)
	b3.set("peek_offset", Vector3(0.9, 0.0, 0.0))
	add_child(b3)

func _spawn_player() -> void:
	var player_script := load("res://scripts/player/player_controller_3d.gd")
	player = CharacterBody3D.new()
	player.name = "Player3D"
	player.set_script(player_script)
	player.position = Vector3(0.0, 0.1, 16.2)
	add_child(player)
	player.connect("hud_state_changed", _on_hud_state_changed)
	player.connect("status_banner_sent", _on_status_banner)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PlaytestHUD"
	add_child(canvas)

	# Crosshair
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.9))
	canvas.add_child(crosshair)

	# Top-left HUD Panel
	hud_label = Label.new()
	hud_label.position = Vector2(20, 18)
	hud_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hud_label)

	# Top-right Round & Controls Help
	round_label = Label.new()
	round_label.position = Vector2(980, 18)
	round_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(round_label)

	# Bottom Status / Reload Banner
	status_label = Label.new()
	status_label.position = Vector2(20, 810)
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	canvas.add_child(status_label)

	# Intel Feed Label
	intel_label = Label.new()
	intel_label.position = Vector2(20, 770)
	intel_label.add_theme_font_size_override("font_size", 17)
	intel_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	canvas.add_child(intel_label)

	player.call("_emit_hud")

func _on_hud_state_changed(state: Dictionary) -> void:
	if hud_label == null:
		return
	var reload_text := ""
	if state["reloading"]:
		reload_text = "\n[RELOADING POD: %d%% — DO NOT SPRINT/SLIDE!]" % int(state["reload_pct"] * 100.0)
	var pump_text := ""
	if state["pump_mode"]:
		pump_text = " | PUMP: %s" % ("RACKED (Ready)" if state["pump_racked"] else "NEEDS RACK [RMB]")

	hud_label.text = (
		"BRACKET: %s\n" % state["bracket_name"] +
		"HOPPER: %d / %d  |  PODS: %d (%d rnds)%s\n" % [state["hopper"], state["hopper_max"], state["pods"], state["pod_cap"], pump_text] +
		"MARKER SHOULDER: %s (Auto-swaps on Q/E Lean or X/MMB)%s" % [state["hand"], reload_text]
	)

func _on_round_updated(round_num: int, remaining: int, time_left: float) -> void:
	if round_label == null:
		return
	round_label.text = (
		"ROUND %d  |  OPFOR ALIVE: %d  |  TIME: %.0fs\n" % [round_num, remaining, time_left] +
		"Controls: WASD Move | Shift Sprint | Ctrl/C Slide/Crouch\n" +
		"Q/E Snap-Lean + Hand Swap | LMB/RMB Shoot/Walk/Pump\n" +
		"R Pod Reload (Spills if Sprint!) | F Ping Intel\n" +
		"1/2/3 Switch Bracket (Speedball / Woodsball / Pump) | T Reset Round"
	)

func _on_round_won(round_num: int) -> void:
	_on_status_banner("ROUND %d WON! All OpFor Eliminated — Press [T] for Next Round" % round_num, Color(0.3, 1.0, 0.45))

func _on_status_banner(msg: String, color: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)

func _on_intel_feed(msg: String) -> void:
	if intel_label:
		intel_label.text = msg
