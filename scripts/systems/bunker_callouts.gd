extends Node
## v0.6 tournament-style bunker callouts ("ACE: 2 in Red Snake 2").
##  - every bunker on each map has a short callout name (<= 24 chars), mirrored by side: Home_* (+Z, ALPHA) = "Red ...",
##    OpFor_* (-Z, BRAVO) = "Blue ...", 50-line bunkers have no side. Snake side = -X, dorito side = +X for both teams.
##  - [V] / mouse thumb button (action "callout_bunker") pings the bunker under the crosshair, else the named bunker
##    nearest the aim ray; N = visible, alive enemies near it (min 1, max 5).
##  - online: NetworkLobby.ping_callout(callout, pos, count) -> the server relays callout_pinged(data) to the pinger's
##    team (pinger included) and we render only from that signal; offline: rendered locally (same renderer).
##  - render: Label3D world marker over the bunker + HUD line "<callsign>: N in <Bunker>" for MARKER_TIME seconds.

const COOLDOWN_MS: int = 1200 # matches the server's CALLOUT_COOLDOWN_MS
const MARKER_TIME: float = 4.0
const MAX_NAME_LEN: int = 24
const MAX_COUNT: int = 5
const ENEMY_RADIUS: float = 7.0 # m (XZ) around the bunker that counts as "in" it
const PICK_MAX_DIST: float = 110.0
const PICK_RAY_SLACK: float = 3.0 # nearest-along-ray: max miss = slack + 12% of the distance
const MARKER_HEIGHT: float = 2.6
const HUD_LINES_MAX: int = 4
const TEAM_COLORS := {"red": Color(0.96, 0.24, 0.18), "blue": Color(0.24, 0.56, 1.0)}

## Mirrored side bunkers: node stem after Home_ / OpFor_ -> callout (prefixed with "Red " / "Blue ").
const SIDE_STEMS := {
	"BreakoutGate": "Home", "BackCenter": "Back Center", "BreakoutCan_L": "Home Can", "BreakoutCan_R": "Back Can",
	"BreakoutBolster": "Log", "BackBrick_L": "Snake Brick", "BackBrick_R": "Dorito Brick",
	"OuterTower_L": "Snake Tree", "OuterTower_R": "Dorito Tree", "CenterAztec": "Cake",
	"MidCan_L": "Snake Can", "MidCan_R": "Dorito Can", "WideTemple_L": "Snake Temple", "WideTemple_R": "Dorito Temple",
	"40_Pin_L": "Snake Pin", "40_Pin_R": "Dorito Pin", "40_Wedge_L": "Snake Wedge", "40_Wedge_R": "Dorito Wedge",
	"Dorito_Corner": "Dorito 1", "Dorito_1": "Dorito 2", "Dorito_2": "Dorito 3",
	"Snake_Corner": "Snake Corner", "Snake_GodCan": "God Can",
}
## Woodsball Heli Crash: the same layout built from spools / crates / stacks / reels.
const WOODS_SIDE_STEMS := {
	"BreakoutCan_L": "Home Spool", "BreakoutCan_R": "Back Spool", "BackBrick_L": "Snake Crate", "BackBrick_R": "Dorito Crate",
	"OuterTower_L": "Snake Stack", "OuterTower_R": "Dorito Stack", "MidCan_L": "Snake Spool", "MidCan_R": "Dorito Spool",
	"40_Wedge_L": "Snake Reel", "40_Wedge_R": "Dorito Reel",
}
## Full node names (both maps): 50-line bunkers and the snake (numbered 1-4 from each team's end).
const FIXED := {
	"Bunker_Center50_W": "Center", "Bunker_50_MiniWin_Left": "Snake Mini", "Bunker_50_MiniWin_Right": "Dorito Mini",
	"Bunker_50_Insert_Left": "Snake Insert", "Bunker_50_Insert_Right": "Dorito Insert", "Bunker_50_GiantDorito": "50 Dorito",
	"Snake_Knuckle_Center50": "Snake 50",
	"Snake_Knuckle_HomeEntry": "Red Snake 1", "Snake_Beam_Home1": "Red Snake 2", "Snake_Knuckle_HomeMid": "Red Snake 3",
	"Snake_Beam_Home2": "Red Snake 4",
	"Snake_Knuckle_OpForEntry": "Blue Snake 1", "Snake_Beam_OpFor1": "Blue Snake 2", "Snake_Knuckle_OpForMid": "Blue Snake 3",
	"Snake_Beam_OpFor2": "Blue Snake 4",
}
## Speedball-only cable spools (GrittyStadiumProps; hidden + collision off on the woods map).
const SPEEDBALL_FIXED := {
	"WoodSpool_BreakoutRight": "Red Home Spool", "WoodSpool_Center50Left": "Snake 50 Spool",
	"WoodSpool_Center50Right": "Dorito 50 Spool", "WoodSpool_TransitionLeft": "Red Snake Spool",
	"WoodSpool_TransitionRight": "Blue Dorito Spool",
}
const WOODS_FIXED := {
	"Heli_CrashFuselage_Center50": "Heli", "Heli_CockpitNose": "Nose", "Heli_BrokenTailBoom": "Tail",
	"Heli_TailRotorPylon": "Tail Rotor", "Tower_WestFlank": "Snake Tower", "Tower_EastFlank": "Dorito Tower",
	"Tower_SouthRidge": "Red Tower", "Tower_NorthRidge": "Blue Tower",
}

