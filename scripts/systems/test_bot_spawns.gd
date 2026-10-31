extends SceneTree
## v0.6.3 practice bot spawns: all 5 OpFor practice bots spawn on speedball (and in the woods), with unique Bot_* node
## names that never collide with the OpFor_CenterAztec / OpFor_BackCenter bunkers. Before the fix get_node_or_null()
## found those bunkers, so only 3 bots spawned and turning bots off deleted the two bunkers.
## Also checks the name-based lookups: network elimination (get_node by bot name), kill feed name, respawn map dots,
## bunker callouts and map switches.
## Run: godot --headless --path . -s scripts/systems/test_bot_spawns.gd

const EXPECTED_BOTS := 5
const EXPECTED_WOODS_BOTS := 5 # bots keep their speedball placements on the woods map too
const BOT_LABELS := ["OpFor Snake-1", "OpFor Snake-Corner", "OpFor Center-Aztec", "OpFor Dorito-2", "OpFor Back-Center"]

var arena: Node
var failures: Array[String] = []
var started := false

func _initialize() -> void:
	root.get_node("NetworkLobby").set("fill_bots_enabled", true)
	var packed := load("res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn") as PackedScene
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

## Every snap_target_bot directly under the arena, wherever it got its name from.
func _bots() -> Array:
	var out: Array = []
	for c in arena.get_children():
		if "bot_name" in c and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _bunker(n: String) -> Node:
	var b := arena.get_node_or_null(n)
	return b if b != null and not ("bot_name" in b) else null

func _check_bots(label: String, want: int) -> void:
	var bots := _bots()
	_check(bots.size() == want, "%s: %d practice bots spawned (got %d)" % [label, want, bots.size()])
	var names: Array = []
	var labels: Array = []
	for b in bots:
		names.append(String(b.name))
		labels.append(String(b.get("bot_name")))
	_check(names == ["Bot_Snake50", "Bot_SnakeCorner", "Bot_CenterAztec", "Bot_Dorito2", "Bot_BackCenter"], "%s: unique Bot_* node names, none renamed by Godot: %s" % [label, str(names)])
	_check(labels == BOT_LABELS, "%s: feed / kill names: %s" % [label, str(labels)])
	var alive := 0
	for b in bots:
		if (b as Node3D).visible and b.get("pro_rig") != null and b.is_processing() and not bool(b.get("is_eliminated")):
			alive += 1
	_check(alive == want, "%s: every bot is built (rig), visible and running its peek/fire loop (%d)" % [label, alive])
	_check((arena.call("get_opfor_bots") as Array).size() == want, "%s: arena.get_opfor_bots() finds all %d" % [label, want])

func _run() -> void:
	await _frames(3)
	var lobby: Node = root.get_node("NetworkLobby")
	lobby.set("local_team", "ALPHA")

	print("[1] speedball, NPC presence ON at load")
	_check_bots("speedball", EXPECTED_BOTS)
	for n in ["OpFor_CenterAztec", "OpFor_BackCenter"]:
		var b := _bunker(n)
		_check(b is StaticBody3D and b.get_script() == null, "speedball bunker %s still exists (not taken over by a bot)" % n)
	for c in arena.get_children():
		if c is StaticBody3D and String(c.name).contains("@"):
			_check(false, "Godot auto-renamed a clashing node: %s" % c.name)

	print("[2] name lookups")
	var aztec := arena.get_node_or_null("Bot_CenterAztec")
	_check(aztec != null and "bot_name" in aztec, "get_node(\"Bot_CenterAztec\") returns the bot (network bot_eliminated lookup)")
	lobby.call("rpc_notify_bot_eliminated", "Bot_BackCenter")
	var back := arena.get_node_or_null("Bot_BackCenter")
	_check(back != null and bool(back.get("is_eliminated")), "rpc_notify_bot_eliminated(\"Bot_BackCenter\") eliminates the Back-Center bot")
	back.call("_respawn_bot")
	var cands: Array = arena.call("respawn_map_candidates")
	_check(cands.size() == EXPECTED_BOTS, "respawn map candidates list all %d bots (got %d)" % [EXPECTED_BOTS, cands.size()])
	var dots: Array = arena.call("filter_dots_to_half", cands, "BRAVO", "practice")
	_check(dots.size() == EXPECTED_BOTS, "all bots stand on the BRAVO half, so a BRAVO-side map shows %d dots (got %d)" % [EXPECTED_BOTS, dots.size()])
	var bc: Node = arena.get_node_or_null("BunkerCallouts")
	if bc != null:
		_check((bc.call("enemy_nodes") as Array).size() == EXPECTED_BOTS, "bunker callouts count all %d bots as ALPHA's enemies" % EXPECTED_BOTS)
		lobby.set("local_team", "BRAVO")
		_check((bc.call("enemy_nodes") as Array).is_empty(), "bots are not BRAVO's enemies")
		lobby.set("local_team", "ALPHA")
	var player: Node = arena.get("player")
	if player != null and player.has_method("_is_cover_bunker_collider"):
		_check(not bool(player.call("_is_cover_bunker_collider", aztec)), "a bot is never treated as cover")
		_check(bool(player.call("_is_cover_bunker_collider", _bunker("OpFor_CenterAztec"))), "the OpFor_CenterAztec bunker is cover")

	print("[3] NPC presence off / on")
	arena.call("_set_opfor_bots_enabled", false)
	await _frames(2)
	_check(_bots().is_empty(), "bots off: no practice bots left")
	_check(_bunker("OpFor_CenterAztec") != null and _bunker("OpFor_BackCenter") != null, "bots off: the OpFor_CenterAztec / OpFor_BackCenter bunkers are NOT deleted")
	arena.call("_set_opfor_bots_enabled", true)
	await _frames(2)
	_check_bots("speedball after off/on", EXPECTED_BOTS)
	arena.call("_set_opfor_bots_enabled", false)
	arena.call("_set_opfor_bots_enabled", true) # same frame: freed bots still hold their names
	await _frames(2)
	_check_bots("speedball after off/on in one frame", EXPECTED_BOTS)

	print("[4] woods map")
	arena.call("switch_arena_map", "woodsball_crash")
	await _frames(3)
	_check_bots("woods", EXPECTED_WOODS_BOTS)
	_check(_bunker("OpFor_CenterAztec") == null and _bunker("OpFor_BackCenter") == null, "woods: no speedball OpFor_CenterAztec / OpFor_BackCenter bunkers left behind")

	print("[5] back to speedball")
	arena.call("switch_arena_map", "speedball")
	await _frames(3)
	_check_bots("speedball again", EXPECTED_BOTS)
	_check(_bunker("OpFor_CenterAztec") != null and _bunker("OpFor_BackCenter") != null, "speedball again: both bunkers rebuilt under their own names")
	for c in arena.get_children():
		if c is StaticBody3D and String(c.name).contains("@"):
			_check(false, "Godot auto-renamed a clashing node after the map switch: %s" % c.name)

	print("RESULT: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	for f in failures:
		print("  - " + f)
	quit(0 if failures.is_empty() else 1)
