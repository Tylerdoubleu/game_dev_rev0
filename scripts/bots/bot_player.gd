extends CharacterBody3D
## v0.7 BotPlayer (plan "Smarter bots"): a real CharacterBody3D runner that shares the player's movement and spread rules
## (scripts/player/movement_rules.gd: walk 5.6 / sprint 8.4, crouch, knee-slide, dive, stance capsules, the movement fire
## lock and the spread cone multipliers), wears the same ProPaintballRig3D + sub-hitboxes, and is driven by a small
## utility / state brain on a BunkerGraph:
##   WAIT_HORN -> BREAK (sprint to the role's primary bunker pocket) -> HOLD (tucked in a pocket)
##   -> PEEK (step out one side; snap-shoot only with a raycast line of sight, after the tier's reaction time)
##   -> TUCK -> HOLD / MOVE (next bunker when the lane is safe; Amateur+ slide into exposed edges).
## Perception (LOS raycasts) runs at ~10 Hz, staggered across bots by bot_index.
## Hits use the existing paint path (resolve_hit_subzone / on_paintball_break); the hit marker only shows when the
## local player's ball made the elimination (the shooter has award_kill_bonus_pod).

const MovementRules = preload("res://scripts/player/movement_rules.gd")
const ProRigScript = preload("res://scripts/player/pro_paintball_rig_3d.gd")
const BotDifficultyScript = preload("res://scripts/bots/bot_difficulty.gd")
const BunkerGraphScript = preload("res://scripts/bots/bunker_graph.gd")

signal shot_fired(bot: Node, origin: Vector3, aim_point: Vector3, kind: String)
signal bot_eliminated(bot: Node, shooter: Node, zone: String)
signal bot_respawned(bot: Node)

enum State { WAIT_HORN, BREAK, HOLD, PEEK, TUCK, MOVE, DEAD }
const STATE_NAMES := ["WAIT_HORN", "BREAK", "HOLD", "PEEK", "TUCK", "MOVE", "DEAD"]

const PERCEPTION_HZ: float = 10.0
const VIEW_RANGE: float = 75.0
const VIEW_CONE_DEG: float = 220.0
const RESPAWN_DELAY: float = 3.2
const GRAVITY: float = 20.0
const TURN_RATE: float = 9.0 # rad/s yaw
const ARRIVE_DIST: float = 0.45
const SLIDE_TRIGGER_MIN: float = 4.5 # slide into the pocket from this far ... (a knee-slide covers ~7 m)
const SLIDE_TRIGGER_MAX: float = 7.5
const SLIDE_EXPOSURE_MIN: float = 0.35 # ... when the edge is this exposed
const SUPPRESS_MEMORY_S: float = 4.0

# --- identity / setup
var bot_name: String = "Bot"
var callsign: String = "Bot"
var team: String = "FFA" # "ALPHA" / "BRAVO" for team modes, "FFA" = everyone is hostile
var ffa: bool = true
var role: String = BunkerGraphScript.ROLE_MID
var bot_index: int = 0
var difficulty: Resource = null
var graph: RefCounted = null
var match_ctrl: Node = null # SoloFfaMatch (scores / respawn points); null = practice behaviour
var paint_color: Color = Color(1.0, 0.55, 0.1)
var rig_team: String = "BRAVO"
var bracket_id: String = "speedball"
var max_bps: float = 10.5
var muzzle_fps: float = 285.0
var base_spread_deg: float = MovementRules.SPREAD_BASE_DEG_SPEEDBALL
var rng := RandomNumberGenerator.new()

# --- state
var state: int = State.WAIT_HORN
var state_time: float = 0.0
var is_eliminated: bool = false
var respawn_timer: float = 0.0
var _respawn_flash_timer: float = 0.0 # spawn protection, same 2.8 s as the player (hits ignored, not targeted)
const SPAWN_PROTECT_S := 2.8
var assigned_node: int = -1 # primary break bunker (graph index)
var current_node: int = -1
var pocket_side: int = -1 # -1 left, +1 right, 0 low
var peek_side: int = -1
var habitual_peek_side: int = -1
var pocket_pos: Vector3 = Vector3.ZERO
var reached_assigned: bool = false
var reached_assigned_at: float = -1.0
var arrival_error: float = -1.0 # metres from the pocket when the break ended (tests)
var hold_timer: float = 0.0
var peek_timer: float = 0.0

