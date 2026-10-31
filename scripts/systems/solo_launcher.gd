extends Node
## v0.6.4 (Bluey): autoload /root/SoloLauncher - one-line entry into the offline Solo FFA (all bots vs you, first to N
## eliminations) for any button. Registered in project.godot as SoloLauncher (no class_name: it would clash).
##   SoloLauncher.start_ffa()                 # Amateur, 4 bots, first to 10
##   SoloLauncher.start_ffa("rookie")         # easier bots
##   get_node("/root/SoloLauncher").start_ffa("amateur", 4, 10)
## Call it from a click handler: the click is the user gesture the web build needs for pointer lock.
## Does exactly what the ?solo=ffa link does: closes the lobby browser, leaves any online room (FFA is offline only),
## then asks the arena (speedball_arena_builder.gd) to build the FFA - speedball map, bots spawned, FFA HUD. If the
## current scene isn't an arena with start_solo_ffa(), it loads the speedball arena first and starts once it's ready.

signal ffa_started(ffa_match: Node)

const TIERS := ["rookie", "amateur"]
const DEFAULT_TIER := "amateur"
const DEFAULT_BOTS := 4
const DEFAULT_KILLS_TO_WIN := 10
const ARENA_SCENE := "res://scenes/maps/speedball_arena_01/speedball_arena_01.tscn"

## The SoloFfaMatch node from the last start (null until one starts).
var last_match: Node = null
var _pending: Dictionary = {}

## Unknown tiers fall back to Amateur; bots are clamped to 1..7, kills_to_win to >= 1.
func start_ffa(tier: String = DEFAULT_TIER, bots: int = DEFAULT_BOTS, kills_to_win: int = DEFAULT_KILLS_TO_WIN) -> void:
	var opts := make_opts(tier, bots, kills_to_win)
	var flow := get_node_or_null("/root/LobbyEntryFlow")
	if flow != null and flow.has_method("close_browser"):
		flow.call("close_browser")
	var lobby := get_node_or_null("/root/NetworkLobby")
	if lobby != null and lobby.has_method("is_online_client") and bool(lobby.call("is_online_client")) and lobby.has_method("disconnect_from_lobby"):
		lobby.call("disconnect_from_lobby")
	var arena := find_arena()
	if arena != null:
		_launch(arena, opts)
		return
	# No arena loaded: load the speedball arena and start as soon as it's in the tree.
	_pending = opts
	if get_tree().change_scene_to_file(ARENA_SCENE) != OK:
		push_warning("SoloLauncher.start_ffa: couldn't load %s" % ARENA_SCENE)
		_pending = {}
		return
	_start_pending.call_deferred()

func _start_pending() -> void:
	for i in 30:
		await get_tree().process_frame
		var arena := find_arena()
		if arena != null and arena.is_node_ready():
			var opts := _pending
			_pending = {}
			await get_tree().process_frame
			var flow := get_node_or_null("/root/LobbyEntryFlow")
			if flow != null and flow.has_method("close_browser"):
				flow.call("close_browser")
			_launch(arena, opts)
			return
	push_warning("SoloLauncher.start_ffa: arena never became ready")
	_pending = {}

func _launch(arena: Node, opts: Dictionary) -> void:
	last_match = arena.call("start_solo_ffa", opts)
	ffa_started.emit(last_match)

## The opts dictionary speedball_arena_builder.start_solo_ffa() takes.
static func make_opts(tier: String = DEFAULT_TIER, bots: int = DEFAULT_BOTS, kills_to_win: int = DEFAULT_KILLS_TO_WIN) -> Dictionary:
	var t := tier.strip_edges().to_lower()
	return {"tier": t if t in TIERS else DEFAULT_TIER, "bots": clampi(bots, 1, 7), "kills_to_win": maxi(kills_to_win, 1)}

## The running arena: the current scene, else any root child with start_solo_ffa().
func find_arena() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene != null and scene.has_method("start_solo_ffa"):
		return scene
	for n in tree.root.get_children():
		if n.has_method("start_solo_ffa"):
			return n
	return null
