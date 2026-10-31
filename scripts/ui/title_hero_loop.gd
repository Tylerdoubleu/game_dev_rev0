extends Node3D
## v0.6.4 title-screen hero loop (Bluey). A self-contained live backdrop: one player (the same ProPaintballRig3D the bots
## use) waits in the pocket behind a vinyl can, peeks out the side, brings the marker up on the camera, fires a 2-3 ball
## burst at the lens, and tucks back. The balls splat on an invisible plane just in front of the lens and fade out.
## Crouched in a red ALPHA jersey round a yellow can (Ren's title still). The peek side alternates every loop;
## stand_peeks adds a standing peek every other pair of loops.
##
## Cheap and safe for a menu: visual-only balls (no physics bodies, no PaintBallistics projectiles), no bot AI or
## perception, no NetworkLobby / match state, no arena. The timeline is deterministic: advance(dt) drives everything.
## Audio is off unless play_sound is set, and nothing here ever creates an AudioServer bus (that silences web audio).
##
## Ren's title screen runs res://scenes/ui/title_hero_loop.tscn inside its own SubViewport. HeroCamera is current in
## whatever viewport holds the scene; nothing here touches the window, the root viewport or project settings.
## Framing: player centre to centre-left, right third kept clear for the button board.
## To use your own camera, set use_own_camera = false and point camera_path at it (or leave it empty to use the
## viewport's current camera). use_own_environment / show_ground / background_props let you supply your own set.

const ProRigScript = preload("res://scripts/player/pro_paintball_rig_3d.gd")
const TeamColorsScript = preload("res://scripts/systems/team_colors.gd")
const GrittyArtThemeScript = preload("res://scripts/systems/gritty_art_theme.gd")
const BunkerGraphScript = preload("res://scripts/bots/bunker_graph.gd")
const PaintImpactAudioScript = preload("res://scripts/systems/paint_impact_audio.gd")

## Rig team ("ALPHA" / "BRAVO"); the jersey and marker color come from TeamColors.for_team (lobby picks if any).
@export var team: String = "ALPHA":
	set(v):
		team = v.strip_edges().to_upper()
		if rig != null:
			rig.set_team_visual(team)
@export var bracket: String = "speedball"
## true: the scene's own HeroCamera is current. false: aim at camera_path, or the viewport's current camera.
@export var use_own_camera: bool = true:
	set(v):
		use_own_camera = v
		_apply_camera_mode()
@export var camera_path: NodePath
@export var autoplay: bool = true
## Off: every peek is crouched (matches the title still). On: loops 2-3, 6-7, ... peek standing.
@export var stand_peeks: bool = false
## Flat team-colour jersey (like the title still) instead of the in-game printed jersey texture.
@export var solid_team_jersey: bool = true
@export var play_sound: bool = false
## Own WorldEnvironment + sun (turn off if the title screen supplies lighting).
@export var use_own_environment: bool = true
@export var show_ground: bool = true
@export var background_props: bool = true
## Loop timing (seconds). Peek / aim / burst / tuck fit in the first ~2.8 s; the rest is the pause.
@export_range(4.0, 6.0, 0.05) var loop_length: float = 4.8
@export_range(0.12, 0.15, 0.005) var shot_interval: float = 0.135
## Ball speed toward the lens (m/s). Real speedball is ~60; a bit slower reads better on a title screen.
@export var ball_speed_mps: float = 40.0
@export var paint_color: Color = Color(1.0, 0.55, 0.1) # BotPlayer's default paint
## Splats on the invisible plane in front of the lens.
@export var lens_splat_distance: float = 0.6
@export var splat_fade_s: float = 1.5
@export var max_splats: int = 6
## Own camera placement: chest height, this far from the can (8-12 m), the can framed centre-left.
@export var camera_distance: float = 8.0
@export var camera_height: float = 1.25
## How far the body steps sideways out of the pocket (0 = auto: just enough for the mask, hopper and marker to clear
## the can edge while most of the body stays covered, i.e. a real corner peek rather than BunkerGraph's full step-out spot).
@export var peek_out_m: float = 0.0
@export var camera_fov: float = 20.0
## Positive turns the camera right, so the player sits centre-left and the right third stays clear for the button board.
@export var camera_frame_offset_deg: float = 4.0

