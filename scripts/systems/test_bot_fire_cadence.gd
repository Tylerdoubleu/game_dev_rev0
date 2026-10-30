extends SceneTree
## v0.6 bot fire cadence: bots fire short 2-3 ball bursts (0.12-0.15s apart) with a 1.5-3.0s pause, instead of a
## steady ~2.2 balls/s while peeked. Simulates bots held peeked for 10s at 60 fps (many seeds) and checks shot count,
## burst size and spacing, that nothing fires while in cover, and the shot volume vs the old cadence over the real
## peek cycle.
## Run: godot --headless --path . -s scripts/systems/test_bot_fire_cadence.gd

var BotScript: GDScript # loaded at runtime so the NetworkLobby autoload exists first
var failures: Array[String] = []
var dt := 1.0 / 60.0

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _new_bot() -> Node:
	var bot: Node = BotScript.new()
	bot.set("fire_cooldown", randf_range(0.0, 3.0)) # same desync as _ready()
	return bot

func _initialize() -> void:
	print("BOT FIRE CADENCE TEST")
	BotScript = load("res://scripts/systems/snap_target_bot.gd")
	var min_shots := 999
	var max_shots := 0
	var total := 0
	var max_burst := 0
	var min_burst := 999
	var min_in_burst_gap := 99.0
	var max_in_burst_gap := 0.0
	var min_pause := 99.0
	var runs := 200
	for r in runs:
		seed(1000 + r)
		var bot := _new_bot()
		var shot_times: Array[float] = []
		var t := 0.0
		for f in 600: # 10s peeked
			t += dt
			if bot.call("tick_fire_cadence", dt, true):
				shot_times.append(t)
		bot.free()
		min_shots = mini(min_shots, shot_times.size())
		max_shots = maxi(max_shots, shot_times.size())
		total += shot_times.size()
		var burst := 1
		for i in range(1, shot_times.size()):
			var gap: float = shot_times[i] - shot_times[i - 1]
			if gap < 0.5:
				burst += 1
				min_in_burst_gap = minf(min_in_burst_gap, gap)
				max_in_burst_gap = maxf(max_in_burst_gap, gap)
			else:
				min_pause = minf(min_pause, gap)
				if i > 1 or burst > 1:
					min_burst = mini(min_burst, burst)
				max_burst = maxi(max_burst, burst)
				burst = 1
		max_burst = maxi(max_burst, burst)
	var avg := float(total) / runs
	print("  10s peeked over %d bots: shots min %d / avg %.1f / max %d (old cadence ~22)" % [runs, min_shots, avg, max_shots])
	print("  burst size %d-%d, in-burst gap %.3f-%.3fs, shortest pause %.2fs" % [min_burst, max_burst, min_in_burst_gap, max_in_burst_gap, min_pause])
	_check(min_shots >= 5 and max_shots <= 20, "10s peeked fires 5-20 balls (got %d-%d)" % [min_shots, max_shots])
	_check(max_burst <= 3, "bursts are at most 3 balls (max %d)" % max_burst)
	_check(min_burst >= 2, "completed bursts are at least 2 balls (min %d)" % min_burst)
	_check(min_in_burst_gap >= 0.11 and max_in_burst_gap <= 0.17, "balls in a burst are ~0.12-0.15s apart")
	_check(min_pause >= 1.45, "pause between bursts >= ~1.5s (min %.2f)" % min_pause)

	# Never fires in cover
	seed(7)
	var cover_bot := _new_bot()
	var cover_shots := 0
	for f in 600:
		if cover_bot.call("tick_fire_cadence", dt, false):
			cover_shots += 1
	cover_bot.free()
	_check(cover_shots == 0, "no shots while in cover")

	# Real peek cycle (peek_interval 2.4, peeked when peek_alpha > 0.75): new vs old shots per bot per minute
	var new_total := 0
	var old_total := 0
	for r in 100:
		seed(5000 + r)
		var bot := _new_bot()
		var timer := randf_range(0.0, 2.4)
		for f in 3600:
			timer += dt
			var peek_alpha: float = clamp((sin(timer * PI / 2.4) + 0.2) / 1.2, 0.0, 1.0)
			var peeked := peek_alpha > 0.75
			if bot.call("tick_fire_cadence", dt, peeked):
				new_total += 1
			if peeked and randf() < dt * 2.2:
				old_total += 1
		bot.free()
	var ratio := float(new_total) / maxf(1.0, float(old_total))
	print("  real peek cycle, shots per bot per minute: old %.1f -> new %.1f (%.0f%%)" % [old_total / 100.0, new_total / 100.0, ratio * 100.0])
	_check(ratio < 0.6, "overall shot volume well under the old cadence (%.0f%%)" % (ratio * 100.0))

	if failures.is_empty():
		print("BOT FIRE CADENCE TEST PASSED")
		quit(0)
	else:
		print("BOT FIRE CADENCE TEST FAILED: %s" % ", ".join(failures))
		quit(1)
