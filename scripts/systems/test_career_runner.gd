extends SceneTree
## v0.7 solo career (Bluey): star / challenge evaluation, the career save (apply_result, awards, merge, save / load),
## and the CareerRunner state machine with a mocked ProfileApi (no HTTP, no real user:// save):
## menu -> start -> attach -> match over -> results -> awards + PUT career, offline queue -> later sync.
## Run: godot --headless --path . -s scripts/systems/test_career_runner.gd

const Tiers = preload("res://scripts/career/career_tiers.gd")
const Eval = preload("res://scripts/career/career_eval.gd")
const Progress = preload("res://scripts/career/career_progress.gd")
const RunnerScript = preload("res://scripts/career/career_runner.gd")
const TrackerScript = preload("res://scripts/career/career_tracker.gd")
const TMP_SAVE := "user://test_career_runner.json"

var fails: Array[String] = []

## Canned ProfileApi: online (200s) or offline (status 0). Records every call.
class StubApi extends ProfileApi:
	var calls: Array = []
	var offline := false
	var remote_career: Variant = null
	var award_status := 200
	var clout := 0
	func _ready() -> void:
		token = "t".repeat(64)
	func _save() -> void:
		pass
	func _load() -> void:
		pass
	func _request(action: String, _path: String, _method: int, body) -> void:
		calls.append([action, body])
		if offline:
			_on_reply(action, 0, {})
			return
		match action:
			"create":
				_on_reply(action, 201, {"profile_id": "p1", "token": "t".repeat(64)})
			"get":
				_on_reply(action, 200, {"callsign": "ACE", "clout": clout, "career": remote_career})
			"solo_award":
				if award_status == 200:
					var k := String(body["kind"])
					clout += 100 if k == "star" else (500 if k == "tier" else 50)
					_on_reply(action, 200, {"awarded": true, "clout": clout, "clout_by_source": {"solo": clout}})
				else:
					_on_reply(action, award_status, {"error": "x"})
			"save_career":
				remote_career = body["career"]
				_on_reply(action, 200, {"callsign": "ACE", "clout": clout, "career": remote_career})
			_:
				_on_reply(action, 200, {})
	func count(action: String) -> int:
		var n := 0
		for c in calls:
			if c[0] == action:
				n += 1
		return n

class FakeMatch extends Node:
	signal kill_logged(entry: Dictionary)
	signal ffa_match_over(winner: String)
	var _player_name := "You"
	var scores := {"You": {"kills": 0, "deaths": 0, "is_player": true}}
	var winner := ""
	var rounds_won := 0
	var rounds_lost := 0
	func player_won() -> bool:
		return winner == _player_name
	func kill(by_player: bool) -> void:
		if by_player:
			scores["You"]["kills"] += 1
		else:
			scores["You"]["deaths"] += 1
		kill_logged.emit({"by_player": by_player, "on_player": not by_player})
	func finish(won: bool) -> void:
		winner = _player_name if won else "BOTS"
		ffa_match_over.emit(winner)

class FakePlayer extends Node3D:
	var slide_timer := 0.0
	var dive_timer := 0.0
	var lobby_open := false
	func set_lobby_open_state(o: bool) -> void:
		lobby_open = o

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c:
		fails.append(m)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_tiers()
	_test_eval()
	_test_progress()
	_test_save_load_merge()
	_test_tracker()
	await _test_runner_online()
	await _test_runner_offline_then_sync()
	_test_deep_link()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	if fails.is_empty():
		print("CAREER RUNNER TEST: ALL PASSED")
		quit(0)
	else:
		print("CAREER RUNNER TEST: %d FAILURE(S)" % fails.size())
		for f in fails:
			print("  - " + f)
		quit(1)

