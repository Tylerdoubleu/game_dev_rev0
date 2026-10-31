extends SceneTree
## v0.5 paint audio: surface classification (vinyl / wood / metal / turf / body) on both maps, and live
## fire + splat + bounce sounds triggered by real PaintBallistics shots.
## Run: godot --headless --path . -s scripts/systems/test_paint_audio.gd
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
func _process(_d: float) -> bool:
	f += 1
	var pb: Node = root.get_node("PaintBallistics")
	var lobby: Node = root.get_node("NetworkLobby")
	if f == 20:
		_check(PaintImpactAudio.classify_surface(arena.get_node_or_null("Bunker_Center50_W")) == "vinyl", "speedball inflatable is vinyl")
		var player := arena.get_node_or_null("Player3D")
		_check(PaintImpactAudio.classify_surface(player) == "body", "player is body")
		PaintImpactAudio.play_counts.clear()
		# straight-on shot at the center bunker -> fire + vinyl splat
		var b := arena.get_node("Bunker_Center50_W") as Node3D
		pb.call("spawn_paintball", b.global_position + Vector3(0, 1.0, 6.0), Vector3(0, 0, -1), 280.0, null)
		# grazing shot along the turf -> bounce
		pb.call("spawn_paintball", Vector3(30, 0.6, 30), Vector3(1, -0.12, 0).normalized(), 280.0, null)
	if f == 120:
		var c: Dictionary = PaintImpactAudio.play_counts
		print("  counts: ", c)
		_check(int(c.get("fire", 0)) == 2, "two marker pops")
		_check(int(c.get("vinyl", 0)) >= 1, "vinyl splat on inflatable")
		_check(int(c.get("bounce", 0)) == 0, "grazing shot is silent (Tyler 10/31: bounce thock removed)")
		lobby.call("select_map", "woodsball_crash")
	if f == 130:
		var w := arena.get_node("WoodsballCrashSiteRoot")
		_check(PaintImpactAudio.classify_surface(w.get_node("Heli_CrashFuselage_Center50")) == "metal", "heli fuselage is metal")
		_check(PaintImpactAudio.classify_surface(w.get_node("Home_BackCenter")) == "wood", "timber bunker is wood")
		_check(PaintImpactAudio.classify_surface(w.get_node("Tower_WestFlank/Tower_WestFlank_Parapet_Back")) == "wood", "tower rail is wood")
		lobby.call("select_map", "speedball")
	if f == 140:
		if failures.is_empty():
			print("=== [PASS] v0.5 paint impact audio (per-surface splats, bounce thock, marker pop) ===")
			quit(0)
		else:
			print("=== [FAIL] ", failures)
			quit(1)
	return false
