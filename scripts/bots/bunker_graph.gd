extends RefCounted
## v0.7 bunker graph for BotPlayer navigation (plan "Smarter bots" > Bunker graph).
## Nodes: every named bunker from bunker_callouts.gd (scan_bunkers), each with left / right / low pockets for a threat
## direction. Edges: runnable paths between nearby bunkers (grid A* around the real collision footprints, so a path never
## clips a bunker) with an exposure score = share of the run that is open ground (> OPEN_CLEARANCE from any cover),
## weighted by length. Built once per arena; paths come from an AStarGrid2D over the rasterised obstacle footprints
## (C++ A*, cheap enough for the web build) instead of a baked NavigationRegion3D.

const BunkerCalloutsScript = preload("res://scripts/systems/bunker_callouts.gd")

const CELL: float = 0.5
const AGENT_RADIUS: float = 0.5 # inflate footprints by the bot's torso + a hair
const POCKET_GAP: float = 0.55 # how far behind the bunker face a pocket sits (body centre)
const OPEN_CLEARANCE: float = 1.8
const EDGE_MAX_DIST: float = 26.0
const EDGE_NEIGHBORS: int = 6
const EDGE_MAX_DETOUR: float = 1.6

const ROLE_FRONT := "front"
const ROLE_MID := "mid"
const ROLE_BACK := "back"
const ROLE_BASES := {
	ROLE_FRONT: ["Snake Corner", "God Can", "Dorito 1", "Dorito 2", "Dorito 3", "Snake 1", "Snake 2", "Snake 3", "Snake 4", "Snake 50", "50 Dorito"],
	ROLE_MID: ["Cake", "Snake Can", "Dorito Can", "Snake Temple", "Dorito Temple", "Snake Pin", "Dorito Pin", "Snake Wedge", "Dorito Wedge", "Snake Tree", "Dorito Tree", "Center", "Snake Mini", "Dorito Mini", "Snake Insert", "Dorito Insert"],
	ROLE_BACK: ["Home", "Back Center", "Home Can", "Back Can", "Log", "Snake Brick", "Dorito Brick"],
}
## Plan primaries per role, in fill order (team-prefixed with Red / Blue).
const ROLE_PRIMARIES := {
	ROLE_FRONT: ["Snake Corner", "Dorito 1", "God Can", "Dorito 2"],
	ROLE_MID: ["Cake", "Snake Can", "Dorito Can", "Snake Temple", "Dorito Temple"],
	ROLE_BACK: ["Back Center", "Back Can", "Home Can", "Home"],
}

## Arena half-extents (speedball netting is at x +-52.4, z +-64.4).
var bounds_min := Vector2(-52.0, -64.0)
var bounds_max := Vector2(52.0, 64.0)
var map_id: String = "speedball"

var nodes: Array = [] # [{id, callout, pos: Vector3, rect: Rect2 (XZ footprint), height}]
var node_index := {} # id -> index
var edges: Array = [] # [{a, b, length, straight, exposure, exposure_score, path: PackedVector3Array}]
var adjacency := {} # index -> Array[edge index]
var obstacles: Array[Rect2] = [] # XZ footprints of every blocking body (not inflated)
var grid := AStarGrid2D.new()

static func build(arena: Node, p_map_id: String = "speedball") -> RefCounted:
	var script: GDScript = load("res://scripts/bots/bunker_graph.gd")
	var g: RefCounted = script.new()
	g.map_id = p_map_id
	g._collect(arena)
	g._build_grid()
	g._build_edges()
	return g

# ---------------------------------------------------------------- footprints
func _collect(arena: Node) -> void:
	nodes.clear()
	node_index.clear()
	obstacles.clear()
	if arena == null:
		return
	var seen := {}
	for e in BunkerCalloutsScript.scan_bunkers(arena, map_id):
		var n := e["node"] as Node3D
		var rect := _footprint_of(n)
		if rect.size == Vector2.ZERO:
			continue
		var id := String(n.name)
		if node_index.has(id):
			continue
		node_index[id] = nodes.size()
		nodes.append({"id": id, "callout": String(e["callout"]), "pos": Vector3(rect.get_center().x, 0.0, rect.get_center().y), "rect": rect, "height": _height_of(n)})
	_collect_obstacles(arena, 0, seen)

