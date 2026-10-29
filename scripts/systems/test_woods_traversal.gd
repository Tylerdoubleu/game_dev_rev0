extends SceneTree
## Physics traversal test for the Woodsball Heli Crash map: walk up a tower ramp onto the deck,
## and walk straight through the crashed helicopter fuselage cargo doors.

var arena: Node
var player: CharacterBody3D
var frame := 0
var phase := 0
var phase_start := 0
var results := {}

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _start_walk(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	player.set("bunker_pocket_weight", 0.0)
	Input.action_press("move_forward")
	phase_start = frame

func _physics_process(_delta: float) -> bool:
	frame += 1
	if player != null and frame % 120 == 0 and phase > 0:
		var names := []
		for i in player.get_slide_collision_count():
			var col := player.get_slide_collision(i)
			names.append("%s@%s" % [String((col.get_collider() as Node).name) if col.get_collider() is Node else "?", str(col.get_position())])
		print(phase, " pos=", player.global_position, " hits=", names)
	if frame == 5:
		root.get_node("NetworkLobby").call("select_map", "woodsball_crash")
		player = _find_player(arena)
		assert(player != null, "Player3D not found")
	elif frame == 10:
		# West flank tower South ramp foot (tower at -25,0,0, ramp x=+1.1 local, extends toward +Z)
		_start_walk(Vector3(-25.0 + 1.1, 0.2, 10.4), 0.0)
		phase = 1
	elif phase == 1 and frame - phase_start > 720:
		Input.action_release("move_forward")
		results["tower_y"] = player.global_position.y
		results["tower_pos"] = player.global_position
		# Walk through the fuselage across the 50 (cabin centered near 0,0,-0.35)
		_start_walk(Vector3(-0.3, 0.2, 4.0), 0.0)
		phase = 2
	elif phase == 2 and frame - phase_start > 420:
		Input.action_release("move_forward")
		results["heli_pos"] = player.global_position
		print("Tower climb end: ", results["tower_pos"], "  Fuselage walk end: ", results["heli_pos"])
		var deck_top: float = GrittyArtTheme.TOWER_DECK_TOP
		var ok_tower: bool = float(results["tower_y"]) > deck_top - 0.15
		var ok_heli: bool = (results["heli_pos"] as Vector3).z < -3.0
		print("[%s] Ramp climb reaches tower deck" % ("PASS" if ok_tower else "FAIL"))
		print("[%s] Walk straight through helicopter fuselage" % ("PASS" if ok_heli else "FAIL"))
		quit(0 if ok_tower and ok_heli else 1)
	return false

func _find_player(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.has_method("_apply_bunker_cover_pocket_physics"):
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null