# --- motor (same rules as the player)
var stance: int = MovementRules.STANCE_STANDING
var want_sprint: bool = false
var ground_speed: float = 0.0
var slide_timer: float = 0.0
var dive_timer: float = 0.0
var movement_fire_recovery_timer: float = 0.0
var slide_dir: Vector3 = Vector3.ZERO
var shot_spread_mult: float = MovementRules.SPREAD_MULT_STANDING
var yaw: float = 0.0
var move_goal: Vector3 = Vector3.ZERO
var has_move_goal: bool = false
var path: PackedVector3Array = PackedVector3Array()
var path_i: int = 0
var path_exposure: float = 0.0
var slide_planned: bool = false
var dive_planned: bool = false
var _stuck_timer: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _replans: int = 0
var look_point: Vector3 = Vector3.ZERO
var has_look_point: bool = false
var lean: float = 0.0
var slides_done: int = 0
var dives_done: int = 0
var distance_moved: float = 0.0

# --- perception
var _perc_accum: float = 0.0
var visible_targets: Array = []
var current_target: Node3D = null
var target_seen_since: float = -1.0
var last_seen_pos: Vector3 = Vector3.ZERO
var last_seen_time: float = -1000.0
var last_seen_node: int = -1
var perception_ticks: int = 0
var los_rays_cast: int = 0
var clock: float = 0.0

# --- fire
var burst_left: int = 0
var shot_cd: float = 0.0
var burst_pause: float = 0.0
var aim_offset: Vector3 = Vector3.ZERO
var burst_kind: String = "snap"
var shots_fired: int = 0
var snap_shots: int = 0
var suppress_shots: int = 0
var shots_blocked_no_los: int = 0
var kills: int = 0
var deaths: int = 0
var spawn_point: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0

## Tests: how many times a bot elimination raised the local hit marker (only the local player's balls may).
static var local_hit_markers_shown: int = 0

var pro_rig: Node3D = null
var hitboxes: Dictionary = {}

func configure(p: Dictionary) -> void:
	callsign = String(p.get("callsign", callsign))
	bot_name = String(p.get("bot_name", callsign))
	name = "Bot_" + callsign.validate_node_name()
	team = String(p.get("team", team))
	ffa = bool(p.get("ffa", team == "FFA"))
	role = String(p.get("role", role))
	bot_index = int(p.get("index", bot_index))
	var d: Variant = p.get("difficulty", null)
	if d is Resource:
		difficulty = d
	elif d is String:
		difficulty = BotDifficultyScript.make(String(d))
	graph = p.get("graph", graph)
	match_ctrl = p.get("match", match_ctrl)
	paint_color = p.get("paint_color", paint_color)
	rig_team = String(p.get("rig_team", "ALPHA" if team == "ALPHA" else "BRAVO"))
	assigned_node = int(p.get("assigned_node", assigned_node))
	spawn_point = p.get("spawn", spawn_point)
	spawn_yaw = float(p.get("spawn_yaw", spawn_yaw))
	rng.seed = int(p.get("seed", hash(callsign)))
	habitual_peek_side = -1 if rng.randf() < 0.5 else 1
	peek_side = habitual_peek_side

func _ready() -> void:
	if difficulty == null:
		difficulty = BotDifficultyScript.make("rookie")
	add_to_group("pb_combatants")
	add_to_group("bot_players")
	var br: Resource = GearRuleEnforcer.active_bracket if GearRuleEnforcer != null else null
	if br != null:
		bracket_id = String(br.get("bracket_id"))
		max_bps = float(br.get("max_bps"))
		muzzle_fps = float(br.get("muzzle_fps"))
		base_spread_deg = MovementRules.bracket_base_spread_deg_for_mode(int(br.get("trigger_mode")))
	pro_rig = ProRigScript.new()
	pro_rig.name = "ProPaintballRig3D"
	add_child(pro_rig)
	pro_rig.build_rig(rig_team, bracket_id)
	hitboxes = pro_rig.build_sub_hitboxes_on(self) # torso capsule doubles as the feet-anchored movement capsule
	floor_snap_length = 0.3
	safe_margin = 0.02
	if spawn_point == Vector3.ZERO:
		spawn_point = global_position
	global_position = Vector3(spawn_point.x, 0.05, spawn_point.z)
	yaw = spawn_yaw
	rotation.y = yaw
	_perc_accum = (float(bot_index % 4) / 4.0) / PERCEPTION_HZ # stagger the 10 Hz raycasts across bots
	_pose(0.0)
	_enter(State.WAIT_HORN)

