extends SceneTree
## v0.6 bunker callouts (BunkerCallouts): every bunker on both maps named (<= 24 chars, unique, Red/Blue mirrored),
## the bots excluded, key bindings (V + mouse thumb; Z / MMB were taken), crosshair pick + nearest-along-ray, enemy
## count (alive + visible, min 1), 1.2 s cooldown, offline local render, online NetworkLobby.ping_callout +
## callout_pinged rendering (team only), marker + HUD line expire after ~4 s.
## Run: godot --headless --path . -s scripts/systems/test_bunker_callouts.gd

var CalloutsScript: GDScript # loaded after the autoloads exist (the script uses NetworkLobby)
const NAME_PREFIXES := ["Home_", "OpFor_", "Bunker_", "Snake_", "Heli_", "Tower_", "WoodSpool_"]

var arena: Node
var player: Node
var bc: Node
var failures: Array[String] = []
var started := false
var elim_script: GDScript

func _initialize() -> void:
	CalloutsScript = load("res://scripts/systems/bunker_callouts.gd")
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _lobby() -> Node:
	return root.get_node("NetworkLobby")

## Every unscripted bunker-ish node the map builders create (direct children, + WoodSpools / woods root children).
func _bunker_nodes(n: Node, depth: int, out: Array) -> void:
	for c in n.get_children():
		if not (c is Node3D) or c.get_script() != null:
			continue
		var nm := String(c.name)
		var hit := false
		for p in NAME_PREFIXES:
			if nm.begins_with(p):
				hit = true
		if hit and (c as Node3D).is_visible_in_tree() and not nm.contains("_Post_") and not nm.contains("_Parapet_") and not nm.contains("_Ramp") and not nm.contains("_Deck") and not nm.contains("_Ladder"):
			out.append(c)
		elif depth < 1:
			_bunker_nodes(c, depth + 1, out)

func _check_map(map_id: String, expect_names: Array) -> Array:
	var entries: Array = CalloutsScript.scan_bunkers(arena, map_id)
	var names: Array = []
	var too_long: Array = []
	for e in entries:
		names.append(String(e["callout"]))
		if String(e["callout"]).length() > CalloutsScript.MAX_NAME_LEN:
			too_long.append(e["callout"])
		_check((e["node"] as Node).get_script() == null, "%s: registry node %s is a bunker, not a bot/avatar" % [map_id, (e["node"] as Node).name]) if (e["node"] as Node).get_script() != null else null
	var uniq := {}
	for n in names:
		uniq[n] = true
	print("  %s callouts (%d): %s" % [map_id, names.size(), ", ".join(PackedStringArray(names))])
	_check(names.size() >= 30, "%s: registry found %d bunkers" % [map_id, names.size()])
	_check(uniq.size() == names.size(), "%s: callouts unique per map (%d / %d)" % [map_id, uniq.size(), names.size()])
	_check(too_long.is_empty(), "%s: all callouts <= 24 chars %s" % [map_id, str(too_long)])
	var unnamed: Array = []
	var nodes: Array = []
	_bunker_nodes(arena, 0, nodes)
	for n in nodes:
		if String(CalloutsScript.callout_for_node_name(String(n.name), map_id)).is_empty():
			unnamed.append(String(n.name))
	_check(unnamed.is_empty(), "%s: every bunker has a callout (unnamed: %s)" % [map_id, str(unnamed)])
	for want in expect_names:
		_check(names.has(want), "%s has \"%s\"" % [map_id, want])
	for e in entries:
		var nm := String((e["node"] as Node).name)
		if nm.begins_with("OpFor_Snake50") or nm.begins_with("OpFor_SnakeCorner") or nm.begins_with("OpFor_Dorito2"):
			_check(false, "bot %s leaked into the registry" % nm)
	return entries

func _entry(entries: Array, cname: String) -> Dictionary:
	for e in entries:
		if String(e["callout"]) == cname:
			return e
	return {}

func _fake_enemy(pos: Vector3, eliminated: bool = false) -> Node3D:
	var n := Node3D.new()
	n.set_script(elim_script)
	n.set("is_eliminated", eliminated)
	arena.add_child(n)
	n.global_position = pos
	return n

