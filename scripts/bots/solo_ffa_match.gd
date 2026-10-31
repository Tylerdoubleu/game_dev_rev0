extends Node
## v0.7 solo FFA deathmatch (plan: "Deathmatch = free-for-all vs bots"): the local player vs N BotPlayers (default 4),
## first to KILLS_TO_WIN eliminations wins. v0.7 (Tyler): ALL BOTS vs YOU - every bot hunts only the human player, never
## another bot (hunt_player_only), and a bot ball never eliminates a bot. You win at KILLS_TO_WIN; the match ends (a bot
## wins) as soon as any one bot reaches KILLS_TO_WIN eliminations on you.
## Offline only. Started from the arena menu ("SOLO FFA DEATHMATCH") or the web link ?solo=ffa[&tier=rookie|amateur]
## [&ffa_bots=N]. Keeps the practice range / snap_target_bot untouched (they are just switched off for this mode).

const BotPlayerScript = preload("res://scripts/bots/bot_player.gd")
const BotDifficultyScript = preload("res://scripts/bots/bot_difficulty.gd")
const BunkerGraphScript = preload("res://scripts/bots/bunker_graph.gd")

signal standings_changed(rows: Array)
signal ffa_match_over(winner_name: String)

const DEFAULT_BOTS: int = 4
const KILLS_TO_WIN: int = 10
const CALLSIGNS := ["Viper", "Ghost", "Rattler", "Blitz", "Hammer", "Nova", "Jinx", "Torque", "Fuse", "Mako", "Sly", "Rook"]
const PAINT_COLORS := [Color(1.0, 0.55, 0.1), Color(0.75, 0.3, 1.0), Color(0.15, 0.95, 0.85), Color(1.0, 0.92, 0.2), Color(0.95, 0.3, 0.55), Color(0.4, 1.0, 0.35)]
const ROLES := ["back", "front", "front", "mid", "mid", "back"]
## Break spots (no sides in FFA): the far gate and corners first, then the near corners, so bots start away from the player.
const SPAWNS := [
	{"pos": Vector3(0.0, 0.0, -45.5), "yaw": PI},
	{"pos": Vector3(-31.0, 0.0, -41.0), "yaw": PI},
	{"pos": Vector3(31.0, 0.0, -41.0), "yaw": PI},
	{"pos": Vector3(31.0, 0.0, 41.0), "yaw": 0.0},
	{"pos": Vector3(-31.0, 0.0, 41.0), "yaw": 0.0},
	{"pos": Vector3(0.0, 0.0, 45.5), "yaw": 0.0},
	{"pos": Vector3(-44.0, 0.0, 0.0), "yaw": -PI / 2.0},
	{"pos": Vector3(44.0, 0.0, 0.0), "yaw": PI / 2.0},
]

var arena: Node3D = null
var player: Node3D = null
var graph: RefCounted = null
var bots: Array = []
var tier: String = "amateur"
var kills_to_win: int = KILLS_TO_WIN
var scores := {} # name -> {"kills": int, "deaths": int, "is_player": bool}
var winner: String = ""
var active: bool = false
var _player_name: String = "You"
## Every credited elimination, oldest first: {"shooter", "victim", "zone", "feed"}. The kill feed line is built from
## the same shooter / victim names the standings credit, so the feed and the standings can never disagree.
var kill_log: Array = []

func combatants() -> Array:
	var out: Array = []
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		out.append(player)
	for b in bots:
		if is_instance_valid(b):
			out.append(b)
	return out