func _test_tiers() -> void:
	print("tiers")
	var t1 := Tiers.tier(1)
	_check(String(t1.get("id", "")) == "t1.local_field" and (t1["challenges"] as Array).size() == 4, "Tier 1 Local Field has 4 challenges")
	for c in t1["challenges"]:
		_check(Tiers.is_playable(c), "%s playable" % c["id"])
		_check(String(c["id"]).length() <= 60 and (c["stars"] as Array).size() == 3, "%s: 3 star lines, id fits the award id rule" % c["id"])
	_check(Tiers.star_id("t1.opening_day", 2) == "t1.opening_day.s2", "star id")
	_check(not Tiers.is_playable(Tiers.tier(2)["challenges"][0]), "Tier 2 cards locked (coming soon)")
	var re := RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,64}$")
	for t in Tiers.TIERS:
		_check(re.search(String(t["id"])) != null, "tier id %s matches server id rule" % t["id"])
		for c in t["challenges"]:
			_check(re.search(Tiers.star_id(String(c["id"]), 3)) != null, "star id for %s matches server id rule" % c["id"])

func _test_eval() -> void:
	print("star evaluation")
	var od := Tiers.challenge("t1.opening_day")
	_check(Eval.evaluate(od, {"won": true, "deaths": 3, "style_kills": 2})["count"] == 3, "opening day: win, 3 deaths, 2 style -> 3 stars")
	_check(Eval.evaluate(od, {"won": true, "deaths": 6, "style_kills": 2})["stars"] == [true, false, true], "opening day: 6 deaths misses star 2 only")
	_check(Eval.evaluate(od, {"won": false, "deaths": 0, "style_kills": 9})["count"] == 0, "opening day: a loss earns nothing")
	var los := Tiers.challenge("t1.last_one_standing")
	_check(Eval.evaluate(los, {"won": true, "rounds_won": 3, "rounds_lost": 1})["stars"] == [true, true, false], "last one standing 3-1 -> 2 stars")
	_check(Eval.evaluate(los, {"won": true, "rounds_won": 3, "rounds_lost": 0})["count"] == 3, "last one standing 3-0 -> 3 stars")
	_check(Eval.evaluate(los, {"won": true, "rounds_won": 3, "rounds_lost": 2})["count"] == 1, "3-2 -> 1 star")
	var sn := Tiers.challenge("t1.run_the_snake")
	_check(Eval.evaluate(sn, {"finished": true, "time_s": 40.0, "deaths": 0})["count"] == 3, "snake 40 s clean -> 3 stars")
	_check(Eval.evaluate(sn, {"finished": true, "time_s": 40.0, "deaths": 1})["stars"] == [true, true, false], "snake 40 s with a splat -> 2")
	_check(Eval.evaluate(sn, {"finished": true, "time_s": 90.0, "deaths": 0})["count"] == 1, "snake 90 s -> 1")
	_check(Eval.evaluate(sn, {"finished": false, "time_s": 10.0})["won"] == false, "snake unfinished = not won")
	var hm := Tiers.challenge("t1.hold_the_middle")
	_check(Eval.evaluate(hm, {"won": true, "zone_kills": 5})["stars"] == [true, true, false], "cake 5 kills -> 2 stars")
	_check(Eval.evaluate(hm, {"won": true, "zone_kills": 10})["count"] == 3, "cake 10 kills -> 3 stars")
	_check(Eval.mask_of([true, false, true]) == 5 and Eval.count_mask(5) == 2, "mask helpers")