# ================================================================= main loop
func _physics_process(delta: float) -> void:
	clock += delta
	if _respawn_flash_timer > 0.0:
		_respawn_flash_timer = maxf(0.0, _respawn_flash_timer - delta)
	if is_eliminated:
		respawn_timer -= delta
		_pose(delta)
		if respawn_timer <= 0.0 and not GameManager.match_ended:
			respawn()
		return
	if GameManager.match_ended:
		has_move_goal = false
		burst_left = 0
	else:
		_perc_accum += delta
		if _perc_accum >= 1.0 / PERCEPTION_HZ:
			_perc_accum -= 1.0 / PERCEPTION_HZ
			perceive()
		_think(delta)
		_tick_fire(delta)
	_motor(delta)
	_pose(delta)

func _enter(s: int) -> void:
	state = s
	state_time = 0.0
	match s:
		State.HOLD:
			stance = MovementRules.STANCE_PRONE if _short_cover() else MovementRules.STANCE_CROUCHING
			hold_timer = rng.randf_range(difficulty.tuck_time_min, difficulty.tuck_time_max) * 0.6
			lean = 0.0
		State.TUCK:
			stance = MovementRules.STANCE_PRONE if _short_cover() else MovementRules.STANCE_CROUCHING
			hold_timer = rng.randf_range(difficulty.tuck_time_min, difficulty.tuck_time_max)
			lean = 0.0
			burst_left = 0
			_go_to(pocket_pos)
		State.PEEK:
			peek_timer = rng.randf_range(difficulty.peek_time_min, difficulty.peek_time_max)
			if difficulty.varies_peek_side:
				peek_side = -peek_side if rng.randf() < 0.65 else peek_side
			else:
				peek_side = habitual_peek_side
			target_seen_since = -1.0
			stance = MovementRules.STANCE_CROUCHING if _short_cover() else MovementRules.STANCE_STANDING
			_go_to(_peek_spot())
			lean = float(peek_side)
		State.BREAK, State.MOVE:
			stance = MovementRules.STANCE_STANDING
			lean = 0.0
			burst_left = 0

func _short_cover() -> bool:
	return graph != null and current_node >= 0 and float(graph.nodes[current_node]["height"]) < 1.2

func state_name() -> String:
	return STATE_NAMES[state]

# ================================================================= brain
func _threat_dir() -> Vector3:
	var from := global_position
	var tp := Vector3.ZERO
	var have := false
	if clock - last_seen_time < 6.0:
		tp = last_seen_pos
		have = true
	elif ffa:
		var n := _nearest_hostile(false)
		if n != null:
			tp = n.global_position
			have = true
	if not have:
		return Vector3(0, 0, -1) if team == "ALPHA" else Vector3(0, 0, 1)
	var d := tp - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.5 else Vector3(0, 0, -1)

func _think(delta: float) -> void:
	state_time += delta
	match state:
		State.WAIT_HORN:
			stance = MovementRules.STANCE_STANDING
			if GameManager.breakout_horn_sounded:
				_start_break()
		State.BREAK, State.MOVE:
			if not has_move_goal and slide_timer <= 0.0 and dive_timer <= 0.0:
				_arrived()
			elif state_time > 14.0:
				_arrived() # give up on a blocked run; fight from where we are
		State.HOLD:
			# a target with a line of sight on our pocket: snap at it from here
			if current_target != null:
				_try_engage()
			hold_timer -= delta
			if hold_timer <= 0.0:
				_enter(State.PEEK)
		State.PEEK:
			peek_timer -= delta
			if current_target != null:
				_try_engage()
			elif difficulty.suppresses and burst_left <= 0 and burst_pause <= 0.0 and clock - last_seen_time < SUPPRESS_MEMORY_S and not has_move_goal:
				_try_suppress()
			if peek_timer <= 0.0 and burst_left <= 0:
				_enter(State.TUCK)
		State.TUCK:
			hold_timer -= delta
			if hold_timer <= 0.0 and not has_move_goal:
				if _lane_safe() and rng.randf() < difficulty.move_chance and _pick_next_bunker():
					return
				_enter(State.HOLD)
				hold_timer = rng.randf_range(0.2, 0.6)

func _start_break() -> void:
	var target_node := assigned_node
	if target_node < 0 and graph != null:
		target_node = graph.nearest_node(global_position)
	_run_to_node(target_node, State.BREAK)