## opts: bots (int), tier ("rookie" / "amateur"), kills_to_win (int), seed (int), graph (prebuilt BunkerGraph)
func start(p_arena: Node3D, p_player: Node3D, opts: Dictionary = {}) -> void:
	arena = p_arena
	player = p_player
	tier = String(opts.get("tier", tier))
	kills_to_win = int(opts.get("kills_to_win", KILLS_TO_WIN))
	var count := clampi(int(opts.get("bots", DEFAULT_BOTS)), 1, 7)
	graph = opts.get("graph", null)
	if graph == null:
		graph = BunkerGraphScript.build(arena, "speedball")
	_player_name = NetworkLobby.local_callsign if NetworkLobby != null and not String(NetworkLobby.local_callsign).is_empty() else "You"
	scores.clear()
	winner = ""
	scores[_player_name] = {"kills": 0, "deaths": 0, "is_player": true}
	GameManager.death_limit_enabled = false
	GameManager.reset_match_stats()
	if player != null:
		player.add_to_group("pb_combatants")
		if player.has_signal("player_eliminated") and not player.is_connected("player_eliminated", _on_player_eliminated):
			player.connect("player_eliminated", _on_player_eliminated)
	var used := {_player_name.to_lower(): true}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", Time.get_ticks_usec()))
	var pool: Array = CALLSIGNS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	for i in count:
		var cs := ""
		for c in pool:
			if not used.has(String(c).to_lower()):
				cs = String(c)
				break
		if cs.is_empty():
			cs = "Bot%d" % (i + 1)
		used[cs.to_lower()] = true
		var sp: Dictionary = SPAWNS[i % SPAWNS.size()]
		var b := CharacterBody3D.new()
		b.set_script(BotPlayerScript)
		var role_i: String = ROLES[i % ROLES.size()]
		b.call("configure", {
			"callsign": cs, "bot_name": cs, "team": "FFA", "ffa": true, "hunt_player_only": true, "role": role_i, "index": i,
			"difficulty": BotDifficultyScript.make(tier), "graph": graph, "match": self,
			"paint_color": PAINT_COLORS[i % PAINT_COLORS.size()], "rig_team": "ALPHA" if i % 2 == 1 else "BRAVO",
			"spawn": sp["pos"], "spawn_yaw": sp["yaw"], "assigned_node": _break_bunker(role_i, sp["pos"]),
			"seed": rng.randi(),
		})
		arena.add_child(b)
		bots.append(b)
		scores[cs] = {"kills": 0, "deaths": 0, "is_player": false}
	active = true
	GameManager.register_round_start(count)
	_emit()

