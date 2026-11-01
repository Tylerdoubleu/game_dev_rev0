extends SceneTree
## v0.6.5 (Tyler playtest: "The 'FFA vs bots' is actually just team death match against a team of bots. Spawn them at
## the breakout for their team to avoid enemies spawning in behind me."): SINGLE PLAYER is YOU (ALPHA, +Z) vs a team of
## bots (BRAVO, -Z). Checks that every bot spawn and every bot respawn - wherever the player stands, all bots dying at
## once, and the real respawn timer - lands in the BRAVO breakout and never on the player's half; that the player's
## start and every respawn-map pick are in the ALPHA breakout; that the respawn map still gets every bot as a bot dot;
## that the HUD / banner / scoreboard say YOU vs BOTS / TEAM DEATHMATCH and never FFA; and first team to N wins.
## Run: godot --headless --path . -s scripts/systems/test_solo_tdm_spawns.gd

var MatchScript: GDScript # loaded in _initialize (after the autoloads exist)

var arena: Node3D
var failures: Array[String] = []
var started := false
var respawn_log: Array = [] # [bot_name, Vector3]

func _initialize() -> void:
	MatchScript = load("res://scripts/bots/solo_ffa_match.gd")
	arena = (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_d: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		failures.append(m)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _in_bravo(p: Vector3) -> bool:
	return MatchScript.in_team_breakout("BRAVO", p) and p.z < 0.0

func _in_alpha(p: Vector3) -> bool:
	return MatchScript.in_team_breakout("ALPHA", p) and p.z > 0.0

func _on_bot_respawned(b: Node) -> void:
	respawn_log.append([String(b.get("bot_name")), (b as Node3D).global_position])

func _run() -> void:
	await _frames(6)
	var lobby: Node = root.get_node("NetworkLobby")
	var GM: Node = root.get_node("GameManager")
	print("[1] spawn tables")
	for sp in MatchScript.team_spawns("BRAVO"):
		_check(_in_bravo(sp["pos"]) and is_equal_approx(float(sp["yaw"]), PI), "BRAVO spawn %s in the BRAVO breakout, facing +Z (%s)" % [sp["id"], str(sp["pos"])])
	for sp in MatchScript.team_spawns("ALPHA"):
		_check(_in_alpha(sp["pos"]), "ALPHA spawn %s in the ALPHA breakout (%s)" % [sp["id"], str(sp["pos"])])

	print("[2] start: 7 bots, you are ALPHA even if the lobby had you on BRAVO")
	lobby.set("local_team", "BRAVO")
	var m: Node = arena.call("start_solo_ffa", {"bots": 7, "tier": "amateur", "kills_to_win": 10, "seed": 3})
	await _frames(3)
	_check(m != null, "match started")
	if m == null:
		_finish()
		return
	_check(String(lobby.get("local_team")) == "ALPHA" and String(m.get("player_team")) == "ALPHA" and String(m.get("bot_team")) == "BRAVO", "you = ALPHA, bots = BRAVO")
	var player: Node3D = arena.get("player")
	_check(player != null and _in_alpha(player.global_position), "player starts at the ALPHA breakout (%s)" % (str(player.global_position) if player else "-"))
	var bots: Array = m.get("bots")
	_check(bots.size() == 7, "7 bots (%d)" % bots.size())
	var starts := {}
	for b in bots:
		var p: Vector3 = (b as Node3D).global_position
		_check(String(b.get("team")) == "BRAVO" and not bool(b.get("ffa")) and String(b.get("rig_team")) == "BRAVO", "%s on the BRAVO team (jersey too)" % b.get("bot_name"))
		_check(_in_bravo(p), "%s spawns in the BRAVO breakout (%s)" % [b.get("bot_name"), str(p)])
		var an := int(b.get("assigned_node"))
		var graph: RefCounted = m.get("graph")
		_check(an >= 0 and Vector3(graph.nodes[an]["pos"]).z < 0.0, "%s breaks to a bunker on the BRAVO half (%s)" % [b.get("bot_name"), String(graph.nodes[an]["callout"]) if an >= 0 else "none"])
		starts["%.1f,%.1f" % [p.x, p.z]] = true
		b.connect("bot_respawned", _on_bot_respawned)
	_check(starts.size() == 7, "no two bots share a start spot (%d distinct)" % starts.size())

	print("[3] bot respawns wherever you stand")
	var spots := [Vector3(0, 0.1, 45.5), Vector3(0, 0.1, 0), Vector3(-30, 0.1, -20), Vector3(0, 0.1, -44), Vector3(31, 0.1, -41)]
	for ps in spots:
		player.global_position = ps
		for b in bots:
			b.call("_die")
			b.call("respawn")
			var p: Vector3 = (b as Node3D).global_position
			_check(_in_bravo(p), "you at %s: %s respawns in the BRAVO breakout (%s)" % [str(ps), b.get("bot_name"), str(p)])
	player.global_position = Vector3(0, 0.1, 45.5)
	# all seven down at once, then respawn one by one: each takes a free spot
	for b in bots:
		b.call("_die")
	var taken := {}
	for b in bots:
		b.call("respawn")
		var p: Vector3 = (b as Node3D).global_position
		taken["%.1f,%.1f" % [p.x, p.z]] = true
	_check(taken.size() == 7, "seven simultaneous respawns use seven different breakout spots (%d)" % taken.size())

	print("[4] real elimination -> respawn timer")
	respawn_log.clear()
	var victim: Node3D = bots[0]
	victim.set("_respawn_flash_timer", 0.0)
	victim.call("on_paintball_break", victim.global_position + Vector3(0, 1.3, 0), player)
	_check(bool(victim.get("is_eliminated")), "your ball eliminates %s" % victim.get("bot_name"))
	var waited := 0
	while bool(victim.get("is_eliminated")) and waited < 600:
		await _frames(10)
		waited += 10
	_check(not respawn_log.is_empty(), "%s came back on its own timer" % victim.get("bot_name"))
	for r in respawn_log:
		_check(_in_bravo(r[1]), "timer respawn of %s in the BRAVO breakout (%s)" % [r[0], str(r[1])])

	print("[5] your respawn map: own breakout zones only, bot dots kept")
	var zones: Array = arena.call("_respawn_zones_for_local", true)
	_check(zones.size() == 5, "5 respawn zones (%d)" % zones.size())
	for i in zones.size():
		var z: Dictionary = zones[i]
		_check(_in_alpha(z["pos"]) and z.has("map_uv") and z.has("id"), "zone %s in the ALPHA breakout (%s)" % [String(z.get("title", "")), str(z["pos"])])
	for i in zones.size():
		player.set("last_shooter_name", String(bots[1].get("bot_name")))
		arena.call("_open_respawn_screen", String(bots[1].get("bot_name")))
		await _frames(1)
		var rs: CanvasLayer = arena.get("death_respawn_canvas")
		_check(rs != null and rs.visible, "respawn map opens after a splat (pick %d)" % (i + 1))
		var dots: Array = arena.get("respawn_map_dots")
		var all_bot := dots.size() == 7
		for d in dots:
			all_bot = all_bot and bool((d as Dictionary).get("bot", false))
		_check(all_bot and bool(arena.get("respawn_map_show_all")), "respawn map gets all 7 bots as bot dots, show_all (%d)" % dots.size())
		arena.call("_on_respawn_zone_selected", i)
		await _frames(1)
		_check(_in_alpha(player.global_position), "pick %d respawns you in the ALPHA breakout (%s)" % [i + 1, str(player.global_position)])
	var bc: Node = arena.get_node_or_null("BunkerCallouts")
	if bc != null:
		_check((bc.call("enemy_nodes") as Array).size() == 7, "bunker callouts see all 7 bots as enemies")

	print("[6] wording: YOU vs BOTS / TEAM DEATHMATCH, never FFA")
	arena.call("_on_round_updated", 1, 0, 120.0)
	var rl: Label = arena.get("round_label")
	_check(rl != null and rl.text.contains("YOU vs BOTS") and rl.text.contains("TEAM DEATHMATCH") and not rl.text.contains("FFA"), "HUD: %s" % (rl.text.split("\n")[0] if rl else "-"))
	var sb := "\n".join(m.call("scoreboard_lines"))
	_check(sb.contains("YOU vs BOTS") and not sb.contains("FFA") and not sb.contains("FREE-FOR-ALL"), "scoreboard header: %s" % sb.split("\n")[0])
	arena.call("stop_solo_ffa")
	await _frames(2)
	m = arena.call("start_solo_ffa", {"bots": 3, "tier": "rookie", "kills_to_win": 2})
	var sl: Label = arena.get("status_label")
	_check(sl != null and sl.text.contains("YOU vs BOTS") and not sl.text.contains("FFA"), "start banner: %s" % (sl.text if sl else "-"))

	print("[7] first team to N")
	bots = m.get("bots")
	m.call("on_bot_eliminated", bots[0], player)
	_check(String(m.get("winner")) == "", "YOU 1 - BOTS 0: match continues")
	player.set("last_shooter_name", String(bots[1].get("bot_name")))
	player.emit_signal("player_eliminated", "%s [GOGGLE]" % bots[1].get("bot_name"))
	player.set("last_shooter_name", String(bots[2].get("bot_name")))
	player.emit_signal("player_eliminated", "%s [GOGGLE]" % bots[2].get("bot_name"))
	_check(String(m.get("winner")) == "BOTS" and bool(GM.get("match_ended")), "two different bots, one each: the bot team reaches 2 and wins")
	_check(sl.text.contains("BOTS WIN") and not sl.text.contains("FFA"), "end banner: %s" % sl.text)
	arena.call("stop_solo_ffa")
	await _frames(2)
	GM.set("match_ended", false)
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("SOLO TDM SPAWNS TEST: ALL PASSED")
		quit(0)
	else:
		print("SOLO TDM SPAWNS TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("   - " + f)
		quit(1)