const BUNKER_SIZE := Vector3(2.0, 2.3, 2.0) # the arena's yellow MidCan (SpeedballArenaBuilder MidCan_L/R); a capsule via decorate_bunker_mesh
const BUNKER_COLOR := Color(0.84, 0.70, 0.16) # the arena's yellow vinyl
const BALL_RADIUS := 0.04 # PaintBallistics' ball mesh
const PEEK_STANCE_STAND := 0
const PEEK_STANCE_CROUCH := 1

# Timeline (seconds into a loop)
const T_PEEK_START := 0.55
const T_PEEK_OUT := 0.95
const T_AIM_UP := 1.25
const T_FIRST_SHOT := 1.32
const T_TUCK_START := 2.15
const T_TUCKED := 2.6

var rig: Node3D
var bunker: StaticBody3D
var camera: Camera3D
var lens_root: Node3D
var balls_root: Node3D

var time_in_loop: float = 0.0
var loop_index: int = 0
var loops_completed: int = 0
var peek_side: int = 1
var peek_stance: int = PEEK_STANCE_CROUCH
var aim_weight: float = 0.0
var out_alpha: float = 0.0
var shots_total: int = 0
var shots_this_loop: int = 0
var splats_total: int = 0
## One entry per finished peek: {"loop", "side", "stance", "shots"}.
var peek_log: Array[Dictionary] = []
var max_live_splats_seen: int = 0

var _shots_planned: int = 3
var _balls: Array[Dictionary] = []
var _splats: Array[Dictionary] = []
var _ball_mesh: SphereMesh
var _ball_mat: StandardMaterial3D
var _splat_tex: Texture2D
var _bunker_radius: float = 0.9
var _pocket_pos := Vector3.ZERO
var _peek_lateral: float = 1.4
var _built := false

## Deterministic burst sizes and lens hit offsets (x, y in metres on the lens plane), so every loop looks intentional.
const BURST_SIZES := [3, 2, 3, 3, 2, 3]
## Where shots land on the lens plane, in units of the view height there (x right, y up; screen x spans about
## +-0.89). Biased to the centre-left so the button board on the right third stays readable.
const LENS_OFFSETS := [Vector2(-0.18, 0.08), Vector2(0.10, -0.05), Vector2(-0.30, 0.16), Vector2(-0.05, -0.14),
	Vector2(0.16, 0.12), Vector2(-0.38, -0.06), Vector2(0.02, 0.18), Vector2(-0.24, -0.16), Vector2(0.12, 0.02)]

func _ready() -> void:
	_build()
	set_process(autoplay)

