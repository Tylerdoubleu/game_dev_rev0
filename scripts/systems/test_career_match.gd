extends SceneTree
## v0.7 solo career (Bluey): the three Tier 1 match types end to end in the real speedball arena, driven through the
## /root/CareerRunner autoload with a mocked ProfileApi (no HTTP, temp save):
##   Opening Day (YOU vs BOT TEAM TDM) / Last One Standing (one-life rounds, first to 3) / Run the Snake (gauntlet)
## Run: godot --headless --path . -s scripts/systems/test_career_match.gd

const TMP_SAVE := "user://test_career_match.json"
var arena: Node3D
var fails: Array[String] = []
var started := false
var runner: Node
var api: ProfileApi

class StubApi extends ProfileApi:
	var calls: Array = []
	func _ready() -> void:
		token = "t".repeat(64)
	func _save() -> void:
		pass
	func _load() -> void:
		pass
	func _request(action: String, _path: String, _method: int, body) -> void:
		calls.append([action, body])
		match action:
			"solo_award":
				_on_reply(action, 200, {"awarded": true, "clout": 0})
			"get":
				_on_reply(action, 200, {"callsign": "ACE", "clout": 0, "career": null})
			_:
				_on_reply(action, 200, {})

func _initialize() -> void:
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
		fails.append(m)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	await _frames(20)
	runner = root.get_node_or_null("CareerRunner")
	_check(runner != null, "CareerRunner autoload")
	if runner == null:
		quit(1)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	runner.set("save_path", TMP_SAVE)
	runner.get("progress").reset()
	runner.set("results_delay_s", 0.0)
	api = StubApi.new()
	root.add_child(api)
	runner.call("bind_api", api)
	var lc: CanvasLayer = arena.get("lobby_canvas")
	_check(lc != null and lc.find_child("CareerButton", true, false) != null, "CAREER button in the TAB menu")
	runner.call("open_career")
	await _frames(2)
	_check(String(runner.get("state")) == "menu", "career screen open")
	await _test_tdm()
	await _test_elimination()
	await _test_gauntlet()
	var p := (runner.get("progress") as RefCounted)
	_check(int(p.call("total_stars")) >= 6, "career stars after the three events: %d" % int(p.call("total_stars")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	if fails.is_empty():
		print("CAREER MATCH TEST: ALL PASSED")
		quit(0)
	else:
		print("CAREER MATCH TEST: %d FAILURE(S)" % fails.size())
		for f in fails:
			print("  - " + f)
		quit(1)

func _splat(bot: Node, by: Node, revive: bool = false) -> void:
	if revive and bool(bot.get("is_eliminated")):
		bot.call("respawn")
	bot.set("_respawn_flash_timer", 0.0)
	bot.call("on_paintball_break", (bot as Node3D).global_position + Vector3(0, 1.2, 0), by)

func _test_tdm() -> void:
	print("Opening Day (TDM)")
	_check(bool(runner.call("start_challenge", "t1.opening_day")), "start_challenge")
	await _frames(3)
	var m: Node = arena.get("ffa_match")
	_check(m != null and String(m.get("mode")) == "tdm" and (m.get("bots") as Array).size() == 4, "4-bot TDM running")
	_check(String(runner.get("state")) == "in_match" and runner.get("current_match") == m, "runner attached to the arena's match")
	_check(String(arena.get_script().get("ffa_rematch_opts").get("career_challenge", "")) == "t1.opening_day", "rematch opts keep the career id")
	var pl: Node = arena.get("player")
	pl.set("slide_timer", 0.4)
	var bots: Array = m.get("bots")
	for i in 10:
		_splat(bots[i % bots.size()], pl, true)
		await _frames(1)
		if i == 1:
			pl.set("slide_timer", 0.0)
	await _frames(3)
	_check(bool(m.call("player_won")), "10 eliminations wins")
	_check(String(runner.get("state")) == "results", "results state")
	var out: Dictionary = runner.get("last_outcome")
	var r: Dictionary = runner.get("last_result")
	_check(int(r.get("style_kills", 0)) >= 2, "slide kills counted as style (%d)" % int(r.get("style_kills", 0)))
	_check(int((out.get("eval", {}) as Dictionary).get("count", 0)) == 3, "3 stars (%s)" % str(out.get("eval")))
	_check(_count("solo_award") == 4, "4 solo_award calls (3 stars + challenge): %d" % _count("solo_award"))
	_check(String(arena.get("status_label").text).contains("CAREER RESULTS"), "banner points at the results")

func _test_elimination() -> void:
	print("Last One Standing (elimination)")
	(runner.get("results") as Node).emit_signal("career_pressed")
	await _frames(1)
	(runner.get("screen") as Node).emit_signal("play_pressed", "t1.last_one_standing")
	await _frames(3)
	var m: Node = arena.get("ffa_match")
	_check(m != null and String(m.get("mode")) == "elimination" and (m.get("bots") as Array).size() == 3, "3-bot elimination")
	_check(bool(arena.call("is_one_life_round_live")), "arena reports a one-life round (hit = spectate)")
	_check(String(arena.get("round_label").text).contains("ELIMINATION"), "elimination HUD line")
	var pl: Node = arena.get("player")
	var bots: Array = m.get("bots")
	# Round 1: you clear the field
	for b in bots:
		_splat(b, pl)
	await _frames(1)
	_check(int(m.get("rounds_won")) == 1 and not bool(m.get("round_live")), "round 1 won, intermission")
	_check(float(bots[0].get("respawn_timer")) == 0.0 or not bool(bots[0].get("is_eliminated")), "bots stood back up for the next round")
	var all_back := true
	for b in bots:
		all_back = all_back and not bool(b.get("is_eliminated")) and (b as Node3D).global_position.z < 0.0
	_check(all_back, "all bots back on their own (BRAVO, -Z) breakout")
	m.call("start_next_round")
	# Round 2: you get hit
	m.call("_on_player_eliminated", "Viper [GOGGLES]")
	_check(int(m.get("rounds_lost")) == 1, "round 2 lost")
	m.call("start_next_round")
	for b in bots:
		_splat(b, pl)
	m.call("start_next_round")
	for b in bots:
		_splat(b, pl)
	await _frames(3)
	_check(String(m.get("winner")) != "" and bool(m.call("player_won")), "3-1: you win")
	_check(String(runner.get("state")) == "results", "results")
	var r: Dictionary = runner.get("last_result")
	_check(String(arena.get("round_label").text).contains("YOU 3 : 1 BOTS"), "HUD shows the final 3 : 1")
	_check(int(r.get("rounds_won", 0)) == 3 and int(r.get("rounds_lost", 0)) == 1, "result rounds 3-1")
	var out: Dictionary = runner.get("last_outcome")
	_check(out.get("new_stars", []) == [1, 2], "stars 1 + 2 (%s)" % str(out.get("new_stars")))

func _test_gauntlet() -> void:
	print("Run the Snake (gauntlet)")
	_check(bool(runner.call("retry")) == true, "retry works") # retry last_one_standing then switch
	await _frames(2)
	_check(bool(runner.call("start_challenge", "t1.run_the_snake")), "start the snake")
	await _frames(3)
	var g: Node = arena.get("ffa_match")
	_check(g != null and g.get_script().resource_path.ends_with("gauntlet_run.gd"), "gauntlet running")
	_check((arena.call("get_opfor_bots") as Array).size() > 0, "practice peekers up")
	_check(String(arena.get("round_label").text).contains("POPS"), "gauntlet HUD")
	for i in 5:
		g.call("record_pop")
	await _frames(3)
	_check(String(runner.get("state")) == "results", "results")
	var r: Dictionary = runner.get("last_result")
	_check(bool(r.get("finished", false)) and int(r.get("pops", 0)) == 5, "5 pops finished (%s)" % str(r))
	var out: Dictionary = runner.get("last_outcome")
	_check(int((out.get("eval", {}) as Dictionary).get("count", 0)) == 3, "fast clean run -> 3 stars")
	arena.call("stop_solo_ffa")

func _count(action: String) -> int:
	var n := 0
	for c in (api as StubApi).calls:
		if c[0] == action:
			n += 1
	return n
