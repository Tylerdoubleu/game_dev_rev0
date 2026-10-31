extends SceneTree
## v0.6.4 team colors (Bluey): one lookup (ProPaintballRig3D.team_color / team_color_name) for every Bluey-owned team
## visual. Defaults ALPHA red / BRAVO blue; reads the lobby's team_colors ({"ALPHA": "red", ...}) when NetworkLobby
## has it; names become colors through Tim's TeamColors (palette_script_override swaps it here), else the
## fallback map; HUD score labels, flags, flag tags, jerseys and markers follow, and re-tint on team_colors_changed.
## Run: godot --headless --path . -s scripts/systems/test_team_color_wiring.gd

var arena: Node3D
var failures: Array[String] = []
var started := false
var real_lobby: Node
var fake_lobby: Node

const FAKE_LOBBY_SRC := """extends Node
signal team_colors_changed(team_colors: Dictionary)
var team_colors := {"ALPHA": "red", "BRAVO": "blue"}
func set_colors(d: Dictionary) -> void:
	team_colors = d
	team_colors_changed.emit(d)
"""
## Swap-in palette stand-ins (not named TeamColors): for_team(team, team_colors) and a by-name color_of(name).
const FAKE_FOR_TEAM_SRC := """extends RefCounted
const COLORS := {"red": Color(0.9, 0.1, 0.1), "blue": Color(0.1, 0.2, 0.9), "green": Color(0.1, 0.8, 0.2)}
static func for_team(team: String, team_colors: Dictionary) -> Color:
	var d := {"ALPHA": "red", "BRAVO": "blue"}
	d.merge(team_colors, true)
	return COLORS.get(String(d.get(team.to_upper(), "red")), COLORS["red"])
"""
const FAKE_COLOR_OF_SRC := """extends RefCounted
static func color_of(n: String) -> Color:
	return {"red": Color(0.8, 0.0, 0.0), "blue": Color(0.0, 0.0, 0.8), "green": Color(0.0, 0.7, 0.0)}.get(n, Color(0.8, 0.0, 0.0))
"""

