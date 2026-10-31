extends SceneTree
## Title-screen hero loop (scenes/ui/title_hero_loop.tscn): a crouched ALPHA player peeks round a yellow can, shoots a
## 2-3 ball burst at the camera, the balls splat on the lens and fade, he tucks, repeat. Checked standalone (no arena,
## no NetworkLobby match state) inside its own SubViewport like Ren's title screen: own camera current there and not
## on the root viewport, rig out while firing and fully hidden when tucked, bursts of 2-3, bounded splats and balls,
## seamless + deterministic loop, and no AudioServer buses created (also with play_sound on).
## Run: godot --headless --path . -s scripts/systems/test_title_hero_loop.gd
const SCENE := "res://scenes/ui/title_hero_loop.tscn"
const DT := 1.0 / 60.0
var f := 0
var failures: Array[String] = []
var vp: SubViewport
var hero: Node3D
var buses_before := 0
var root_cam_before: Camera3D

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: failures.append(m)

func _initialize() -> void:
	buses_before = AudioServer.bus_count
	root_cam_before = root.get_camera_3d()
	vp = SubViewport.new()
	vp.size = Vector2i(320, 180)
	vp.own_world_3d = true
	root.add_child(vp)
	var ps := load(SCENE) as PackedScene
	_check(ps != null, "scene loads from exactly %s" % SCENE)
	hero = ps.instantiate()
	hero.set("autoplay", false) # the test drives advance() so it is frame-rate independent
	vp.add_child(hero)

func _run_loops(h: Node3D, n_loops: int) -> Dictionary:
	var r := {"fire_frames": 0, "fire_exposed": 0, "fire_head": 0, "fire_partial": 0, "hidden_frames": 0, "hidden_leaks": 0,
		"max_balls": 0, "max_splats": 0, "wrap_ok": true}
	var loop_len := float(h.get("loop_length"))
	var steps := int(ceil(loop_len * float(n_loops) / DT)) + 2
	var last_loop := int(h.get("loop_index"))
	for i in steps:
		h.call("advance", DT)
		var ph := String(h.call("phase"))
		var ex: Dictionary = h.call("rig_exposure")
		if ph == "fire":
			r["fire_frames"] += 1
			if int(ex["count"]) > 0: r["fire_exposed"] += 1
			if bool(ex["head"]) and bool(ex["muzzle"]): r["fire_head"] += 1
			if int(ex["count"]) < int(ex["total"]): r["fire_partial"] += 1
		elif ph == "hidden":
			r["hidden_frames"] += 1
			if int(ex["count"]) != 0: r["hidden_leaks"] += 1
		r["max_balls"] = maxi(r["max_balls"], int(h.call("live_ball_count")))
		r["max_splats"] = maxi(r["max_splats"], int(h.call("live_splat_count")))
		var li := int(h.get("loop_index"))
		if li != last_loop:
			last_loop = li
			# seamless wrap: a new loop starts tucked behind the can, exactly as the last one ended
			if float(h.get("out_alpha")) > 0.001 or int(ex["count"]) != 0:
				r["wrap_ok"] = false
	return r

