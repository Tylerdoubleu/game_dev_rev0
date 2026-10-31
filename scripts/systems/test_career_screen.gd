extends SceneTree
## v0.7 CareerScreen: shows callsign / clout from ProfileApi, challenge cards (select, locked, play payload), career keys with profile.stats fallback, EDIT opens
## CallsignEntry, and the board fits 1280x720.
var fails: Array = []
func _check(ok: bool, what: String) -> void:
	print(("  [ok] " if ok else "  [FAIL] ") + what)
	if not ok: fails.append(what)

## ProfileApi with no server (every call -> status 0) and no user:// I/O.
class OfflineApi extends ProfileApi:
	func _ready() -> void:
		pass
	func _save() -> void:
		pass
	func _request(action: String, _path: String, _method: int, _body) -> void:
		_on_reply(action, 0, {"error": "request_failed"})

func _initialize() -> void:
	pc = OfflineApi.new()
	root.add_child(pc)
	cs = CareerScreen.new()
	cs.bind_api(pc)
	root.add_child(cs)

var cs: CareerScreen
var pc: OfflineApi
var frames := 0
func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		_run()
	return false

func _run() -> void:
	_check(cs._callsign.text == "NO CALLSIGN" and cs._nums["clout"].text == "0", "blank before any data")
	_check(cs._tier.text == "ROOKIE" and cs._team.text == "FREE AGENT", "defaults: ROOKIE, FREE AGENT")

	_check(cs._status.text == "OFFLINE", "no server -> OFFLINE")
	pc.completed.emit("get", 200, {"callsign": "Viper", "clout": 12450, "stats": {"matches": 30, "wins": 18, "eliminations": 211, "flags": 9}})
	_check(cs._callsign.text == "Viper", "callsign from profile")
	_check(cs._nums["clout"].text == "12,450", "clout from profile, with commas")
	_check(cs._nums["wins"].text == "18" and cs._nums["losses"].text == "12", "stats fallback (losses = matches - wins)")
	_check(cs._status.text == "ONLINE", "status ONLINE after profile")

	cs.show_career({"tier": "amateur", "next_tier": "d2", "xp": 300, "xp_next": 400, "team": "Dynasty B", "season": 2, "wins": 21, "losses": 4})
	_check(cs._tier.text == "AMATEUR" and cs._next.text == "NEXT  D2", "tier + next tier")
	_check(is_equal_approx(cs._bar.value, 75.0), "xp/xp_next -> 75% bar")
	_check(cs._nums["wins"].text == "21" and cs._nums["losses"].text == "4", "career totals win over stats")
	_check(cs._nums["eliminations"].text == "211", "missing career key falls back to stats")
	_check(cs._team.text == "SEASON 2  //  DYNASTY B", "season + team line")
	cs.show_career({"tier": "PRO", "progress": 1.4})
	_check(cs._next.text == "TOP TIER" and cs._bar.value == 100.0, "top tier, progress clamped")

	var edited := [false]
	cs.edit_callsign_pressed.connect(func() -> void: edited[0] = true)
	cs.edit_callsign()
	_check(edited[0] and cs.entry.visible and cs.entry._field.text == "Viper", "EDIT opens CallsignEntry with the name")
	_check(cs.entry.api == pc, "entry shares the screen's ProfileApi")
	cs.entry.callsign_saved.emit("Viper2")
	_check(cs._callsign.text == "Viper2", "saved callsign shows on the screen")

	# --- challenges ---
	var played: Array = []
	cs.play_pressed.connect(func(id: String) -> void: played.append(id))
	cs.show_career({"tier": "D2"})
	cs.play()
	_check(played == [""], "no challenges -> play_pressed(\"\")")
	_check(not cs._cards_scroll.visible and not cs._play.disabled, "no cards shown, NEXT MATCH on")

	cs.show_career({"tier": "D2", "stars": 14, "clout": 5, "challenges": [
		{"id": "c_lock", "name": "Locked First", "mode": "CTF", "best_stars": 0, "locked": true},
		{"id": "c_a", "name": "Alpha", "mode": "ELIM", "best_stars": 2, "locked": false},
		{"id": "c_b", "name": "Bravo", "mode": "CTF", "best_stars": 3, "locked": false}]})
	_check(cs.challenge_cards.size() == 3 and cs._cards_scroll.visible, "3 cards built")
	_check(cs.selected_challenge == "c_a", "first UNLOCKED card selected by default")
	_check(cs.challenge_cards["c_a"].get_node("Outline").visible and not cs.challenge_cards["c_b"].get_node("Outline").visible, "neon outline on the selected card only")
	_check(cs._stars_total.text == "14" and cs._stars_box.visible, "stars total next to the tier")
	_check(cs._nums["clout"].text == "9,999,999" or cs._nums["clout"].text == "12,450", "server clout wins over career clout")
	_check(cs.challenge_cards["c_lock"].disabled and cs.challenge_cards["c_lock"].has_node("Padlock") and cs.challenge_cards["c_lock"].has_node("LockTape"), "locked card disabled, padlocked + taped")
	_check(cs.challenge_cards["c_a"].find_child("Stars", true, false).filled == 2 and cs.challenge_cards["c_b"].find_child("Stars", true, false).filled == 3, "best_stars drawn")
	_check(not cs.select_challenge("c_lock") and cs.selected_challenge == "c_a", "locked card can't be selected")
	_check(not cs.select_challenge("nope"), "unknown id ignored")
	cs.challenge_cards["c_b"].pressed.emit()
	_check(cs.selected_challenge == "c_b" and cs.challenge_cards["c_b"].get_node("Outline").visible, "click selects an unlocked card")
	cs.play()
	_check(played[-1] == "c_b", "play_pressed sends the selected id")
	cs.show_career(cs.career)
	_check(cs.selected_challenge == "c_b", "selection kept across a refresh")
	cs.show_career({"tier": "D2", "challenges": [{"id": "x", "name": "X", "mode": "ELIM", "locked": true}]})
	_check(cs.selected_challenge == "" and cs._play.disabled, "all locked -> nothing selected, NEXT MATCH disabled")
	var n_before := played.size()
	cs.play()
	_check(played.size() == n_before, "disabled NEXT MATCH emits nothing")
	var saved_profile := cs.profile
	cs.profile = {}
	cs.show_career({"clout": 77})
	_check(cs._nums["clout"].text == "77", "career clout used when the profile has none")
	cs.profile = saved_profile

	var eight: Array = []
	for i in 8:
		eight.append({"id": "c%d" % i, "name": "Very Long Challenge Name Number %d" % i, "mode": "CAPTURE THE FLAG", "best_stars": i % 4, "locked": i > 5})
	cs.show_career({"tier": "AMATEUR", "next_tier": "D2", "stars": 999, "season": 12, "team": "Dynasty B", "sponsor": "Brass Eagle", "event": "Midwest Open", "challenges": eight})
	_check(cs.challenge_cards.size() == 8 and cs._cards_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "8 cards = 2 rows, no scroll")
	cs.profile["clout"] = 9999999
	cs._refresh()
	var need: Vector2 = cs._board.get_combined_minimum_size()
	_check(need.x <= 1280 and need.y <= 720, "board fits 1280x720 with big numbers + 8 cards (%s)" % need)
	var twelve: Array = eight + eight.slice(0, 4).map(func(c): var d: Dictionary = c.duplicate(); d["id"] += "b"; return d)
	cs.show_career({"tier": "AMATEUR", "challenges": twelve})
	need = cs._board.get_combined_minimum_size()
	_check(cs._cards_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO and need.y <= 720, "12 cards scroll, still fits (%s)" % need)
	print("=== [%s] v0.7 career screen ===" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	quit(0 if fails.is_empty() else 1)