## Closest plan-role bunker to the spawn that no other bot has taken (FFA has no Red / Blue sides).
func _break_bunker(role_id: String, spawn: Vector3) -> int:
	var taken := {}
	for b in bots:
		taken[int(b.get("assigned_node"))] = true
	var best := -1
	var best_d := INF
	for i in graph.role_nodes(role_id, ""):
		if taken.has(i):
			continue
		var d: float = spawn.distance_to(graph.nodes[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best

## Web builds publish a tiny status object (window.__ffaState, 1 Hz) for the headless-Chrome smoke test / debugging.
var _web_state_t: float = 0.0
func _process(delta: float) -> void:
	if not active or not OS.has_feature("web"):
		return
	_web_state_t -= delta
	if _web_state_t > 0.0:
		return
	_web_state_t = 1.0
	var bs := {}
	for b in bots:
		if is_instance_valid(b):
			var p: Vector3 = (b as Node3D).global_position
			bs[String(b.get("bot_name"))] = {"x": snappedf(p.x, 0.1), "z": snappedf(p.z, 0.1), "state": String(b.call("state_name")),
				"moved": snappedf(float(b.get("distance_moved")), 0.1), "shots": int(b.get("shots_fired"))}
	JavaScriptBridge.eval("window.__ffaState = %s;" % JSON.stringify({"bots": bs, "standings": standings(), "winner": winner, "kills": kill_log.slice(-8)}), true)

func stop() -> void:
	active = false
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	GameManager.death_limit_enabled = true

func _exit_tree() -> void:
	GameManager.death_limit_enabled = true

func is_bot(n: Node) -> bool:
	return n in bots

func _name_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if n == player:
		return _player_name
	if "bot_name" in n:
		return String(n.get("bot_name"))
	return ""

func on_bot_eliminated(bot: Node, shooter: Node, zone: String = "") -> void:
	if not active:
		return
	if shooter != bot and is_bot(shooter):
		return # all bots vs you: bots never score on each other (the bot already ignores these balls)
	var victim := _name_of(bot)
	if scores.has(victim):
		scores[victim]["deaths"] += 1
	var killer := _name_of(shooter)
	if not killer.is_empty() and killer != victim and scores.has(killer):
		scores[killer]["kills"] += 1
	_log_kill(killer, victim, zone)
	_emit()
	_check_win(killer)

## Feed: SHOOTER SPLATTED VICTIM [zone] (same names as the standings rows).
func _log_kill(killer: String, victim: String, zone: String) -> void:
	var line := BotPlayerScript.kill_feed_line(killer if not killer.is_empty() else "?", victim, zone)
	kill_log.append({"shooter": killer, "victim": victim, "zone": zone, "feed": line})
	IntelBus.intel_feed_updated.emit(line)

func _on_player_eliminated(killer_label: String) -> void:
	if not active:
		return
	scores[_player_name]["deaths"] += 1
	var killer := String(player.get("last_shooter_name")) if player != null else ""
	if scores.has(killer) and killer != _player_name:
		scores[killer]["kills"] += 1
		var kb := _bot_named(killer)
		if kb != null:
			kb.set("kills", int(kb.get("kills")) + 1)
	var zone := ""
	var lb := killer_label.rfind("[")
	if lb >= 0 and killer_label.ends_with("]"):
		zone = killer_label.substr(lb + 1, killer_label.length() - lb - 2)
	_log_kill(killer, _player_name, zone)
	_emit()
	_check_win(killer)

func _bot_named(n: String) -> Node:
	for b in bots:
		if is_instance_valid(b) and String(b.get("bot_name")) == n:
			return b
	return null

func _check_win(killer: String) -> void:
	if killer.is_empty() or not scores.has(killer) or not winner.is_empty():
		return
	if int(scores[killer]["kills"]) >= kills_to_win:
		winner = killer
		active = false
		var label := "%s (%d eliminations)" % [winner, kills_to_win]
		GameManager.end_match("FFA Deathmatch", label)
		ffa_match_over.emit(winner)

func standings() -> Array:
	var rows: Array = []
	for n in scores.keys():
		var s: Dictionary = scores[n]
		rows.append({"name": n, "kills": int(s["kills"]), "deaths": int(s["deaths"]), "is_player": bool(s["is_player"])})
	rows.sort_custom(func(a, b): return a["kills"] > b["kills"] or (a["kills"] == b["kills"] and a["deaths"] < b["deaths"]))
	return rows

func _emit() -> void:
	standings_changed.emit(standings())
	_web_state_t = 0.0 # publish window.__ffaState on the next frame, so a browser check never pairs a new feed line with old standings

## Respawn spot farthest from every live combatant.
func respawn_point_for(who: Node) -> Dictionary:
	var best: Dictionary = SPAWNS[0]
	var best_score := -INF
	for sp in SPAWNS:
		var nearest := INF
		for c in combatants():
			if c == who or not is_instance_valid(c):
				continue
			if "is_eliminated" in c and bool(c.get("is_eliminated")):
				continue
			nearest = minf(nearest, (c as Node3D).global_position.distance_to(sp["pos"]))
		if nearest > best_score:
			best_score = nearest
			best = sp
	return best

## Player respawn zones for the respawn screen in FFA: the same farthest-from-everyone logic, top 5.
func player_respawn_zones() -> Array[Dictionary]:
	var scored: Array = []
	for sp in SPAWNS:
		var nearest := INF
		for b in bots:
			if is_instance_valid(b) and not bool(b.get("is_eliminated")):
				nearest = minf(nearest, (b as Node3D).global_position.distance_to(sp["pos"]))
		scored.append([nearest, sp])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array[Dictionary] = []
	for k in mini(5, scored.size()):
		var sp: Dictionary = scored[k][1]
		var p: Vector3 = sp["pos"]
		out.append({"title": "FFA Spawn %d" % (k + 1), "pos": Vector3(p.x, 0.1, p.z), "yaw": float(sp["yaw"]), "desc": "%.0fm from the nearest bot" % minf(scored[k][0], 999.0)})
	return out

func scoreboard_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("FREE-FOR-ALL DEATHMATCH  —  first to %d eliminations  (%s bots)" % [kills_to_win, BotDifficultyScript.make(tier).display_name])
	lines.append("----------------------------------------------------------------------")
	lines.append("#   NAME                            KILLS     DEATHS")
	var i := 1
	for r in standings():
		lines.append("%-3d %-30s  %-8d  %d" % [i, String(r["name"]) + (" (YOU)" if r["is_player"] else " [BOT]"), r["kills"], r["deaths"]])
		i += 1
	return lines
