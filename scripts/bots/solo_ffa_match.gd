extends Node
## v0.7 solo vs bots (offline). v0.6.5 (Tyler playtest): this is YOU vs A TEAM OF BOTS - a team deathmatch, not a
## free-for-all. You play your team (ALPHA, the home side, +Z); every bot is on the other team (BRAVO, -Z), hunts only
## you (hunt_player_only) and never eliminates another bot. First TEAM to kills_to_win eliminations wins: your own
## eliminations vs the bots' combined eliminations on you.
## Spawns (Tyler: "spawn them at the breakout for their team to avoid enemies spawning in behind me"): every bot spawn
## and respawn is one of the bot team's own breakout spots (team_spawns(bot_team)); the player starts at the own
## breakout gate and respawns only on the own team zones. No bot ever appears on your half / behind you.
## The class keeps its SoloFfaMatch name and the start_ffa / ?solo=ffa entry points so the title screen, lobby browser
## and old links keep working. Keeps the practice range / snap_target_bot untouched (switched off for this mode).

const BotPlayerScript = preload("res://scripts/bots/bot_player.gd")
const BotDifficultyScript = preload("res://scripts/bots/bot_difficulty.gd")
const BunkerGraphScript = preload("res://scripts/bots/bunker_graph.gd")

signal standings_changed(rows: Array)
signal ffa_match_over(winner_name: String)
## v0.7 career: every credited elimination ({"shooter", "victim", "zone", "feed", "by_player", "on_player"}).
signal kill_logged(entry: Dictionary)
## v0.7 career elimination mode: a one-life round ended.
signal round_over(player_won_round: bool, rounds_won: int, rounds_lost: int)

const DEFAULT_BOTS: int = 4
const KILLS_TO_WIN: int = 10
const CALLSIGNS := ["Viper", "Ghost", "Rattler", "Blitz", "Hammer", "Nova", "Jinx", "Torque", "Fuse", "Mako", "Sly", "Rook"]
const PAINT_COLORS := [Color(1.0, 0.55, 0.1), Color(0.75, 0.3, 1.0), Color(0.15, 0.95, 0.85), Color(1.0, 0.92, 0.2), Color(0.95, 0.3, 0.55), Color(0.4, 1.0, 0.35)]
const ROLES := ["back", "front", "front", "mid", "mid", "back"]
## Breakout spots for the ALPHA side (+Z); BRAVO uses the mirror (z -> -z, yaw + PI). Gate first, then the gate wings,
## the corner tapes and the back bricks - all inside the team's own start area (|z| >= 33).
const SIDE_SPAWNS := [
	{"pos": Vector3(0.0, 0.0, 45.5), "id": "gate"},
	{"pos": Vector3(-6.0, 0.0, 44.5), "id": "gate_l"},
	{"pos": Vector3(6.0, 0.0, 44.5), "id": "gate_r"},
	{"pos": Vector3(-31.0, 0.0, 41.0), "id": "snake_corner"},
	{"pos": Vector3(31.0, 0.0, 41.0), "id": "dorito_corner"},
	{"pos": Vector3(-13.0, 0.0, 33.5), "id": "left_brick"},
	{"pos": Vector3(13.0, 0.0, 33.5), "id": "right_brick"},
]
## A spawn spot is "in the team's breakout" when it is at least this deep on its own half.
const BREAKOUT_MIN_DEPTH := 30.0
const PLAYER_TEAM := "ALPHA"
const BOT_TEAM := "BRAVO"

## The breakout spawn spots of a team: [{"pos", "yaw", "id"}], facing the other side.
static func team_spawns(team: String) -> Array:
	var side := 1.0 if team == "ALPHA" else -1.0
	var out: Array = []
	for sp in SIDE_SPAWNS:
		var p: Vector3 = sp["pos"]
		out.append({"pos": Vector3(p.x, p.y, p.z * side), "yaw": 0.0 if side > 0.0 else PI, "id": "%s_%s" % [team.to_lower(), sp["id"]]})
	return out

