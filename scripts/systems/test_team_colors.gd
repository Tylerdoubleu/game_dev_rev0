extends SceneTree
## v0.6.4 TeamColors palette: NAMES/order, PALETTE, DEFAULTS, color_of and for_team fallbacks.
## Run: godot --headless --path . -s res://scripts/systems/test_team_colors.gd
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _init() -> void:
	print("--- TeamColors ---")
	var TC: Script = load("res://scripts/systems/team_colors.gd")
	_check(TC.NAMES == ["red", "blue", "yellow", "pink", "orange", "purple", "cyan", "green"], "NAMES in picker order")
	_check(TC.names() == TC.NAMES, "names() returns NAMES")
	_check(TC.PALETTE.keys() == TC.NAMES, "PALETTE has exactly NAMES, same order")
	var distinct := {}
	for k in TC.NAMES:
		distinct[TC.color_of(k).to_html()] = true
	_check(distinct.size() == 8, "8 distinct colors")
	_check(TC.DEFAULTS == {"ALPHA": "red", "BRAVO": "blue"}, "defaults Alpha red, Bravo blue")
	_check(TC.color_of("blue") == TC.PALETTE["blue"] and TC.color_of("Cyan") == TC.PALETTE["cyan"] and TC.color_of("mauve") == TC.PALETTE["red"], "color_of known / any case / unknown -> red")
	_check(TC.is_valid("cyan") and not TC.is_valid("Cyan") and not TC.is_valid("white") and not TC.is_valid(""), "is_valid is exact")
	_check(TC.for_team("ALPHA", {}) == TC.PALETTE["red"] and TC.for_team("BRAVO", {}) == TC.PALETTE["blue"], "for_team defaults")
	_check(TC.for_team("BRAVO", {"BRAVO": "green"}) == TC.PALETTE["green"], "for_team uses the room's pick")
	_check(TC.for_team("blue", {"BRAVO": "pink"}) == TC.PALETTE["pink"], "team alias blue -> BRAVO")
	_check(TC.for_team("ALPHA", {"ALPHA": "magenta"}) == TC.PALETTE["red"], "invalid pick falls back to the default")
	print("=== [PASS] v0.6.4 team colors ===" if fails.is_empty() else "=== [FAIL] team colors: %s" % [fails])
	quit(0 if fails.is_empty() else 1)
