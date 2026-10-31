extends SceneTree
## v0.7 Solo FFA deathmatch (Bluey, plan "Smarter bots"): ?solo=ffa query parsing, 4 bots with unique callsigns spawn
## through the arena entry point, the respawn map runs in deathmatch mode, FFA bots paint EACH OTHER (bot-on-bot kills
## credited in the standings), every snap shot had an independent raycast line of sight to its target, first-to-N ends
## the match with a winner, and stopping restores the GameManager death limit.
## Run: godot --headless --path . -s scripts/systems/test_ffa_bots.gd

var BotPlayerScript: GDScript # loaded in _initialize (after the autoloads exist)
var ArenaScript: GDScript

var arena: Node3D
var GM: Node
var failures: Array[String] = []
var started := false
var snap_checked := 0
var snap_no_los := 0
var bot_on_bot_kills := 0

func _initialize() -> void:
	BotPlayerScript = load("res://scripts/bots/bot_player.gd")
	ArenaScript = load("res://scripts/systems/speedball_arena_builder.gd")
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

## `seconds` of game time (physics delta is already scaled by Engine.time_scale).
func _sim(seconds: float) -> void:
	await _frames(maxi(1, int(ceil(seconds * float(Engine.physics_ticks_per_second) / Engine.time_scale))))

