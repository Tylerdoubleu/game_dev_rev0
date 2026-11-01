extends RefCounted
## v0.7 solo career (Bluey): the tier / challenge table (approved v0.7 plan). Pure data, no nodes.
## Tier 1 "Local Field - Sunday Rec Ball" is fully playable; Tier 2+ are listed (locked) so the ladder shows.
## A challenge:
##   id          stable id (career save + server award ids) - never rename a shipped one
##   name, mode  card text ("TDM", "ELIMINATION", "GAUNTLET")
##   kind        "tdm" | "elimination" | "gauntlet" - what CareerRunner launches
##   tier        bot difficulty ("rookie" / "amateur")
##   bots        bot count;  kills_to_win (tdm) / rounds_to_win (elimination) / pops + time_limit_s (gauntlet)
##   stars       3 lines of star text, in order (CareerEval decides them)
##   zone        optional {"name", "center": Vector3, "radius"} - kills from inside it count as zone_kills
## Award ids (server SOLO_ID_RE ^[A-Za-z0-9_.:-]{1,64}$):
##   star       "<challenge id>.s<1..3>"      e.g. "t1.opening_day.s2"   (+100 first time, then 0)
##   challenge  "<challenge id>"              on every win                (+50 first, +13 repeats)
##   tier       "<tier id>"                   when the tier's star gate is reached (+500 once)

const STAR_CLOUT := 100
const CHALLENGE_CLOUT := 50
const CHALLENGE_REPEAT_CLOUT := 13
const TIER_CLOUT := 500

## The Cake on the home (ALPHA, +Z) side: Home_CenterAztec at (0, 0, 19), 2.8 x 1.8 m. "From the Cake" = within 5 m.
const HOME_CAKE := {"name": "CAKE", "center": Vector3(0.0, 0.0, 19.0), "radius": 5.0}

const TIERS := [
	{
		"id": "t1.local_field", "index": 1, "name": "LOCAL FIELD", "subtitle": "SUNDAY REC BALL", "label": "ROOKIE",
		"bots_tier": "rookie", "unlock_stars": 0, "clear_stars": 8,
		"challenges": [
			{"id": "t1.opening_day", "name": "OPENING DAY", "mode": "TDM", "kind": "tdm", "tier": "rookie", "bots": 4, "kills_to_win": 10,
				"blurb": "You vs 4 Rookie bots. First team to 10.",
				"stars": ["WIN", "WIN WITH 5 OR FEWER DEATHS", "WIN WITH 2 DIVE / SLIDE KILLS"]},
			{"id": "t1.last_one_standing", "name": "LAST ONE STANDING", "mode": "ELIMINATION", "kind": "elimination", "tier": "rookie", "bots": 3, "rounds_to_win": 3,
				"blurb": "One life a round vs 3 Rookie bots. Best of 5.",
				"stars": ["WIN THE SERIES", "WIN 3-0 OR 3-1", "SWEEP IT 3-0"]},
			{"id": "t1.run_the_snake", "name": "RUN THE SNAKE", "mode": "GAUNTLET", "kind": "gauntlet", "tier": "rookie", "pops": 5, "time_limit_s": 180.0,
				"blurb": "Pop 5 peekers on the clock. 3:00 limit.",
				"stars": ["FINISH", "UNDER 60 SECONDS", "UNDER 45 S, NEVER SPLATTED"]},
			{"id": "t1.hold_the_middle", "name": "HOLD THE MIDDLE", "mode": "TDM", "kind": "tdm", "tier": "rookie", "bots": 4, "kills_to_win": 12,
				"zone": HOME_CAKE, "blurb": "Win from the Cake. First team to 12.",
				"stars": ["WIN", "WIN WITH 5 KILLS FROM THE CAKE", "WIN WITH 10 KILLS FROM THE CAKE"]},
		],
	},
	{
		"id": "t2.regional", "index": 2, "name": "REGIONAL SERIES", "subtitle": "D3 TRAVEL BALL", "label": "AMATEUR",
		"bots_tier": "amateur", "unlock_stars": 8, "clear_stars": 10, "coming_soon": true,
		"challenges": [
			{"id": "t2.five_man_ctf", "name": "FIVE-MAN CTF", "mode": "CTF", "kind": "ctf", "tier": "amateur", "stars": ["WIN", "WIN 3-1 OR BETTER", "HANG 2 FLAGS YOURSELF"]},
			{"id": "t2.home_snake", "name": "HOME SNAKE", "mode": "TDM", "kind": "tdm", "tier": "amateur", "stars": ["WIN", "", ""]},
			{"id": "t2.wire_to_wire", "name": "WIRE TO WIRE", "mode": "ELIMINATION", "kind": "elimination", "tier": "amateur", "stars": ["WIN", "", ""]},
			{"id": "t2.pump_day", "name": "PUMP DAY", "mode": "PUMP", "kind": "pump", "tier": "amateur", "stars": ["WIN", "", ""]},
		],
	},
	{"id": "t3.national", "index": 3, "name": "NATIONAL CIRCUIT", "subtitle": "D1 / PRO", "label": "PRO", "bots_tier": "pro",
		"unlock_stars": 20, "clear_stars": 30, "coming_soon": true, "challenges": []},
	{"id": "t4.world_cup", "index": 4, "name": "WORLD CUP", "subtitle": "KISSIMMEE", "label": "LEGEND", "bots_tier": "legend",
		"unlock_stars": 32, "clear_stars": 42, "coming_soon": true, "challenges": []},
]

static func tier(i: int) -> Dictionary:
	for t in TIERS:
		if int(t["index"]) == i:
			return t
	return {}

static func tier_of(challenge_id: String) -> Dictionary:
	for t in TIERS:
		for c in t["challenges"]:
			if String(c["id"]) == challenge_id:
				return t
	return {}

static func challenge(id: String) -> Dictionary:
	for t in TIERS:
		for c in t["challenges"]:
			if String(c["id"]) == id:
				return c
	return {}

## Only Tier 1 kinds are wired in v0.7.
static func is_playable(c: Dictionary) -> bool:
	return String(c.get("kind", "")) in ["tdm", "elimination", "gauntlet"] and not bool(tier_of(String(c.get("id", ""))).get("coming_soon", false))

static func star_id(challenge_id: String, n: int) -> String:
	return "%s.s%d" % [challenge_id, n]