func _test_progress() -> void:
	print("progress / awards")
	var p := Progress.new()
	var od := Tiers.challenge("t1.opening_day")
	var o := p.apply_result(od, {"won": true, "kills": 10, "deaths": 2, "style_kills": 0})
	_check(o["new_stars"] == [1, 2], "first win: stars 1 + 2 new (%s)" % str(o["new_stars"]))
	_check(int(o["clout"]) == 250, "first win clout 100+100+50 = 250 (%d)" % int(o["clout"]))
	_check(p.pending().size() == 3, "3 awards queued")
	o = p.apply_result(od, {"won": true, "kills": 10, "deaths": 2, "style_kills": 3})
	_check(o["new_stars"] == [3] and int(o["clout"]) == 113, "repeat win: star 3 (100) + repeat challenge (13) = 113 (%d)" % int(o["clout"]))
	o = p.apply_result(od, {"won": true, "kills": 10, "deaths": 2, "style_kills": 3})
	_check(o["new_stars"].is_empty() and int(o["clout"]) == 13, "third win: just the +13 repeat")
	p.ack_award("star", "t1.opening_day.s1")
	p.queue_award("star", "t1.opening_day.s1")
	_check(p.pending().size() == 5, "an acknowledged star is never queued again (%d pending)" % p.pending().size())
	o = p.apply_result(od, {"won": false, "kills": 3, "deaths": 10})
	_check(int(o["clout"]) == 0 and int(p.data["stats"]["losses"]) == 1, "a loss: no clout, counts a loss")
	# Tier clear at 8 stars
	p.apply_result(Tiers.challenge("t1.last_one_standing"), {"won": true, "rounds_won": 3, "rounds_lost": 0})
	_check(p.tier_stars(Tiers.tier(1)) == 6, "6 tier stars")
	var sn := Tiers.challenge("t1.run_the_snake")
	o = p.apply_result(sn, {"finished": true, "time_s": 50.0, "deaths": 1})
	_check(String(o["tier_cleared"]) == "t1.local_field", "8th star clears Local Field")
	var tier_awards := 0
	for a in o["awards"]:
		if a["kind"] == "tier":
			tier_awards += 1
			_check(int(a["clout"]) == 500, "tier award 500")
	_check(tier_awards == 1, "one tier award")
	_check(float(p.entry("t1.run_the_snake")["best_time_s"]) == 50.0, "snake best time kept")
	o = p.apply_result(sn, {"finished": true, "time_s": 30.0, "deaths": 0})
	_check(String(o["tier_cleared"]) == "" and float(p.entry("t1.run_the_snake")["best_time_s"]) == 30.0, "tier only clears once; best time improves")
	var d := p.to_screen_dict("ACE")
	_check(String(d["tier"]) == "ROOKIE" and String(d["team"]) == "ACE" and typeof(d["season"]) == TYPE_INT, "screen dict: tier label, callsign, int season")
	_check(int(d["stars"]) == p.total_stars() and (d["challenges"] as Array).size() == 8, "screen dict: stars + 4 tier-1 cards + 4 locked tier-2 cards")
	var locked := 0
	for c in d["challenges"]:
		locked += 1 if bool(c["locked"]) else 0
	_check(locked == 4, "tier-2 cards shown locked")
	_check(JSON.stringify(p.server_blob()).length() < 32 * 1024 and not p.server_blob().has("pending"), "server blob < 32 KB, no pending queue")

func _test_save_load_merge() -> void:
	print("save / load / merge")
	var p := Progress.new()
	p.apply_result(Tiers.challenge("t1.opening_day"), {"won": true, "deaths": 1, "style_kills": 2})
	_check(p.save(TMP_SAVE), "saved to user://")
	var q := Progress.new()
	_check(q.load_from(TMP_SAVE), "loaded")
	_check(q.mask("t1.opening_day") == 7 and q.pending().size() == 4, "mask 7 + 4 pending awards survive a reload")
	var r := Progress.new()
	r.apply_result(Tiers.challenge("t1.hold_the_middle"), {"won": true, "zone_kills": 5})
	r.ack_award("star", "t1.opening_day.s1")
	_check(q.merge(r.server_blob()), "merge changes the copy")
	_check(q.mask("t1.opening_day") == 7 and q.mask("t1.hold_the_middle") == 3, "merge is a union")
	_check(q.pending().size() == 3, "a star the other copy got paid for leaves the pending queue")
	_check(not q.merge(r.server_blob()), "merging the same copy again changes nothing")
	var broken := FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	broken.store_string("{not json")
	broken.close()
	_check(not q.load_from(TMP_SAVE) and q.total_stars() == 0, "a broken save loads as a fresh career")

func _test_tracker() -> void:
	print("tracker")
	var m := FakeMatch.new()
	var pl := FakePlayer.new()
	root.add_child(m)
	m.add_child(pl)
	var tr: Node = TrackerScript.new()
	var hm := Tiers.challenge("t1.hold_the_middle")
	m.add_child(tr)
	tr.call("setup", hm, m, pl)
	pl.position = Vector3(0, 0, 19)
	m.kill(true) # zone kill
	pl.position = Vector3(20, 0, 0)
	pl.slide_timer = 0.3
	m.kill(true) # style kill, outside zone
	pl.slide_timer = 0.0
	tr.set("clock", 1.0)
	m.kill(true) # 1 s after the slide: still style
	tr.set("clock", 5.0)
	m.kill(true) # plain
	m.kill(false)
	var got := []
	tr.connect("finished", func(res): got.append(res))
	m.finish(true)
	_check(got.size() == 1, "finished once on match over")
	var res: Dictionary = got[0] if got.size() > 0 else {}
	_check(int(res.get("kills", -1)) == 4 and int(res.get("deaths", -1)) == 1, "kills 4 / deaths 1 (%s)" % str(res))
	_check(int(res.get("style_kills", -1)) == 2, "style kills: the slide kill + the one right after it (%d)" % int(res.get("style_kills", -1)))
	_check(int(res.get("zone_kills", -1)) == 1 and bool(res.get("won", false)), "1 zone kill, won")
	m.free()