## True when pos is inside team's own breakout / start area (its half, at least BREAKOUT_MIN_DEPTH deep).
static func in_team_breakout(team: String, pos: Vector3) -> bool:
	return (pos.z if team == "ALPHA" else -pos.z) >= BREAKOUT_MIN_DEPTH

static func other_team(team: String) -> String:
	return "BRAVO" if team == "ALPHA" else "ALPHA"

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
var player_team: String = PLAYER_TEAM
var bot_team: String = BOT_TEAM
## Every credited elimination, oldest first: {"shooter", "victim", "zone", "feed"}. The kill feed line is built from
## the same shooter / victim names the standings credit, so the feed and the standings can never disagree.
var kill_log: Array = []
## v0.7 career modes. "tdm" (default: first team to kills_to_win) or "elimination": one life a round, bots stay down,
## first to rounds_to_win rounds. The career runner reads these and the opts it was started with.
const MODE_TDM := "tdm"
const MODE_ELIMINATION := "elimination"
const ROUND_INTERMISSION_S := 2.5
var mode: String = MODE_TDM
var rounds_to_win: int = 3
var rounds_won: int = 0
var rounds_lost: int = 0
var round_no: int = 1
var round_live: bool = false
var start_opts: Dictionary = {}
var _round_gen: int = 0

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
	start_opts = opts.duplicate()
	start_opts.erase("graph")
	mode = MODE_ELIMINATION if String(opts.get("mode", MODE_TDM)) == MODE_ELIMINATION else MODE_TDM
	rounds_to_win = maxi(1, int(opts.get("rounds_to_win", 3)))
	rounds_won = 0
	rounds_lost = 0
	round_no = 1
	var count := clampi(int(opts.get("bots", DEFAULT_BOTS)), 1, 7)
	player_team = String(opts.get("player_team", PLAYER_TEAM))
	if not player_team in ["ALPHA", "BRAVO"]:
		player_team = PLAYER_TEAM
	bot_team = other_team(player_team)
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
		var spawns := team_spawns(bot_team)
		var sp: Dictionary = spawns[i % spawns.size()]
		var b := CharacterBody3D.new()
		b.set_script(BotPlayerScript)
		var role_i: String = ROLES[i % ROLES.size()]
		b.call("configure", {
			"callsign": cs, "bot_name": cs, "team": bot_team, "ffa": false, "hunt_player_only": true, "role": role_i, "index": i,
			"difficulty": BotDifficultyScript.make(tier), "graph": graph, "match": self,
			"paint_color": PAINT_COLORS[i % PAINT_COLORS.size()], "rig_team": bot_team,
			"spawn": sp["pos"], "spawn_yaw": sp["yaw"], "assigned_node": _break_bunker(role_i, sp["pos"]),
			"seed": rng.randi(),
		})
		arena.add_child(b)
		bots.append(b)
		scores[cs] = {"kills": 0, "deaths": 0, "is_player": false}
	active = true
	round_live = true
	GameManager.register_round_start(count)
	_emit()