var builder: Node = null # SpeedballArenaBuilder (the arena root)
var player: Node = null # PlayerController3D
var last_ping_ms: int = -100000
var clock_override_ms: int = -1 # tests
var online_override: int = -1 # tests: -1 = ask NetworkLobby, 0 = offline, 1 = online
var send_override: Callable = Callable() # tests: capture the online send instead of NetworkLobby.ping_callout
var pings_sent: int = 0
var pings_local: int = 0
var pings_rendered: int = 0
var blocked_cooldown: int = 0
var markers := {} # callout -> {node: Label3D, left: float}
var hud_lines: Array = [] # [{text, color, left}]
var canvas: CanvasLayer
var hud_box: VBoxContainer

func setup(p_builder: Node, p_player: Node) -> void:
	builder = p_builder
	player = p_player
	canvas = CanvasLayer.new()
	canvas.name = "CalloutHUD"
	canvas.layer = 6
	add_child(canvas)
	hud_box = VBoxContainer.new()
	hud_box.name = "CalloutLines"
	hud_box.position = Vector2(24, 430)
	hud_box.custom_minimum_size = Vector2(520, 0)
	hud_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_box)
	if NetworkLobby.has_signal("callout_pinged") and not NetworkLobby.is_connected("callout_pinged", on_callout_pinged):
		NetworkLobby.connect("callout_pinged", on_callout_pinged)

## =========================================== naming ===========================================

static func is_woods_map(map_id: String) -> bool:
	return map_id in ["woodsball_crash", "woods", "woodsball", "crash_site"]

## Callout for a bunker node name on a map ("" = not a callout bunker).
static func callout_for_node_name(node_name: String, map_id: String) -> String:
	var woods := is_woods_map(map_id)
	var out := ""
	if woods and WOODS_FIXED.has(node_name):
		out = String(WOODS_FIXED[node_name])
	elif not woods and SPEEDBALL_FIXED.has(node_name):
		out = String(SPEEDBALL_FIXED[node_name])
	elif FIXED.has(node_name):
		out = String(FIXED[node_name])
	else:
		for pre in ["Home_", "OpFor_"]:
			if node_name.begins_with(pre):
				var stem := node_name.substr(pre.length())
				var base := ""
				if woods and WOODS_SIDE_STEMS.has(stem):
					base = String(WOODS_SIDE_STEMS[stem])
				elif SIDE_STEMS.has(stem):
					base = String(SIDE_STEMS[stem])
				if not base.is_empty():
					out = ("Red " if pre == "Home_" else "Blue ") + base
	return out.substr(0, MAX_NAME_LEN)

func current_map_id() -> String:
	if builder != null:
		var w: Variant = builder.get("woodsball_map_root")
		if w is Node and is_instance_valid(w):
			return "woodsball_crash"
	return "speedball"

static func _is_bunker_candidate(n: Node) -> bool:
	# bots (snap_target_bot: OpFor_CenterAztec / OpFor_BackCenter ...) and avatars share the names: skip scripted nodes
	if not (n is Node3D) or n.get_script() != null or "is_eliminated" in n:
		return false
	return (n as Node3D).is_visible_in_tree()

## Every named bunker currently in the arena: [{callout, node, pos}] (pos = bunker centre, ground level).
static func scan_bunkers(arena: Node, map_id: String) -> Array:
	var out: Array = []
	if arena == null:
		return out
	_scan_into(arena, map_id, 0, out)
	return out

static func _scan_into(n: Node, map_id: String, depth: int, out: Array) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var cname := callout_for_node_name(String(c.name), map_id)
		if not cname.is_empty() and _is_bunker_candidate(c):
			var p := (c as Node3D).global_position
			out.append({"callout": cname, "node": c, "pos": Vector3(p.x, 0.0, p.z)})
			continue
		if depth < 2 and (c.get_script() == null):
			_scan_into(c, map_id, depth + 1, out)

## Walk a collider up to the nearest named bunker node (tower posts -> Tower_*), else "".
static func callout_for_collider(collider: Object, map_id: String, arena: Node) -> String:
	var n := collider as Node
	while n != null and n != arena:
		if n.get_script() == null:
			var cname := callout_for_node_name(String(n.name), map_id)
			if not cname.is_empty():
				return cname
		n = n.get_parent()
	return ""

