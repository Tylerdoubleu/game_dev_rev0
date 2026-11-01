extends Node
## v0.7 solo career (Bluey): rides along one career match (child of the SoloFfaMatch / GauntletRun node, so it is
## freed with it) and builds the result CareerEval judges:
##   style_kills  your eliminations made while sliding / diving or within CareerEval.STYLE_WINDOW_S after one ended
##                (the marker can't fire mid-slide, so "dive kill" = the shot right out of the dive)
##   zone_kills   your eliminations fired from inside the challenge zone (e.g. the Cake, 5 m)
## finished(result) fires once when the match / run ends.

const Eval = preload("res://scripts/career/career_eval.gd")

signal finished(result: Dictionary)

var challenge: Dictionary = {}
var match_node: Node = null
var player: Node = null
var style_kills: int = 0
var zone_kills: int = 0
var kills_seen: int = 0
var clock: float = 0.0
var last_move_t: float = -1000.0
var done: bool = false

func setup(c: Dictionary, m: Node, p: Node) -> void:
	challenge = c
	match_node = m
	player = p
	name = "CareerTracker"
	if m.has_signal("kill_logged"):
		m.connect("kill_logged", _on_kill_logged)
	if m.has_signal("ffa_match_over"):
		m.connect("ffa_match_over", func(_w: String) -> void: _finish())
	if m.has_signal("finished"):
		m.connect("finished", func(_r: Dictionary) -> void: _finish())

func _physics_process(delta: float) -> void:
	clock += delta
	if player != null and is_instance_valid(player) and moving_flashy(player):
		last_move_t = clock

static func moving_flashy(p: Object) -> bool:
	return ("slide_timer" in p and float(p.get("slide_timer")) > 0.0) or ("dive_timer" in p and float(p.get("dive_timer")) > 0.0)

func _on_kill_logged(e: Dictionary) -> void:
	if not bool(e.get("by_player", false)):
		return
	kills_seen += 1
	var flashy := player != null and is_instance_valid(player) and moving_flashy(player)
	if flashy:
		last_move_t = clock
	if flashy or clock - last_move_t <= Eval.STYLE_WINDOW_S:
		style_kills += 1
	var z: Dictionary = challenge.get("zone", {})
	if not z.is_empty() and player != null and is_instance_valid(player) and player is Node3D:
		if in_zone((player as Node3D).global_position, z):
			zone_kills += 1

static func in_zone(pos: Vector3, z: Dictionary) -> bool:
	var c: Vector3 = z.get("center", Vector3.ZERO)
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= float(z.get("radius", 5.0))

func _finish() -> void:
	if done:
		return
	done = true
	finished.emit(result())

func result() -> Dictionary:
	var kind := String(challenge.get("kind", "tdm"))
	if match_node != null and is_instance_valid(match_node) and match_node.has_method("result"):
		var r: Dictionary = match_node.call("result")
		r["kind"] = kind
		return r
	var r := {"kind": kind, "won": false, "kills": 0, "deaths": 0, "style_kills": style_kills, "zone_kills": zone_kills,
		"rounds_won": 0, "rounds_lost": 0, "time_s": snappedf(clock, 0.01)}
	if match_node != null and is_instance_valid(match_node):
		r["won"] = bool(match_node.call("player_won")) if match_node.has_method("player_won") else false
		var pn := String(match_node.get("_player_name")) if "_player_name" in match_node else ""
		var scores: Dictionary = match_node.get("scores") if "scores" in match_node else {}
		if scores.has(pn):
			r["kills"] = int(scores[pn]["kills"])
			r["deaths"] = int(scores[pn]["deaths"])
		if "rounds_won" in match_node:
			r["rounds_won"] = int(match_node.get("rounds_won"))
			r["rounds_lost"] = int(match_node.get("rounds_lost"))
		if match_node.has_method("team_scores"):
			var t: Dictionary = match_node.call("team_scores")
			r["team_you"] = int(t.get("you", 0))
			r["team_bots"] = int(t.get("bots", 0))
	return r
