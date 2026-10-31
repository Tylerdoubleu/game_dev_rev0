extends SceneTree
## v0.7 BunkerGraph (Bluey): built from the bunker_callouts speedball bunkers; left / right / low pockets, edges with an
## exposure score, A* paths that avoid bunkers, role primaries per side.
## Run: godot --headless --path . -s scripts/systems/test_bunker_graph.gd

var BunkerGraphScript: GDScript # loaded in _initialize (after the autoloads exist)
var arena: Node3D
var failures: Array[String] = []
var started := false

func _initialize() -> void:
	BunkerGraphScript = load("res://scripts/bots/bunker_graph.gd")
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

func _run() -> void:
	for i in 3:
		await physics_frame
	var t0 := Time.get_ticks_msec()
	var g: RefCounted = BunkerGraphScript.build(arena, "speedball")
	var ms := Time.get_ticks_msec() - t0
	var callouts: Array = load("res://scripts/systems/bunker_callouts.gd").scan_bunkers(arena, "speedball")
	_check(g.nodes.size() == callouts.size() and g.nodes.size() >= 40, "one node per callout bunker (%d)" % g.nodes.size())
	_check(g.edges.size() > g.nodes.size(), "edges built (%d)" % g.edges.size())
	_check(ms < 1500, "build is fast enough for a match start (%d ms)" % ms)
	var bad_exp := 0
	var bad_path := 0
	for e in g.edges:
		var x: float = e["exposure"]
		if x < 0.0 or x > 1.0 or not is_equal_approx(float(e["exposure_score"]), x * float(e["length"]) / 10.0):
			bad_exp += 1
		if (e["path"] as PackedVector3Array).is_empty():
			bad_path += 1
	_check(bad_exp == 0, "edge exposure = open fraction in [0, 1]; score = exposed metres / 10")
	_check(bad_path == 0, "every edge has a walkable path")
	var lone := 0
	for i in g.nodes.size():
		if g.neighbors(i).is_empty():
			lone += 1
	_check(lone == 0, "every bunker has a neighbour")
	var bad_pockets: Array = []
	for i in g.nodes.size():
		for side in [-1, 0, 1]:
			var p: Vector3 = g.team_pocket(i, "ALPHA", side)
			if g.is_blocked(p):
				bad_pockets.append("%s/%d" % [g.nodes[i]["callout"], side])
	_check(bad_pockets.is_empty(), "left / low / right pockets are standable %s" % str(bad_pockets.slice(0, 6)))
	var i_sc: int = g.index_of_callout("Red Snake Corner")
	if i_sc >= 0:
		var c: Vector3 = g.nodes[i_sc]["pos"]
		var l: Vector3 = g.team_pocket(i_sc, "ALPHA", -1)
		var r: Vector3 = g.team_pocket(i_sc, "ALPHA", 1)
		_check(l.x < r.x and l.z > c.z - 0.5, "ALPHA pockets: left is -X, behind the bunker (+Z)")
	for team in ["ALPHA", "BRAVO"]:
		for role in ["front", "mid", "back"]:
			var n: int = g.primary_for(role, team, 0)
			_check(n >= 0 and BunkerGraphScript.role_of_callout(String(g.nodes[n]["callout"])) == role, "%s %s primary: %s" % [team, role, g.nodes[n]["callout"] if n >= 0 else "-"])
	var path: PackedVector3Array = g.plan_path(Vector3(0, 0, 45.5), Vector3(0, 0, -45.5))
	var clear := true
	for k in range(path.size() - 1):
		if not g.segment_clear(path[k], path[k + 1]):
			clear = false
	_check(path.size() >= 2 and clear, "gate-to-gate path avoids every bunker (%d pts, %.0f m)" % [path.size(), g.path_length(Vector3(0, 0, 45.5), path)])
	var any_blocked := false
	for n in g.nodes:
		if g.is_blocked(n["pos"]):
			any_blocked = true
			break
	_check(any_blocked, "bunker footprints are solid in the grid")
	var open_e: float = 0.0
	var covered_e: float = 1.0
	for e in g.edges:
		open_e = maxf(open_e, e["exposure_score"])
		covered_e = minf(covered_e, e["exposure_score"])
	_check(open_e > covered_e + 0.2, "exposure varies by lane (%.2f .. %.2f)" % [covered_e, open_e])
	if failures.is_empty():
		print("BUNKER GRAPH TEST: ALL PASSED")
		quit(0)
	else:
		print("BUNKER GRAPH TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
