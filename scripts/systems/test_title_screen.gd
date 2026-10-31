extends SceneTree
## v0.6.4 (Ren): TitleScreen - title over the hero backdrop (live loop or still), 2 caption-less prints, SINGLE PLAYER (shared LobbyBrowser.launch_single_player
## path, ROOKIE / AMATEUR) and MULTIPLAYER (LobbyEntryFlow.open_browser), fits 1280x720. Run after an import:
##   godot --headless --path . -s scripts/systems/test_title_screen.gd
var f := 0
var fails: Array[String] = []
var ts: TitleScreen
var asked: Array = []
var multi := 0
const TAG_CFG := "user://test_title_player_tag.cfg"
const TOKEN := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

## ProfileApi with canned replies (Tim's reply handling as-is), no user:// I/O.
class FakeApi extends ProfileApi:
	var calls: Array = []
	var replies: Dictionary = {}
	func _ready() -> void:
		pass
	func _save() -> void:
		pass
	func _request(action: String, path: String, method: int, body) -> void:
		calls.append(action)
		var r: Array = replies.get(action, [])
		if r.is_empty():
			match action:
				"create": r = [201, {"profile_id": "p_1", "token": TOKEN, "callsign": null}]
				"set_callsign": r = [200, {"profile_id": "p_1", "callsign": body["callsign"]}]
				_: r = [200, {"profile_id": "p_1", "callsign": null}]
		_on_reply(action, r[0], r[1].duplicate())

func _new_title(api: ProfileApi = null) -> TitleScreen:
	var t := TitleScreen.new()
	t.tag_cfg_path = TAG_CFG
	t.bind_api(api if api != null else FakeApi.new())
	root.add_child(t)
	return t

func _close_browser() -> void:
	var flow := root.get_node_or_null("LobbyEntryFlow")
	if flow != null and flow.has_method("close_browser"):
		flow.call("close_browser")

func _lobby_name() -> String:
	var nl := root.get_node_or_null("NetworkLobby")
	return String(nl.get("local_callsign")) if nl != null else ""
func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_CFG))
		ts = _new_title()
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
		ts = _new_title()
	if f == 8:
		ts.set_solo_difficulty("rookie")
		ts.single_player_requested.connect(func(d): asked.append(d))
		ts.single_btn.pressed.emit()
		var expect := "solo_launcher" if LobbyBrowser.solo_launcher(ts) != null else "signal_only"
		_check(asked == ["rookie"] and ts.last_solo_route == expect, "SINGLE PLAYER -> shared path (%s, %s)" % [asked, ts.last_solo_route])
		_check(not ts.visible, "title goes away after SINGLE PLAYER")
		_check(CallsignEntry.is_valid_callsign(ts.applied_tag) and _lobby_name() == ts.applied_tag, "SINGLE PLAYER with no tag plays under a suggested one (%s)" % ts.applied_tag)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_CFG))
		ts = _new_title()
	if f == 11:
		# -------- player tag on the first menu
		var field := ts.find_child("TagField", true, false) as LineEdit
		var status := ts.find_child("TagStatus", true, false) as Label
		_check(field != null and status != null and field.is_visible_in_tree(), "PLAYER TAG field on the board")
		_check(ts.find_child("Board", true, false).is_ancestor_of(field), "the tag sits on the board, not on a photo")
		_check(field.text == "" and status.text == TitleScreen.TAG_EMPTY_TEXT, "empty tag: gentle prompt (%s)" % status.text)
		var need := ts.get_combined_minimum_size().max(ts.find_child("Board", true, false).get_combined_minimum_size())
		_check(need.x <= 1280 and need.y <= 720, "still fits 1280x720 with the tag (min %s)" % need)
		ts.request_multiplayer()
		_check(ts.last_multi_result == "need_tag" and ts.visible and status.text == TitleScreen.TAG_NEEDED_TEXT, "MULTIPLAYER needs a tag (%s / %s)" % [ts.last_multi_result, status.text])
		field.text = "x!"
		ts.request_multiplayer()
		_check(ts.last_multi_result == "bad_tag" and ts.visible and status.text == "BAD NAME", "bad tag -> BAD NAME, stays (%s)" % status.text)
		var fake := ts.api as FakeApi
		fake.replies["set_callsign"] = [409, {"error": "callsign_taken"}]
		field.text = "Viper"
		ts.request_multiplayer()
		_check(ts.last_multi_result == "taken" and ts.visible and status.text == "CALLSIGN TAKEN", "taken tag -> CALLSIGN TAKEN, stays (%s)" % status.text)
		fake.replies.erase("set_callsign")
		field.text = "Viper_2"
		ts.request_multiplayer()
		_check(ts.last_multi_result == "opened" and not ts.visible and ts.reserved_tag == "Viper_2", "free tag reserved, MULTIPLAYER opens (%s)" % ts.last_multi_result)
		_check("set_callsign" in fake.calls and "create" in fake.calls, "reserved through ProfileApi (profile made first) %s" % [fake.calls])
		_check(_lobby_name() == "Viper_2", "NetworkLobby plays under the tag (%s)" % _lobby_name())
		var nl := root.get_node_or_null("NetworkLobby")
		if nl != null and not bool(nl.call("is_online_client")):
			var me: Dictionary = (nl.get("players") as Dictionary).get(1, {})
			_check(String(me.get("name", "")) == "Viper_2", "waiting room roster shows the tag (%s)" % me)
		_check(TitleScreen.load_saved_tag(TAG_CFG) == "Viper_2", "tag remembered on this device")
		_close_browser()
		ts = _new_title()
	if f == 14:
		_check(ts.current_tag() == "Viper_2" and _lobby_name() == "Viper_2", "next visit: field prefilled with the saved tag")
		# a saved profile callsign wins over the device cache (until the player types)
		var fake := FakeApi.new()
		fake.token = TOKEN
		fake.replies["get"] = [200, {"profile_id": "p_1", "callsign": "Ghost"}]
		ts.queue_free()
		ts = _new_title(fake)
	if f == 17:
		var fake := ts.api as FakeApi
		_check(ts.current_tag() == "Ghost" and ts.reserved_tag == "Ghost" and _lobby_name() == "Ghost", "prefilled with the profile's callsign (%s)" % ts.current_tag())
		ts.request_multiplayer()
		_check(ts.last_multi_result == "opened" and not ("set_callsign" in fake.calls), "already-reserved tag opens MULTIPLAYER straight away %s" % [fake.calls])
		_close_browser()
		var off := FakeApi.new()
		off.replies["create"] = [0, {"error": "request_failed"}]
		ts = _new_title(off)
		(ts.find_child("TagField", true, false) as LineEdit).text = "Rookie_9"
		ts.request_multiplayer()
		_check(ts.last_multi_result == "opened" and _lobby_name() == "Rookie_9", "profile server offline: keeps the tag and still opens (%s)" % ts.last_multi_result)
		_close_browser()
		ts = _new_title()
		(ts.find_child("TagField", true, false) as LineEdit).text = "Solo_Ace"
		ts.start_single_player("rookie")
		_check(_lobby_name() == "Solo_Ace", "SINGLE PLAYER plays under the typed tag")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TAG_CFG))
	if f == 40:
		print("=== [PASS] v0.6.4 title screen ===" if fails.is_empty() else "=== [FAIL] %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
