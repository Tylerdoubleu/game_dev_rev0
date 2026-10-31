extends SceneTree
## v0.6.4 (Tim) player names: (1) the server sanitizes register_player_info names to the client's CallsignEntry rule
## (uppercase, A-Z 0-9 _ -, 3-16; strip + truncate, under 3 -> Player_NNN) inside the existing handler, no RPC change;
## (2) the title's saved PLAYER TAG (user://player_tag.cfg [player] tag) is applied by NetworkLobby before any
## auto-connect unless ?name= / --name= named the player, so deep links (no title screen) don't join as Player_NNN.
## Run: godot --headless --path . -s res://scripts/systems/test_player_name_rules.gd
const PORT := 19241
const CFG := "user://test_tim_player_tag.cfg"
var L: Node
var f := 0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _write_tag(t: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "tag", t)
	cfg.save(CFG)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	L = root.get_node("NetworkLobby")
	print("--- sanitize_player_name ---")
	var cases := {
		"tyler": "TYLER", "Jeet-Ball_9": "JEET-BALL_9", "  sp ace  ": "SPACE", "a!b@c#d": "ABCD",
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ": "ABCDEFGHIJKLMNOP", "zz": "Player_7", "!!": "Player_7", "": "Player_7",
		"ÉCLAIR": "CLAIR", "<script>": "SCRIPT", "x y": "Player_7",
	}
	for raw in cases:
		var got: String = L.sanitize_player_name(raw, "Player_7")
		_check(got == cases[raw], "%s -> %s (got %s)" % [JSON.stringify(raw), cases[raw], got])

	print("--- saved PLAYER TAG before connect ---")
	var src := FileAccess.get_file_as_string("res://scripts/autoload/network_lobby.gd")
	var ready_at := src.find("func _ready()")
	var apply_at := src.find("apply_saved_player_tag()", ready_at)
	var connect_at := src.find("connect_to_lobby(current_ws_url)", ready_at)
	_check(apply_at > ready_at and apply_at < connect_at, "NetworkLobby._ready applies the saved tag before its auto-connect")
	_check(not src.contains("TitleScreen") or not src.contains("preload(\"res://scripts/ui/title_screen.gd\")"), "no TitleScreen preload in NetworkLobby")
	_check(L.player_tag_cfg_path == "user://player_tag.cfg", "default path is the title's user://player_tag.cfg")
	var saved_name: String = L.local_callsign
	var saved_from_url: bool = L.name_from_url
	L.player_tag_cfg_path = CFG
	L.name_from_url = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	L.local_callsign = "Player_123"
	_check(not L.apply_saved_player_tag() and L.local_callsign == "Player_123", "no saved tag -> keep Player_NNN")
	_write_tag("Tyler_W")
	_check(L.apply_saved_player_tag() and L.local_callsign == "Tyler_W", "saved tag applied (%s)" % L.local_callsign)
	L.local_callsign = "Player_123"
	_write_tag("x!")
	_check(not L.apply_saved_player_tag() and L.local_callsign == "Player_123", "invalid saved tag ignored")
	_write_tag("Tyler_W")
	L.name_from_url = true
	L.local_callsign = "FromLink"
	_check(not L.apply_saved_player_tag() and L.local_callsign == "FromLink", "?name= / --name= wins over the saved tag")
	L.name_from_url = false
	L._parse_query_string("?room=lobby_03&name=LinkName")
	_check(L.name_from_url and L.local_callsign == "LinkName", "?name= marks the name as from the link")
	L.name_from_url = saved_from_url
	L.local_callsign = saved_name
	L.player_tag_cfg_path = "user://player_tag.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

	print("--- server register_player_info sanitizes ---")
	L.start_dedicated_server(PORT)
	L.outbound_capture = []
	L._server_register_peer(501, "tyler white!!", "", "speedball", false, "lobby_01", "", "")
	_check(String(L.players[501]["name"]) == "TYLERWHITE", "spaces/punctuation stripped, uppercased (%s)" % L.players[501]["name"])
	L._server_register_peer(502, "ThisNameIsWayTooLongForTheBoard", "", "speedball", false, "lobby_01", "", "")
	_check(String(L.players[502]["name"]) == "THISNAMEISWAYTOO", "truncated to 16 (%s)" % L.players[502]["name"])
	L._server_register_peer(503, "?!", "", "speedball", false, "lobby_01", "", "")
	_check(String(L.players[503]["name"]) == "Player_503", "under 3 chars -> Player_NNN default (%s)" % L.players[503]["name"])
	var room_row: Array = L._room_roster(L.rooms["lobby_01"]).filter(func(r): return int(r["peer"]) == 501)
	_check(room_row.size() == 1 and room_row[0]["name"] == "TYLERWHITE", "room roster carries the sanitized name")
	var reg_args := -1
	for m in L.get_method_list():
		if String(m["name"]) == "register_player_info":
			reg_args = (m["args"] as Array).size()
	_check(reg_args == 7, "register_player_info RPC signature unchanged (7 args)")

	print("=== [PASS] v0.6.4 player name rules ===" if fails.is_empty() else "=== [FAIL] player name rules: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
	return true