func _collect_obstacles(n: Node, depth: int, seen: Dictionary) -> void:
	for c in n.get_children():
		if c.get_script() != null and depth > 0:
			continue
		if c is StaticBody3D and c.get_script() == null:
			var nm := String(c.name)
			if nm == "TurfFloor" or nm.begins_with("Walkable") or nm.begins_with("Ramp_") or nm.begins_with("TowerFloor_") or nm.begins_with("SafetyNet") or nm.begins_with("RemotePlayer"):
				continue
			var lo_hi := _y_range_of(c as Node3D)
			if lo_hi.y < 0.45 or lo_hi.x > 1.2:
				continue # floor decals / overhead beams do not block a runner
			var rect := _footprint_of(c as Node3D)
			if rect.size == Vector2.ZERO or rect.size.x > 30.0 or rect.size.y > 30.0:
				continue # perimeter netting is handled by the bounds
			if not seen.has(c.get_instance_id()):
				seen[c.get_instance_id()] = true
				obstacles.append(rect)
		elif depth < 3 and c is Node3D and c.get_script() == null:
			_collect_obstacles(c, depth + 1, seen)

static func _shape_points(cs: CollisionShape3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var s := cs.shape
	if s is BoxShape3D:
		var h: Vector3 = (s as BoxShape3D).size * 0.5
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					pts.append(Vector3(h.x * x, h.y * y, h.z * z))
	elif s is CylinderShape3D:
		var r: float = (s as CylinderShape3D).radius
		var hh: float = (s as CylinderShape3D).height * 0.5
		for x in [-r, r]:
			for y in [-hh, hh]:
				for z in [-r, r]:
					pts.append(Vector3(x, y, z))
	elif s is CapsuleShape3D:
		var r2: float = (s as CapsuleShape3D).radius
		var hh2: float = (s as CapsuleShape3D).height * 0.5
		for x in [-r2, r2]:
			for y in [-hh2, hh2]:
				for z in [-r2, r2]:
					pts.append(Vector3(x, y, z))
	elif s is SphereShape3D:
		var r3: float = (s as SphereShape3D).radius
		for x in [-r3, r3]:
			for y in [-r3, r3]:
				for z in [-r3, r3]:
					pts.append(Vector3(x, y, z))
	elif s is ConvexPolygonShape3D:
		pts = (s as ConvexPolygonShape3D).points
	var out := PackedVector3Array()
	var xf := cs.global_transform if cs.is_inside_tree() else _accum_xform(cs)
	for p in pts:
		out.append(xf * p)
	return out

static func _accum_xform(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

static func _shapes_under(n: Node, out: Array, depth: int = 0) -> void:
	for c in n.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled and (c as CollisionShape3D).shape != null:
			out.append(c)
		elif depth < 3:
			_shapes_under(c, out, depth + 1)

static func _footprint_of(n: Node3D) -> Rect2:
	var shapes: Array = []
	_shapes_under(n, shapes)
	var have := false
	var r := Rect2()
	for cs in shapes:
		for p in _shape_points(cs):
			var q := Vector2(p.x, p.z)
			if not have:
				r = Rect2(q, Vector2.ZERO)
				have = true
			else:
				r = r.expand(q)
	return r if have else Rect2()

static func _y_range_of(n: Node3D) -> Vector2:
	var shapes: Array = []
	_shapes_under(n, shapes)
	var lo := INF
	var hi := -INF
	for cs in shapes:
		for p in _shape_points(cs):
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return Vector2(lo, hi) if lo <= hi else Vector2(0.0, 0.0)

static func _height_of(n: Node3D) -> float:
	return _y_range_of(n).y

# ---------------------------------------------------------------- grid
func _build_grid() -> void:
	var size := Vector2i(int(ceil((bounds_max.x - bounds_min.x) / CELL)) + 1, int(ceil((bounds_max.y - bounds_min.y) / CELL)) + 1)
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = bounds_min
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for r in obstacles:
		var g := (r as Rect2).grow(AGENT_RADIUS)
		var c0 := _to_cell(g.position)
		var c1 := _to_cell(g.end)
		for i in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			for j in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
				if g.has_point(_cell_pos(Vector2i(i, j))):
					grid.set_point_solid(Vector2i(i, j), true)

func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(round((p.x - bounds_min.x) / CELL)), int(round((p.y - bounds_min.y) / CELL)))

func _cell_pos(c: Vector2i) -> Vector2:
	return bounds_min + Vector2(c) * CELL

func _in_grid(c: Vector2i) -> bool:
	return grid.region.has_point(c)

func is_blocked(p: Vector3) -> bool:
	var c := _to_cell(Vector2(p.x, p.z))
	return not _in_grid(c) or grid.is_point_solid(c)

## Nearest free grid cell to a world point (spiral search), as a world point.
func nearest_free(p: Vector3, max_r: int = 12) -> Vector3:
	var c := _to_cell(Vector2(p.x, p.z))
	c = Vector2i(clampi(c.x, 0, grid.region.size.x - 1), clampi(c.y, 0, grid.region.size.y - 1))
	if not grid.is_point_solid(c):
		return Vector3(p.x, 0.0, p.z) if _in_grid(_to_cell(Vector2(p.x, p.z))) else _v3(_cell_pos(c))
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for i in range(-r, r + 1):
			for j in range(-r, r + 1):
				if maxi(absi(i), absi(j)) != r:
					continue
				var q := c + Vector2i(i, j)
				if _in_grid(q) and not grid.is_point_solid(q):
					var d := _cell_pos(q).distance_squared_to(Vector2(p.x, p.z))
					if d < best_d:
						best_d = d
						best = q
		if best.x >= 0:
			return _v3(_cell_pos(best))
	return Vector3(p.x, 0.0, p.z)

static func _v3(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)

## Straight run between two points stays out of every inflated footprint.
func segment_clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := maxi(1, int(ceil(d.length() / (CELL * 0.5))))
	for k in range(n + 1):
		var t := float(k) / float(n)
		var c := _to_cell(Vector2(a.x, a.z) + d * t)
		if not _in_grid(c) or grid.is_point_solid(c):
			return false
	return true

## Waypoints (XZ, y = 0) from a to b around the cover, string-pulled. Empty when unreachable.
func plan_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sa := nearest_free(a)
	var sb := nearest_free(b)
	if segment_clear(sa, sb):
		out.append(sb)
		return out
	var raw: PackedVector2Array = grid.get_point_path(_to_cell(Vector2(sa.x, sa.z)), _to_cell(Vector2(sb.x, sb.z)))
	if raw.is_empty():
		return out
	var pts: Array[Vector3] = []
	for p in raw:
		pts.append(Vector3(p.x, 0.0, p.y))
	pts[pts.size() - 1] = sb
	# string pulling: from the current anchor jump to the furthest point still in a clear straight line
	var anchor := sa
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not segment_clear(anchor, pts[j]):
			j -= 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out

static func path_length(from: Vector3, pts: PackedVector3Array) -> float:
	var total := 0.0
	var prev := from
	for p in pts:
		total += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
	return total

## Share of open ground along a run (samples further than OPEN_CLEARANCE from every footprint).
func open_fraction(from: Vector3, pts: PackedVector3Array) -> float:
	var samples := 0
	var open := 0
	var prev := from
	for p in pts:
		var seg := Vector2(p.x - prev.x, p.z - prev.z)
		var n := maxi(1, int(ceil(seg.length())))
		for k in range(n):
			var q := Vector2(prev.x, prev.z) + seg * (float(k) + 0.5) / float(n)
			samples += 1
			if clearance_at(q) > OPEN_CLEARANCE:
				open += 1
		prev = p
	return float(open) / float(maxi(samples, 1))

func clearance_at(q: Vector2) -> float:
	var best := INF
	for r in obstacles:
		var rr := r as Rect2
		var dx := maxf(maxf(rr.position.x - q.x, 0.0), q.x - rr.end.x)
		var dz := maxf(maxf(rr.position.y - q.y, 0.0), q.y - rr.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best

# ---------------------------------------------------------------- pockets
## Pocket behind node i against a threat direction (unit XZ toward the threat). side: -1 left, +1 right, 0 low/centre.
## "Left" is the runner's left while facing the threat.
func pocket(i: int, threat_dir: Vector3, side: int) -> Vector3:
	var nd: Dictionary = nodes[i]
	var r: Rect2 = nd["rect"]
	var t := Vector3(threat_dir.x, 0.0, threat_dir.z)
	if t.length() < 0.01:
		t = Vector3(0, 0, -1)
	t = t.normalized()
	var lat := Vector3(-t.z, 0.0, t.x) # right of the threat-facing runner
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var half := Vector3(r.size.x * 0.5, 0.0, r.size.y * 0.5)
	var depth := absf(t.x) * half.x + absf(t.z) * half.z
	var width := absf(lat.x) * half.x + absf(lat.z) * half.z
	var p := c - t * (depth + AGENT_RADIUS + POCKET_GAP) + lat * float(side) * maxf(width - 0.35, 0.0)
	return nearest_free(p, 6)

## Pockets for a team facing (ALPHA fights toward -Z, BRAVO toward +Z).
func team_pocket(i: int, team: String, side: int) -> Vector3:
	return pocket(i, Vector3(0, 0, -1) if team == "ALPHA" else Vector3(0, 0, 1), side)

## Peek spot: step out past the bunker edge on `side` from the pocket.
func peek_point(i: int, threat_dir: Vector3, side: int) -> Vector3:
	var nd: Dictionary = nodes[i]
	var r: Rect2 = nd["rect"]
	var t := Vector3(threat_dir.x, 0.0, threat_dir.z).normalized()
	if t.length() < 0.01:
		t = Vector3(0, 0, -1)
	var lat := Vector3(-t.z, 0.0, t.x)
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var half := Vector3(r.size.x * 0.5, 0.0, r.size.y * 0.5)
	var depth := absf(t.x) * half.x + absf(t.z) * half.z
	var width := absf(lat.x) * half.x + absf(lat.z) * half.z
	var s := float(side if side != 0 else 1)
	return nearest_free(c - t * (depth + AGENT_RADIUS + POCKET_GAP) + lat * s * (width + AGENT_RADIUS + 0.35), 4)

# ---------------------------------------------------------------- edges
func _build_edges() -> void:
	edges.clear()
	adjacency.clear()
	for i in nodes.size():
		adjacency[i] = []
	var done := {}
	for i in nodes.size():
		var pi: Vector3 = nodes[i]["pos"]
		var cand: Array = []
		for j in nodes.size():
			if j == i:
				continue
			var d := pi.distance_to(nodes[j]["pos"])
			if d <= EDGE_MAX_DIST:
				cand.append([d, j])
		cand.sort_custom(func(x, y): return x[0] < y[0])
		for k in range(mini(EDGE_NEIGHBORS, cand.size())):
			var j: int = cand[k][1]
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if done.has(key):
				continue
			done[key] = true
			var a := _edge_anchor(i, j)
			var b := _edge_anchor(j, i)
			var path := plan_path(a, b)
			if path.is_empty():
				continue
			var length := path_length(a, path)
			var straight := Vector2(b.x - a.x, b.z - a.z).length()
			if length > maxf(straight * EDGE_MAX_DETOUR, straight + 4.0):
				continue
			var expo := open_fraction(a, path)
			var e := {"a": i, "b": j, "length": length, "straight": straight, "exposure": expo, "exposure_score": expo * length / 10.0, "path": path}
			adjacency[i].append(edges.size())
			adjacency[j].append(edges.size())
			edges.append(e)

## Point beside bunker i on the side facing bunker j.
func _edge_anchor(i: int, j: int) -> Vector3:
	var dir: Vector3 = (Vector3(nodes[j]["pos"]) - Vector3(nodes[i]["pos"]))
	dir.y = 0.0
	return pocket(i, -dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1), 0)

func neighbors(i: int) -> Array:
	var out: Array = []
	for ei in adjacency.get(i, []):
		var e: Dictionary = edges[ei]
		out.append(int(e["b"]) if int(e["a"]) == i else int(e["a"]))
	return out

func edge_between(i: int, j: int) -> Dictionary:
	for ei in adjacency.get(i, []):
		var e: Dictionary = edges[ei]
		if (int(e["a"]) == i and int(e["b"]) == j) or (int(e["a"]) == j and int(e["b"]) == i):
			return e
	return {}

# ---------------------------------------------------------------- lookups
func index_of_callout(callout: String) -> int:
	for i in nodes.size():
		if String(nodes[i]["callout"]) == callout:
			return i
	return -1

func nearest_node(p: Vector3, max_dist: float = INF) -> int:
	var best := -1
	var best_d := max_dist
	for i in nodes.size():
		var r: Rect2 = nodes[i]["rect"]
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.z, 0.0), p.z - r.end.y)
		var d := sqrt(dx * dx + dz * dz)
		if d < best_d:
			best_d = d
			best = i
	return best

static func role_of_callout(callout: String) -> String:
	var base := callout
	for pre in ["Red ", "Blue "]:
		if base.begins_with(pre):
			base = base.substr(pre.length())
	for role in ROLE_BASES.keys():
		if base in ROLE_BASES[role]:
			return role
	return ""

## Indices of the role's bunkers; team "ALPHA" -> Red side, "BRAVO" -> Blue side, "" -> both.
func role_nodes(role: String, team: String = "") -> Array:
	var out: Array = []
	for i in nodes.size():
		var c := String(nodes[i]["callout"])
		if team == "ALPHA" and not c.begins_with("Red "):
			continue
		if team == "BRAVO" and not c.begins_with("Blue "):
			continue
		if role_of_callout(c) == role:
			out.append(i)
	return out

## Primary break bunker for a role on a team (the k-th plan primary that exists), else -1.
func primary_for(role: String, team: String, k: int = 0) -> int:
	var prefix := "Red " if team == "ALPHA" else "Blue "
	var list: Array = ROLE_PRIMARIES.get(role, [])
	var found: Array = []
	for base in list:
		var idx := index_of_callout(prefix + String(base))
		if idx >= 0:
			found.append(idx)
	if found.is_empty():
		return -1
	return int(found[k % found.size()])
