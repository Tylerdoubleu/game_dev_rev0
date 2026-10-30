extends SceneTree
## v0.6 movement foley + break horn: footsteps paced by distance, sprint steps + exhales, slide scrape/effort,
## dive effort + landing thud, fall landing, the director attaching foley to the real local player in the
## speedball arena, and the horn firing on NetworkLobby.break_horn.
## Run: godot --headless --path . -s scripts/systems/test_movement_audio.gd
var arena: Node
var f := 0
var failures: Array[String] = []
func _initialize() -> void:
	arena = (load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: failures.append(m)
func _run(fo: MovementFoley, st: Dictionary, secs: float) -> void:
	fo.debug_state = st
	for i in int(secs * 60.0):
		fo.step(1.0 / 60.0)
func _process(_d: float) -> bool:
	f += 1
	if f == 20:
		var fo := MovementFoley.new()
		root.add_child(fo)
		MovementFoley.play_counts.clear()
		_run(fo, {"speed": 5.6, "on_floor": true, "stance": 0}, 3.0)  # walk 16.8 m
		var walk := int(MovementFoley.play_counts.get("step", 0))
		_check(walk >= 10 and walk <= 12, "walking 3s at 5.6 m/s -> ~11 footsteps (got %d)" % walk)
		_check(not MovementFoley.play_counts.has("breath"), "no breathing while walking")
		_run(fo, {"speed": 0.0, "on_floor": true, "stance": 0}, 1.0)
		_check(int(MovementFoley.play_counts.get("step", 0)) == walk, "standing still makes no steps")
		_run(fo, {"speed": 8.4, "on_floor": true, "stance": 0}, 4.0)
		var sp := int(MovementFoley.play_counts.get("step_sprint", 0))
		_check(sp >= 14 and sp <= 17, "sprinting 4s -> heavier sprint steps on a longer stride (got %d)" % sp)
		_check(int(MovementFoley.play_counts.get("breath", 0)) >= 1, "exhales start after ~2s of sprinting")
		_run(fo, {"speed": 9.0, "on_floor": true, "stance": 1, "slide": true}, 0.5)
		_check(MovementFoley.play_counts.get("slide", 0) == 1 and MovementFoley.play_counts.get("effort_slide", 0) == 1, "knee-slide -> one scrape + one effort")
		_run(fo, {"speed": 9.0, "on_floor": false, "stance": 2, "dive": true}, 0.3)
		_check(MovementFoley.play_counts.get("effort_dive", 0) == 1 and not MovementFoley.play_counts.has("dive_land"), "dive take-off -> hup effort, no thud mid-air")
		_run(fo, {"speed": 4.0, "on_floor": true, "stance": 2, "dive": true}, 0.3)
		_check(MovementFoley.play_counts.get("dive_land", 0) == 1, "dive touchdown -> one chest-pad thud")
		_run(fo, {"speed": 0.0, "on_floor": true, "stance": 2}, 0.3)
		_check(MovementFoley.play_counts.get("dive_land", 0) == 1, "no second thud when the dive ends")
		_run(fo, {"speed": 3.0, "on_floor": false, "stance": 0}, 0.6)
		_run(fo, {"speed": 0.0, "on_floor": true, "stance": 0}, 0.1)
		_check(MovementFoley.play_counts.get("land", 0) == 1, "landing after a fall")
		fo.queue_free()
	if f == 30:
		var players := arena.find_children("*", "CharacterBody3D", true, false).filter(func(n): return root.get_node("MovementAudioDirector").is_local_player(n))
		_check(players.size() >= 1, "arena has a local player")
		if players.size() >= 1:
			_check(players[0].get_node_or_null("MovementFoley") != null, "director attached MovementFoley to the local player")
		var dir: Node = root.get_node("MovementAudioDirector")
		var before: int = dir.horn_count
		root.get_node("NetworkLobby").emit_signal("break_horn", {})
		_check(dir.horn_count == before + 1, "break_horn from NetworkLobby plays the air horn")
		var h0: int = dir.player_hit_count
		root.get_node("NetworkLobby").emit_signal("room_event", "player_eliminated", {"victim": 999, "shooter": 1})
		root.get_node("NetworkLobby").emit_signal("room_event", "round_started", {})
		_check(dir.player_hit_count == h0 + 1, "player_eliminated plays the player-hit sound (and only that event)")
		var hm = dir.get_node("HitMarker")
		var m0: int = hm.show_count
		var me: int = int(root.get_node("NetworkLobby").call("_my_peer_id"))
		root.get_node("NetworkLobby").emit_signal("room_event", "player_eliminated", {"victim": 999, "shooter": me, "scored": true})
		_check(hm.show_count == m0 + 1, "hit marker shows when my shot is the confirmed elimination")
		root.get_node("NetworkLobby").emit_signal("room_event", "player_eliminated", {"victim": me, "shooter": 999, "scored": true})
		_check(hm.show_count == m0 + 1, "no hit marker when I'm the one eliminated")
	if f == 31:
		root.get_node("MovementAudioDirector").debug_menu_open = true
	if f == 40:
		var m: AudioStreamPlayer = root.get_node("MovementAudioDirector").music
		_check(m.playing and bool(m.stream.get("loop")), "menu music loops while a menu is open")
		root.get_node("MovementAudioDirector").debug_menu_open = false
	if f == 170:
		_check(not root.get_node("MovementAudioDirector").music.playing, "menu music fades out and stops once the menu closes")
	if f == 172:
		print("=== [%s] v0.6 movement foley + break horn ===" % ("PASS" if failures.is_empty() else "FAIL"))
		quit(0 if failures.is_empty() else 1)
	return false