func _build() -> void:
	if _built:
		return
	_built = true
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = BALL_RADIUS
	_ball_mesh.height = BALL_RADIUS * 2.0
	_ball_mesh.radial_segments = 12
	_ball_mesh.rings = 6
	_ball_mat = GrittyArtThemeScript.create_oily_paint_material(paint_color, false)
	_splat_tex = GrittyArtThemeScript.load_texture_safe("res://assets/textures/paint_splat_mask.png")

	if use_own_environment:
		var env := WorldEnvironment.new()
		env.name = "WorldEnvironment"
		env.environment = GrittyArtThemeScript.create_overcast_stadium_environment()
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-34.0, -28.0, 0.0) # low sun over the camera's left shoulder: the player's front and the can face are lit
		sun.shadow_enabled = not OS.has_feature("web")
		sun.light_color = Color(0.9, 0.9, 0.92)
		sun.light_energy = 0.85
		add_child(sun)
		# one short ortho shadow map is all the shot needs (the set is ~25 m deep): cheap behind a menu
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 25.0
		var fill := DirectionalLight3D.new()
		fill.name = "Fill"
		fill.rotation_degrees = Vector3(-12.0, 20.0, 0.0) # soft front fill from camera right, no shadows
		fill.shadow_enabled = false
		fill.light_energy = 0.35
		fill.light_color = Color(1.0, 0.94, 0.86)
		add_child(fill)

	if show_ground:
		var ground := MeshInstance3D.new()
		ground.name = "Turf"
		var pm := PlaneMesh.new()
		pm.size = Vector2(60.0, 60.0)
		ground.mesh = pm
		var turf := GrittyArtThemeScript.create_muddy_turf_material().duplicate() as StandardMaterial3D
		turf.uv1_scale = Vector3(16.0, 16.0, 1.0) # same tiling density as the 108 x 132 m arena floor
		turf.albedo_color = Color(0.62, 0.62, 0.55) # a touch darker: the low sun behind the camera washes it out
		ground.material_override = turf
		ground.position = Vector3(0.0, 0.0, -10.0)
		add_child(ground)

	# The hero bunker sits on the world origin; the camera sits camera_distance in front of it (+Z).
	bunker = _make_bunker("Bunker_HeroCan", Vector3.ZERO, BUNKER_SIZE, BUNKER_COLOR)
	_bunker_radius = minf(BUNKER_SIZE.x, BUNKER_SIZE.z) * 0.48
	if background_props:
		_make_bunker("Bunker_Bg_Dorito", Vector3(-3.6, 0.0, -9.0), Vector3(2.5, 2.1, 2.5), Color(0.22, 0.36, 0.64))
		_make_bunker("Bunker_Bg_Brick", Vector3(-5.0, 0.0, -19.0), Vector3(2.6, 2.0, 1.6), Color(0.42, 0.43, 0.45))
		_make_bunker("Bunker_Bg_Temple", Vector3(-1.5, 0.0, -24.0), Vector3(2.8, 2.3, 1.8), Color(0.72, 0.22, 0.20))

	# Pocket: straight behind the can from the camera, POCKET_GAP behind its back face (BunkerGraph's pocket rule).
	# Peek: out to the side by the can's half width + the bot's AGENT_RADIUS, then BotPlayer's lean (+-1) on top.
	var depth := BUNKER_SIZE.z * 0.5
	_pocket_pos = Vector3(0.0, 0.0, -(depth + BunkerGraphScript.POCKET_GAP))
	_peek_lateral = peek_out_m if peek_out_m > 0.0 else _bunker_radius * 0.78

	rig = ProRigScript.new()
	rig.name = "HeroRig"
	rig.set("team_id", team)
	rig.set("bracket_id", bracket)
	add_child(rig)
	rig.position = _pocket_pos

	camera = Camera3D.new()
	camera.name = "HeroCamera"
	camera.fov = camera_fov
	camera.position = Vector3(0.0, camera_height, camera_distance)
	add_child(camera)
	camera.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-camera_frame_offset_deg), 0.0) # turn right: bunker sits centre-left
	_apply_camera_mode()

	lens_root = Node3D.new()
	lens_root.name = "LensSplats"
	add_child(lens_root)
	balls_root = Node3D.new()
	balls_root.name = "Paintballs"
	add_child(balls_root)

	_start_loop(0)
	_pose_rig(0.0)

