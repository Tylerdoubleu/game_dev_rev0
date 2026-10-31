extends SceneTree
## v0.6.4 SINGLE PLAYER (Bluey): the SoloLauncher autoload's start_ffa(tier, bots, kills_to_win) does what ?solo=ffa
## does - closes the lobby browser, starts the all-bots-vs-you Solo FFA (bots spawned, FFA HUD, deathmatch respawn map)
## - the ?solo=ffa path goes through it too, Ren's SINGLE PLAYER button (lobby_browser.gd) calls it, and with no arena
## loaded it loads the speedball arena itself.
## Run: godot --headless --path . -s scripts/systems/test_solo_launcher.gd

var arena: Node3D
var failures: Array[String] = []
var started := false

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

func _run() -> void:
	await _frames(20) # LobbyEntryFlow attaches within ~10 frames
	var launcher: Node = root.get_node_or_null("SoloLauncher")
	_check(launcher != null and launcher.has_method("start_ffa"), "SoloLauncher autoload at /root/SoloLauncher")
	if launcher == null:
		quit(1)
		return
	_check(launcher.get_script().get_global_name() == &"", "no class_name on the autoload script")
	_test_opts(launcher)
	await _test_ren_button(launcher)
	await _test_rookie_custom(launcher)
	await _test_url_path()
	await _test_no_arena(launcher)
	if failures.is_empty():
		print("SOLO LAUNCHER TEST: ALL PASSED")
		quit(0)
	else:
		print("SOLO LAUNCHER TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

func _test_opts(launcher: Node) -> void:
	var o: Dictionary = launcher.make_opts()
	_check(o == {"tier": "amateur", "bots": 4, "kills_to_win": 10}, "defaults: amateur, 4 bots, first to 10 (%s)" % str(o))
	o = launcher.make_opts("ROOKIE ", 12, 0)
	_check(o == {"tier": "rookie", "bots": 7, "kills_to_win": 1}, "tier normalised, bots clamped to 7, kills >= 1 (%s)" % str(o))
	o = launcher.make_opts("pro")
	_check(String(o["tier"]) == "amateur", "unknown tier falls back to amateur")

## Ren's SINGLE PLAYER click: lobby browser open (the bare-link start screen), pick ROOKIE / AMATEUR, press it -> FFA.
func _test_ren_button(launcher: Node) -> void:
	var flow := root.get_node_or_null("LobbyEntryFlow")
	_check(flow != null and flow.has_method("open_browser"), "LobbyEntryFlow present")
	if flow == null:
		return
	var b: Control = flow.call("open_browser")
	_check(bool(flow.call("is_open")), "lobby browser open before the click")
	var single := b.find_child("SinglePlayerButton", true, false) as Button
	var amateur := b.find_child("Difficulty_amateur", true, false) as Button
	_check(single != null and amateur != null, "Ren's SINGLE PLAYER button + AMATEUR pick found")
	if single == null:
		return
	var got := []
	launcher.ffa_started.connect(func(m): got.append(m), CONNECT_ONE_SHOT)
	amateur.pressed.emit()
	single.pressed.emit()
	await _frames(6)
	_check(String(b.get("last_solo_route")) == "solo_launcher", "button routed through the autoload (%s)" % str(b.get("last_solo_route")))
	var m: Node = arena.get("ffa_match")
	_check(got.size() == 1 and got[0] == m and launcher.last_match == m, "autoload started the match (ffa_started / last_match)")
	_check(m != null and bool(arena.call("is_solo_ffa_active")), "click -> Solo FFA running")
	_check(not bool(flow.call("is_open")), "lobby browser closed by the launcher")
	if m == null:
		return
	_check((m.get("bots") as Array).size() == 4, "4 bots in the match (%d)" % (m.get("bots") as Array).size())
	_check(get_nodes_in_group("bot_players").size() == 4, "4 BotPlayers spawned in the scene (%d)" % get_nodes_in_group("bot_players").size())
	_check(String(m.get("tier")) == "amateur", "AMATEUR pick -> amateur tier (%s)" % str(m.get("tier")))
	_check(int(m.get("kills_to_win")) == 10, "first to 10")
	for bot in m.get("bots"):
		_check(bool(bot.get("ffa")) and bool(bot.get("hunt_player_only")), "%s: FFA bot hunting the player" % bot.get("bot_name"))
	_check(String(arena.call("respawn_map_mode")) == "deathmatch", "respawn map in deathmatch mode")
	_check(not bool(root.get_node("GameManager").get("death_limit_enabled")), "death limit off (FFA)")
	var lc: Variant = arena.get("lobby_canvas")
	_check(lc == null or not (lc as CanvasLayer).visible, "arena lobby overlay hidden")
	arena.call("_on_round_updated", 1, 0, 200.0)
	var rl: Label = arena.get("round_label")
	_check(rl != null and rl.text.contains("YOUR ELIMS") and rl.text.contains("FIRST TO 10") and not rl.text.contains("FLAG:"), "HUD in FFA mode (%s)" % (rl.text.split("\n")[0] if rl != null else "no label"))
	# ROOKIE pick on Ren's button
	b = flow.call("open_browser")
	(b.find_child("Difficulty_rookie", true, false) as Button).pressed.emit()
	(b.find_child("SinglePlayerButton", true, false) as Button).pressed.emit()
	await _frames(4)
	m = arena.get("ffa_match")
	_check(m != null and String(m.get("tier")) == "rookie" and not bool(flow.call("is_open")), "ROOKIE pick -> rookie FFA, browser closed")

func _test_rookie_custom(launcher: Node) -> void:
	launcher.start_ffa("rookie", 2, 5)
	await _frames(4)
	var m: Node = launcher.last_match
	_check(m != null and m == arena.get("ffa_match"), "second start replaces the first match")
	if m == null:
		return
	_check(String(m.get("tier")) == "rookie" and (m.get("bots") as Array).size() == 2 and int(m.get("kills_to_win")) == 5, "rookie, 2 bots, first to 5")
	_check(get_nodes_in_group("bot_players").size() == 2, "old bots removed, 2 left (%d)" % get_nodes_in_group("bot_players").size())

## ?solo=ffa&tier=rookie&ffa_bots=3 goes through the same launcher (browser closed after the entry flow attaches).
func _test_url_path() -> void:
	arena.call("stop_solo_ffa")
	var flow := root.get_node_or_null("LobbyEntryFlow")
	if flow != null:
		flow.call("open_browser")
	var opts: Dictionary = arena.get_script().parse_ffa_query("?solo=ffa&tier=rookie&ffa_bots=3")
	await arena.call("_start_ffa_when_lobby_ready", opts)
	await _frames(2)
	var m: Node = arena.get("ffa_match")
	_check(m != null and String(m.get("tier")) == "rookie" and (m.get("bots") as Array).size() == 3 and int(m.get("kills_to_win")) == 10, "?solo=ffa link -> rookie, 3 bots, first to 10")
	if flow != null:
		_check(not bool(flow.call("is_open")), "?solo=ffa closes the browser")

## No arena loaded (e.g. some other screen is the current scene): the autoload loads the speedball arena itself.
func _test_no_arena(launcher: Node) -> void:
	arena.call("stop_solo_ffa")
	var blank := Node.new()
	blank.name = "BlankScreen"
	root.add_child(blank)
	current_scene = blank
	root.remove_child(arena)
	arena.free()
	await _frames(2)
	_check(launcher.find_arena() == null, "no arena in the tree")
	var got := []
	launcher.ffa_started.connect(func(m): got.append(m), CONNECT_ONE_SHOT)
	launcher.start_ffa("rookie", 3)
	for i in 60:
		await process_frame
		if not got.is_empty():
			break
	var a2: Node = launcher.find_arena()
	_check(a2 != null and a2 == current_scene, "arena loaded by the launcher")
	_check(got.size() == 1 and got[0] != null and String(got[0].get("tier")) == "rookie" and (got[0].get("bots") as Array).size() == 3, "FFA started on the loaded arena (rookie, 3 bots)")
	if a2 != null:
		a2.call("stop_solo_ffa")