## The named bunker the aim ray passes closest to (perpendicular miss <= slack + 12% of range), else {}.
static func nearest_along_ray(entries: Array, origin: Vector3, dir: Vector3) -> Dictionary:
	var d := dir.normalized()
	var best := {}
	var best_score := INF
	for e in entries:
		var v: Vector3 = Vector3(e["pos"]) + Vector3(0, 1.0, 0) - origin
		var t := v.dot(d)
		if t < 0.5 or t > PICK_MAX_DIST:
			continue
		var miss := (v - d * t).length()
		if miss > PICK_RAY_SLACK + t * 0.12:
			continue
		var score := miss / (1.0 + t * 0.05) # forgive more miss further out
		if score < best_score:
			best_score = score
			best = e
	return best

## =========================================== picking / counting ===========================================

func _aim() -> Array:
	var cam: Camera3D = player.get("camera") if player != null else null
	if cam == null or not cam.is_inside_tree():
		return []
	return [cam.global_position, -cam.global_transform.basis.z]

## Pick the bunker for an aim ray: the collider under the crosshair first, else nearest along the ray.
func pick_bunker(origin: Vector3, dir: Vector3) -> Dictionary:
	var map_id := current_map_id()
	var entries := scan_bunkers(builder, map_id)
	if entries.is_empty():
		return {}
	var w3d: World3D = builder.get_viewport().world_3d if builder != null and builder.is_inside_tree() else null
	if w3d != null and w3d.direct_space_state != null:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * PICK_MAX_DIST)
		if player is CollisionObject3D:
			q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := w3d.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var cname := callout_for_collider(hit.get("collider"), map_id, builder)
			if not cname.is_empty():
				for e in entries:
					if String(e["callout"]) == cname:
						return e
	return nearest_along_ray(entries, origin, dir)

## Alive, visible enemies: online the remote avatars of the other team, offline the OpFor practice bots.
func enemy_nodes() -> Array:
	var out: Array = []
	if _is_online():
		for pid in NetworkLobby.remote_player_nodes.keys():
			var info: Dictionary = NetworkLobby.players.get(pid, {})
			if info.is_empty() or String(info.get("team", "")) == NetworkLobby.local_team or not bool(info.get("alive", true)):
				continue
			var n: Variant = NetworkLobby.remote_player_nodes[pid]
			if n is Node3D and is_instance_valid(n):
				out.append(n)
	elif builder != null:
		for c in builder.get_children():
			if c is Node3D and "is_eliminated" in c and String(c.name).begins_with("OpFor_") == (NetworkLobby.local_team == "ALPHA"):
				out.append(c)
	return out

## N for "N in <Bunker>": enemies within ENEMY_RADIUS (XZ) of the bunker that are alive and visible (min 1, max 5).
func count_enemies_near(pos: Vector3, nodes: Array = []) -> int:
	var list := nodes if not nodes.is_empty() else enemy_nodes()
	var cam: Camera3D = player.get("camera") if player != null else null
	var n := 0
	for e in list:
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var node := e as Node3D
		if "is_eliminated" in node and bool(node.get("is_eliminated")):
			continue
		if node.is_inside_tree() and not node.is_visible_in_tree():
			continue
		var gp := node.global_position if node.is_inside_tree() else node.position
		if Vector2(gp.x - pos.x, gp.z - pos.z).length() > ENEMY_RADIUS:
			continue
		if cam != null and cam.is_inside_tree() and not cam.is_position_in_frustum(gp + Vector3(0, 1.0, 0)):
			continue
		n += 1
	return clampi(n, 1, MAX_COUNT)

## =========================================== send / render ===========================================

func _now_ms() -> int:
	return clock_override_ms if clock_override_ms >= 0 else Time.get_ticks_msec()

func _is_online() -> bool:
	return online_override == 1 if online_override >= 0 else NetworkLobby.is_online_client()

func cooldown_left_ms() -> int:
	return maxi(0, COOLDOWN_MS - (_now_ms() - last_ping_ms))

func can_callout() -> bool:
	if player != null:
		for flag in ["lobby_open", "awaiting_respawn_choice", "spectating"]:
			if bool(player.get(flag)):
				return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("callout_bunker"):
		return
	var aim := _aim()
	if aim.is_empty():
		return
	try_callout(aim[0], aim[1])