func _make_bunker(bname: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	# Same mesh path as SpeedballArenaBuilder._spawn_bunker (decorate_bunker_mesh picks can / dorito / brick shapes),
	# but with no collision shape: nothing here needs physics.
	var body := StaticBody3D.new()
	body.name = bname
	body.collision_layer = 0
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	var mesh := MeshInstance3D.new()
	mesh.name = "BunkerMesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	body.add_child(mesh)
	GrittyArtThemeScript.decorate_bunker_mesh(body, mesh, size, color)
	_smooth_bunker_textures(mesh)
	add_child(body)
	return body

static var _mip_cache: Dictionary = {}

## The arena's vinyl textures are imported without mipmaps, which shimmers into a moire grid on a big close-up can.
## For this one hero shot swap in mipmapped copies (built once, cached; done at build time, never per frame).
func _smooth_bunker_textures(mesh: MeshInstance3D) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null or DisplayServer.get_name() == "headless":
		return
	mat = mat.duplicate() as StandardMaterial3D
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_texture = _mipmapped(mat.albedo_texture)
	mat.roughness_texture = _mipmapped(mat.roughness_texture)
	mat.normal_texture = _mipmapped(mat.normal_texture)
	mesh.material_override = mat

static func _mipmapped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _mip_cache.has(tex):
		return _mip_cache[tex]
	var out: Texture2D = tex
	var img := tex.get_image()
	if img != null and not img.is_compressed():
		img = img.duplicate() as Image
		if not img.has_mipmaps():
			img.generate_mipmaps()
		out = ImageTexture.create_from_image(img)
	_mip_cache[tex] = out
	return out

func _apply_camera_mode() -> void:
	if camera == null:
		return
	camera.current = use_own_camera
	camera.visible = use_own_camera

## The camera the player aims at: own HeroCamera, camera_path, or the viewport's current camera.
func target_camera() -> Camera3D:
	if use_own_camera and camera != null:
		return camera
	if not camera_path.is_empty():
		var c := get_node_or_null(camera_path) as Camera3D
		if c != null:
			return c
	var vc := get_viewport().get_camera_3d() if is_inside_tree() else null
	return vc if vc != null else camera

func team_color() -> Color:
	var lobby: Dictionary = ProRigScript.lobby_team_colors()
	return TeamColorsScript.for_team(team, lobby)

# ------------------------------------------------------------------ timeline
func _process(delta: float) -> void:
	advance(minf(delta, 0.1))

## Step the loop by dt seconds (tests call this directly; _process calls it while autoplay is on).
func advance(dt: float) -> void:
	if not _built:
		_build()
	var prev := time_in_loop
	time_in_loop += dt
	# shots whose time falls in (prev, time_in_loop]
	for i in _shots_planned:
		var ts := T_FIRST_SHOT + float(i) * shot_interval
		if prev < ts and time_in_loop >= ts:
			_fire_shot(i)
	if prev < T_TUCKED and time_in_loop >= T_TUCKED:
		peek_log.append({"loop": loop_index, "side": peek_side, "stance": peek_stance, "shots": shots_this_loop})
	_pose_rig(dt)
	_tick_balls(dt)
	_tick_splats(dt)
	if time_in_loop >= loop_length:
		loops_completed += 1
		var carry := time_in_loop - loop_length
		_start_loop(loop_index + 1)
		time_in_loop = carry

func _start_loop(i: int) -> void:
	loop_index = i
	time_in_loop = 0.0
	shots_this_loop = 0
	peek_side = 1 if i % 2 == 0 else -1 # side flips every loop
	# crouched like Ren's still; with stand_peeks on, every other pair of loops peeks standing instead
	peek_stance = PEEK_STANCE_STAND if stand_peeks and (i / 2) % 2 == 1 else PEEK_STANCE_CROUCH
	_shots_planned = BURST_SIZES[i % BURST_SIZES.size()]

## 0 hidden .. 1 fully out, eased.
func _out_target(t: float) -> float:
	if t <= T_PEEK_START or t >= T_TUCKED:
		return 0.0
	if t < T_PEEK_OUT:
		return _smooth((t - T_PEEK_START) / (T_PEEK_OUT - T_PEEK_START))
	if t <= T_TUCK_START:
		return 1.0
	return 1.0 - _smooth((t - T_TUCK_START) / (T_TUCKED - T_TUCK_START))

func _aim_target(t: float) -> float:
	var last_shot := T_FIRST_SHOT + float(_shots_planned - 1) * shot_interval
	if t < T_PEEK_OUT - 0.1 or t > T_TUCK_START + 0.08:
		return 0.0
	if t < T_AIM_UP:
		return _smooth((t - (T_PEEK_OUT - 0.1)) / (T_AIM_UP - (T_PEEK_OUT - 0.1)))
	if t <= maxf(last_shot + 0.25, T_TUCK_START - 0.1):
		return 1.0
	return 1.0 - _smooth((t - (T_TUCK_START - 0.1)) / 0.18)

static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

func phase() -> String:
	var t := time_in_loop
	if t < T_PEEK_START or t >= T_TUCKED:
		return "hidden"
	if t < T_AIM_UP:
		return "peek"
	if t < T_TUCK_START:
		return "fire"
	return "tuck"

func _pose_rig(dt: float) -> void:
	if rig == null:
		return
	out_alpha = _out_target(time_in_loop)
	aim_weight = _aim_target(time_in_loop)
	var cam := target_camera()
	var cam_local := to_local(cam.global_position) if cam != null else Vector3(0.0, camera_height, camera_distance)
	# step out sideways from the pocket (BotPlayer moves the body to the peek spot, then leans)
	rig.position = _pocket_pos + _lateral_axis(cam_local) * float(peek_side) * _peek_lateral * out_alpha
	# face the camera (yaw only), like a bot squaring up to its target; the rig's forward is -Z
	var face := cam_local - rig.position
	if Vector2(face.x, face.z).length() > 0.01:
		rig.rotation.y = atan2(-face.x, -face.z)
	# BotPlayer._pose(): lean only while peeking, matched hand on the peek side, pocket tuck while hidden
	rig.call("apply_pose", dt, {
		"velocity": Vector3.ZERO,
		"stance": peek_stance,
		"lean": float(peek_side) * out_alpha,
		"is_left_handed": peek_side < 0,
		"bunker_tuck": 1.0 - out_alpha,
		"is_sliding": false,
		"is_diving": false,
		"is_reloading": false,
		"is_eliminated": false,
		"team": team,
		"bracket": bracket,
	})
	_pose_marker_on_aim(cam)
	_apply_title_jersey()

## The printed red jersey reads almost black at title-screen size; Ren's still shows a solid team-red jersey, so the
## hero tints it flat with the team colour (TeamColors.for_team). Cheap: one null check per frame, re-applied only if
## the rig re-skins itself (e.g. NetworkLobby.team_colors_changed).
func _apply_title_jersey() -> void:
	if not solid_team_jersey or rig == null:
		return
	var mj = rig.get("_mat_jersey")
	if mj is StandardMaterial3D:
		var m := mj as StandardMaterial3D
		if m.albedo_texture != null:
			m.albedo_texture = null
			m.albedo_color = team_color().darkened(0.08)

## Local axis that is the rig's right hand side while it faces the camera from the pocket; peek_side +1 steps that way.
func _lateral_axis(cam_local: Vector3) -> Vector3:
	var to_cam := cam_local - _pocket_pos
	to_cam.y = 0.0
	if to_cam.length() < 0.01:
		to_cam = Vector3(0, 0, 1)
	return to_cam.normalized().cross(Vector3.UP).normalized()

## BotPlayer._pose_marker_on_aim(): blend the marker pivot from the procedural carry onto the aim line.
func _pose_marker_on_aim(cam: Camera3D) -> void:
	var piv: Node3D = rig.get("marker_assembly_pivot")
	if piv == null or not piv.is_inside_tree() or aim_weight <= 0.001 or cam == null:
		return
	var aim_dir := (cam.global_position - piv.global_position).normalized()
	var posed := piv.global_transform.basis.orthonormalized()
	var aimed := Basis.looking_at(aim_dir, Vector3.UP)
	var b := posed.slerp(aimed, aim_weight) if aim_weight < 0.999 else aimed
	var sc := piv.global_transform.basis.get_scale()
	piv.global_transform = Transform3D(b.scaled(sc), piv.global_position)

func muzzle_position() -> Vector3:
	var tip: Node3D = rig.get("muzzle_tip_node") if rig != null else null
	return tip.global_position if tip != null else rig.global_position + Vector3(0, 1.4, 0)

# ------------------------------------------------------------------ balls + lens splats
func _lens_point(cam: Camera3D, off: Vector2) -> Vector3:
	var b := cam.global_transform.basis
	var view_h := 2.0 * lens_splat_distance * tan(deg_to_rad(cam.fov * 0.5))
	return cam.global_position - b.z * lens_splat_distance + (b.x * off.x + b.y * off.y) * view_h

func _fire_shot(i: int) -> void:
	var cam := target_camera()
	if cam == null:
		return
	shots_this_loop += 1
	shots_total += 1
	var origin := muzzle_position()
	var off: Vector2 = LENS_OFFSETS[(shots_total - 1) % LENS_OFFSETS.size()]
	var target := _lens_point(cam, off)
	var dist := origin.distance_to(target)
	var flight := maxf(dist / maxf(ball_speed_mps, 1.0), 0.05)
	var node := MeshInstance3D.new()
	node.mesh = _ball_mesh
	node.material_override = _ball_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	balls_root.add_child(node)
	node.global_position = origin
	_balls.append({"node": node, "from": origin, "to": target, "off": off, "t": 0.0, "flight": flight})
	if play_sound:
		PaintImpactAudioScript.play(self, "fire", origin, 0.03)

func _tick_balls(dt: float) -> void:
	var cam := target_camera()
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		b["t"] = float(b["t"]) + dt
		var s := clampf(float(b["t"]) / float(b["flight"]), 0.0, 1.0)
		var node: MeshInstance3D = b["node"]
		# drop-compensated lob: a little rise and fall over the flight (g t^2 / 8 at the apex)
		var arc := 9.81 * float(b["flight"]) * float(b["flight"]) * 0.5 * s * (1.0 - s)
		if is_instance_valid(node):
			node.global_position = (b["from"] as Vector3).lerp(b["to"], s) + Vector3.UP * arc
		if s >= 1.0:
			if is_instance_valid(node):
				node.queue_free()
			_balls.remove_at(i)
			if cam != null:
				_spawn_lens_splat(cam, b["off"])

func _spawn_lens_splat(cam: Camera3D, off: Vector2) -> void:
	while _splats.size() >= max_splats:
		var old: Dictionary = _splats.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()
	splats_total += 1
	var q := MeshInstance3D.new()
	q.name = "LensSplat_%d" % splats_total
	var qm := QuadMesh.new()
	# sized against the view height at the lens plane so a splat covers ~22-30% of the frame height whatever the fov
	var view_h := 2.0 * lens_splat_distance * tan(deg_to_rad((cam.fov if cam != null else camera_fov) * 0.5))
	var sz := view_h * (0.22 + 0.04 * float(splats_total % 3))
	qm.size = Vector2(sz, sz)
	q.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint_color
	mat.albedo_texture = _splat_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.metallic = 0.08
	mat.roughness = 0.1
	mat.emission_enabled = true
	mat.emission = paint_color * 0.55
	mat.emission_energy_multiplier = 0.45
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens_root.add_child(q)
	# face the lens, random-but-deterministic spin
	var p := _lens_point(cam, off)
	var cb := cam.global_transform.basis.orthonormalized()
	q.global_transform = Transform3D(cb.rotated(cb.z.normalized(), float(splats_total) * 2.39996), p)
	_splats.append({"node": q, "mat": mat, "age": 0.0, "size": sz})
	max_live_splats_seen = maxi(max_live_splats_seen, _splats.size())

func _tick_splats(dt: float) -> void:
	for i in range(_splats.size() - 1, -1, -1):
		var s: Dictionary = _splats[i]
		s["age"] = float(s["age"]) + dt
		var age := float(s["age"])
		var node: MeshInstance3D = s["node"]
		if age >= splat_fade_s or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_splats.remove_at(i)
			continue
		# pop open in 60 ms, then fade out over splat_fade_s (ease-in so it lingers, then goes)
		var pop := clampf(age / 0.06, 0.0, 1.0)
		node.scale = Vector3.ONE * lerpf(0.55, 1.0, pop) * (1.0 + 0.06 * (age / splat_fade_s))
		var a := 1.0 - pow(age / splat_fade_s, 1.6)
		var m: StandardMaterial3D = s["mat"]
		m.albedo_color.a = clampf(a, 0.0, 1.0)

func live_splat_count() -> int:
	return _splats.size()

func live_ball_count() -> int:
	return _balls.size()

# ------------------------------------------------------------------ exposure (geometric, no physics)
## How many of the rig's sample points (head, muzzle, hopper, torso, hands, knees, boots) the camera can see past
## the hero can. Uses the can's capsule shape, so it works with no physics world.
func rig_exposure(cam: Camera3D = null) -> Dictionary:
	var c := cam if cam != null else target_camera()
	var names := ["neck_head_pivot", "muzzle_tip_node", "hopper_unit_pivot", "torso_pivot", "left_glove_hand",
		"right_glove_hand", "left_knee_pivot", "right_knee_pivot", "left_boot_cleat", "right_boot_cleat"]
	var seen: Array[String] = []
	for n in names:
		var nd: Node3D = rig.get(n)
		if nd == null:
			continue
		if not _blocked_by_bunker(c.global_position, nd.global_position):
			seen.append(n)
	return {"visible": seen, "count": seen.size(), "total": names.size(),
		"head": seen.has("neck_head_pivot"), "muzzle": seen.has("muzzle_tip_node")}

func _blocked_by_bunker(from: Vector3, to: Vector3) -> bool:
	var axis := bunker.global_position # capsule centre
	var half_h := BUNKER_SIZE.y * 0.5
	var r := _bunker_radius
	for k in range(1, 64):
		var p := from.lerp(to, float(k) / 64.0)
		var dy := clampf(p.y - axis.y, -(half_h - r), half_h - r)
		var core := Vector3(axis.x, axis.y + dy, axis.z)
		if p.distance_to(core) < r:
			return true
	return false
