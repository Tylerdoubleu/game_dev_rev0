extends RefCounted
## v0.7 solo career (Bluey): the career save. One JSON blob, kept in user://career.json (works offline) and mirrored to
## the profile server (PUT /api/profile/career, <= 32 KB) so it follows the profile token.
## Schema v1:
##   {"v": 1, "challenges": {id: {"mask": int (bit k = star k+1), "wins": int, "plays": int, "best_time_s": float}},
##    "tiers_cleared": {tier_id: true}, "stats": {"wins", "losses", "matches", "eliminations", "deaths"},
##    "pending": [{"kind", "id"}]  (local only - awards not yet acknowledged by the server),
##    "awarded": {"star:<id>": true, ...}  (acknowledged), "clout_earned": int (local estimate), "updated_unix": int}
## Merging a server copy is a union (masks OR, counters max), so two devices / an offline run never lose stars.

const Tiers = preload("res://scripts/career/career_tiers.gd")
const Eval = preload("res://scripts/career/career_eval.gd")

const SCHEMA := 1
const LOCAL_PATH := "user://career.json"
const STAT_KEYS := ["wins", "losses", "matches", "eliminations", "deaths"]

var data: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	data = {"v": SCHEMA, "challenges": {}, "tiers_cleared": {}, "stats": {}, "pending": [], "awarded": {},
		"clout_earned": 0, "updated_unix": 0}
	for k in STAT_KEYS:
		data["stats"][k] = 0

# ------------------------------------------------------------------ queries --

func entry(id: String) -> Dictionary:
	var c: Dictionary = data["challenges"]
	if not c.has(id):
		c[id] = {"mask": 0, "wins": 0, "plays": 0, "best_time_s": 0.0}
	return c[id]

func mask(id: String) -> int:
	return int((data["challenges"] as Dictionary).get(id, {}).get("mask", 0))

func best_stars(id: String) -> int:
	return Eval.count_mask(mask(id))

func tier_stars(t: Dictionary) -> int:
	var n := 0
	for c in t.get("challenges", []):
		n += best_stars(String(c["id"]))
	return n

func total_stars() -> int:
	var n := 0
	for id in data["challenges"]:
		n += best_stars(String(id))
	return n

func tier_unlocked(t: Dictionary) -> bool:
	return total_stars() >= int(t.get("unlock_stars", 0))

## The highest unlocked tier that has playable challenges (Tier 1 in v0.7).
func current_tier() -> Dictionary:
	var best: Dictionary = Tiers.TIERS[0]
	for t in Tiers.TIERS:
		if tier_unlocked(t) and not bool(t.get("coming_soon", false)):
			best = t
	return best

func next_tier_after(t: Dictionary) -> Dictionary:
	return Tiers.tier(int(t.get("index", 1)) + 1)

func pending() -> Array:
	return data["pending"]

# ------------------------------------------------------------------ results --

## Book one finished career match. Returns {"new_stars": [1..3 numbers newly earned], "awards": [{kind,id,clout}],
## "tier_cleared": tier id or "", "clout": expected clout from this match, "best_stars", "eval"}.
func apply_result(c: Dictionary, r: Dictionary) -> Dictionary:
	var id := String(c.get("id", ""))
	var ev := Eval.evaluate(c, r)
	var e := entry(id)
	var old_mask := int(e["mask"])
	var new_mask := Eval.mask_of(ev["stars"])
	var gained := new_mask & ~old_mask
	e["mask"] = old_mask | new_mask
	e["plays"] = int(e["plays"]) + 1
	var stats: Dictionary = data["stats"]
	stats["matches"] = int(stats.get("matches", 0)) + 1
	stats["eliminations"] = int(stats.get("eliminations", 0)) + int(r.get("kills", 0))
	stats["deaths"] = int(stats.get("deaths", 0)) + int(r.get("deaths", 0))
	var awards: Array = []
	var new_stars: Array = []
	for i in 3:
		if gained & (1 << i):
			new_stars.append(i + 1)
			awards.append({"kind": "star", "id": Tiers.star_id(id, i + 1), "clout": Tiers.STAR_CLOUT})
	if bool(ev["won"]):
		stats["wins"] = int(stats.get("wins", 0)) + 1
		awards.append({"kind": "challenge", "id": id, "clout": Tiers.CHALLENGE_CLOUT if int(e["wins"]) == 0 else Tiers.CHALLENGE_REPEAT_CLOUT})
		e["wins"] = int(e["wins"]) + 1
		var t := float(r.get("time_s", 0.0))
		if String(c.get("kind", "")) == "gauntlet" and t > 0.0 and (float(e.get("best_time_s", 0.0)) <= 0.0 or t < float(e["best_time_s"])):
			e["best_time_s"] = t
	else:
		stats["losses"] = int(stats.get("losses", 0)) + 1
	var cleared := ""
	var t_def := Tiers.tier_of(id)
	if not t_def.is_empty() and not (data["tiers_cleared"] as Dictionary).has(t_def["id"]) and tier_stars(t_def) >= int(t_def.get("clear_stars", 999)):
		data["tiers_cleared"][t_def["id"]] = true
		cleared = String(t_def["id"])
		awards.append({"kind": "tier", "id": cleared, "clout": Tiers.TIER_CLOUT})
	var clout := 0
	for a in awards:
		clout += int(a["clout"])
		queue_award(String(a["kind"]), String(a["id"]))
	data["clout_earned"] = int(data.get("clout_earned", 0)) + clout
	touch()
	return {"new_stars": new_stars, "awards": awards, "tier_cleared": cleared, "clout": clout, "best_stars": Eval.count_mask(int(e["mask"])), "eval": ev}

