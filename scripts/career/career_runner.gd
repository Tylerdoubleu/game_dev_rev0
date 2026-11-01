extends Node
## v0.7 solo CAREER RUNNER (Bluey). Autoload /root/CareerRunner (no class_name). Owns the career loop:
##   IDLE -> MENU (Ren's CareerScreen: tier, stars, challenge cards) -> STARTING (SoloLauncher.start_event)
##        -> IN_MATCH (CareerTracker rides the match) -> RESULTS (stars judged, clout queued, career saved) -> MENU ...
## Entry points: CareerRunner.open_career()  (a CAREER button; ?solo=career / --solo=career deep link opens it on boot)
## Save: user://career.json first (always works offline), then the profile server: one POST /api/profile/solo_award per
## new star / challenge win / tier clear (sent one at a time: the reply carries no id), then PUT /api/profile/career.
## Anything that fails offline stays queued in the local save and is sent the next time the profile loads.
## The arena calls attach_match() after it starts an event whose opts carry "career_challenge" - so a [T] rematch
## (scene reload) of a career event is tracked too.

const Tiers = preload("res://scripts/career/career_tiers.gd")
const Eval = preload("res://scripts/career/career_eval.gd")
const Progress = preload("res://scripts/career/career_progress.gd")
const Tracker = preload("res://scripts/career/career_tracker.gd")
const ResultsScreen = preload("res://scripts/career/career_results_screen.gd")
const CAREER_SCREEN_PATH := "res://scripts/ui/career_screen.gd"

signal state_changed(state: String)
signal match_finished(outcome: Dictionary)
signal synced

const IDLE := "idle"
const MENU := "menu"
const STARTING := "starting"
const IN_MATCH := "in_match"
const RESULTS := "results"
const LAYER := 62 # above the title screen / lobby browser (60)
const RESULTS_DELAY_S := 1.8
const RATE_LIMIT_RETRY_S := 65.0

var state: String = IDLE
var progress := Progress.new()
var save_path: String = Progress.LOCAL_PATH
var api: ProfileApi = null
var online: bool = false
var current_challenge: Dictionary = {}
var current_match: Node = null
var tracker: Node = null
var last_result: Dictionary = {}
var last_outcome: Dictionary = {}
var career_dirty: bool = false
var award_in_flight: Dictionary = {}
var saving_career: bool = false
var awards_sent: int = 0
var results_delay_s: float = RESULTS_DELAY_S
## Tests: replace the launcher (Callable(opts) -> void) instead of SoloLauncher.start_event.
var launch_override: Callable = Callable()
var layer: CanvasLayer = null
var screen: Control = null
var results: Control = null

func _ready() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and bool(nl.get("is_dedicated_server")):
		return
	progress.load_from(save_path)
	if wants_career_link(_page_query(), OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		_open_from_link.call_deferred()

# -------------------------------------------------------------------- entry --

## ?solo=career (web) or --solo=career (desktop).
static func wants_career_link(query: String, cmdline: Array) -> bool:
	for part in query.strip_edges().trim_prefix("?").split("&", false):
		var kv := part.split("=", true, 1)
		if kv[0].uri_decode().to_lower() == "solo" and kv.size() == 2 and kv[1].uri_decode().to_lower() == "career":
			return true
	for a in cmdline:
		if String(a).to_lower() == "--solo=career":
			return true
	return false

static func _page_query() -> String:
	if not OS.has_feature("web"):
		return ""
	var q: Variant = JavaScriptBridge.eval("window.location.search || ''", true)
	return String(q) if typeof(q) == TYPE_STRING else ""

func _open_from_link() -> void:
	for _i in 16: # after LobbyEntryFlow has attached (it skips the title screen for ?solo=)
		await get_tree().process_frame
	open_career()

# -------------------------------------------------------------------- state --

func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)

## The career screen (Ren's CareerScreen) on its own layer. Safe to call from any menu button.
func open_career() -> Control:
	_ensure_api()
	_close_other_menus()
	_clear_ui()
	_ensure_layer()
	var scr := load(CAREER_SCREEN_PATH) as Script if ResourceLoader.exists(CAREER_SCREEN_PATH) else null
	if scr == null:
		push_warning("CareerRunner: career_screen.gd missing")
		return null
	screen = scr.new()
	screen.call("bind_api", api)
	layer.add_child(screen)
	screen.call("show_career", screen_dict())
	screen.connect("play_pressed", _on_play_pressed)
	screen.connect("back_pressed", close_career)
	_set_player_menu(true)
	_set_state(MENU)
	return screen