func _run() -> void:
	await _frames(4)
	var nl := _lobby()
	player = arena.get("player")
	bc = arena.get("bunker_callouts")
	_check(player != null and bc != null and bc.get_parent() == arena, "arena built the BunkerCallouts node")
	if bc == null:
		_finish()
		return
	if arena.has_method("_set_lobby_overlay_visible"):
		arena.call("_set_lobby_overlay_visible", false)
	player.call("set_lobby_open_state", false)
	elim_script = GDScript.new()
	elim_script.source_code = "extends Node3D\nvar is_eliminated: bool = false\n"
	elim_script.reload()

	print("[1] key bindings")
	var cb := InputMap.action_get_events("callout_bunker") if InputMap.has_action("callout_bunker") else []
	var has_v := false
	var has_x1 := false
	for ev in cb:
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_V:
			has_v = true
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_XBUTTON1:
			has_x1 = true
	_check(has_v and has_x1, "callout_bunker = V + mouse thumb (XBUTTON1)")
	var clash: Array = []
	for a in InputMap.get_actions():
		if String(a) == "callout_bunker" or String(a).begins_with("ui_"):
			continue
		for ev in InputMap.action_get_events(a):
			if (ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_V) or (ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_XBUTTON1):
				clash.append(String(a))
	_check(clash.is_empty(), "V / XBUTTON1 used by no other action %s" % str(clash))
	var z_taken := false
	for ev in InputMap.action_get_events("prone_dive"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_Z:
			z_taken = true
	_check(z_taken, "Z stays on prone_dive (it was taken), MMB stays on swap_shoulder")

	print("[2] naming tables: mirrored by side")
	for stem in CalloutsScript.SIDE_STEMS.keys():
		for map_id in ["speedball", "woodsball_crash"]:
			var r := String(CalloutsScript.callout_for_node_name("Home_" + stem, map_id))
			var b := String(CalloutsScript.callout_for_node_name("OpFor_" + stem, map_id))
			if not (r.begins_with("Red ") and b.begins_with("Blue ") and r.substr(4) == b.substr(5)):
				_check(false, "%s %s mirrors: %s / %s" % [map_id, stem, r, b])
	_check(String(CalloutsScript.callout_for_node_name("Snake_Beam_Home1", "speedball")) == "Red Snake 2" and String(CalloutsScript.callout_for_node_name("Snake_Beam_OpFor1", "speedball")) == "Blue Snake 2", "snake numbered from each end: Red Snake 2 / Blue Snake 2")
	_check(String(CalloutsScript.callout_for_node_name("Home_MidCan_L", "woodsball_crash")) == "Red Snake Spool" and String(CalloutsScript.callout_for_node_name("Home_MidCan_L", "speedball")) == "Red Snake Can", "per-map names (Can on speedball, Spool in the woods)")
	_check(String(CalloutsScript.callout_for_node_name("OpFor_Snake50", "speedball")).is_empty(), "bot names are not bunkers")

	print("[3] speedball registry")
	var sb := _check_map("speedball", ["Red Home", "Blue Home", "Red Snake 2", "Blue Snake 4", "Snake 50", "Center", "50 Dorito", "Red Cake", "Red Dorito 1", "Blue Dorito 3", "Red Home Spool", "Snake Insert"])
	_check(_entry(sb, "Blue Cake").is_empty() and _entry(sb, "Blue Back Center").is_empty(), "speedball: OpFor_CenterAztec / OpFor_BackCenter are practice bots there, not bunkers")

	print("[4] aim pick (crosshair collider, nearest along the ray)")
	await _frames(2)
	var origin := Vector3(-8.5, 1.6, 30.0)
	var r1: Dictionary = bc.call("pick_bunker", origin, (Vector3(-8.5, 1.15, 17.5) - origin).normalized())
	_check(String(r1.get("callout", "")) == "Red Snake Can", "crosshair on Home_MidCan_L -> Red Snake Can: %s" % r1.get("callout", ""))
	var r2: Dictionary = bc.call("pick_bunker", origin, (Vector3(-8.5, 4.2, 17.5) - origin).normalized())
	_check(String(r2.get("callout", "")) == "Red Snake Can", "aim just over it -> nearest along the ray: %s" % r2.get("callout", ""))
	var o3 := Vector3(-30.0, 1.6, 30.0)
	var r3: Dictionary = bc.call("pick_bunker", o3, (Vector3(-35.0, 0.5, 15.0) - o3).normalized())
	_check(String(r3.get("callout", "")) == "Red Snake 2" or String(r3.get("callout", "")) == "Red God Can", "aim down the snake -> %s" % r3.get("callout", ""))
	var r4: Dictionary = bc.call("pick_bunker", Vector3(0, 1.6, 30), Vector3(0, 1, 0))
	_check(r4.is_empty(), "aiming at the sky picks nothing")
	var syn := [{"callout": "A", "pos": Vector3(0, 0, -10)}, {"callout": "B", "pos": Vector3(3, 0, -20)}, {"callout": "C", "pos": Vector3(0, 0, 10)}]
	_check(String(CalloutsScript.nearest_along_ray(syn, Vector3(0, 1, 0), Vector3(0.14, 0, -1)).get("callout", "")) == "B", "nearest_along_ray prefers the bunker the ray passes closest to")
	_check(String(CalloutsScript.nearest_along_ray(syn, Vector3(0, 1, 0), Vector3(0, 0, 1)).get("callout", "")) == "C", "behind the shooter is never picked")

	print("[5] enemy count (alive, visible, near; min 1, max 5)")
	nl.local_team = "ALPHA"
	bc.set("online_override", 0)
	var center := Vector3(-8.5, 0, -17.5)
	var near := [_fake_enemy(center + Vector3(1, 0, 1)), _fake_enemy(center + Vector3(-2, 0, 0.5)), _fake_enemy(center + Vector3(0, 0, -3))]
	var far := _fake_enemy(center + Vector3(0, 0, 15))
	var dead := _fake_enemy(center + Vector3(0.5, 0, 0), true)
	var hidden := _fake_enemy(center + Vector3(0.2, 0, 0.2))
	hidden.visible = false
	var saved_player: Node = bc.get("player")
	bc.set("player", null) # no camera frustum for the raw count
	var lst: Array = near.duplicate()
	lst.append_array([far, dead, hidden])
	_check(int(bc.call("count_enemies_near", center, lst)) == 3, "3 alive + visible within range (far / eliminated / hidden skipped)")
	_check(int(bc.call("count_enemies_near", center, [far])) == 1, "none near -> minimum 1")
	var many: Array = []
	for i in range(7):
		many.append(_fake_enemy(center + Vector3(i * 0.3, 0, 0)))
	_check(int(bc.call("count_enemies_near", center, many)) == 5, "capped at 5 (server clamps 0..5)")
	bc.set("player", saved_player)
	for n in many + lst:
		(n as Node).queue_free()

	print("[6] offline: cooldown 1.2 s + local render")
	nl.local_callsign = "ACE"
	bc.set("clock_override_ms", 100000)
	bc.set("last_ping_ms", -100000)
	var d := (Vector3(-8.5, 1.15, 17.5) - origin).normalized()
	var res: Dictionary = bc.call("try_callout", origin, d)
	_check(bool(res.get("ok", false)) and String(res.get("callout", "")) == "Red Snake Can", "ping ok: %s" % str(res))
	var hud: Array = bc.call("hud_texts")
	_check(hud.size() == 1 and String(hud[0]) == "ACE: %d in Red Snake Can" % int(res["count"]), "HUD line: %s" % str(hud))
	var mk: Array = bc.call("marker_texts")
	_check(mk.size() == 1 and String(mk[0]).ends_with("in Red Snake Can"), "world marker over the bunker: %s" % str(mk))
	var lbl := bc.find_child("CalloutLine", true, false) as Label
	_check(lbl != null and lbl.text.begins_with("ACE: ") and lbl.is_visible_in_tree(), "HUD label shows")
	var marker := arena.find_child("CalloutMarker", true, false) as Label3D
	_check(marker != null and marker.global_position.y > 2.0 and Vector2(marker.global_position.x, marker.global_position.z).distance_to(Vector2(-8.5, 17.5)) < 0.1, "marker sits over Home_MidCan_L")
	bc.set("clock_override_ms", 100600)
	_check(String((bc.call("try_callout", origin, d) as Dictionary).get("reason", "")) == "cooldown", "0.6 s later: cooldown")
	bc.set("clock_override_ms", 101199)
	_check(String((bc.call("try_callout", origin, d) as Dictionary).get("reason", "")) == "cooldown", "1.199 s later: still cooldown")
	bc.set("clock_override_ms", 101200)
	_check(bool((bc.call("try_callout", origin, d) as Dictionary).get("ok", false)), "1.2 s later: ok again")
	_check(int(bc.get("pings_local")) == 2 and int(bc.get("pings_sent")) == 0, "offline never touches the network")
	bc.call("tick", 3.0)
	_check((bc.call("hud_texts") as Array).size() >= 1, "still up at 3 s")
	bc.call("tick", 1.1)
	_check((bc.call("hud_texts") as Array).is_empty() and (bc.call("marker_texts") as Array).is_empty(), "gone after ~4 s")
	player.set("lobby_open", true)
	bc.set("clock_override_ms", 200000)
	_check(String((bc.call("try_callout", origin, d) as Dictionary).get("reason", "")) == "blocked", "no callouts with the lobby open")
	player.set("lobby_open", false)

	print("[7] online: NetworkLobby.ping_callout + render only from callout_pinged")
	var sent: Array = []
	bc.set("online_override", 1)
	bc.set("send_override", func(c: String, p: Vector3, n: int) -> void: sent.append([c, p, n]))
	bc.set("clock_override_ms", 300000)
	var rendered0 := int(bc.get("pings_rendered"))
	var ro: Dictionary = bc.call("try_callout", origin, d)
	_check(bool(ro.get("ok", false)) and sent.size() == 1 and String(sent[0][0]) == "Red Snake Can" and int(sent[0][2]) >= 1 and (sent[0][1] as Vector3).distance_to(Vector3(-8.5, 0, 17.5)) < 0.1, "sent ping_callout(callout, pos, count): %s" % str(sent))
	_check(int(bc.get("pings_rendered")) == rendered0, "no local echo online (the server sends callout_pinged back)")
	nl.callout_pinged.emit({"room": "r", "peer": 7, "name": "Mate", "team": "ALPHA", "color": "red", "callout": "Blue Snake 2", "count": 2, "pos": Vector3(-35, 0, -15)})
	_check((bc.call("hud_texts") as Array).has("Mate: 2 in Blue Snake 2"), "callout_pinged -> HUD line: %s" % str(bc.call("hud_texts")))
	_check((bc.call("marker_texts") as Array).has("2 in Blue Snake 2"), "callout_pinged -> marker")
	nl.callout_pinged.emit({"room": "r", "peer": 9, "name": "Foe", "team": "BRAVO", "color": "blue", "callout": "Red Home", "count": 1, "pos": Vector3(0, 0, 48)})
	_check(not (bc.call("hud_texts") as Array).has("Foe: 1 in Red Home"), "other team's ping ignored")
	_check(String(CalloutsScript.hud_line_text({"name": "X", "count": 0, "callout": "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"})) == "X: 1 in ABCDEFGHIJKLMNOPQRSTUVWX", "names capped at 24 chars, count >= 1")
	bc.set("online_override", -1)
	bc.set("send_override", Callable())
	bc.call("tick", 5.0)

	print("[8] woodsball heli crash registry")
	arena.call("switch_arena_map", "woodsball_crash")
	await _frames(3)
	var wd := _check_map("woodsball_crash", ["Heli", "Nose", "Tail", "Tail Rotor", "Snake Tower", "Dorito Tower", "Red Tower", "Blue Tower", "Red Snake Spool", "Blue Snake Reel", "Red Snake 2", "Snake 50", "Blue Cake"])
	_check(_entry(wd, "Snake 50 Spool").is_empty() and _entry(wd, "Dorito 50 Spool").is_empty() and _entry(wd, "Center").is_empty(), "woods: hidden speedball spools / center bunker not listed")
	var post := arena.find_child("Tower_WestFlank_Post_1", true, false)
	_check(String(CalloutsScript.callout_for_collider(post, "woodsball_crash", arena)) == "Snake Tower", "a tower post resolves to its tower")
	_check(String(bc.call("current_map_id")) == "woodsball_crash", "map id follows switch_arena_map")
	arena.call("switch_arena_map", "speedball")
	await _frames(2)
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("BUNKER CALLOUTS TEST: ALL CHECKS PASSED")
		quit(0)
	else:
		print("BUNKER CALLOUTS TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
