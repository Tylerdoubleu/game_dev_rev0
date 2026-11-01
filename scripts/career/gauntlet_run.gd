extends Node
## v0.7 solo career (Bluey): GAUNTLET - pop N of the practice-range peekers (snap_target_bot, the arena's 5 OpFor
## targets: snake, snake corner, center Aztec, Dorito, back center) on the clock. The clock starts on the horn.
## Splats by the peekers don't end the run (you respawn) but count as deaths for the stars.
## Built by speedball_arena_builder.start_career_gauntlet(opts); CareerRunner reads result().

signal standings_changed(rows: Array)
signal finished(result: Dictionary)

var arena: Node = null
var player: Node = null
var pops_needed: int = 5
var time_limit_s: float = 180.0
var pops: int = 0
var deaths: int = 0
var elapsed: float = 0.0
var started: bool = false # horn sounded
var active: bool = false
var done: bool = false
var won: bool = false
var start_opts: Dictionary = {}
var kills_to_win: int = 0 # the arena's solo HUD / banner read this off any solo match node
var _npc_base: int = 0

func start(p_arena: Node, p_player: Node, opts: Dictionary = {}) -> void:
	arena = p_arena
	player = p_player
	start_opts = opts.duplicate()
	pops_needed = maxi(1, int(opts.get("pops", 5)))
	time_limit_s = maxf(5.0, float(opts.get("time_limit_s", 180.0)))
	pops = 0
	deaths = 0
	elapsed = 0.0
	started = false
	done = false
	won = false
	GameManager.death_limit_enabled = false
	GameManager.reset_match_stats()
	_npc_base = GameManager.npc_deaths
	if player != null and player.has_signal("player_eliminated") and not player.is_connected("player_eliminated", _on_player_eliminated):
		player.connect("player_eliminated", _on_player_eliminated)
	active = true
	GameManager.register_round_start(pops_needed)
	_emit()

func _process(delta: float) -> void:
	if not active or done:
		return
	if not started:
		started = GameManager.breakout_horn_sounded and GameManager.round_active
		return
	elapsed += delta
	var p := GameManager.npc_deaths - _npc_base
	if p != pops:
		pops = p
		_emit()
	if pops >= pops_needed:
		_finish(true)
	elif elapsed >= time_limit_s:
		_finish(false)

## Tests: drive the run without bots.
func record_pop() -> void:
	if active and not done:
		pops += 1
		_npc_base -= 1 # keep the npc_deaths delta in step
		_emit()
		if pops >= pops_needed:
			_finish(true)

func _on_player_eliminated(_killer: String = "") -> void:
	if active and not done:
		deaths += 1
		_emit()

func _finish(ok: bool) -> void:
	done = true
	active = false
	won = ok
	GameManager.end_match("Gauntlet", ("YOU (%d pops in %.1fs)" % [pops, elapsed]) if ok else "THE CLOCK (%d/%d pops)" % [pops, pops_needed])
	finished.emit(result())

func player_won() -> bool:
	return done and won

func result() -> Dictionary:
	return {"kind": "gauntlet", "won": done and won, "finished": done and won, "pops": pops, "deaths": deaths,
		"kills": pops, "time_s": snappedf(elapsed, 0.01)}

func standings() -> Array:
	return [{"name": "YOU", "kills": pops, "deaths": deaths, "is_player": true}]

func _emit() -> void:
	standings_changed.emit(standings())

func hud_text() -> String:
	var left := maxf(0.0, time_limit_s - elapsed)
	return "CAREER — RUN THE SNAKE  |  POPS: %d / %d  |  TIME: %.1fs  |  LIMIT %d:%02d  |  SPLATS: %d" % [
		pops, pops_needed, elapsed, int(left) / 60, int(left) % 60, deaths]

func scoreboard_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("CAREER GAUNTLET — pop %d peekers before the clock runs out" % pops_needed)
	lines.append("POPS %d / %d   —   TIME %.1fs   —   SPLATS %d" % [pops, pops_needed, elapsed, deaths])
	return lines

## Respawn screen choices (the arena asks its solo match): your own team's breakout zones.
func player_respawn_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if arena != null and is_instance_valid(arena) and arena.has_method("_get_team_respawn_zones"):
		for z in arena.call("_get_team_respawn_zones", "ALPHA"):
			out.append((z as Dictionary).duplicate())
	return out

func stop() -> void:
	active = false
	GameManager.death_limit_enabled = true

func _exit_tree() -> void:
	GameManager.death_limit_enabled = true