func screen_dict() -> Dictionary:
	var cs := ""
	if api != null and api.profile.get("callsign") != null:
		cs = String(api.profile.get("callsign"))
	return progress.to_screen_dict(cs)

## BACK from the career screen: the title screen again (or just the arena when there is none).
func close_career() -> void:
	_clear_ui()
	_set_player_menu(false)
	_set_state(IDLE)
	var flow := get_node_or_null("/root/LobbyEntryFlow")
	if flow != null and flow.has_method("show_title_screen") and DisplayServer.get_name() != "headless":
		flow.call("show_title_screen")

func _on_play_pressed(id: String) -> void:
	start_challenge(id)

## Launch a Tier challenge. false when the id is unknown / not playable yet.
func start_challenge(id: String) -> bool:
	var c := Tiers.challenge(id)
	if c.is_empty() or not Tiers.is_playable(c):
		return false
	current_challenge = c
	_clear_ui()
	_set_player_menu(false)
	_set_state(STARTING)
	var opts := event_opts(c)
	if launch_override.is_valid():
		launch_override.call(opts)
	else:
		var sl := get_node_or_null("/root/SoloLauncher")
		if sl != null:
			sl.call("start_event", opts)
	return true

## The opts SoloLauncher.start_event / the arena take for a challenge.
static func event_opts(c: Dictionary) -> Dictionary:
	var kind := String(c.get("kind", "tdm"))
	var o := {"kind": kind, "tier": String(c.get("tier", "rookie")), "career_challenge": String(c.get("id", ""))}
	match kind:
		"elimination":
			o["mode"] = "elimination"
			o["bots"] = int(c.get("bots", 3))
			o["rounds_to_win"] = int(c.get("rounds_to_win", 3))
			o["kills_to_win"] = 999
		"gauntlet":
			o["pops"] = int(c.get("pops", 5))
			o["time_limit_s"] = float(c.get("time_limit_s", 180.0))
		_:
			o["mode"] = "tdm"
			o["bots"] = int(c.get("bots", 4))
			o["kills_to_win"] = int(c.get("kills_to_win", 10))
	return o

## Called by the arena right after it starts a career event (also after a [T] rematch reload).
func attach_match(_arena: Node, match_node: Node, opts: Dictionary) -> void:
	var c := Tiers.challenge(String(opts.get("career_challenge", "")))
	if c.is_empty() or match_node == null:
		return
	current_challenge = c
	current_match = match_node
	_clear_ui()
	tracker = Tracker.new()
	match_node.add_child(tracker)
	var p: Node = _arena_player(_arena)
	tracker.call("setup", c, match_node, p)
	tracker.connect("finished", _on_tracker_finished)
	_set_state(IN_MATCH)

func _arena_player(arena: Node) -> Node:
	if arena != null and is_instance_valid(arena) and "player" in arena:
		return arena.get("player")
	return null

func _on_tracker_finished(r: Dictionary) -> void:
	finish_match(r)

## Judge a finished career match: stars, clout awards, local save, server sync, results card.
func finish_match(r: Dictionary) -> Dictionary:
	if state != IN_MATCH or current_challenge.is_empty():
		return {}
	last_result = r.duplicate()
	last_outcome = progress.apply_result(current_challenge, r)
	progress.save(save_path)
	career_dirty = true
	_set_state(RESULTS)
	match_finished.emit(last_outcome)
	if results_delay_s > 0.0 and is_inside_tree():
		get_tree().create_timer(results_delay_s).timeout.connect(show_results)
	else:
		show_results()
	_ensure_api()
	sync()
	return last_outcome

func show_results() -> Control:
	if state != RESULTS:
		return null
	_clear_ui()
	_ensure_layer()
	results = ResultsScreen.new()
	layer.add_child(results)
	results.call("show_outcome", current_challenge, last_result, last_outcome)
	_refresh_results_status()
	results.connect("retry_pressed", retry)
	results.connect("career_pressed", open_career)
	_set_player_menu(true)
	return results

func retry() -> bool:
	return start_challenge(String(current_challenge.get("id", "")))

func _refresh_results_status() -> void:
	if results == null or not is_instance_valid(results):
		return
	var pend := progress.pending().size()
	if pend == 0 and not career_dirty and not saving_career:
		results.call("set_sync", "CAREER SAVED  //  SYNCED TO YOUR PROFILE", true)
	elif online:
		results.call("set_sync", "SYNCING CAREER... (%d TO SEND)" % pend, true)
	else:
		results.call("set_sync", "SAVED ON THIS DEVICE  //  WILL SYNC WHEN ONLINE", false)
	var total := int(progress.data.get("clout_earned", 0))
	if api != null and api.profile.get("clout") != null:
		total = int(api.profile["clout"])
	results.call("set_clout_total", total)