## Ping the bunker the aim ray picks. Returns {ok, reason, callout, count, pos}.
func try_callout(origin: Vector3, dir: Vector3) -> Dictionary:
	if not can_callout():
		return {"ok": false, "reason": "blocked"}
	if cooldown_left_ms() > 0:
		blocked_cooldown += 1
		return {"ok": false, "reason": "cooldown"}
	var e := pick_bunker(origin, dir)
	if e.is_empty():
		return {"ok": false, "reason": "no_bunker"}
	var pos: Vector3 = e["pos"]
	var cname := String(e["callout"]).substr(0, MAX_NAME_LEN)
	var count := count_enemies_near(pos)
	last_ping_ms = _now_ms()
	if _is_online():
		pings_sent += 1
		if send_override.is_valid():
			send_override.call(cname, pos, count)
		else:
			NetworkLobby.ping_callout(cname, pos, count) # the server echoes callout_pinged back to us
	else:
		pings_local += 1
		var team := NetworkLobby.local_team
		on_callout_pinged({"room": "", "peer": 0, "name": NetworkLobby.local_callsign, "team": team,
			"color": NetworkLobby.team_label(team), "callout": cname, "count": count, "pos": pos, "local": true})
	return {"ok": true, "reason": "", "callout": cname, "count": count, "pos": pos}

static func hud_line_text(data: Dictionary) -> String:
	var who := String(data.get("name", "")).strip_edges()
	if who.is_empty():
		who = "TEAMMATE"
	return "%s: %d in %s" % [who, maxi(1, int(data.get("count", 1))), String(data.get("callout", "")).substr(0, MAX_NAME_LEN)]

## NetworkLobby.callout_pinged(data) {room, peer, name, team, color, callout, count, pos} (team only, pinger included).
func on_callout_pinged(data: Dictionary) -> void:
	var cname := String(data.get("callout", "")).strip_edges()
	if cname.is_empty():
		return
	if data.has("team") and not NetworkLobby.local_team.is_empty() and String(data["team"]) != NetworkLobby.local_team:
		return # the server only sends to the team; guard anyway
	pings_rendered += 1
	var col: Color = TEAM_COLORS.get(String(data.get("color", "red")), Color(1, 0.85, 0.2))
	var pos := _to_vec3(data.get("pos", Vector3.ZERO))
	_show_marker(cname, pos, maxi(1, int(data.get("count", 1))), col)
	hud_lines.push_front({"text": hud_line_text(data), "color": col, "left": MARKER_TIME})
	while hud_lines.size() > HUD_LINES_MAX:
		hud_lines.pop_back()
	_refresh_hud()

func _show_marker(cname: String, pos: Vector3, count: int, col: Color) -> void:
	var m: Label3D = null
	if markers.has(cname) and is_instance_valid(markers[cname]["node"]):
		m = markers[cname]["node"]
	else:
		m = Label3D.new()
		m.name = "CalloutMarker"
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.fixed_size = true
		m.pixel_size = 0.0011
		m.font_size = 40
		m.outline_size = 10
		m.render_priority = 10
		var parent: Node = builder if builder != null else self
		parent.add_child(m)
	m.text = "%d in %s" % [count, cname]
	m.modulate = col
	m.outline_modulate = Color(0, 0, 0, 0.9)
	m.position = pos + Vector3(0, MARKER_HEIGHT, 0)
	markers[cname] = {"node": m, "left": MARKER_TIME}

func marker_texts() -> Array:
	var out: Array = []
	for k in markers.keys():
		if is_instance_valid(markers[k]["node"]):
			out.append(String((markers[k]["node"] as Label3D).text))
	return out

func hud_texts() -> Array:
	var out: Array = []
	for l in hud_lines:
		out.append(String(l["text"]))
	return out

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	for k in markers.keys():
		markers[k]["left"] = float(markers[k]["left"]) - delta
		if float(markers[k]["left"]) <= 0.0:
			var n: Variant = markers[k]["node"]
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
			markers.erase(k)
	var changed := false
	for l in hud_lines:
		l["left"] = float(l["left"]) - delta
	while not hud_lines.is_empty() and float(hud_lines[-1]["left"]) <= 0.0:
		hud_lines.pop_back()
		changed = true
	if changed or not hud_lines.is_empty():
		_refresh_hud()

func _refresh_hud() -> void:
	if hud_box == null:
		return
	while hud_box.get_child_count() > hud_lines.size():
		var ch := hud_box.get_child(hud_box.get_child_count() - 1)
		hud_box.remove_child(ch)
		ch.queue_free()
	while hud_box.get_child_count() < hud_lines.size():
		var l := Label.new()
		l.name = "CalloutLine"
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_box.add_child(l)
	for i in range(hud_lines.size()):
		var l := hud_box.get_child(i) as Label
		l.text = String(hud_lines[i]["text"])
		l.add_theme_color_override("font_color", hud_lines[i]["color"])
		l.modulate.a = clampf(float(hud_lines[i]["left"]) / 0.6, 0.0, 1.0)

static func _to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if typeof(v) == TYPE_DICTIONARY:
		return Vector3(float(v.get("x", 0)), float(v.get("y", 0)), float(v.get("z", 0)))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
