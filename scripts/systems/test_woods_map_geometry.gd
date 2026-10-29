extends SceneTree
## v0.4.3 Woodsball Heli Crash geometry verification using real physics queries (the same intersect_ray that
## PaintBallistics uses for paintballs, plus player-capsule shape queries):
##  - every tower ramp lands flush on the deck through a clear parapet doorway (capsule + rays)
##  - parapet top vs crouch/stand eye heights read from player_controller_3d.gd, plus downward line of sight
##  - helicopter fuselage doorways and windows are open (rays + capsule) while the hull still covers a crouched player
## Run: godot --headless --path . -s scripts/systems/test_woods_map_geometry.gd

const TOWERS := ["Tower_WestFlank", "Tower_EastFlank", "Tower_SouthRidge", "Tower_NorthRidge"]

var arena: Node
var frame := 0
var failures: Array[String] = []
var exclude_rids: Array[RID] = []
var space: PhysicsDirectSpaceState3D

func _initialize() -> void:
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] ", msg)
	else:
		print("  [FAIL] ", msg)
		failures.append(msg)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = exclude_rids
	return space.intersect_ray(q)

func _hit_name(h: Dictionary) -> String:
	if h.is_empty():
		return "<none>"
	var c: Object = h.get("collider")
	return String((c as Node).name) if c is Node else "?"

func _capsule_hits(xf: Transform3D) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.38
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = xf
	q.exclude = exclude_rids
	var names := []
	for r in space.intersect_shape(q, 16):
		names.append(String((r.get("collider") as Node).name) if r.get("collider") is Node else "?")
	return names

