extends SceneTree
## v0.6.4 NetworkLobby client side of team colors: sync_lobby_state / cl_room_event -> team_colors_changed and
## team_color_rejected, lobby snapshot "team_colors", offline no-op and leave_room reset.
## Run: godot --headless --path . -s res://scripts/systems/test_team_color_client.gd
var f := 0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var L: Node = root.get_node("NetworkLobby")
	L.is_dedicated_server = false
	var changed: Array = []
	var rejected: Array = []
	L.team_colors_changed.connect(func(c: Dictionary) -> void: changed.append(c))
	L.team_color_rejected.connect(func(r: String) -> void: rejected.append(r))
	print("--- team colors (client) ---")
	_check(L.get_lobby_state_snapshot()["team_colors"] == {"ALPHA": "red", "BRAVO": "blue"}, "snapshot defaults")
	L.sync_lobby_state({"room": "lobby_01", "team_colors": {"ALPHA": "pink", "BRAVO": "blue"}})
	_check(changed.size() == 1 and changed[0] == {"ALPHA": "pink", "BRAVO": "blue"} and L.get_lobby_state_snapshot()["team_colors"]["ALPHA"] == "pink", "sync_lobby_state -> team_colors_changed + snapshot")
	L.sync_lobby_state({"room": "lobby_01", "team_colors": {"ALPHA": "pink", "BRAVO": "blue"}})
	_check(changed.size() == 1, "no repeat signal when nothing changed")
	L.cl_room_event("team_colors_changed", {"team_colors": {"ALPHA": "pink", "BRAVO": "cyan"}, "team": "BRAVO", "color": "cyan"})
	_check(changed.size() == 2 and changed[1]["BRAVO"] == "cyan", "room event team_colors_changed -> signal")
	L.cl_room_event("team_color_rejected", {"reason": "taken", "color": "pink", "team_colors": {"ALPHA": "pink", "BRAVO": "cyan"}})
	_check(rejected == ["taken"] and changed.size() == 2, "room event team_color_rejected -> team_color_rejected(reason)")
	# nametags: built with the room color, re-tinted on team_colors_changed
	var body: Node3D = L._create_remote_player_avatar(9001, "BRAVO", "Tagger")
	L.remote_player_nodes[9001] = body
	var tag := body.get_node("CallsignTag3D") as Label3D
	_check(tag.modulate.is_equal_approx(TeamColors.color_of("cyan").lightened(0.3)), "nametag uses BRAVO's cyan (%s)" % [tag.modulate])
	L.cl_room_event("team_colors_changed", {"team_colors": {"ALPHA": "pink", "BRAVO": "orange"}})
	_check(tag.modulate.is_equal_approx(TeamColors.color_of("orange").lightened(0.3)), "nametag re-tinted on team_colors_changed")
	L.remote_player_nodes.erase(9001)
	body.free()
	# offline: no server to confirm -> nothing emitted (Ren's waiting room keeps the optimistic pick)
	var n_changed := changed.size()
	var n_rej := rejected.size()
	L.request_team_color("green")
	_check(changed.size() == n_changed and rejected.size() == n_rej, "offline request_team_color is a no-op")
	L.leave_room()
	_check(L.team_colors == {"ALPHA": "red", "BRAVO": "blue"}, "leave_room resets to the defaults")
	print("=== [PASS] v0.6.4 team colors client ===" if fails.is_empty() else "=== [FAIL] team colors client: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true
