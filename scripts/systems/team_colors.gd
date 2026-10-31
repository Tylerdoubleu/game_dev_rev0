class_name TeamColors
extends RefCounted
## v0.6.4 team colors: the single shared palette (server validation, waiting-room picker, respawn screen, HUD).
## NAMES are the lowercase color names sent over the network, in picker order. The server accepts exactly these.
## Red and blue match the colors the waiting room already showed, so the defaults don't shift visually.
## Static script: use TeamColors.X; don't preload autoloads from here.

const NAMES := ["red", "blue", "yellow", "pink", "orange", "purple", "cyan", "green"]

const PALETTE := {
	"red": Color(0.86, 0.2, 0.17),
	"blue": Color(0.2, 0.45, 0.95),
	"yellow": Color(0.95, 1.0, 0.15),
	"pink": Color(1.0, 0.28, 0.62),
	"orange": Color(1.0, 0.55, 0.1),
	"purple": Color(0.58, 0.3, 0.9),
	"cyan": Color(0.1, 0.8, 0.85),
	"green": Color(0.16, 0.5, 0.2),
}

## Team id -> color name when a room has no (or an invalid) pick.
const DEFAULTS := {"ALPHA": "red", "BRAVO": "blue"}

static func names() -> Array:
	return NAMES

## True only for an exact NAMES entry (case-sensitive).
static func is_valid(color_name: String) -> bool:
	return NAMES.has(color_name)

## The Color for a name (case-insensitive); unknown names fall back to red.
static func color_of(color_name: String) -> Color:
	return PALETTE.get(color_name.strip_edges().to_lower(), PALETTE["red"])

## "ALPHA"/"BRAVO" (also "red"/"blue" team aliases) -> the dictionary key used by team_colors.
static func team_key(team: String) -> String:
	return "BRAVO" if team.strip_edges().to_upper() in ["BRAVO", "BLUE"] else "ALPHA"

## The color name a team uses: team_colors[team] if valid, else DEFAULTS[team].
static func name_for_team(team: String, team_colors: Dictionary = {}) -> String:
	var t := team_key(team)
	var chosen := String(team_colors.get(t, "")).strip_edges().to_lower()
	return chosen if is_valid(chosen) else String(DEFAULTS[t])

## The Color a team uses, e.g. TeamColors.for_team("BRAVO", lobby_state.get("team_colors", {})).
static func for_team(team: String, team_colors: Dictionary = {}) -> Color:
	return color_of(name_for_team(team, team_colors))