func _run_to_node(i: int, s: int) -> void:
	if graph == null or i < 0:
		pocket_pos = global_position
		_arrived()
		return
	current_node = i
	pocket_side = 0 if float(graph.nodes[i]["height"]) < 1.2 else (habitual_peek_side if not difficulty.varies_peek_side else (-1 if rng.randf() < 0.5 else 1))
	pocket_pos = _pocket_for(i)
	_enter(s)
	_go_to(pocket_pos)
	want_sprint = true
	path_exposure = graph.open_fraction(global_position, path) if not path.is_empty() else 0.0
	slide_planned = difficulty.can_slide and path_exposure >= SLIDE_EXPOSURE_MIN
	dive_planned = difficulty.can_dive and path_exposure >= 0.6 and rng.randf() < 0.5

func _pocket_for(i: int) -> Vector3:
	if ffa:
		return graph.pocket(i, _threat_dir_from(Vector3(graph.nodes[i]["pos"])), pocket_side)
	return graph.team_pocket(i, team, pocket_side)

func _threat_dir_from(p: Vector3) -> Vector3:
	var best: Node3D = null
	var best_d := INF
	for n in _combatants():
		if n == self or not _is_hostile(n) or not _is_alive(n):
			continue
		var d := (n as Node3D).global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return Vector3(0, 0, -1)
	var v := best.global_position - p
	v.y = 0.0
	return v.normalized() if v.length() > 0.5 else Vector3(0, 0, -1)

func _arrived() -> void:
	has_move_goal = false
	want_sprint = false
	if current_node == assigned_node and not reached_assigned:
		reached_assigned = true
		reached_assigned_at = clock
		arrival_error = Vector2(global_position.x - pocket_pos.x, global_position.z - pocket_pos.z).length()
	_enter(State.HOLD)

func _peek_spot() -> Vector3:
	if graph == null or current_node < 0:
		return global_position
	var td := _threat_dir() if not ffa else _threat_dir_from(global_position)
	if not ffa and clock - last_seen_time > 6.0:
		td = Vector3(0, 0, -1) if team == "ALPHA" else Vector3(0, 0, 1)
	if float(graph.nodes[current_node]["height"]) < 1.2:
		# short cover (snake / log): pop up from the low pocket instead of stepping out
		return pocket_pos
	return graph.peek_point(current_node, td, peek_side)

func _lane_safe() -> bool:
	return clock - last_seen_time > difficulty.safe_after_s and visible_targets.is_empty()

## Next bunker: forward progress toward the fight, minus edge exposure, minus bunkers a bot already holds.
func _pick_next_bunker() -> bool:
	if graph == null or current_node < 0:
		return false
	var goal := _fight_point()
	var here: Vector3 = graph.nodes[current_node]["pos"]
	var best := -1
	var best_score := -INF
	for j in graph.neighbors(current_node):
		var e: Dictionary = graph.edge_between(current_node, j)
		var there: Vector3 = graph.nodes[j]["pos"]
		var progress := here.distance_to(goal) - there.distance_to(goal)
		if progress < 1.0:
			continue
		var score := progress - float(e.get("exposure_score", 0.0)) * (6.0 if not difficulty.can_slide else 3.0)
		if _node_taken(j):
			score -= 20.0
		score += rng.randf_range(-1.5, 1.5)
		if score > best_score:
			best_score = score
			best = j
	if best < 0 or best_score < -2.0:
		return false
	_run_to_node(best, State.MOVE)
	return true

func _fight_point() -> Vector3:
	if clock - last_seen_time < 10.0:
		return last_seen_pos
	var n := _nearest_hostile(false)
	if n != null:
		return n.global_position
	return Vector3.ZERO

func _node_taken(j: int) -> bool:
	for b in get_tree().get_nodes_in_group("bot_players"):
		if b != self and int(b.get("current_node")) == j and not bool(b.get("is_eliminated")):
			return true
	return false

# ================================================================= perception (10 Hz, staggered)
func _combatants() -> Array:
	if match_ctrl != null and match_ctrl.has_method("combatants"):
		return match_ctrl.call("combatants")
	return get_tree().get_nodes_in_group("pb_combatants") if is_inside_tree() else []

static func team_of(n: Node) -> String:
	if n == null:
		return ""
	if "team" in n:
		return String(n.get("team"))
	if n.has_method("award_kill_bonus_pod"):
		return NetworkLobby.local_team
	return ""

func _is_hostile(n: Node) -> bool:
	if n == self or n == null:
		return false
	if ffa:
		return true
	var t := team_of(n)
	return t != team or t == "FFA"

