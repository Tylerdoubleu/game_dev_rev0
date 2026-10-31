extends SceneTree
## v0.6.4 (Bluey, Tyler: "Not hearing the buzzer on round start"): the solo FFA runs GameManager's local 3 s break,
## not the server's break_countdown / break_horn, so the arena mirrors it into MovementAudioDirector: one beep on 2,
## one on 1, then the air horn on GO - exactly once each, also on a rematch, and never outside a solo FFA.
## Run: godot --headless --path . -s scripts/systems/test_solo_break_audio.gd
var arena: Node
var failures: Array[String] = []
var started := false

func _initialize() -> void:
	arena = (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: failures.append(m)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _process(_d: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _run() -> void:
	await _frames(10)
	var dir: Node = root.get_node("MovementAudioDirector")
	var GM: Node = root.get_node("GameManager")
	# Arena load runs a local break too, but with no solo FFA it must stay silent.
	await _frames(240)
	_check(dir.horn_count == 0 and dir.beep_count == 0, "no horn / beeps from the arena's idle break (got %d / %d)" % [dir.horn_count, dir.beep_count])
	for attempt in 2:
		var h0: int = dir.horn_count
		var b0: int = dir.beep_count
		var m: Node = arena.call("start_solo_ffa", {"bots": 2, "tier": "rookie", "kills_to_win": 10})
		_check(m != null and not GM.breakout_horn_sounded, "[%d] solo FFA starts on a 3-2-1 break" % attempt)
		await _frames(30)
		_check(dir.horn_count == h0, "[%d] no horn before GO" % attempt)
		var t := 0
		while not GM.breakout_horn_sounded and t < 600:
			await process_frame
			t += 1
		await _frames(30)
		_check(dir.beep_count == b0 + 2, "[%d] beep on 2 and on 1 (got %d)" % [attempt, dir.beep_count - b0])
		_check(dir.horn_count == h0 + 1, "[%d] exactly one air horn on GO (got %d)" % [attempt, dir.horn_count - h0])
		var lbl: Label = arena.get("breakout_horn_label")
		_check(lbl != null and lbl.text == "GO!", "[%d] GO banner shown (%s)" % [attempt, lbl.text if lbl != null else "null"])
	arena.call("stop_solo_ffa")
	print("=== [%s] v0.6.4 solo FFA break audio ===" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