func _new_runner(api: ProfileApi) -> Node:
	var r: Node = RunnerScript.new()
	r.set("save_path", TMP_SAVE)
	r.set("results_delay_s", 0.0)
	r.call("bind_api", api)
	var launched := []
	r.set("launch_override", func(o: Dictionary) -> void: launched.append(o))
	r.set_meta("launched", launched)
	root.add_child(r)
	return r

func _test_runner_online() -> void:
	print("runner (online)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var api := StubApi.new()
	root.add_child(api)
	var r := _new_runner(api)
	var states := []
	r.connect("state_changed", func(s): states.append(s))
	var scr: Control = r.call("open_career")
	await process_frame
	await process_frame
	_check(scr != null and scr is CareerScreen and String(r.get("state")) == "menu", "open_career -> Ren's CareerScreen, state menu")
	_check(api.count("get") >= 1, "career screen fetched the profile")
	_check(scr != null and scr.find_child("Challenge_t1.opening_day", true, false) != null or (scr != null and _has_text(scr, "OPENING DAY")), "Tier 1 cards on the screen")
	_check(not bool(r.call("start_challenge", "t2.five_man_ctf")), "a Tier 2 card doesn't start")
	scr.emit_signal("play_pressed", "t1.opening_day")
	var launched: Array = r.get_meta("launched")
	_check(String(r.get("state")) == "starting" and launched.size() == 1, "PLAY -> starting, launcher called")
	var o: Dictionary = launched[0] if launched.size() > 0 else {}
	_check(String(o.get("kind", "")) == "tdm" and int(o.get("bots", 0)) == 4 and int(o.get("kills_to_win", 0)) == 10 and String(o.get("career_challenge", "")) == "t1.opening_day", "event opts %s" % str(o))
	var lo := RunnerScript.event_opts(Tiers.challenge("t1.last_one_standing"))
	_check(String(lo["mode"]) == "elimination" and int(lo["rounds_to_win"]) == 3, "elimination opts")
	var go := RunnerScript.event_opts(Tiers.challenge("t1.run_the_snake"))
	_check(String(go["kind"]) == "gauntlet" and int(go["pops"]) == 5, "gauntlet opts")
	var puts_before := api.count("save_career")
	var m := FakeMatch.new()
	root.add_child(m)
	r.call("attach_match", null, m, o)
	_check(String(r.get("state")) == "in_match", "attach -> in_match")
	for i in 10:
		m.kill(true)
	m.kill(false)
	m.finish(true)
	await process_frame
	_check(String(r.get("state")) == "results", "match over -> results")
	var res: Node = r.get("results")
	_check(res != null and _has_text(res, "CHALLENGE COMPLETE"), "results screen: CHALLENGE COMPLETE")
	var out: Dictionary = r.get("last_outcome")
	_check(out.get("new_stars", []) == [1, 2], "stars 1 + 2 (no style kills) (%s)" % str(out.get("new_stars")))
	_check(api.count("solo_award") == 3, "3 solo_award calls (2 stars + challenge) (%d)" % api.count("solo_award"))
	_check(api.count("save_career") == puts_before + 1, "career PUT once after the match")
	_check(int(api.profile.get("clout", 0)) == 250 and _has_text(res, "+250 CLOUT"), "server clout 250 shown")
	_check(_has_text(res, "SYNCED"), "results say synced")
	var prog = r.get("progress")
	_check(prog.pending().is_empty(), "award queue drained")
	_check(typeof(api.remote_career) == TYPE_DICTIONARY and int(api.remote_career["challenges"]["t1.opening_day"]["mask"]) == 3, "server got the career blob")
	var saved := Progress.new()
	_check(saved.load_from(TMP_SAVE) and saved.mask("t1.opening_day") == 3, "local save written")
	# RETRY -> starting again; CAREER -> menu
	res.emit_signal("retry_pressed")
	_check(String(r.get("state")) == "starting" and (r.get_meta("launched") as Array).size() == 2, "RETRY relaunches the same event")
	r.call("attach_match", null, m, o)
	m.winner = ""
	m.finish(false)
	await process_frame
	_check(_has_text(r.get("results"), "NOT THIS TIME"), "a loss: NOT THIS TIME")
	(r.get("results") as Node).emit_signal("career_pressed")
	await process_frame
	_check(String(r.get("state")) == "menu" and r.get("screen") != null, "CAREER -> back on the career screen")
	_check("in_match" in states and "results" in states, "state machine path %s" % str(states))
	r.call("close_career")
	_check(String(r.get("state")) == "idle" and not bool(r.call("is_open")), "BACK -> idle, no career UI")
	m.free()
	r.free()
	api.free()

func _test_runner_offline_then_sync() -> void:
	print("runner (offline, later sync)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var api := StubApi.new()
	api.offline = true
	root.add_child(api)
	var r := _new_runner(api)
	r.call("start_challenge", "t1.hold_the_middle")
	var m := FakeMatch.new()
	root.add_child(m)
	r.call("attach_match", null, m, RunnerScript.event_opts(Tiers.challenge("t1.hold_the_middle")))
	r.call("finish_match", {"won": true, "kills": 12, "deaths": 0, "zone_kills": 6})
	await process_frame
	var prog = r.get("progress")
	_check(prog.pending().size() == 3, "offline: 3 awards wait in the queue (%d)" % prog.pending().size())
	_check(_has_text(r.get("results"), "THIS DEVICE"), "results: saved on this device")
	var p2 := Progress.new()
	_check(p2.load_from(TMP_SAVE) and p2.pending().size() == 3 and p2.mask("t1.hold_the_middle") == 3, "queue + stars in the local save")
	r.free()
	# Next session, online: the runner loads the local save, the profile fetch merges the server copy and flushes.
	api.offline = false
	api.calls.clear()
	var srv := Progress.new()
	srv.apply_result(Tiers.challenge("t1.last_one_standing"), {"won": true, "rounds_won": 3, "rounds_lost": 0})
	api.remote_career = srv.server_blob()
	var r2 := _new_runner(api)
	_check((r2.get("progress")).pending().size() == 3, "reload: queue restored from user://")
	api.fetch_profile()
	await process_frame
	var pr2 = r2.get("progress")
	_check(pr2.pending().is_empty() and api.count("solo_award") == 3, "back online: queued awards sent (%d)" % api.count("solo_award"))
	_check(pr2.mask("t1.last_one_standing") == 7 and pr2.mask("t1.hold_the_middle") == 3, "server career merged with the local one")
	_check(api.count("save_career") == 1 and int(api.remote_career["challenges"]["t1.hold_the_middle"]["mask"]) == 3, "merged career PUT back")
	# 400 drops the bad award instead of wedging; 0 keeps it
	pr2.queue_award("star", "bad id!")
	api.award_status = 400
	r2.call("sync")
	_check(pr2.pending().is_empty(), "400: bad award dropped")
	api.free()
	r2.free()

func _test_deep_link() -> void:
	print("deep link")
	_check(RunnerScript.wants_career_link("?solo=career", []), "?solo=career")
	_check(RunnerScript.wants_career_link("?x=1&SOLO=Career", []), "case-insensitive, any position")
	_check(not RunnerScript.wants_career_link("?solo=ffa", []), "?solo=ffa is not career")
	_check(RunnerScript.wants_career_link("", ["--solo=career"]), "--solo=career")
	var auto := root.get_node_or_null("CareerRunner")
	_check(auto != null and auto.get_script().get_global_name() == &"", "CareerRunner autoload, no class_name")

func _has_text(n: Node, t: String) -> bool:
	if n == null:
		return false
	if (n is Label or n is Button) and String(n.get("text")).contains(t):
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false