static func _is_alive(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
		return false
	if "is_eliminated" in n and bool(n.get("is_eliminated")):
		return false
	if "awaiting_respawn_choice" in n and bool(n.get("awaiting_respawn_choice")):
		return false
	if "spectating" in n and bool(n.get("spectating")):
		return false
	if "_respawn_flash_timer" in n and float(n.get("_respawn_flash_timer")) > 0.2:
		return false # spawn protection: not worth a ball
	return (n as Node3D).is_visible_in_tree()

func _nearest_hostile(require_visible: bool) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var pool: Array = visible_targets if require_visible else _combatants()
	for n in pool:
		if not _is_hostile(n) or not _is_alive(n):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func eye_position() -> Vector3:
	return global_position + Vector3(0.0, MovementRules.eye_height(slide_timer, dive_timer, stance), 0.0)

static func aim_points_of(n: Node3D) -> Array:
	var pts: Array = []
	var mask := n.get_node_or_null("Hitbox_Mask") as Node3D
	if mask != null:
		pts.append(mask.global_position)
	var torso := n.get_node_or_null("Hitbox_Torso") as Node3D
	if torso != null:
		pts.append(torso.global_position + Vector3(0, 0.15, 0))
	if pts.is_empty():
		pts.append(n.global_position + Vector3(0, 1.3, 0))
		pts.append(n.global_position + Vector3(0, 0.8, 0))
	return pts

## Ray from `from` to `to` (self excluded). True when it reaches `target` (or nothing blocks the point).
func has_los(from: Vector3, to: Vector3, target: Node = null) -> bool:
	if not is_inside_tree():
		return false
	los_rays_cast += 1
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col: Object = hit.get("collider")
	if target != null and (col == target or (col is Node and (target as Node).is_ancestor_of(col))):
		return true
	return (hit["position"] as Vector3).distance_to(to) < 0.35

func perceive() -> void:
	perception_ticks += 1
	visible_targets.clear()
	var eye := eye_position()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var cone_cos := cos(deg_to_rad(VIEW_CONE_DEG * 0.5))
	for n in _combatants():
		if not _is_hostile(n) or not _is_alive(n):
			continue
		var tn := n as Node3D
		var v := tn.global_position - global_position
		v.y = 0.0
		var dist := v.length()
		if dist > VIEW_RANGE:
			continue
		if dist > 3.0 and fwd.dot(v / maxf(dist, 0.001)) < cone_cos:
			continue
		for ap in aim_points_of(tn):
			if has_los(eye, ap, tn):
				visible_targets.append(tn)
				break
	var nearest := _nearest_hostile(true)
	if nearest != current_target:
		current_target = nearest
		target_seen_since = clock if nearest != null else -1.0
	if current_target != null and target_seen_since < 0.0:
		target_seen_since = clock
	if current_target != null:
		last_seen_pos = current_target.global_position
		last_seen_time = clock
		if graph != null:
			last_seen_node = graph.nearest_node(last_seen_pos, 4.0)

# ================================================================= shooting
func _try_engage() -> void:
	if current_target == null or burst_left > 0 or burst_pause > 0.0:
		return
	if target_seen_since < 0.0 or clock - target_seen_since < difficulty.reaction_s:
		return
	if MovementRules.is_fire_locked(slide_timer, dive_timer, movement_fire_recovery_timer):
		return
	_start_burst("snap")

func _try_suppress() -> void:
	if last_seen_node < 0 or graph == null:
		return
	# keep the lane busy: aim at the bunker edge the target tucked behind, not at the player
	var r: Rect2 = graph.nodes[last_seen_node]["rect"]
	var me := Vector2(global_position.x, global_position.z)
	var c := r.get_center()
	var to_me := (me - c).normalized()
	var lat := Vector2(-to_me.y, to_me.x)
	var half := r.size * 0.5
	var width := absf(lat.x) * half.x + absf(lat.y) * half.y
	var s := 1.0 if (Vector2(last_seen_pos.x, last_seen_pos.z) - c).dot(lat) >= 0.0 else -1.0
	var edge := c + lat * s * (width + 0.25) + to_me * (absf(to_me.x) * half.x + absf(to_me.y) * half.y)
	look_point = Vector3(edge.x, 1.25, edge.y)
	has_look_point = true
	_start_burst("suppress")

func _start_burst(kind: String) -> void:
	burst_kind = kind
	burst_left = rng.randi_range(difficulty.burst_min, difficulty.burst_max)
	shot_cd = 0.0
	# aim error is sampled once per burst (a consistent miss, not a shotgun)
	var tp := _aim_point()
	var rng_m := eye_position().distance_to(tp)
	var err: float = difficulty.aim_error_at(rng_m)
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * err
	aim_offset = Vector3(cos(a) * r, sin(a) * r * 0.6, sin(a) * r * 0.4)

func _aim_point() -> Vector3:
	if burst_kind == "snap" and current_target != null and is_instance_valid(current_target):
		var pts := aim_points_of(current_target)
		return pts[pts.size() - 1] if pts.size() > 1 else pts[0]
	return look_point

func _muzzle() -> Vector3:
	if pro_rig != null and pro_rig.get("muzzle_tip_node") != null:
		return (pro_rig.get("muzzle_tip_node") as Node3D).global_position
	return eye_position() + Vector3(-sin(yaw), -0.15, -cos(yaw)) * 0.5

func _tick_fire(delta: float) -> void:
	if burst_pause > 0.0:
		burst_pause -= delta
	if burst_left <= 0:
		return
	shot_cd -= delta
	if shot_cd > 0.0:
		return
	if MovementRules.is_fire_locked(slide_timer, dive_timer, movement_fire_recovery_timer):
		return
	if burst_kind == "snap" and (current_target == null or not _is_alive(current_target)):
		burst_left = 0
		return
	var aim := _aim_point() + aim_offset
	var origin := _muzzle()
	# fire only with a line of sight: snap -> to the target itself, suppress -> to the bunker-edge aim point
	var los_target: Node = current_target if burst_kind == "snap" else null
	var los_ok := has_los(eye_position(), _aim_point(), los_target)
	if not los_ok:
		shots_blocked_no_los += 1
		burst_left = 0
		burst_pause = 0.3
		return
	var dir := (aim - origin).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	var up := right.cross(dir).normalized()
	var spread := base_spread_deg * shot_spread_mult
	var shot_dir := MovementRules.apply_spread_cone(dir, right, up, spread)
	PaintBallistics.spawn_paintball(origin, shot_dir, muzzle_fps, self, paint_color)
	shots_fired += 1
	if burst_kind == "snap":
		snap_shots += 1
	else:
		suppress_shots += 1
	shot_fired.emit(self, origin, aim, burst_kind)
	burst_left -= 1
	shot_cd = difficulty.shot_interval(max_bps)
	if burst_left <= 0:
		burst_pause = rng.randf_range(difficulty.burst_pause_min, difficulty.burst_pause_max)

# ================================================================= motor (MovementRules)
func _go_to(p: Vector3) -> void:
	move_goal = Vector3(p.x, 0.0, p.z)
	has_move_goal = true
	_stuck_timer = 0.0
	_stuck_ref = global_position
	_replans = 0
	_replan()

func _replan() -> void:
	path = graph.plan_path(global_position, move_goal) if graph != null else PackedVector3Array([move_goal])
	if path.is_empty():
		path = PackedVector3Array([move_goal])
	path_i = 0

func _motor(delta: float) -> void:
	# --- timers (identical windows to the player)
	if movement_fire_recovery_timer > 0.0 and slide_timer <= 0.0 and dive_timer <= 0.0:
		movement_fire_recovery_timer = maxf(0.0, movement_fire_recovery_timer - delta)
	var move_dir := Vector3.ZERO
	var sprint := false
	if has_move_goal and not is_eliminated:
		var flat := Vector3(global_position.x, 0.0, global_position.z)
		while path_i < path.size() and flat.distance_to(path[path_i]) < ARRIVE_DIST and path_i < path.size() - 1:
			path_i += 1
		var wp := path[mini(path_i, path.size() - 1)]
		var to := wp - flat
		var dist_goal := flat.distance_to(move_goal)
		if dist_goal < ARRIVE_DIST:
			has_move_goal = false
		else:
			move_dir = to.normalized()
			sprint = want_sprint and (state == State.BREAK or state == State.MOVE)
			# Amateur+: knee-slide (or Pro dive) into the pocket across an exposed final edge
			if sprint and path_i >= path.size() - 1 and slide_timer <= 0.0 and dive_timer <= 0.0 and ground_speed > MovementRules.WALK_SPEED \
					and dist_goal > SLIDE_TRIGGER_MIN and dist_goal < SLIDE_TRIGGER_MAX:
				if dive_planned:
					dive_timer = MovementRules.DIVE_DURATION
					slide_dir = move_dir
					dives_done += 1
					dive_planned = false
				elif slide_planned:
					slide_timer = MovementRules.SLIDE_DURATION
					slide_dir = move_dir
					slides_done += 1
					slide_planned = false
		# stuck: replan, then sidestep, then give up
		_stuck_timer += delta
		if _stuck_timer > 1.0:
			if global_position.distance_to(_stuck_ref) < 0.4 and slide_timer <= 0.0 and dive_timer <= 0.0:
				_replans += 1
				if _replans > 3:
					has_move_goal = false
				else:
					_replan()
			_stuck_timer = 0.0
			_stuck_ref = global_position
	# --- facing: fight target > look point > movement
	var face := Vector3.ZERO
	if current_target != null and is_instance_valid(current_target) and (state == State.PEEK or state == State.HOLD or burst_left > 0):
		face = current_target.global_position - global_position
	elif burst_left > 0 and has_look_point:
		face = look_point - global_position
	elif move_dir.length() > 0.1 and (state == State.BREAK or state == State.MOVE):
		face = move_dir
	elif state == State.HOLD or state == State.PEEK or state == State.TUCK:
		face = _threat_dir()
	face.y = 0.0
	if face.length() > 0.05:
		var want := atan2(-face.x, -face.z)
		yaw = rotate_toward(yaw, want, TURN_RATE * delta)
		rotation.y = yaw
	# --- slide / dive (player numbers)
	if dive_timer > 0.0:
		dive_timer -= delta
		var dspd := MovementRules.dive_speed(dive_timer)
		velocity.x = slide_dir.x * dspd
		velocity.z = slide_dir.z * dspd
		if dive_timer <= 0.0:
			dive_timer = 0.0
			movement_fire_recovery_timer = MovementRules.MOVEMENT_FIRE_RECOVERY
			stance = MovementRules.STANCE_PRONE
			ground_speed = 0.0
	elif slide_timer > 0.0:
		slide_timer -= delta
		var sspd := MovementRules.slide_speed(slide_timer)
		velocity.x = slide_dir.x * sspd
		velocity.z = slide_dir.z * sspd
		if slide_timer <= 0.0:
			slide_timer = 0.0
			movement_fire_recovery_timer = MovementRules.MOVEMENT_FIRE_RECOVERY
			stance = MovementRules.STANCE_CROUCHING
			ground_speed = 0.0
	else:
		var local_in := Vector2.ZERO
		if move_dir.length() > 0.1:
			var l := Basis(Vector3.UP, yaw).inverse() * move_dir
			local_in = Vector2(l.x, l.z).normalized()
		var target_speed := MovementRules.gait_target_speed(local_in, sprint, stance) if local_in.length() > 0.1 else 0.0
		var speed_mult := 1.0 if GameManager.breakout_horn_sounded else 0.18
		ground_speed = MovementRules.step_ground_speed(ground_speed, target_speed, speed_mult, delta)
		var dir := move_dir if move_dir.length() > 0.1 else Vector3(velocity.x, 0.0, velocity.z).normalized()
		velocity.x = dir.x * ground_speed
		velocity.z = dir.z * ground_speed
		if has_move_goal and stance == MovementRules.STANCE_PRONE:
			stance = MovementRules.STANCE_CROUCHING
	if is_on_floor():
		velocity.y = maxf(velocity.y, -0.5)
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	if is_inside_tree():
		move_and_slide()
	distance_moved += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	# keep inside the netting
	global_position.x = clampf(global_position.x, -51.5, 51.5)
	global_position.z = clampf(global_position.z, -63.5, 63.5)
	if global_position.y < -5.0:
		global_position = Vector3(global_position.x, 0.1, global_position.z)
		velocity = Vector3.ZERO
	# --- spread cone: same target / bloom / recovery as the player
	var in_pocket := (state == State.HOLD or state == State.TUCK or state == State.PEEK) and global_position.distance_to(pocket_pos) < 1.6
	var sliding_or_diving := slide_timer > 0.0 or dive_timer > 0.0
	var airborne := not sliding_or_diving and is_inside_tree() and not is_on_floor()
	var tgt := MovementRules.target_spread_mult(in_pocket, stance, ground_speed, sliding_or_diving, airborne)
	shot_spread_mult = MovementRules.step_spread_mult(shot_spread_mult, tgt, delta)

func _pose(delta: float) -> void:
	if pro_rig == null:
		return
	var tuck := 1.0 if (state == State.HOLD or state == State.TUCK) and not has_move_goal else 0.0
	pro_rig.apply_pose(delta, {
		"velocity": velocity,
		"stance": stance,
		"lean": lean * (1.0 if state == State.PEEK else 0.0),
		"is_left_handed": peek_side < 0,
		"bunker_tuck": tuck,
		"is_sliding": slide_timer > 0.0,
		"is_diving": dive_timer > 0.0,
		"is_reloading": false,
		"is_eliminated": is_eliminated,
		"team": rig_team,
		"bracket": bracket_id,
	})

func get_stance_capsule_target() -> float:
	return MovementRules.stance_capsule_target(slide_timer, dive_timer, stance)

func is_fire_locked_by_movement() -> bool:
	return MovementRules.is_fire_locked(slide_timer, dive_timer, movement_fire_recovery_timer)

# ================================================================= hits / elimination (existing paint path)
func resolve_hit_subzone(world_hit_pos: Vector3) -> Dictionary:
	var h_col := get_node_or_null("Hitbox_HopperMarker") as Node3D
	if h_col != null and world_hit_pos.distance_to(h_col.global_position) <= 0.30:
		return {"zone": "HOPPER / MARKER", "bounce_cos_threshold": 0.28}
	var m_col := get_node_or_null("Hitbox_Mask") as Node3D
	if m_col != null and world_hit_pos.distance_to(m_col.global_position) <= 0.26:
		return {"zone": "MASK / GOGGLES", "bounce_cos_threshold": 0.28}
	var p_col := get_node_or_null("Hitbox_PodPack") as Node3D
	if p_col != null and world_hit_pos.distance_to(p_col.global_position) <= 0.28:
		return {"zone": "POD PACK", "bounce_cos_threshold": 0.32}
	return {"zone": "TORSO / JERSEY", "bounce_cos_threshold": 0.48}

func on_paintball_break(hit_pos: Vector3, shooter: Node) -> void:
	if is_eliminated or _respawn_flash_timer > 0.2 or GameManager.match_ended:
		return
	var zone := String(resolve_hit_subzone(hit_pos).get("zone", "TORSO / JERSEY"))
	var by := "?"
	if shooter != null and is_instance_valid(shooter):
		if "bot_name" in shooter:
			by = String(shooter.get("bot_name"))
		elif shooter.has_method("award_kill_bonus_pod"):
			by = NetworkLobby.local_callsign
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("award_kill_bonus_pod"):
		shooter.call("award_kill_bonus_pod", "%s [%s]" % [bot_name, zone])
		local_hit_markers_shown += 1
		MovementAudioDirector.show_local_hit_marker() # only the local player's own ball gets the marker
	_die()
	IntelBus.intel_feed_updated.emit("%s SPLATTED %s [%s]" % [by.to_upper(), bot_name.to_upper(), zone])
	if shooter != null and is_instance_valid(shooter) and shooter != self and "kills" in shooter and shooter.has_method("on_paintball_break"):
		shooter.set("kills", int(shooter.get("kills")) + 1)
	bot_eliminated.emit(self, shooter, zone)
	if match_ctrl != null and match_ctrl.has_method("on_bot_eliminated"):
		match_ctrl.call("on_bot_eliminated", self, shooter)
	else:
		GameManager.notify_enemy_eliminated()

func on_paintball_bounce(_hit_pos: Vector3) -> void:
	pass

func _die() -> void:
	is_eliminated = true
	deaths += 1
	respawn_timer = RESPAWN_DELAY
	state = State.DEAD
	has_move_goal = false
	burst_left = 0
	slide_timer = 0.0
	dive_timer = 0.0
	velocity = Vector3.ZERO
	ground_speed = 0.0
	current_target = null
	visible_targets.clear()
	collision_layer = 0 # balls and runners pass through the "dead man walking"
	collision_mask = 1
	visible = true

func respawn() -> void:
	var p := spawn_point
	var y := spawn_yaw
	if match_ctrl != null and match_ctrl.has_method("respawn_point_for"):
		var r: Dictionary = match_ctrl.call("respawn_point_for", self)
		p = r.get("pos", p)
		y = float(r.get("yaw", y))
	is_eliminated = false
	collision_layer = 1
	collision_mask = 1
	global_position = Vector3(p.x, 0.05, p.z)
	velocity = Vector3.ZERO
	ground_speed = 0.0
	yaw = y
	rotation.y = y
	stance = MovementRules.STANCE_STANDING
	last_seen_time = -1000.0
	target_seen_since = -1.0
	reached_assigned = false
	_respawn_flash_timer = SPAWN_PROTECT_S
	if graph != null:
		assigned_node = _respawn_bunker()
	bot_respawned.emit(self)
	_start_break()

## After a respawn: the closest bunker of this bot's role (FFA has no sides), else the closest bunker.
func _respawn_bunker() -> int:
	var best := -1
	var best_d := INF
	for i in graph.role_nodes(role, "" if ffa else team):
		var d: float = global_position.distance_to(graph.nodes[i]["pos"])
		if d < best_d and not _node_taken(i):
			best_d = d
			best = i
	return best if best >= 0 else graph.nearest_node(global_position)