## Closest plan-role bunker on the bot team's side that no other bot has taken; else the closest free bunker on the
## bot team's half (7 bots can outnumber a role's bunkers).
func _break_bunker(role_id: String, spawn: Vector3) -> int:
	var taken := {}
	for b in bots:
		taken[int(b.get("assigned_node"))] = true
	var best := -1
	var best_d := INF
	for i in graph.role_nodes(role_id, bot_team):
		if taken.has(i):
			continue
		var d: float = spawn.distance_to(graph.nodes[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	for i in graph.nodes.size():
		var p: Vector3 = graph.nodes[i]["pos"]
		if taken.has(i) or (p.z if bot_team == "ALPHA" else -p.z) <= 0.5:
			continue
		var d: float = spawn.distance_to(p)
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
		return # you vs the bot team: bots never score on each other (the bot already ignores these balls)
	var victim := _name_of(bot)
	if scores.has(victim):
		scores[victim]["deaths"] += 1
	var killer := _name_of(shooter)
	if not killer.is_empty() and killer != victim and scores.has(killer):
		scores[killer]["kills"] += 1
	_log_kill(killer, victim, zone)
	_emit()
	if mode == MODE_ELIMINATION:
		bot.set("respawn_timer", INF) # stays down until the next round (reset_for_round)
		if round_live and _live_bots() == 0:
			_end_round(true)
		return
	_check_win(killer)

## Feed: SHOOTER SPLATTED VICTIM [zone] (same names as the standings rows).
func _log_kill(killer: String, victim: String, zone: String) -> void:
	var line := BotPlayerScript.kill_feed_line(killer if not killer.is_empty() else "?", victim, zone)
	var entry := {"shooter": killer, "victim": victim, "zone": zone, "feed": line,
		"by_player": killer == _player_name, "on_player": victim == _player_name}
	kill_log.append(entry)
	IntelBus.intel_feed_updated.emit(line)
	kill_logged.emit(entry)

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
	if mode == MODE_ELIMINATION:
		if round_live:
			_end_round(false)
		return
	_check_win(killer)

# ------------------------------------------------------------ v0.7 elimination rounds --------

## The player controller asks the scene (arena.is_one_life_round_live) - while true a hit means spectate, not respawn.
func is_one_life_round_live() -> bool:
	return active and mode == MODE_ELIMINATION

func _live_bots() -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and not bool(b.get("is_eliminated")):
			n += 1
	return n

func _end_round(player_won_round: bool) -> void:
	round_live = false
	if player_won_round:
		rounds_won += 1
	else:
		rounds_lost += 1
	round_over.emit(player_won_round, rounds_won, rounds_lost)
	IntelBus.intel_feed_updated.emit("ROUND %d %s  -  YOU %d : %d BOTS" % [round_no, "WON" if player_won_round else "LOST", rounds_won, rounds_lost])
	if rounds_won >= rounds_to_win or rounds_lost >= rounds_to_win:
		winner = _player_name if rounds_won >= rounds_to_win else BOTS_WINNER
		active = false
		GameManager.end_match("Elimination", "%s (%d-%d)" % ["YOU" if winner == _player_name else "BOTS", maxi(rounds_won, rounds_lost), mini(rounds_won, rounds_lost)])
		ffa_match_over.emit(winner)
		return
	# Freeze the field: no horn until the next round starts, everyone back to their own breakout.
	GameManager.round_active = false
	GameManager.breakout_horn_sounded = false
	_reset_positions()
	_round_gen += 1
	var gen := _round_gen
	if is_inside_tree():
		get_tree().create_timer(ROUND_INTERMISSION_S).timeout.connect(_on_intermission_done.bind(gen))

func _on_intermission_done(gen: int) -> void:
	if gen == _round_gen:
		start_next_round()

## Bots back on their breakout spots (WAIT_HORN), the player back at the own gate.
func _reset_positions() -> void:
	var spawns := team_spawns(bot_team)
	for i in bots.size():
		var b: Node = bots[i]
		if is_instance_valid(b):
			var sp: Dictionary = spawns[i % spawns.size()]
			b.call("reset_for_round", sp["pos"], float(sp["yaw"]))
	if player != null and is_instance_valid(player):
		if player.has_method("set_spectating"):
			player.call("set_spectating", false)
		if player.has_method("respawn_at_team_gate"):
			player.call("respawn_at_team_gate", player_team)

## Next one-life round (called by the intermission timer; tests call it directly).
func start_next_round() -> void:
	if not active or mode != MODE_ELIMINATION or round_live:
		return
	round_no += 1
	round_live = true
	GameManager.register_round_start(bots.size())
	_emit()

func _bot_named(n: String) -> Node:
	for b in bots:
		if is_instance_valid(b) and String(b.get("bot_name")) == n:
			return b
	return null

## Team totals: your eliminations, and the bot team's combined eliminations (= eliminations on you).
func team_scores() -> Dictionary:
	var you := 0
	var bots_total := 0
	for n in scores.keys():
		if bool(scores[n]["is_player"]):
			you += int(scores[n]["kills"])
		else:
			bots_total += int(scores[n]["kills"])
	return {"you": you, "bots": bots_total}

## Name the match reports as the winner when the bot team gets there.
const BOTS_WINNER := "BOTS"

## First team to kills_to_win: you, or the bot team's combined eliminations.
func _check_win(_killer: String = "") -> void:
	if not winner.is_empty():
		return
	var t := team_scores()
	if int(t["you"]) >= kills_to_win:
		winner = _player_name
	elif int(t["bots"]) >= kills_to_win:
		winner = BOTS_WINNER
	else:
		return
	active = false
	GameManager.end_match("Team Deathmatch", "%s (%d eliminations)" % ["YOU" if winner == _player_name else "BOTS", kills_to_win])
	ffa_match_over.emit(winner)

func player_won() -> bool:
	return not winner.is_empty() and winner == _player_name

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

## Bot respawn: one of the bot team's own breakout spots - the one farthest from the player, skipping spots a live
## bot is standing on. Never the player's half.
func respawn_point_for(who: Node) -> Dictionary:
	var spawns := team_spawns(bot_team)
	var best: Dictionary = spawns[0]
	var best_score := -INF
	for sp in spawns:
		var p: Vector3 = sp["pos"]
		var score := 0.0
		if player != null and is_instance_valid(player) and player.is_inside_tree():
			score = player.global_position.distance_to(p)
		for b in bots:
			if b == who or not is_instance_valid(b) or bool(b.get("is_eliminated")):
				continue
			if (b as Node3D).global_position.distance_to(p) < 2.5:
				score -= 100.0
		if score > best_score:
			best_score = score
			best = sp
	return best

## Player respawn zones for the respawn screen: your own team's 5 standard breakout zones (the arena's team zones when
## it has them, so ids / titles / map spots match every other mode), never a spot on the bots' side.
func player_respawn_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if arena != null and is_instance_valid(arena) and arena.has_method("_get_team_respawn_zones"):
		for z in arena.call("_get_team_respawn_zones", player_team):
			out.append((z as Dictionary).duplicate())
		return out
	var k := 1
	for sp in team_spawns(player_team):
		var p: Vector3 = sp["pos"]
		out.append({"id": String(sp["id"]), "title": "[%d] %s BREAKOUT" % [k, player_team], "pos": Vector3(p.x, 0.1, p.z), "yaw": float(sp["yaw"]), "desc": "%s breakout" % player_team})
		k += 1
		if out.size() >= 5:
			break
	return out

## v0.7 career: HUD line for elimination (the arena keeps its TDM line when this is empty).
func hud_text() -> String:
	if mode != MODE_ELIMINATION:
		return ""
	return "YOU vs BOTS — ELIMINATION  |  ROUND %d  |  YOU %d : %d BOTS  |  FIRST TO %d  |  BOTS UP: %d / %d" % [
		round_no, rounds_won, rounds_lost, rounds_to_win, _live_bots(), bots.size()]

func scoreboard_lines() -> Array[String]:
	var lines: Array[String] = []
	var t := team_scores()
	if mode == MODE_ELIMINATION:
		lines.append("YOU vs BOTS  —  ELIMINATION  —  one life a round, first to %d rounds  (%s bots)" % [rounds_to_win, BotDifficultyScript.make(tier).display_name])
		lines.append("ROUND %d   —   YOU %d : %d BOTS" % [round_no, rounds_won, rounds_lost])
	else:
		lines.append("YOU vs BOTS  —  TEAM DEATHMATCH  —  first team to %d eliminations  (%s bots)" % [kills_to_win, BotDifficultyScript.make(tier).display_name])
		lines.append("YOU %d   —   BOTS %d" % [int(t["you"]), int(t["bots"])])
	lines.append("----------------------------------------------------------------------")
	lines.append("#   NAME                            KILLS     DEATHS")
	var i := 1
	for r in standings():
		lines.append("%-3d %-30s  %-8d  %d" % [i, String(r["name"]) + (" (YOU)" if r["is_player"] else " [BOT]"), r["kills"], r["deaths"]])
		i += 1
	return lines
