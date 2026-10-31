extends SceneTree
## v0.6.3 respawn wiring: Ren's RespawnScreen is the arena's death_respawn_canvas. Opening it (the
## _on_local_player_eliminated path) frees the cursor; a click or 1-5 key (read by the screen itself, mirrored for
## BRAVO) fires the existing _on_respawn_zone_selected -> player.respawn_at_map_zone exactly once; Alpha = red,
## Bravo = blue; it closes on respawn, round_started (clear_gameplay_input_blocks) and match end.
## Run: godot --headless --path . -s scripts/systems/test_respawn_wiring.gd

var arena: Node
var player: Node
var failures: Array[String] = []
var started := false
var respawns: Array = []

func _initialize() -> void:
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
		await process_frame

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await _frames(1)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	root.push_input(r)
	await _frames(1)

func _lobby() -> Node:
	return root.get_node("NetworkLobby")

func _open(team: String, killer: String) -> RespawnScreen:
	_lobby().set("local_team", team)
	respawns.clear()
	arena.call("_open_respawn_screen", killer)
	await _frames(2)
	return arena.get("death_respawn_canvas") as RespawnScreen

func _run() -> void:
	await _frames(3)
	player = arena.get("player")
	var gm: Node = root.get_node("GameManager")
	player.connect("respawned", func(lbl: String) -> void: respawns.append(lbl))
	var guard: Node = null
	for n in arena.get_children():
		if n.has_method("capture_policy"):
			guard = n
	if guard == null:
		guard = root.find_child("MouseCaptureGuard", true, false)

	print("[1] RespawnScreen replaces the old overlay")
	var rs := arena.get("death_respawn_canvas") as RespawnScreen
	_check(rs != null and rs.get_parent() == arena and rs.name == "RespawnScreen", "death_respawn_canvas is Ren's RespawnScreen")
	_check(arena.get_node_or_null("DeathRespawnMapOverlay") == null, "old DeathRespawnMapOverlay is gone")
	_check(not rs.visible, "hidden until you get hit")

	print("[2] ALPHA: open + key 1 = snake corner, one respawn")
	rs = await _open("ALPHA", "Viper")
	_check(rs.visible and bool(player.get("awaiting_respawn_choice")), "open: screen up, awaiting_respawn_choice set")
	_check(rs._by_label.text == "by Viper", "header names the shooter")
	_check(rs._zones.size() == 5 and (rs._zones[0]["pos"] as Vector3).is_equal_approx((arena.call("_get_team_respawn_zones", "ALPHA")[0]["pos"])), "screen got the arena's ALPHA zones")
	_check(rs._deaths_label.text == "DEATHS %d / %d" % [int(gm.get("local_deaths")), int(gm.get("MAX_DEATHS_TO_LOSE"))], "deaths line from GameManager")
	if guard != null:
		_check(String(guard.call("capture_policy")) == "release", "respawn screen frees the cursor (guard policy = release)")
	_check(rs._team_color().r > rs._team_color().b, "ALPHA spots are red")
	await _key(KEY_1)
	var p: Vector3 = player.global_position
	_check(absf(p.x - (-31.0)) < 0.1 and absf(p.z - 38.5) < 0.6, "key 1 -> snake corner (-31, 38.5): %s" % str(p))
	_check(respawns.size() == 1, "exactly one respawn per key (arena no longer double-handles 1-5): %d" % respawns.size())
	_check(not rs.visible and not bool(player.get("awaiting_respawn_choice")), "screen closed, input unblocked")

	print("[3] BRAVO: mirrored, key 1 = leftmost (dorito corner), blue")
	rs = await _open("BRAVO", "")
	_check(rs._team_color().b > rs._team_color().r, "BRAVO spots are blue")
	_check(rs._spots[4].position.x < rs._spots[0].position.x, "BRAVO view mirrored")
	await _key(KEY_1)
	p = player.global_position
	_check(absf(p.x - 30.0) < 0.1 and absf(p.z - (-38.5)) < 0.6, "key 1 -> dorito corner (30, -38.5): %s" % str(p))
	_check(respawns.size() == 1, "one respawn")

	print("[4] click a spot -> existing respawn call")
	rs = await _open("ALPHA", "Viper")
	rs._spots[3].pressed.emit()
	await _frames(1)
	p = player.global_position
	_check(absf(p.x - 13.0) < 0.1 and absf(p.z - 33.5) < 0.6, "click spot 4 -> right brick (13, 33.5): %s" % str(p))
	_check(respawns.size() == 1 and not rs.visible, "one respawn, closed")

	print("[5] closes on round_started / match end")
	rs = await _open("ALPHA", "Viper")
	arena.call("clear_gameplay_input_blocks", "round_started")
	await _frames(1)
	_check(not rs.visible and not bool(player.get("awaiting_respawn_choice")), "clear_gameplay_input_blocks (round_started) closes it")
	rs = await _open("ALPHA", "Viper")
	root.get_node("NetworkLobby").emit_signal("room_event", "match_ended", {})
	await _frames(1)
	_check(not rs.visible and not bool(player.get("awaiting_respawn_choice")), "online match_ended closes it")
	rs = await _open("ALPHA", "Viper")
	arena.call("_on_match_over", "You", "OpFor")
	await _frames(1)
	_check(not rs.visible and not bool(player.get("awaiting_respawn_choice")), "offline match over closes it")
	gm.set("match_ended", true)
	rs = await _open("ALPHA", "Viper")
	_check(not rs.visible, "never opens once the match has ended")
	gm.set("match_ended", false)
	await _key(KEY_2)
	_check(respawns.is_empty(), "1-5 do nothing while the screen is closed")

	print("[6] shooter + death spot reach open() (real offline hit path)")
	_lobby().set("local_team", "ALPHA")
	_lobby().set("fill_bots_enabled", true)
	if arena.get_node_or_null("Bot_CenterAztec") == null:
		arena.call("_spawn_opfor_bots")
		await _frames(2)
	var bot := arena.get_node_or_null("Bot_CenterAztec") as Node3D
	_check(bot != null, "OpFor bots present")
	player.set("_respawn_flash_timer", 0.0)
	player.global_position = Vector3(6.0, 0.1, 22.0)
	var died_at: Vector3 = player.global_position
	var killer := [""]
	var cb := func(k: String) -> void: killer[0] = k
	player.connect("player_eliminated", cb)
	bot.set_process(false) # freeze its peek so the position we compare stays put
	var shot_from: Vector3 = bot.global_position
	player.call("on_paintball_break", player.global_position + Vector3(0, 1.4, 0), bot)
	player.disconnect("player_eliminated", cb)
	_check(killer[0].begins_with("OpFor Center-Aztec ["), "hit by the bot: killer '%s'" % killer[0])
	_check((player.get("last_death_position") as Vector3).is_equal_approx(died_at), "death spot captured before the reset to the start")
	rs = await _open("ALPHA", killer[0])
	_check(rs._death_pos.is_equal_approx(died_at), "open() got the death spot %s" % str(rs._death_pos))
	_check(bot != null and rs._shooter_pos.is_equal_approx(shot_from), "open() got the shooter position %s" % str(rs._shooter_pos))
	arena.call("_on_respawn_zone_selected", 2)
	await _frames(1)
	print("[7] half-field dot filter (ALPHA z>0, BRAVO z<0, none in deathmatch)")
	var cands := [{"team": "ALPHA", "pos": Vector3(5, 0, 20), "name": "a_home"}, {"team": "BRAVO", "pos": Vector3(-3, 0, 10), "name": "b_in_alpha_half"},
		{"team": "ALPHA", "pos": Vector3(0, 0, -15), "name": "a_in_bravo_half"}, {"team": "BRAVO", "pos": Vector3(2, 0, -40), "name": "b_home"},
		{"team": "BRAVO", "pos": Vector3(9, 0, 0.0), "name": "on_50"}]
	var names := func(arr: Array) -> Array:
		var o: Array = []
		for d in arr: o.append(d["name"])
		return o
	var fa: Array = names.call(arena.call("filter_dots_to_half", cands, "ALPHA", "practice"))
	_check(fa == ["a_home", "b_in_alpha_half"], "ALPHA: teammates + enemies on z>0 only %s" % str(fa))
	var fb: Array = names.call(arena.call("filter_dots_to_half", cands, "BRAVO", "ctf"))
	_check(fb == ["a_in_bravo_half", "b_home"], "BRAVO: everyone on z<0 only %s" % str(fb))
	_check((arena.call("filter_dots_to_half", cands, "ALPHA", "deathmatch") as Array).is_empty(), "deathmatch: no dots")
	print("[7b] bot dots: shown anywhere in a bot match (any mode), half-filtered otherwise")
	var bcands := [{"team": "BRAVO", "pos": Vector3(0, 0, -30), "name": "far_bot", "bot": true}, {"team": "BRAVO", "pos": Vector3(0, 0, -20), "name": "far_human"},
		{"team": "BRAVO", "pos": Vector3(0, 0, 12), "name": "near_human"}]
	_check(names.call(arena.call("respawn_dots_for", bcands, "ALPHA", "deathmatch", true)) == ["far_bot"], "bot match + deathmatch: humans none, every bot kept")
	_check(names.call(arena.call("respawn_dots_for", bcands, "ALPHA", "practice", true)) == ["near_human", "far_bot"], "bot match + team mode: humans on my half + every bot")
	_check(names.call(arena.call("respawn_dots_for", bcands, "ALPHA", "ctf", false)) == ["near_human"], "no bot match: v0.6.3 half rule for everyone")
	print("[8] live refresh while open (offline practice = a bot match: every live bot, anywhere, orange)")
	rs = await _open("ALPHA", "Viper")
	await create_timer(0.4).timeout
	var nbots := (arena.call("get_opfor_bots") as Array).filter(func(b) -> bool: return not bool(b.get("is_eliminated")) and (b as Node3D).visible).size()
	var dots0: Array = arena.get("respawn_map_dots")
	_check(bool(arena.call("is_bot_match")), "offline practice range counts as a bot match")
	_check(nbots > 0 and dots0.size() == nbots, "every live OpFor bot is sent though they all stand on the Bravo half (%d of %d)" % [dots0.size(), nbots])
	_check(dots0.all(func(d) -> bool: return bool(d.get("bot", false))), "every bot dot carries \"bot\": true")
	_check(bool(arena.get("respawn_map_show_all")), "set_players(dots, true) - show_all on in a bot match")
	_check(rs._dots.size() == nbots, "Ren's screen keeps all %d bot dots (show_all skips its half filter): %d" % [nbots, rs._dots.size()])
	bot.global_position = Vector3(-4.0, 0.0, 14.0)
	await create_timer(0.4).timeout
	var live: Array = arena.get("respawn_map_dots")
	var aztec := live.filter(func(d) -> bool: return String(d["name"]) == "OpFor Center-Aztec")
	_check(aztec.size() == 1 and (aztec[0]["pos"] as Vector3).is_equal_approx(Vector3(-4.0, 0.0, 14.0)) and not bool(aztec[0]["teammate"]), "moved bot's dot follows it within 0.25s: %s" % str(aztec))
	arena.set("respawn_map_mode_override", "deathmatch")
	await create_timer(0.4).timeout
	_check((arena.get("respawn_map_dots") as Array).size() == nbots and rs._dots.size() == nbots and bool(arena.get("respawn_map_show_all")), "deathmatch mode in a bot match: bots NOT stripped (%d)" % rs._dots.size())
	arena.set("respawn_map_mode_override", "")
	bot.global_position = Vector3(-4.0, 0.0, -14.0)
	await create_timer(0.4).timeout
	_check(rs._dots.size() == nbots, "bot back on its own half: still shown (%d)" % rs._dots.size())
	arena.call("_on_respawn_zone_selected", 2)

	print("=== [%s] v0.6.3 respawn wiring ===" % ("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
