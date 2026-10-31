extends SceneTree
## v0.6 RespawnScreen: opens with the killer, places 5 spots on your half, 1-5 run left to right for both teams.
var fails: Array = []
func _check(ok: bool, what: String) -> void:
	print(("  [ok] " if ok else "  [FAIL] ") + what)
	if not ok: fails.append(what)
func _zones(side: float) -> Array:
	return [{"id":"snake_corner","pos":Vector3(-31,0.1,38.5*side)},{"id":"left_brick","pos":Vector3(-13,0.1,33.5*side)},
		{"id":"home_gate","pos":Vector3(0,0.1,45.5*side)},{"id":"right_brick","pos":Vector3(13,0.1,33.5*side)},
		{"id":"dorito_corner","pos":Vector3(30,0.1,38.5*side)}]
func _initialize() -> void:
	var rs := RespawnScreen.new()
	root.add_child(rs)
	var picked := [-1]
	rs.zone_picked.connect(func(i: int) -> void: picked[0] = i)
	rs.open("Viper", "ALPHA", _zones(1.0), 3, 10)
	_check(rs.visible and rs._by_label.text == "by Viper", "opens with who hit you")
	_check(rs._spots[0].position.x < rs._spots[4].position.x, "ALPHA: snake corner on the left")
	_check(rs._index_for_slot(0) == 0, "ALPHA: key 1 = snake corner")
	rs.pick(rs._index_for_slot(2))
	_check(picked[0] == 2 and not rs.visible, "picking emits the zone and closes")
	rs.open("", "BRAVO", _zones(-1.0))
	_check(rs._spots[4].position.x < rs._spots[0].position.x, "BRAVO: view mirrored (dorito corner on the left)")
	_check(rs._index_for_slot(0) == 4, "BRAVO: key 1 = leftmost spot")
	_check(not rs._by_label.visible, "no killer line when unknown")
	print("=== [%s] v0.6 respawn screen ===" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	quit(0 if fails.is_empty() else 1)
