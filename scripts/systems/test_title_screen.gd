extends SceneTree
## v0.6.4 (Ren): TitleScreen - title over the hero backdrop (live loop or still), 2 caption-less prints, SINGLE PLAYER (shared LobbyBrowser.launch_single_player
## path, ROOKIE / AMATEUR) and MULTIPLAYER (LobbyEntryFlow.open_browser), fits 1280x720. Run after an import:
##   godot --headless --path . -s scripts/systems/test_title_screen.gd
var f := 0
var fails: Array[String] = []
var ts: TitleScreen
var asked: Array = []
var multi := 0
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		ts = TitleScreen.new()
		root.add_child(ts)
	if f == 5:
		var title := ts.find_child("Title", true, false) as Label
		_check(title != null and title.text == "JEET-BALL", "game title shown")
		# hero backdrop: the live loop when it is in the build, else the still (poster)
		var expect_src := "loop" if not TitleScreen.hero_loop_path().is_empty() else "still"
		_check(ts.hero_source == expect_src, "hero backdrop = %s (%s)" % [ts.hero_source, TitleScreen.hero_loop_path()])
		var still := ts.find_child("HeroStill", true, false) as TextureRect
		_check(still != null and still.texture != null and still.texture.get_width() == 1920, "hero still is the 1920x1080 render")
		var hfa := FileAccess.open(TitleScreen.HERO_STILL_PATH, FileAccess.READ)
		_check(hfa != null and hfa.get_length() < 400 * 1024, "title_hero.jpg under 400 KB")
		_check(ts.find_child("Vignette", true, false) != null, "darkened vignette over the hero")
		var face := ts.hero_focus_point()
		var covered := []
		for n in ["Title", "Tagline", "Board", "PhotoStrip"]:
			var c := ts.find_child(n, true, false) as Control
			var r := c.get_global_rect()
			if n == "PhotoStrip":
				r = Rect2()
				for pc in ts.photo_cards:
					r = pc.get_global_rect() if r.size == Vector2.ZERO else r.merge(pc.get_global_rect())
			if r.grow(40).has_point(face):
				covered.append(n)
		_check(covered.is_empty(), "nothing covers the player's mask at %s %s" % [face, covered])
		_check(ts.photo_cards.size() == 2, "two small prints")
		var tex_ok := true
		var no_words := true
		for c in ts.photo_cards:
			var shot := c.find_child("Shot", true, false) as TextureRect
			tex_ok = tex_ok and shot != null and shot.texture != null and shot.texture.get_width() >= 320
			no_words = no_words and c.find_children("*", "Label", true, false).is_empty()
		_check(tex_ok, "every print has its in-game shot")
		_check(no_words, "no words on the photos")
		var small := true
		for p in TitleScreen.PHOTOS:
			var path: String = (p[0] as Texture2D).resource_path
			var fa := FileAccess.open(path, FileAccess.READ)
			small = small and fa != null and fa.get_length() < 200 * 1024
		_check(small, "print shots are under 200 KB each")
		# a 3D loop scene goes into its own SubViewport (silent) behind the UI
		var probe := Node3D.new()
		var ps := PackedScene.new()
		ps.pack(probe)
		probe.free()
		ResourceSaver.save(ps, "user://title_loop_probe.tscn")
		var held := ts._build_hero("user://title_loop_probe.tscn")
		var box := held.find_child("HeroLoop", true, false) as SubViewportContainer
		_check(ts.hero_source == "loop" and box != null and box.get_child(0) is SubViewport and (box.get_child(0) as SubViewport).own_world_3d, "a 3D loop scene plays in its own SubViewport")
		held.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title_loop_probe.tscn"))
		ts.hero_source = expect_src
		_check(ts.single_btn.text == "SINGLE PLAYER" and ts.multi_btn.text == "MULTIPLAYER", "two big buttons")
		_check(ts.single_btn.size.y >= 80 and ts.multi_btn.size.y >= 80, "buttons are big (%s / %s)" % [ts.single_btn.size, ts.multi_btn.size])
		var need := ts.get_combined_minimum_size()
		for n in ["Board"]:
			need = need.max(ts.find_child(n, true, false).get_combined_minimum_size())
		_check(need.x <= 1280 and need.y <= 720, "fits 1280x720 (min %s)" % need)
		var vp := root.get_visible_rect().size
		var inside := true
		for c in ts.photo_cards:
			var r := c.get_global_rect()
			inside = inside and r.position.x >= -4 and r.position.y >= -4 and r.end.x <= vp.x + 4 and r.end.y <= vp.y + 4
		_check(inside, "prints stay on screen (%s)" % vp)
		_check(ts.solo_difficulty == "amateur" and (ts.find_child("Diff_amateur", true, false) as Button).button_pressed, "defaults to AMATEUR")
		ts.set_solo_difficulty("rookie")
		_check(ts.solo_difficulty == "rookie" and not (ts.find_child("Diff_amateur", true, false) as Button).button_pressed, "ROOKIE pick toggles")
		ts.set_solo_difficulty("pro")
		_check(ts.solo_difficulty == "rookie", "unknown tier ignored")
		ts._next_spotlight()
		_check(ts.photo_cards[1].z_index > ts.photo_cards[0].z_index, "slow spotlight moves to the other print")
		ts.multiplayer_requested.connect(func(): multi += 1)
		ts.open_multiplayer()
		var flow := root.get_node_or_null("LobbyEntryFlow")
		_check(multi == 1 and not ts.visible, "MULTIPLAYER emits and the title goes away")
		_check(flow == null or bool(flow.call("is_open")), "MULTIPLAYER opens the lobby browser (LobbyEntryFlow)")
		if flow != null:
			flow.call("close_browser")
		ts = TitleScreen.new()
		root.add_child(ts)
	if f == 8:
		ts.set_solo_difficulty("rookie")
		ts.single_player_requested.connect(func(d): asked.append(d))
		ts.single_btn.pressed.emit()
		var expect := "solo_launcher" if LobbyBrowser.solo_launcher(ts) != null else "signal_only"
		_check(asked == ["rookie"] and ts.last_solo_route == expect, "SINGLE PLAYER -> shared path (%s, %s)" % [asked, ts.last_solo_route])
		_check(not ts.visible, "title goes away after SINGLE PLAYER")
	if f == 40:
		print("=== [PASS] v0.6.4 title screen ===" if fails.is_empty() else "=== [FAIL] %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
