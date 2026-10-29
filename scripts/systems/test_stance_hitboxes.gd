extends SceneTree
## v0.4.4 stance-scaled movement capsule / torso hitbox verification (local PlayerController3D, real physics):
##  - per-stance capsule heights (stand 1.38 / crouch 1.00 / slide 0.70 / prone 0.50 / dive 0.50), feet planted, no pop
##  - crouched behind a 1.25m tower rail and the 1.22m fuselage sill: paintball rays at rail/sill height miss the player
##  - a standing player behind the same rail is still hittable (torso/mask)
##  - ceiling check: standing up is blocked under a low ceiling, prone is kept under a crawl-height ceiling,
##    and the player rises once the ceiling is gone / inside the fuselage cabin (2.15m roof)
##  - crouch-walking straight through the fuselage cargo doors still works
## Run: godot --headless --path . -s scripts/systems/test_stance_hitboxes.gd

var arena: Node
var player: CharacterBody3D
var frame := 0
var phase := 0
var phase_start := 0
var failures: Array[String] = []
var ceiling: StaticBody3D = null
var samples: Array[float] = []
var feet_y0: float = 0.0
var feet_drift: float = 0.0

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _find_player(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.has_method("get_stance_capsule_target"):
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p != null:
			return p
	return null

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _space() -> PhysicsDirectSpaceState3D:
	return arena.get_viewport().get_world_3d().direct_space_state

func _ray_hits_player(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var h := _space().intersect_ray(q)
	if h.is_empty():
		return {"hit": false, "what": "<none>"}
	var c: Object = h.get("collider")
	if c == player:
		var owner_id: int = player.shape_find_owner(int(h.get("shape", 0)))
		var sn := String((player.shape_owner_get_owner(owner_id) as Node).name)
		return {"hit": true, "what": "player:" + sn}
	return {"hit": false, "what": String((c as Node).name) if c is Node else "?"}

func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	player.set("bunker_pocket_weight", 0.0)
	phase_start = frame

func _release_all() -> void:
	for a in ["crouch_slide", "prone_dive", "move_forward", "sprint", "lean_peek"]:
		Input.action_release(a)

func _cap_h() -> float:
	return float(player.get("torso_capsule_height"))

func _cap_top() -> float:
	var col := player.get("torso_col") as CollisionShape3D
	var cap := col.shape as CapsuleShape3D
	return col.global_position.y + cap.height * 0.5

func _mask_top() -> float:
	var m := player.get_node("Hitbox_Mask") as CollisionShape3D
	return m.global_position.y + (m.shape as SphereShape3D).radius

func _highest_hitbox_top() -> float:
	var top := -INF
	for c in player.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			var cs := c as CollisionShape3D
			var aabb: AABB = cs.shape.get_debug_mesh().get_aabb()
			var xf := cs.global_transform
			for i in 8:
				top = maxf(top, (xf * aabb.get_endpoint(i)).y)
	return top

func _add_ceiling(center: Vector3, bottom_y: float) -> void:
	ceiling = StaticBody3D.new()
	ceiling.name = "TestLowCeiling"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.2, 3.0)
	cs.shape = box
	ceiling.add_child(cs)
	arena.add_child(ceiling)
	ceiling.global_position = Vector3(center.x, bottom_y + 0.1, center.z)

func _remove_ceiling() -> void:
	if ceiling != null:
		ceiling.get_parent().remove_child(ceiling)
		ceiling.free()
		ceiling = null

func _stance() -> int:
	return int(player.get("stance"))

func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		root.get_node("NetworkLobby").call("select_map", "woodsball_crash")
		player = _find_player(arena)
		if player == null:
			print("=== [FAIL] Player3D not found ===")
			quit(1)
			return true
		phase = 1
		_place(Vector3(-0.3, 0.2, 4.0), 0.0)
	match phase:
		1:
			# Open turf south of the fuselage: standing baseline, then crouch transition (feet planted, monotonic)
			if frame - phase_start == 40:
				_check(absf(_cap_h() - 1.38) < 0.01, "Standing capsule height %.3f == 1.38" % _cap_h())
				_check(bool(player.call("has_headroom_for", 1.77)), "Open turf has standing headroom (1.77m probe clear)")
				feet_y0 = player.global_position.y
				samples.clear()
				Input.action_press("crouch_slide")
			elif frame - phase_start > 40 and frame - phase_start <= 100:
				samples.append(_cap_h())
				feet_drift = maxf(feet_drift, absf(player.global_position.y - feet_y0))
			elif frame - phase_start == 101:
				var mono := true
				for i in range(1, samples.size()):
					if samples[i] > samples[i - 1] + 0.0005:
						mono = false
				_check(mono, "Crouch capsule shrinks monotonically (no pop/jitter): %.2f -> %.2f over %d frames" % [samples[0], samples[-1], samples.size()])
				_check(feet_drift < 0.03, "Feet stay planted during crouch (max y drift %.3f)" % feet_drift)
				_check(_stance() == 1, "Stance is CROUCHING")
				_check(absf(_cap_h() - 1.00) < 0.01, "Crouch capsule height %.3f == 1.00 (center %.2f)" % [_cap_h(), (player.get("torso_col") as Node3D).position.y])
				_check(_highest_hitbox_top() - player.global_position.y < 1.20, "Crouched: every hitbox top %.2fm < 1.22 sill and 1.25 rail" % (_highest_hitbox_top() - player.global_position.y))
				# Low ceiling (bottom 1.30m) above the crouched player: releasing crouch must NOT stand up
				_add_ceiling(player.global_position, player.global_position.y + 1.30)
				phase = 2
				phase_start = frame
		2:
			if frame - phase_start == 3:
				# give the physics broadphase a step to register the new static body (real map geometry is static)
				_check(not bool(player.call("has_headroom_for", 1.77)), "Headroom probe detects the 1.30m ceiling")
				_check(bool(player.call("has_headroom_for", 1.11)), "Headroom probe still allows crouch height under it")
				Input.action_release("crouch_slide")
			elif frame - phase_start == 45:
				_check(_stance() == 1, "Under a 1.30m ceiling, releasing crouch keeps CROUCHING (stance %d)" % _stance())
				_check(_cap_h() < 1.01, "Capsule stays at crouch height %.3f under the ceiling" % _cap_h())
				_check(_mask_top() < player.global_position.y + 1.30, "Mask top %.2f stays under the ceiling" % (_mask_top() - player.global_position.y))
				_remove_ceiling()
				samples.clear()
			elif frame - phase_start > 45 and frame - phase_start <= 105:
				samples.append(_cap_h())
			elif frame - phase_start == 106:
				_check(_stance() == 0, "Ceiling removed: player stands back up automatically (stance %d)" % _stance())
				_check(absf(_cap_h() - 1.38) < 0.01, "Standing capsule restored to %.3f" % _cap_h())
				var mono := true
				for i in range(1, samples.size()):
					if samples[i] < samples[i - 1] - 0.0005:
						mono = false
				_check(mono, "Stand-up capsule grows monotonically (no pop)")
				# Prone
				Input.action_press("prone_dive")
				phase = 3
				phase_start = frame
		3:
			if frame - phase_start == 60:
				_check(_stance() == 2, "Prone stance (stance %d)" % _stance())
				_check(absf(_cap_h() - 0.50) < 0.01, "Prone capsule height %.3f == 0.50" % _cap_h())
				_check(_cap_top() - player.global_position.y < 0.51, "Prone capsule top %.2f" % (_cap_top() - player.global_position.y))
				_add_ceiling(player.global_position, player.global_position.y + 0.80)
			elif frame - phase_start == 63:
				Input.action_release("prone_dive")
			elif frame - phase_start == 110:
				_check(_stance() == 2, "Under a 0.80m crawl ceiling, releasing prone keeps PRONE (stance %d)" % _stance())
				var low_ceiling := ceiling
				_add_ceiling(player.global_position, player.global_position.y + 1.30)
				var high_ceiling := ceiling
				ceiling = low_ceiling
				# swap ceilings across a physics step so the new one is registered before the crawl ceiling goes away
				get_root().set_meta("pending_ceiling", high_ceiling)
			elif frame - phase_start == 113:
				_remove_ceiling()
				ceiling = get_root().get_meta("pending_ceiling") as StaticBody3D
			elif frame - phase_start == 160:
				_check(_stance() == 1, "Raised to a 1.30m ceiling: rises only to CROUCHING (stance %d)" % _stance())
				_remove_ceiling()
			elif frame - phase_start == 210:
				_check(_stance() == 0, "Open sky: back to STANDING (stance %d)" % _stance())
				phase = 4
				_start_tower()
		4:
			_tower_phase()
		5:
			_fuselage_window_phase()
		6:
			# Crouch-walk through the fuselage cargo doors
			if frame - phase_start == 1:
				player.set("slide_timer", 0.5)
				var slide_h: float = player.call("get_stance_capsule_target")
				player.set("slide_timer", 0.0)
				player.set("dive_timer", 0.5)
				var dive_h: float = player.call("get_stance_capsule_target")
				player.set("dive_timer", 0.0)
				_check(absf(slide_h - 0.70) < 0.001 and absf(dive_h - 0.50) < 0.001, "Knee-slide capsule %.2f, Superman-dive capsule %.2f" % [slide_h, dive_h])
				Input.action_press("crouch_slide")
			elif frame - phase_start == 30:
				Input.action_press("move_forward")
			elif frame - phase_start == 700:
				_release_all()
				var p := player.global_position
				_check(p.z < -3.0, "Crouch-walk straight through the fuselage doors (end z %.2f, stance %d)" % [p.z, _stance()])
				_check(_stance() == 1, "Stayed crouched through the cabin")
				_finish()
	return false

var tower_center := Vector3(-25.0, 0.0, 0.0)

func _start_tower() -> void:
	_release_all()
	var deck: float = GrittyArtTheme.TOWER_DECK_TOP
	# Behind the east (field-facing) rail of the West flank tower, 0.55m from the rail's inner face
	_place(tower_center + Vector3(GrittyArtTheme.TOWER_HALF - 0.75, deck + 0.05, -0.6), -PI * 0.5)
	Input.action_press("crouch_slide")

func _tower_phase() -> void:
	var deck: float = GrittyArtTheme.TOWER_DECK_TOP
	var rail_top: float = deck + GrittyArtTheme.TOWER_PARAPET_H
	var t := frame - phase_start
	var p := player.global_position
	var outside_x := tower_center.x + GrittyArtTheme.TOWER_HALF + 8.0
	if t == 70:
		_check(absf(p.y - deck) < 0.12, "Player settled on the tower deck (y %.2f, deck %.2f)" % [p.y, deck])
		_check(_stance() == 1, "Crouched behind the tower rail")
		var top := _highest_hitbox_top()
		_check(top < rail_top - 0.02, "Crouched highest hitbox top %.2f < rail top %.2f" % [top, rail_top])
		_check(_cap_top() < rail_top - 0.2, "Crouched torso capsule top %.2f < rail top %.2f" % [_cap_top(), rail_top])
		var any_hit := false
		for dy in [0.0, 0.03, 0.08, 0.15, 0.3]:
			for dz in [-0.2, 0.0, 0.2]:
				for src_y in [rail_top + dy, rail_top + dy + 0.6]:
					# level shots and plunging shots from a taller enemy angle, all clearing the rail top
					var r := _ray_hits_player(Vector3(outside_x, src_y, p.z + dz), Vector3(p.x - 0.6, rail_top + dy - (src_y - rail_top - dy) * 0.05, p.z + dz))
					if r["hit"]:
						any_hit = true
						print("    crouched exposed: ray y=%.2f dz=%.1f -> %s" % [src_y, dz, r["what"]])
		_check(not any_hit, "Paintball rays skimming the 1.25m rail top miss the crouched player")
		var low := _ray_hits_player(Vector3(outside_x, deck + 0.6, p.z), Vector3(p.x - 1.0, deck + 0.6, p.z))
		_check(not low["hit"], "Rail covers the crouched body at 0.6m (hit %s)" % low["what"])
		Input.action_release("crouch_slide")
	elif t == 130:
		_check(_stance() == 0, "Stands up on the open deck")
		var r := _ray_hits_player(Vector3(outside_x, rail_top + 0.06, p.z), Vector3(p.x - 1.0, rail_top + 0.06, p.z))
		_check(r["hit"], "Standing player's torso/mask above the rail is hittable (hit %s)" % r["what"])
		var r2 := _ray_hits_player(Vector3(outside_x, deck + 1.33, p.z), Vector3(p.x - 1.0, deck + 1.33, p.z))
		_check(r2["hit"] and String(r2["what"]) in ["player:Hitbox_Torso", "player:Hitbox_Mask"], "Standing torso band at 1.33m is hittable (hit %s)" % r2["what"])
		phase = 5
		_start_fuselage_window()

var heli: Node3D

func _start_fuselage_window() -> void:
	heli = arena.find_child("Heli_CrashFuselage_Center50", true, false) as Node3D
	if heli == null:
		_check(false, "Heli_CrashFuselage_Center50 found")
		phase = 6
		_place(Vector3(-0.3, 0.2, 4.0), 0.0)
		return
	# Inside the cabin, behind the south wall window (local x 2.8), facing out
	_place(heli.global_transform * Vector3(2.8, 0.15, 0.85), heli.global_rotation.y)
	Input.action_press("crouch_slide")

func _fuselage_window_phase() -> void:
	var t := frame - phase_start
	var hxf := heli.global_transform
	var sill: float = GrittyArtTheme.FUSELAGE_WINDOW_SILL
	if t == 70:
		var p_local := hxf.affine_inverse() * player.global_position
		_check(_stance() == 1, "Crouched inside the fuselage beside a window (local %s)" % str(p_local.snapped(Vector3(0.01, 0.01, 0.01))))
		var any_hit := false
		for dy in [0.01, 0.05, 0.12, 0.3]:
			for dx in [-0.2, 0.0, 0.2]:
				var a := hxf * Vector3(p_local.x + dx, sill + dy, 4.5)
				var b := hxf * Vector3(p_local.x + dx, sill + dy, p_local.z - 0.8)
				var r := _ray_hits_player(a, b)
				if r["hit"]:
					any_hit = true
					print("    crouched exposed through window: y=%.2f -> %s" % [sill + dy, r["what"]])
		_check(not any_hit, "Rays through the window just above the 1.22m sill miss the crouched player")
		# Standing up inside the cabin is allowed (roof 2.15m)
		Input.action_release("crouch_slide")
	elif t == 130:
		_check(_stance() == 0, "Standing up inside the fuselage cabin is allowed (roof 2.15m, stance %d)" % _stance())
		var p_local := hxf.affine_inverse() * player.global_position
		var r := _ray_hits_player(hxf * Vector3(p_local.x, sill + 0.15, 4.5), hxf * Vector3(p_local.x, sill + 0.15, p_local.z - 0.8))
		_check(r["hit"], "Standing player in the window is hittable through it (hit %s)" % r["what"])
		phase = 6
		_place(Vector3(-0.3, 0.2, 4.0), 0.0)

func _finish() -> void:
	if failures.is_empty():
		print("=== [PASS] v0.4.4 stance-scaled torso hitbox / capsule, rail & sill cover, ceiling check, fuselage crouch-walk ===")
		quit(0)
	else:
		print("=== [FAIL] %d stance hitbox checks failed ===" % failures.size())
		for f in failures:
			print("   - ", f)
		quit(1)