func _collect_character_rids(n: Node) -> void:
	if n is CharacterBody3D or String(n.name).begins_with("RemotePlayer") or String(n.name).begins_with("Bot"):
		if n is CollisionObject3D:
			exclude_rids.append((n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_collect_character_rids(c)

func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		root.get_node("NetworkLobby").call("select_map", "woodsball_crash")
	elif frame == 8:
		space = arena.get_viewport().get_world_3d().direct_space_state
		_collect_character_rids(arena)
		_run_checks()
		if failures.is_empty():
			print("=== [PASS] v0.4.3 Woodsball Heli Crash geometry: tower doorways/ramps, parapet heights, fuselage doors & windows ===")
			quit(0)
		else:
			print("=== [FAIL] %d geometry checks failed ===" % failures.size())
			for f in failures:
				print("   - ", f)
			quit(1)
	return false

func _run_checks() -> void:
	var consts: Dictionary = (load("res://scripts/player/player_controller_3d.gd") as Script).get_script_constant_map()
	var stand_eye: float = float(consts["HEIGHT_STANDING"])
	var crouch_eye: float = float(consts["HEIGHT_CROUCH"])
	var mask_r: float = 0.17 # Hitbox_Mask sphere radius in player_controller_3d.gd (follows head_pivot)
	var crouch_head_top: float = crouch_eye + mask_r
	var step_tol: float = 0.05
	var max_floor_deg: float = 50.0

	var woods_root := arena.get_node_or_null("WoodsballCrashSiteRoot") as Node3D
	_check(woods_root != null, "WoodsballCrashSiteRoot spawned")
	if woods_root == null:
		return
	var deck_top: float = GrittyArtTheme.TOWER_DECK_TOP
	var half: float = GrittyArtTheme.TOWER_HALF
	var rx: float = GrittyArtTheme.TOWER_RAMP_X
	var ramp_w: float = GrittyArtTheme.TOWER_RAMP_W
	var ramp_run: float = deck_top / tan(deg_to_rad(GrittyArtTheme.TOWER_RAMP_DEG))

	print("Player: standing eye %.2f, crouch eye %.2f, crouched mask top %.2f, capsule r0.25 h1.38" % [stand_eye, crouch_eye, crouch_head_top])

	for t_name in TOWERS:
		var tower := woods_root.get_node_or_null(t_name) as Node3D
		_check(tower != null, "%s exists" % t_name)
		if tower == null:
			continue
		var xf := tower.global_transform
		print("%s (deck top %.2f m):" % [t_name, deck_top])
		# Parapet heights
		for side in ["Front", "Back", "Left", "Right"]:
			var p := tower.get_node_or_null("%s_Parapet_%s" % [t_name, side]) as StaticBody3D
			_check(p != null, "%s_Parapet_%s exists and is rigid cover" % [t_name, side] if p == null else "%s_Parapet_%s exists" % [t_name, side])
			if p == null:
				continue
			_check(bool(p.get_meta("is_rigid_cover", false)), "%s_Parapet_%s keeps rigid PB-16 pocket cover meta" % [t_name, side])
			var bs := (p.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
			var top_above_deck: float = p.position.y + bs.size.y * 0.5 - deck_top
			_check(top_above_deck - crouch_head_top >= 0.1, "%s %s parapet top %.2f hides crouched mask top %.2f (margin %.2f)" % [t_name, side, top_above_deck, crouch_head_top, top_above_deck - crouch_head_top])
			_check(stand_eye - top_above_deck >= 0.3, "%s %s standing eye %.2f clears parapet %.2f by %.2f" % [t_name, side, stand_eye, top_above_deck, stand_eye - top_above_deck])
		# Ramps + doorways
		for ramp_info in [["South", 1.0], ["North", -1.0]]:
			var r_dir: float = ramp_info[1]
			var ramp := tower.get_node_or_null("WalkableRamp_%s_%s" % [t_name, ramp_info[0]]) as StaticBody3D
			if ramp == null:
				continue
			var x: float = rx * r_dir
			# Doorway: player capsule standing just inside the deck edge and straddling the parapet line
			for dz in [0.3, 0.08]:
				var c_local := Vector3(x, deck_top + 0.69 + 0.03, r_dir * (half - dz))
				var hits := _capsule_hits(Transform3D(xf.basis, xf * c_local))
				_check(hits.is_empty(), "%s %s doorway capsule at %.2fm inside edge is clear (hits %s)" % [t_name, ramp_info[0], dz, str(hits)])
			# Doorway width: horizontal rays across the gap at the parapet line must find >=1.1m free span
			var free_span: float = 0.0
			var lx: float = x - 1.2
			while lx <= x + 1.2:
				var a := xf * Vector3(lx, deck_top + 0.7, r_dir * (half - 1.0))
				var b := xf * Vector3(lx, deck_top + 0.7, r_dir * (half + 0.3))
				if _ray(a, b).is_empty():
					free_span += 0.05
				lx += 0.05
			_check(free_span >= 1.1, "%s %s doorway free width %.2fm >= 1.1m" % [t_name, ramp_info[0], free_span])
			for h in [0.5, 1.2, 1.8]:
				var hh := _ray(xf * Vector3(x, deck_top + h, r_dir * (half - 1.0)), xf * Vector3(x, deck_top + h, r_dir * (half + 0.6)))
				_check(hh.is_empty(), "%s %s doorway clear at %.1fm above deck (hit %s)" % [t_name, ramp_info[0], h, _hit_name(hh)])
			# Lip check: ground height just outside vs just inside the deck edge
			var out_h := _ray(xf * Vector3(x, deck_top + 1.0, r_dir * (half + 0.03)), xf * Vector3(x, -1.0, r_dir * (half + 0.03)))
			var in_h := _ray(xf * Vector3(x, deck_top + 1.0, r_dir * (half - 0.03)), xf * Vector3(x, -1.0, r_dir * (half - 0.03)))
			if not out_h.is_empty() and not in_h.is_empty():
				var lip: float = absf((in_h["position"] as Vector3).y - (out_h["position"] as Vector3).y)
				_check(lip <= step_tol, "%s %s ramp->deck lip %.3fm (<= %.2f)" % [t_name, ramp_info[0], lip, step_tol])
			else:
				_check(false, "%s %s lip probe found surfaces" % [t_name, ramp_info[0]])
			# Slope walkable
			var mid := _ray(xf * Vector3(x, deck_top + 1.0, r_dir * (half + ramp_run * 0.5)), xf * Vector3(x, -1.0, r_dir * (half + ramp_run * 0.5)))
			if not mid.is_empty():
				var slope_deg: float = rad_to_deg(acos(clampf((mid["normal"] as Vector3).dot(Vector3.UP), -1.0, 1.0)))
				_check(_hit_name(mid).begins_with("Walkable") and slope_deg < max_floor_deg, "%s %s ramp slope %.1f deg < floor_max_angle %.0f (%s)" % [t_name, ramp_info[0], slope_deg, max_floor_deg, _hit_name(mid)])
			# Foot of the ramp meets the ground cleanly
			var foot := _ray(xf * Vector3(x, 1.0, r_dir * (half + ramp_run - 0.05)), xf * Vector3(x, -1.0, r_dir * (half + ramp_run - 0.05)))
			_check(not foot.is_empty() and (foot["position"] as Vector3).y <= 0.04, "%s %s ramp foot height %.3fm (clean ground transition)" % [t_name, ramp_info[0], (foot["position"] as Vector3).y if not foot.is_empty() else -99.0])
		# Line of sight over the Left parapet (solid side on every tower)
		var inner: float = half - 0.15
		var eye_stand := xf * Vector3(-(inner - 0.26), deck_top + stand_eye, 0.0)
		var ground_pt := xf * Vector3(-(half + 6.5), 0.05, 0.0)
		var los := _ray(eye_stand, ground_pt)
		_check(not _hit_name(los).begins_with(t_name), "%s standing eye looks down over its own parapet to the ground 6.5m out (first hit %s; any non-tower hit is other map cover)" % [t_name, _hit_name(los)])
		var crouch_los := _ray(xf * Vector3(-(inner - 0.26), deck_top + crouch_eye, 0.0), ground_pt)
		_check(_hit_name(crouch_los).contains("_Parapet_"), "%s crouched eye blocked by parapet (hit %s)" % [t_name, _hit_name(crouch_los)])
		var head_shot := _ray(xf * Vector3(-(half + 8.0), deck_top + crouch_head_top, 0.0), xf * Vector3(-(inner - 0.26), deck_top + crouch_head_top, 0.0))
		_check(_hit_name(head_shot).contains("_Parapet_"), "%s paintball at crouched mask top height stops on parapet (hit %s)" % [t_name, _hit_name(head_shot)])

	# Helicopter fuselage
	var heli := woods_root.get_node_or_null("Heli_CrashFuselage_Center50") as StaticBody3D
	_check(heli != null and bool(heli.get_meta("is_rigid_cover", false)), "Heli_CrashFuselage_Center50 exists as rigid cover")
	if heli == null:
		return
	var hxf := heli.global_transform
	var sill: float = GrittyArtTheme.FUSELAGE_WINDOW_SILL
	var wtop: float = GrittyArtTheme.FUSELAGE_WINDOW_TOP
	var wy: float = (sill + wtop) * 0.5
	print("Fuselage: window sill %.2f, top %.2f (%.2fm tall); crouched mask top %.2f, standing eye %.2f" % [sill, wtop, wtop - sill, crouch_head_top, stand_eye])
	_check(sill - crouch_head_top >= 0.1, "Window sill %.2f hides crouched mask top %.2f (margin %.2f)" % [sill, crouch_head_top, sill - crouch_head_top])
	_check(stand_eye - sill >= 0.3 and wtop - stand_eye >= 0.15, "Standing eye %.2f sits inside the window band %.2f-%.2f" % [stand_eye, sill, wtop])
	# Doorways (cargo doors on both long sides, local |x| < 1.1, open to 1.95m)
	for dz in [1.34, 0.0, -1.34]:
		var hits := _capsule_hits(Transform3D(hxf.basis, hxf * Vector3(0.0, 0.72, dz)))
		_check(hits.is_empty(), "Fuselage doorway capsule at local z=%.2f is clear (hits %s)" % [dz, str(hits)])
	for h in [0.4, 1.0, 1.75]:
		var through := _ray(hxf * Vector3(0.0, h, 4.0), hxf * Vector3(0.0, h, -4.0))
		_check(through.is_empty(), "Paintball ray straight through both cargo doors at %.2fm (hit %s)" % [h, _hit_name(through)])
	var door_free: float = 0.0
	var sx: float = -1.6
	while sx <= 1.6:
		if _ray(hxf * Vector3(sx, 1.0, 3.0), hxf * Vector3(sx, 1.0, -3.0)).is_empty():
			door_free += 0.05
		sx += 0.05
	_check(door_free >= 1.1, "Cargo door free width %.2fm >= 1.1m" % door_free)
	var head_clear := _ray(hxf * Vector3(0.0, 1.0, 0.0), hxf * Vector3(0.0, 3.5, 0.0))
	if not head_clear.is_empty():
		var ceil_y: float = (head_clear["position"] as Vector3).y - heli.global_position.y
		_check(ceil_y >= stand_eye + mask_r + 0.15, "Cabin headroom %.2fm clears standing mask top %.2f" % [ceil_y, stand_eye + mask_r])
	# Windows: two per side at local |x| in [2.0, 3.6]
	var window_count := 0
	for wx in [-2.8, 2.8]:
		for side in [1.0, -1.0]:
			var into := _ray(hxf * Vector3(wx, wy, side * 3.5), hxf * Vector3(wx, wy, 0.0))
			var ok: bool = into.is_empty()
			if ok:
				window_count += 1
			_check(ok, "Paintball ray through window center (x=%.1f, side %+d) passes (hit %s)" % [wx, int(side), _hit_name(into)])
			var shoot_out := _ray(hxf * Vector3(wx, stand_eye, 0.0), hxf * Vector3(wx, 0.3, side * 9.0))
			_check(shoot_out.is_empty() or _hit_name(shoot_out) == "TurfFloor", "Standing shooter inside can fire out and down through window (x=%.1f, side %+d, hit %s)" % [wx, int(side), _hit_name(shoot_out)])
			var crouched := _ray(hxf * Vector3(wx, crouch_head_top, side * 3.5), hxf * Vector3(wx, crouch_head_top, 0.0))
			_check(_hit_name(crouched) == heli.name, "Hull below window covers a crouched player's mask (x=%.1f, side %+d, hit %s)" % [wx, int(side), _hit_name(crouched)])
			var low := _ray(hxf * Vector3(wx, 0.6, side * 3.5), hxf * Vector3(wx, 0.6, 0.0))
			_check(_hit_name(low) == heli.name, "Outside wall gives pocket cover at 0.6m (x=%.1f, side %+d)" % [wx, int(side)])
			var from_inside := _ray(hxf * Vector3(wx, 0.6, 0.0), hxf * Vector3(wx, 0.6, side * 3.5))
			_check(_hit_name(from_inside) == heli.name, "Inside wall gives pocket cover at 0.6m (x=%.1f, side %+d)" % [wx, int(side)])
	_check(window_count >= 4, "Fuselage has %d open shooting windows" % window_count)