func queue_award(kind: String, id: String) -> void:
	# Stars and tiers pay once: never queue one twice. Challenge wins repeat (+13), so every win queues.
	if kind != "challenge":
		if (data["awarded"] as Dictionary).has("%s:%s" % [kind, id]):
			return
		for p in data["pending"]:
			if String(p["kind"]) == kind and String(p["id"]) == id:
				return
	(data["pending"] as Array).append({"kind": kind, "id": id})

## The server took the head of the queue.
func ack_award(kind: String, id: String) -> void:
	var q: Array = data["pending"]
	for i in q.size():
		if String(q[i]["kind"]) == kind and String(q[i]["id"]) == id:
			q.remove_at(i)
			break
	data["awarded"]["%s:%s" % [kind, id]] = true

func touch() -> void:
	data["updated_unix"] = int(Time.get_unix_time_from_system())

# ------------------------------------------------------------------ merge / io --

## Union with a career blob from the server (or another save). Returns true if this copy changed.
func merge(other: Variant) -> bool:
	if typeof(other) != TYPE_DICTIONARY or (other as Dictionary).is_empty():
		return false
	var o: Dictionary = other
	var before := JSON.stringify(data)
	var oc: Variant = o.get("challenges", {})
	if typeof(oc) == TYPE_DICTIONARY:
		for id in oc:
			if typeof(oc[id]) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = oc[id]
			var e := entry(String(id))
			e["mask"] = int(e["mask"]) | (int(src.get("mask", 0)) & 7)
			e["wins"] = maxi(int(e["wins"]), int(src.get("wins", 0)))
			e["plays"] = maxi(int(e["plays"]), int(src.get("plays", 0)))
			var bt := float(src.get("best_time_s", 0.0))
			if bt > 0.0 and (float(e["best_time_s"]) <= 0.0 or bt < float(e["best_time_s"])):
				e["best_time_s"] = bt
	var ot: Variant = o.get("tiers_cleared", {})
	if typeof(ot) == TYPE_DICTIONARY:
		for k in ot:
			data["tiers_cleared"][String(k)] = true
	var os: Variant = o.get("stats", {})
	if typeof(os) == TYPE_DICTIONARY:
		for k in STAT_KEYS:
			data["stats"][k] = maxi(int(data["stats"].get(k, 0)), int(os.get(k, 0)))
	var oa: Variant = o.get("awarded", {})
	if typeof(oa) == TYPE_DICTIONARY:
		for k in oa:
			data["awarded"][String(k)] = true
	data["clout_earned"] = maxi(int(data.get("clout_earned", 0)), int(o.get("clout_earned", 0)))
	# A star / tier the other copy already got paid for is not pending any more.
	var keep: Array = []
	for p in data["pending"]:
		if String(p["kind"]) == "challenge" or not (data["awarded"] as Dictionary).has("%s:%s" % [p["kind"], p["id"]]):
			keep.append(p)
	data["pending"] = keep
	var changed := JSON.stringify(data) != before
	if changed:
		data["updated_unix"] = maxi(int(data.get("updated_unix", 0)), int(o.get("updated_unix", 0)))
	return changed

## The copy that goes to the server (pending awards stay on this device).
func server_blob() -> Dictionary:
	var b := data.duplicate(true)
	b.erase("pending")
	return b

func to_json() -> String:
	return JSON.stringify(data)

func save(path: String = LOCAL_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	f.close()
	return true

## Loads (replacing) from path; a missing / broken file leaves a fresh career. Returns true when a save was read.
func load_from(path: String = LOCAL_PATH) -> bool:
	reset()
	if not FileAccess.file_exists(path):
		return false
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	merge(parsed)
	var pend: Variant = (parsed as Dictionary).get("pending", [])
	if typeof(pend) == TYPE_ARRAY:
		for p in pend:
			if typeof(p) == TYPE_DICTIONARY and p.has("kind") and p.has("id"):
				(data["pending"] as Array).append({"kind": String(p["kind"]), "id": String(p["id"])})
	data["updated_unix"] = int((parsed as Dictionary).get("updated_unix", 0))
	return true

# ------------------------------------------------------------------ screen --

## The dictionary Ren's CareerScreen.show_career() takes.
func to_screen_dict(callsign: String = "") -> Dictionary:
	var t := current_tier()
	var nt := next_tier_after(t)
	var ts := tier_stars(t)
	var need := int(t.get("clear_stars", 8))
	var cards: Array = []
	for c in t.get("challenges", []):
		cards.append({"id": c["id"], "name": c["name"], "mode": c["mode"], "best_stars": best_stars(String(c["id"])),
			"locked": not Tiers.is_playable(c), "stars_text": c.get("stars", []), "blurb": c.get("blurb", "")})
	if not nt.is_empty():
		for c in nt.get("challenges", []):
			cards.append({"id": c["id"], "name": c["name"], "mode": "T%d · %s" % [int(nt["index"]), c["mode"]],
				"best_stars": best_stars(String(c["id"])), "locked": true})
	var st: Dictionary = data["stats"]
	return {
		"tier": String(t.get("label", "ROOKIE")),
		"next_tier": String(nt.get("label", "")) if not nt.is_empty() else "",
		"xp": ts, "xp_next": need, "progress": clampf(float(ts) / float(maxi(1, need)), 0.0, 1.0),
		"team": callsign if not callsign.is_empty() else "SOLO",
		"sponsor": "",
		"season": 1,
		"event": "%s — %s" % [t.get("name", ""), t.get("subtitle", "")],
		"wins": int(st.get("wins", 0)), "losses": int(st.get("losses", 0)), "matches": int(st.get("matches", 0)),
		"eliminations": int(st.get("eliminations", 0)), "flags": 0,
		"stars": total_stars(), "clout": int(data.get("clout_earned", 0)),
		"challenges": cards,
	}
