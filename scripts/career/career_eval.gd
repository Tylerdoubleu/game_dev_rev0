extends RefCounted
## v0.7 solo career (Bluey): match result -> stars. Pure functions (tests call them directly).
## result (CareerTracker.result()):
##   kind: String, won: bool, finished: bool (gauntlet), kills, deaths, style_kills (a kill while sliding / diving or
##   within STYLE_WINDOW_S of one ending), zone_kills (kills from the challenge zone), rounds_won, rounds_lost,
##   time_s (gauntlet: horn to last pop), pops
## Each star is judged on its own (you can earn star 3 before star 2); a star needs the win (or a finish).

const STYLE_WINDOW_S := 1.25

## -> {"won": bool, "stars": [bool, bool, bool], "count": int}
static func evaluate(c: Dictionary, r: Dictionary) -> Dictionary:
	var id := String(c.get("id", ""))
	var won := bool(r.get("won", false))
	var s := [false, false, false]
	match id:
		"t1.opening_day":
			s = [won, won and int(r.get("deaths", 99)) <= 5, won and int(r.get("style_kills", 0)) >= 2]
		"t1.last_one_standing":
			var lost := int(r.get("rounds_lost", 99))
			s = [won, won and lost <= 1, won and lost == 0]
		"t1.run_the_snake":
			var fin := bool(r.get("finished", false))
			won = fin
			var t := float(r.get("time_s", INF))
			s = [fin, fin and t < 60.0, fin and t < 45.0 and int(r.get("deaths", 1)) == 0]
		"t1.hold_the_middle":
			var z := int(r.get("zone_kills", 0))
			s = [won, won and z >= 5, won and z >= 10]
		_:
			s = [won, false, false]
	var n := 0
	for b in s:
		n += 1 if b else 0
	return {"won": won, "stars": s, "count": n}

## Bitmask helpers (bit k = star k+1) - the save keeps a mask per challenge.
static func mask_of(stars: Array) -> int:
	var m := 0
	for i in stars.size():
		if bool(stars[i]):
			m |= 1 << i
	return m

static func count_mask(m: int) -> int:
	var n := 0
	for i in 3:
		if m & (1 << i):
			n += 1
	return n