func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		var cam := hero.get("camera") as Camera3D
		_check(cam != null and cam.current, "own HeroCamera is current")
		_check(vp.get_camera_3d() == cam, "...as the SubViewport's camera (Ren's title SubViewport)")
		_check(root.get_camera_3d() == root_cam_before, "root viewport camera untouched")
		var src := (load("res://scripts/ui/title_hero_loop.gd") as GDScript).source_code
		var touches := false
		for bad in ["get_window", "get_tree().root", "DisplayServer.window", "root.size", "get_tree().get_root", "Engine.max_fps", "ProjectSettings.set"]:
			if src.contains(bad): touches = true
		_check(not touches, "sets no window / root-viewport / project settings")
		var names := []
		for c in hero.get_children(): names.append(String(c.name))
		_check(names.has("WorldEnvironment") and names.has("Sun"), "brings its own WorldEnvironment + light")
		var bunker := hero.get("bunker") as Node3D
		var bmesh := bunker.get_node_or_null("BunkerMesh") as MeshInstance3D if bunker != null else null
		_check(bmesh != null and bmesh.mesh is CapsuleMesh, "hero bunker is a can (arena bunker mesh path)")
		var bmat := bmesh.material_override as StandardMaterial3D if bmesh != null else null
		_check(bmat != null and bmat.albedo_color.r > 0.6 and bmat.albedo_color.g > 0.5 and bmat.albedo_color.b < 0.3, "...in yellow vinyl")
		var tc: Color = hero.call("team_color")
		_check(String(hero.get("team")) == "ALPHA" and tc.r > 0.6 and tc.g < 0.4, "default team ALPHA -> red (TeamColors)")
		_check(hero.get("play_sound") == false and hero.get("use_own_camera") == true, "defaults: play_sound off, own camera on")
		# the rig starts tucked
		var ex0: Dictionary = hero.call("rig_exposure")
		_check(String(hero.call("phase")) == "hidden" and int(ex0["count"]) == 0, "starts hidden behind the can")
		var loop_len := float(hero.get("loop_length"))
		_check(loop_len >= 4.0 and loop_len <= 6.0, "loop is 4-6 s (%.2f)" % loop_len)

		var r := _run_loops(hero, 4)
		_check(int(hero.get("loops_completed")) >= 4, "ran >= 4 full loops standalone (%d)" % int(hero.get("loops_completed")))
		_check(r["fire_frames"] > 0 and r["fire_exposed"] == r["fire_frames"], "rig is out every firing frame (%d/%d)" % [r["fire_exposed"], r["fire_frames"]])
		_check(r["fire_head"] == r["fire_frames"], "head + muzzle clear the can edge while firing")
		_check(r["fire_partial"] == r["fire_frames"], "...but it is a corner peek: part of the body stays behind the can")
		_check(r["hidden_frames"] > 0 and r["hidden_leaks"] == 0, "fully hidden when tucked (%d leaky frames)" % r["hidden_leaks"])
		_check(r["wrap_ok"], "loop wraps seamlessly (tucked at the seam)")
		var log: Array = hero.get("peek_log")
		var shots_ok := log.size() >= 4
		var sides := []
		var crouched := true
		for e in log:
			var s := int(e["shots"])
			if s < 2 or s > 3: shots_ok = false
			sides.append(int(e["side"]))
			if int(e["stance"]) != 1: crouched = false
		_check(shots_ok, "every peek fires a 2-3 ball burst (%s)" % str(log.map(func(e): return e["shots"])))
		_check(sides.size() >= 2 and sides[0] != sides[1] and sides[1] != sides[2], "peek side alternates each loop (%s)" % str(sides))
		_check(crouched, "every peek is crouched by default (matches the title still)")
		var si := float(hero.get("shot_interval"))
		_check(si >= 0.12 and si <= 0.15, "shots %.3f s apart" % si)
		var max_splats := int(hero.get("max_splats"))
		_check(r["max_splats"] >= 1 and r["max_splats"] <= max_splats, "lens splats appear and stay bounded (peak %d <= %d)" % [r["max_splats"], max_splats])
		_check(int(hero.get("max_live_splats_seen")) <= max_splats, "splat cap never exceeded")
		_check(r["max_balls"] >= 1 and r["max_balls"] <= 3, "visual balls in flight bounded (peak %d)" % r["max_balls"])
		var lens := hero.get_node("LensSplats")
		var balls := hero.get_node("Paintballs")
		var live_lens := lens.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
		var live_balls := balls.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
		_check(live_lens <= max_splats and live_balls <= 3, "spent balls / faded splats are freed, no build-up (%d splats, %d balls live)" % [live_lens, live_balls])
		_check(AudioServer.bus_count == buses_before and buses_before == 1, "no AudioServer buses created (%d)" % AudioServer.bus_count)

		# determinism: a fresh instance produces the same peek log
		var h2 := (load(SCENE) as PackedScene).instantiate()
		h2.set("autoplay", false)
		vp.add_child(h2)
		_run_loops(h2, 4)
		var l2: Array = h2.get("peek_log")
		var same := l2.size() == log.size()
		if same:
			for i in log.size():
				if str(log[i]) != str(l2[i]): same = false
		_check(same, "deterministic: a second instance replays the same peeks")
		h2.queue_free()

		# play_sound on still creates no buses (pooled 3D players on the default bus)
		var h3 := (load(SCENE) as PackedScene).instantiate()
		h3.set("autoplay", false)
		h3.set("play_sound", true)
		h3.set("background_props", false)
		vp.add_child(h3)
		_run_loops(h3, 1)
		_check(AudioServer.bus_count == 1, "play_sound on: still no new AudioServer buses")
		h3.queue_free()
	if f == 6:
		print("=== [%s] title hero loop ===" % ("PASS" if failures.is_empty() else "FAIL"))
		quit(0 if failures.is_empty() else 1)
	return false
