extends SceneTree
## v0.6.4 (Ren): waiting-room team color picker. You pick only for your own team, only while waiting; the other
## team's color is crossed out; a pick is optimistic and reverts on team_color_rejected; headers take the color;
## RespawnScreen reads the same colors. Offline (no server). Run after `godot --headless --import`:
##   godot --headless --path . -s scripts/systems/test_team_color_picker.gd
var f := 0
var fails: Array[String] = []
var wr: LobbyWaitingRoom
var rs: RespawnScreen
var asked: Array = []
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)

func _waiting(colors = null) -> Dictionary:
	var s := {"room": "lobby_07", "status": "waiting", "match": {"phase": "waiting"}, "mode": "ctf",
		"players": {1: {"name": "Tyler", "team": "ALPHA", "room": "lobby_07", "ready": true}, 2: {"name": "Friend", "team": "BRAVO", "room": "lobby_07", "ready": true}}}
	if colors != null:
		s["team_colors"] = colors
	return s

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		wr = LobbyWaitingRoom.new()
		root.add_child(wr)
		rs = RespawnScreen.new()
		root.add_child(rs)
	if f == 4:
		wr.team_color_requested.connect(func(t: String, n: String) -> void: asked.append([t, n]))
		wr.apply_state(_waiting())
		var names := LobbyWaitingRoom.color_names()
		_check(names.size() >= 8 and "red" in names and "blue" in names, "palette has 8+ names incl. red/blue (%s)" % [names])
		_check(wr._swatches["ALPHA"].size() == names.size() and wr._swatches["BRAVO"].size() == names.size(), "a swatch row under each roster")
		_check(wr.my_team() == "ALPHA", "my team from the room state")
		_check(wr.shown_color("ALPHA") == "red" and wr.shown_color("BRAVO") == "blue", "defaults: ALPHA red, BRAVO blue")
		_check(wr._swatches["ALPHA"]["red"].ringed and wr._swatches["BRAVO"]["blue"].ringed, "each team's color is ringed")
		_check(wr._swatches["ALPHA"]["blue"].crossed and wr._swatches["ALPHA"]["blue"].disabled, "other team's color crossed out on my row")
		_check(not wr._swatches["ALPHA"]["pink"].disabled, "free colors on my row are pickable")
		var all_off := true
		for n in wr._swatches["BRAVO"]: all_off = all_off and wr._swatches["BRAVO"][n].disabled
		_check(all_off, "can't pick for the other team")
		_check(wr._red_head.text.begins_with("RED"), "header names the color")

		_check(not wr.pick_team_color("blue") and asked.is_empty(), "other team's color is blocked (no request)")
		_check(not wr.pick_team_color("mauve") and asked.is_empty(), "unknown color is blocked")
		wr._swatches["ALPHA"]["pink"].pressed.emit()
		_check(asked == [["ALPHA", "pink"]], "swatch click emits team_color_requested(ALPHA, pink)")
		_check(wr.shown_color("ALPHA") == "pink" and wr._swatches["ALPHA"]["pink"].ringed and not wr._swatches["ALPHA"]["red"].ringed, "pick shows at once (optimistic ring)")
		_check(wr._red_head.text.begins_with("PINK") and wr._red_head.get_theme_color("font_color").is_equal_approx(wr.team_color("ALPHA").lightened(0.2)), "header takes the picked color")
		_check(wr._swatches["BRAVO"]["pink"].crossed, "BRAVO's row sees pink crossed out")
		wr.on_team_color_rejected("taken")
		_check(wr.shown_color("ALPHA") == "red" and wr._swatches["ALPHA"]["red"].ringed, "rejected -> reverts to the confirmed color")
		_check(wr._color_note["ALPHA"].text == "TAKEN BY THE OTHER TEAM", "rejection reason shown in LED")
		for r in ["round_active", "invalid", "rate_limited"]:
			wr.on_team_color_rejected(r)
			_check(wr._color_note["ALPHA"].text == LobbyWaitingRoom.REJECT_TEXT[r], "reason %s has a message" % r)

		wr.pick_team_color("purple")
		wr.apply_team_colors({"ALPHA": "purple", "BRAVO": "blue"})
		_check(wr._optimistic.is_empty() and wr.shown_color("ALPHA") == "purple" and wr._color_note["ALPHA"].text == "", "server confirm clears the pending pick")
		wr.apply_team_colors({"ALPHA": "cyan", "BRAVO": "orange"})
		_check(wr._swatches["ALPHA"]["cyan"].ringed and wr._swatches["BRAVO"]["orange"].ringed, "apply_team_colors moves the rings")
		_check(wr._swatches["ALPHA"]["orange"].crossed and wr._swatches["BRAVO"]["cyan"].crossed, "and the cross-outs")
		_check(wr._blue_head.text.begins_with("ORANGE") and wr._blue_head.get_theme_color("font_color").is_equal_approx(LobbyWaitingRoom.color_of_name("orange").lightened(0.2)), "BRAVO header takes its color")
		var line: Label = wr._red_list.get_child(wr._red_list.get_child_count() - 1)
		_check(line.get_theme_color("font_color").is_equal_approx(LobbyWaitingRoom.color_of_name("cyan").lightened(0.45)), "roster names take the team color")
		wr.apply_state(_waiting({"ALPHA": "yellow", "BRAVO": "green"}))
		_check(wr.shown_color("ALPHA") == "yellow" and wr.shown_color("BRAVO") == "green", "lobby state team_colors applied")

		var locked := _waiting({"ALPHA": "yellow", "BRAVO": "green"})
		locked["status"] = "in_match"; locked["match"] = {"phase": "live"}
		wr.apply_state(locked)
		var n_asked := asked.size()
		_check(wr._swatches["ALPHA"]["pink"].disabled and not wr.pick_team_color("pink") and asked.size() == n_asked, "colors locked once the match starts")
		wr.apply_state(_waiting({"ALPHA": "yellow", "BRAVO": "green"}))
		_check(not wr._swatches["ALPHA"]["pink"].disabled, "unlocked again back in waiting")

		var need: Vector2 = wr.find_child("Board", true, false).get_combined_minimum_size()
		_check(need.x <= 1280 and need.y <= 720, "waiting room fits 1280x720 (%s)" % need)

		_check(rs.color_for("ALPHA").is_equal_approx(RespawnScreen.RED) and rs.color_for("BRAVO").is_equal_approx(RespawnScreen.BLUE), "respawn: no colors -> old red / blue")
		rs.set_team_colors({"ALPHA": "pink", "BRAVO": "cyan"})
		_check(rs.color_for("ALPHA").is_equal_approx(LobbyWaitingRoom.color_of_name("pink")) and rs._team_color().is_equal_approx(rs.color_for("ALPHA")), "respawn: field + dots use the team colors")
		print("=== [PASS] v0.6.4 team color picker ===" if fails.is_empty() else "=== [FAIL] %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