# -------------------------------------------------------------------- sync --

func bind_api(a: ProfileApi) -> void:
	if api == a:
		return
	api = a
	if api != null and not api.completed.is_connected(_on_api):
		api.completed.connect(_on_api)

func _ensure_api() -> void:
	if api != null:
		return
	var a := ProfileApi.new()
	a.name = "CareerProfileApi"
	add_child(a)
	bind_api(a)
	a.ensure_profile.call_deferred()

## Send queued awards (one at a time), then the career blob.
func sync() -> void:
	if api == null or not award_in_flight.is_empty() or saving_career:
		return
	var q := progress.pending()
	if not q.is_empty():
		award_in_flight = (q[0] as Dictionary).duplicate()
		api.solo_award(String(award_in_flight["kind"]), String(award_in_flight["id"]))
		return
	if career_dirty:
		career_dirty = false
		saving_career = true
		api.save_career(progress.server_blob())
		return
	_refresh_results_status()

func _on_api(action: String, status: int, d: Dictionary) -> void:
	if status == 0 or status >= 500:
		online = false
	match action:
		"create":
			if status == 201:
				online = true
				career_dirty = true # a brand-new profile has no career yet
				sync()
		"get":
			if status == 200:
				online = true
				var remote: Variant = d.get("career")
				var local_before := JSON.stringify(progress.server_blob())
				if progress.merge(remote):
					progress.save(save_path)
				if typeof(remote) != TYPE_DICTIONARY or JSON.stringify(progress.server_blob()) != JSON.stringify(remote) or local_before != JSON.stringify(progress.server_blob()):
					career_dirty = true
				_refresh_screen()
				sync()
			elif status == 401 and (screen == null or not is_instance_valid(screen)):
				api.create_profile() # CareerScreen does this itself when it is up
		"solo_award":
			var head := award_in_flight
			award_in_flight = {}
			if status == 200:
				online = true
				awards_sent += 1
				progress.ack_award(String(head.get("kind", "")), String(head.get("id", "")))
				progress.save(save_path)
				sync()
			elif status == 400:
				progress.ack_award(String(head.get("kind", "")), String(head.get("id", ""))) # bad id: drop it, don't wedge the queue
				progress.save(save_path)
				sync()
			elif status == 429 and is_inside_tree():
				get_tree().create_timer(RATE_LIMIT_RETRY_S).timeout.connect(sync)
		"save_career":
			saving_career = false
			if status == 200:
				online = true
				synced.emit()
			elif status != 413: # too large is permanent; anything else retries on the next sync
				career_dirty = true
	_refresh_results_status()

func _refresh_screen() -> void:
	if screen != null and is_instance_valid(screen) and state == MENU:
		screen.call("show_career", screen_dict())

# -------------------------------------------------------------------- ui --

func _ensure_layer() -> void:
	if layer != null and is_instance_valid(layer):
		return
	layer = CanvasLayer.new()
	layer.name = "CareerLayer"
	layer.layer = LAYER
	add_child(layer)

func _clear_ui() -> void:
	for n in [screen, results]:
		if n != null and is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	screen = null
	results = null

func _close_other_menus() -> void:
	var flow := get_node_or_null("/root/LobbyEntryFlow")
	if flow != null:
		if flow.has_method("close_browser"):
			flow.call("close_browser")
		var ts: Variant = flow.get("title_screen")
		if ts is Node and is_instance_valid(ts) and ts.has_method("dismiss"):
			ts.call("dismiss")
	var arena := _arena()
	if arena != null and arena.has_method("_set_lobby_overlay_visible"):
		arena.call("_set_lobby_overlay_visible", false)

## Menus up: free the mouse (the arena's mouse guard reads player.lobby_open).
func _set_player_menu(open: bool) -> void:
	var p := _arena_player(_arena())
	if p != null and is_instance_valid(p) and p.has_method("set_lobby_open_state"):
		p.call("set_lobby_open_state", open)
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _arena() -> Node:
	var sl := get_node_or_null("/root/SoloLauncher")
	if sl != null and sl.has_method("find_arena"):
		return sl.call("find_arena")
	return null

func is_open() -> bool:
	return (screen != null and is_instance_valid(screen)) or (results != null and is_instance_valid(results))