func _run() -> void:
	GM = root.get_node("GameManager")
	await _frames(4)
	_test_query()
	Engine.time_scale = 4.0
	await _test_ffa_match()
	await _test_first_to_n()
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("FFA BOTS TEST: ALL PASSED")
		quit(0)
	else:
		print("FFA BOTS TEST: %d FAILURE(S)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)

func _test_query() -> void:
	var o: Dictionary = ArenaScript.parse_ffa_query("?solo=ffa")
	_check(int(o.get("bots", 0)) == 4 and String(o.get("tier", "")) == "amateur", "?solo=ffa -> 4 amateur bots (%s)" % str(o))
	o = ArenaScript.parse_ffa_query("?solo=ffa&tier=rookie&ffa_bots=12")
	_check(int(o.get("bots", 0)) == 7 and String(o.get("tier", "")) == "rookie", "tier=rookie, ffa_bots clamped to 7 (%s)" % str(o))
	o = ArenaScript.parse_ffa_query("?room=abc")
	_check(o.is_empty(), "no solo=ffa -> no auto start")

func _on_shot(bot: Node, _origin: Vector3, _aim: Vector3, kind: String) -> void:
	if kind != "snap":
		return
	snap_checked += 1
	var tgt: Node3D = bot.get("current_target")
	if tgt == null:
		snap_no_los += 1
		return
	var eye: Vector3 = bot.call("eye_position")
	var space := (bot as Node3D).get_world_3d().direct_space_state
	var seen := false
	for ap in BotPlayerScript.aim_points_of(tgt):
		var q := PhysicsRayQueryParameters3D.create(eye, ap)
		q.exclude = [(bot as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			seen = true
		else:
			var col: Object = hit.get("collider")
			if col == tgt or (col is Node and tgt.is_ancestor_of(col)) or (hit["position"] as Vector3).distance_to(ap) < 0.35:
				seen = true
		if seen:
			break
	if not seen:
		snap_no_los += 1

func _on_bot_elim(_bot: Node, shooter: Node, _zone: String) -> void:
	if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("bot_players"):
		bot_on_bot_kills += 1

func _test_ffa_match() -> void:
	var player: Node3D = arena.get("player")
	var m: Node = arena.call("start_solo_ffa", {"bots": 4, "tier": "amateur", "seed": 7})
	_check(m != null and bool(arena.call("is_solo_ffa_active")), "start_solo_ffa creates the match")
	if m == null:
		return
	if player != null:
		player.global_position = Vector3(0, 0.1, 62.5) # park the human behind the gate so the bots fight each other
	var bots: Array = m.get("bots")
	_check(bots.size() == 4, "default FFA has 4 bots (%d)" % bots.size())
	var names := {}
	for b in bots:
		names[String(b.get("bot_name")).to_lower()] = true
		b.connect("shot_fired", _on_shot)
		b.connect("bot_eliminated", _on_bot_elim)
		_check(bool(b.get("ffa")), "%s is FFA" % b.get("bot_name"))
	_check(names.size() == 4 and not names.has(String(m.get("_player_name")).to_lower()), "callsigns unique (and not the player's): %s" % str(names.keys()))
	_check(int(m.get("kills_to_win")) == 10, "first to 10")
	_check(not bool(GM.get("death_limit_enabled")), "GameManager death limit off during FFA")
	_check(String(arena.call("respawn_map_mode")) == "deathmatch", "respawn map in deathmatch mode")
	# HUD: no CTF text during FFA - your eliminations, the leader and first-to-N instead.
	arena.call("_on_round_updated", 1, 0, 200.0)
	var rl: Label = arena.get("round_label")
	if rl != null:
		var hud := rl.text
		_check(not hud.contains("FLAG:") and not hud.contains("DEATHS:") and not hud.contains("Flag Pull"), "FFA HUD hides CTF flag / death-limit text")
		_check(hud.contains("YOUR ELIMS: 0") and hud.contains("LEADER:") and hud.contains("FIRST TO 10"), "FFA HUD shows your elims, leader, first to 10")
		arena.call("_on_status_banner", "BUZZER! CLEAN BREAKOUT! (+15% Sprint Burst for 1.5s — Go Get Center Flag!)", Color.WHITE)
		var sl: Label = arena.get("status_label")
		_check(sl == null or not sl.text.contains("Center Flag"), "FFA breakout banner drops 'Go Get Center Flag'")
	var ft: String = ArenaScript.ffa_round_text([{"name": "Viper", "kills": 4, "deaths": 1, "is_player": false}, {"name": "Me", "kills": 2, "deaths": 3, "is_player": true}], 10, 90.0)
	_check(ft.contains("YOUR ELIMS: 2") and ft.contains("LEADER: Viper (4)") and ft.contains("FIRST TO 10"), "ffa_round_text: elims 2, leader Viper (4), first to 10")
	var zones: Array = m.call("player_respawn_zones")
	_check(zones.size() >= 3, "player gets FFA respawn zones (%d)" % zones.size())
	var start_pos := {}
	for b in bots:
		start_pos[b] = (b as Node3D).global_position
	var t := 0.0
	while t < 150.0 and bot_on_bot_kills < 2:
		await _sim(1.0)
		t += 1.0
	var moved := 0
	for b in bots:
		if float(b.get("distance_moved")) > 5.0:
			moved += 1
	_check(moved >= 3, "bots move around (%d of 4 moved > 5 m)" % moved)
	_check(bot_on_bot_kills >= 1, "FFA bots eliminate each other (%d bot-on-bot kills in %.0f s)" % [bot_on_bot_kills, t])
	var bot_kills_in_standings := 0
	for row in m.call("standings"):
		if not bool(row["is_player"]):
			bot_kills_in_standings += int(row["kills"])
	_check(bot_kills_in_standings >= bot_on_bot_kills, "standings credit the kills (%d)" % bot_kills_in_standings)
	_check(snap_checked > 0 and snap_no_los == 0, "every snap shot had raycast LOS to its target (%d shots, %d without)" % [snap_checked, snap_no_los])
	var respawned := 0
	for b in bots:
		if int(b.get("deaths")) > 0 and not bool(b.get("is_eliminated")):
			respawned += 1
	print("    standings: %s" % str(m.call("standings")))
	arena.call("stop_solo_ffa")
	await _frames(2)
	_check(not bool(arena.call("is_solo_ffa_active")), "stop_solo_ffa ends the match")
	_check(bool(GM.get("death_limit_enabled")), "death limit restored after stop")
	_check(get_nodes_in_group("bot_players").is_empty(), "FFA bots removed on stop")
	arena.call("_on_round_updated", 1, 5, 200.0)
	var rl2: Label = arena.get("round_label")
	_check(rl2 == null or rl2.text.contains("FLAG:"), "CTF HUD text back after FFA stops")

func _test_first_to_n() -> void:
	var m: Node = arena.call("start_solo_ffa", {"bots": 2, "tier": "amateur", "kills_to_win": 2})
	var bots: Array = m.get("bots")
	var a: Node = bots[0]
	var b: Node = bots[1]
	var over := [""]
	m.connect("ffa_match_over", func(w): over[0] = w)
	m.call("on_bot_eliminated", b, a)
	_check(String(m.get("winner")) == "" and not bool(GM.get("match_ended")), "1 kill: match continues")
	m.call("on_bot_eliminated", b, a)
	_check(String(m.get("winner")) == String(a.get("bot_name")) and over[0] == String(a.get("bot_name")), "2 kills with kills_to_win=2: %s wins" % a.get("bot_name"))
	_check(bool(GM.get("match_ended")), "GameManager match ended")
	arena.call("stop_solo_ffa")
	await _frames(2)
