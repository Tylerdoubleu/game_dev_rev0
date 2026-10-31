extends SceneTree
## v0.7 CareerScreen: shows callsign / clout from /api/profile, career keys with profile.stats fallback, EDIT opens
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

	cs.profile["clout"] = 9999999
	cs._refresh()
	var need: Vector2 = cs._board.get_combined_minimum_size()
	_check(need.x <= 1280 and need.y <= 720, "board fits 1280x720 with big numbers (%s)" % need)
	print("=== [%s] v0.7 career screen ===" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	quit(0 if fails.is_empty() else 1)