func _initialize() -> void:
	arena = (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_d: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func _run() -> void:
	await _frames(4)
	var Rig: GDScript = load("res://scripts/player/pro_paintball_rig_3d.gd")
	var red: Color = Rig.color_for_name("red")
	var blue: Color = Rig.color_for_name("blue")
	var green: Color = Rig.color_for_name("green")
	var tcs: Script = load("res://scripts/systems/team_colors.gd")
	_check(_near(Rig.team_color("ALPHA"), tcs.call("for_team", "ALPHA", {})) and _near(Rig.team_color("BRAVO"), tcs.call("for_team", "BRAVO", {})), "team_color == TeamColors.for_team")
	_check(_near(red, Rig.FALLBACK_TEAM_COLORS["red"]) and _near(blue, Rig.FALLBACK_TEAM_COLORS["blue"]), "fallback red/blue equal the palette's")
	var hud: Node = arena.get("match_client")

	# 1) Defaults (lobby on its defaults): ALPHA red, BRAVO blue.
	_check(Rig.team_color_name("ALPHA") == "red" and Rig.team_color_name("BRAVO") == "blue", "default names ALPHA red / BRAVO blue")
	_check(Rig.team_color_name("red") == "red" and Rig.team_color_name("blue") == "blue", "HUD side tags red/blue map to ALPHA/BRAVO")
	_check(_near(Rig.team_color("ALPHA"), red) and _near(Rig.team_color("BRAVO"), blue), "default colors")
	if hud != null:
		_check(_near(hud.call("_tc", "red"), red) and _near(hud.call("_tc", "blue"), blue), "HUD _tc defaults")
		_check(_near(hud.call("_tc", "draw"), hud.GOLD), "HUD _tc non-team -> GOLD fallback")

	# 2) Jerseys + markers: ALPHA wears red (the red printed jersey), BRAVO blue - the old rig had them swapped.
	var ra: Node3D = Rig.new()
	root.add_child(ra)
	ra.call("build_rig", "ALPHA", "speedball")
	var rb: Node3D = Rig.new()
	root.add_child(rb)
	rb.call("build_rig", "BRAVO", "speedball")
	_check(_jersey_tex(ra).ends_with("jersey_pro_bravo.png"), "ALPHA jersey is the red print (%s)" % _jersey_tex(ra))
	_check(_jersey_tex(rb).ends_with("jersey_pro_alpha.png"), "BRAVO jersey is the blue print (%s)" % _jersey_tex(rb))
	_check(_near(_marker(ra), red) and _near(_marker(rb), blue), "markers anodized in team color")

	# 3) Lobby value: swap in a NetworkLobby that has team_colors + team_colors_changed (Tim's API shape).
	real_lobby = root.get_node("NetworkLobby")
	var fs := GDScript.new()
	fs.source_code = FAKE_LOBBY_SRC
	fs.reload()
	fake_lobby = fs.new()
	real_lobby.name = "NetworkLobbyReal"
	fake_lobby.name = "NetworkLobby"
	root.add_child(fake_lobby)
	fake_lobby.call("set_colors", {"ALPHA": "blue", "BRAVO": "red"})
	_check(Rig.team_color_name("ALPHA") == "blue" and _near(Rig.team_color("ALPHA"), blue), "lobby ALPHA=blue is read")
	var r2: Node3D = Rig.new()
	root.add_child(r2) # _ready connects team_colors_changed
	r2.call("build_rig", "ALPHA", "speedball")
	_check(_jersey_tex(r2).ends_with("jersey_pro_alpha.png"), "lobby ALPHA=blue -> blue jersey")
	fake_lobby.call("set_colors", {"ALPHA": "green", "BRAVO": "blue"})
	_check(_jersey_tex(r2) == "" and _near(_marker(r2), green), "team_colors_changed re-tints a live rig (green, plain jersey)")
	fake_lobby.call("set_colors", {"ALPHA": "chartreuse", "BRAVO": ""})
	_check(Rig.team_color_name("ALPHA") == "red" and Rig.team_color_name("BRAVO") == "blue", "unknown / empty names fall back to defaults")

	# 4) HUD follows (apply_team_colors is what the HUD runs on team_colors_changed).
	fake_lobby.call("set_colors", {"ALPHA": "green", "BRAVO": "blue"})
	if hud != null:
		hud.call("apply_team_colors")
		var rsl: Label = hud.get("red_score_label")
		_check(rsl != null and _near(rsl.get_theme_color("font_color"), green), "ALPHA score label green")
		_check(rsl != null and rsl.text.begins_with("GREEN"), "ALPHA score label reads GREEN (%s)" % (rsl.text if rsl != null else ""))
		var fl: Dictionary = hud.get("flag_nodes")
		if fl.has("red"):
			var cloth := (fl["red"] as Node).get_node("Cloth") as MeshInstance3D
			_check(_near((cloth.material_override as StandardMaterial3D).albedo_color, green), "ALPHA flag cloth green")
			_check(((fl["red"] as Node).get_node("FlagTag") as Label3D).text == "GREEN FLAG", "ALPHA flag tag GREEN FLAG")
		else:
			_check(true, "flags not built in this headless setup (skipped)")
		_check(hud.call("_tn", "red") == "GREEN" and hud.call("_tn", "blue") == "BLUE", "HUD _tn names")

	# 5) The palette script supplies the actual colors (TeamColors; swappable).
	_check(Rig._team_palette() == load("res://scripts/systems/team_colors.gd"), "palette is Tim's TeamColors")
	var ps := GDScript.new()
	ps.source_code = FAKE_FOR_TEAM_SRC
	ps.reload()
	Rig.palette_script_override = ps
	_check(_near(Rig.team_color("ALPHA"), Color(0.1, 0.8, 0.2)) and _near(Rig.team_color("BRAVO"), Color(0.1, 0.2, 0.9)), "for_team(team, team_colors) palette used (lobby ALPHA green)")
	_check(_near(Rig.team_color("red"), Color(0.1, 0.8, 0.2)), "HUD side tag 'red' -> ALPHA via for_team")
	var ps2 := GDScript.new()
	ps2.source_code = FAKE_COLOR_OF_SRC
	ps2.reload()
	Rig.palette_script_override = ps2
	_check(_near(Rig.team_color("ALPHA"), Color(0.0, 0.7, 0.0)) and _near(Rig.team_color("BRAVO"), Color(0.0, 0.0, 0.8)), "color_of(name) palette used")
	Rig.palette_script_override = null
	Rig.reset_palette_lookup()

	# restore
	fake_lobby.queue_free()
	fake_lobby.name = "NetworkLobbyFake"
	real_lobby.name = "NetworkLobby"
	await _frames(1)
	_check(Rig.team_color_name("ALPHA") == "red", "real NetworkLobby on defaults -> red again")
	# 6) Tim's real NetworkLobby: a server team_colors_changed re-tints the live HUD + rigs via the signal (no manual call).
	_check(real_lobby.has_signal("team_colors_changed"), "NetworkLobby has team_colors_changed")
	var r3: Node3D = Rig.new()
	root.add_child(r3)
	r3.call("build_rig", "BRAVO", "speedball")
	real_lobby.call("_client_set_team_colors", {"ALPHA": "pink", "BRAVO": "cyan"})
	await _frames(1)
	_check(_near(_marker(r3), tcs.call("color_of", "cyan")), "live rig BRAVO -> cyan from the signal")
	if hud != null:
		var bsl: Label = hud.get("blue_score_label")
		_check(bsl != null and bsl.text.contains("CYAN") and _near(bsl.get_theme_color("font_color"), tcs.call("color_of", "cyan")), "HUD BRAVO score label CYAN from the signal (%s)" % (bsl.text if bsl != null else ""))
	real_lobby.call("_client_set_team_colors", {"ALPHA": "red", "BRAVO": "blue"})
	r3.queue_free()
	for n in [ra, rb, r2]:
		n.queue_free()
	if failures.is_empty():
		print("TEAM COLORS TEST: ALL PASSED")
		quit(0)
	else:
		print("TEAM COLORS TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

func _jersey_tex(rig: Node) -> String:
	var m: StandardMaterial3D = rig.get("_mat_jersey")
	if m == null or m.albedo_texture == null:
		return ""
	var p := m.albedo_texture.resource_path
	return p if p != "" else String(m.albedo_texture.get_meta("src", "img"))

func _marker(rig: Node) -> Color:
	var m: StandardMaterial3D = rig.get("_mat_anodized_marker")
	return m.albedo_color if m != null else Color.BLACK
