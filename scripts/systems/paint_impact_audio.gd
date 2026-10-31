class_name PaintImpactAudio
extends RefCounted
## v0.5 (Ren): positional paint audio. Wet splats tuned per surface (inflatable vinyl, wood/spools/timber,
## heli metal, turf, player padding), a hollow rubbery "thock" when a ball bounces without breaking,
## a marker shot, and a near-miss whiz. Splats/thock/whiz are procedurally synthesized WAVs in
## res://assets/audio/paint/. v0.6: the marker shot is a real recording Tyler supplied, cut into five
## variants (marker_fire_1..5.wav) that rotate without repeats. Played through a small round-robin pool
## of AudioStreamPlayer3D nodes.

const STREAMS := {
	"vinyl": preload("res://assets/audio/paint/splat_vinyl.wav"),
	"wood": preload("res://assets/audio/paint/splat_wood.wav"),
	"metal": preload("res://assets/audio/paint/splat_metal.wav"),
	"turf": preload("res://assets/audio/paint/splat_turf.wav"),
	"body": preload("res://assets/audio/paint/splat_body.wav"),
	"bounce": preload("res://assets/audio/paint/bounce_thock.wav"),
	"fire": preload("res://assets/audio/paint/marker_fire.wav"),
	"whiz": preload("res://assets/audio/paint/flyby_whiz.wav"),
}
## Real-recording variants for kinds that rotate (no clip plays twice in a row).
const VARIANTS := {
	"fire": [
		preload("res://assets/audio/paint/marker_fire_1.wav"),
		preload("res://assets/audio/paint/marker_fire_2.wav"),
		preload("res://assets/audio/paint/marker_fire_3.wav"),
		preload("res://assets/audio/paint/marker_fire_4.wav"),
		preload("res://assets/audio/paint/marker_fire_5.wav"),
	],
}
## Recorded sounds already vary naturally, so they get only a light pitch wobble.
const MAX_PITCH_JITTER := {"fire": 0.03}
static var _last_variant: Dictionary = {}

const VOLUME_DB := {"vinyl": -4.0, "wood": -4.0, "metal": -6.0, "turf": -9.0, "body": -2.0, "bounce": -5.0, "fire": -14.0, "whiz": -7.0}
## Other players' / bots' shots: anything firing further than this from the local player is not your own marker,
## so it plays a bit quieter and falls off a bit faster (Tyler: bot test mode was a constant roar), with the same tone as
## your own shot (Tyler 10/31: the muffled 2.2 kHz version made bot shots sound too different).
const OWN_SHOT_RADIUS := 3.0
const FAR_FIRE_EXTRA_DB := -5.0
const FAR_FIRE_UNIT_SIZE := 4.0
const FAR_FIRE_FILTER_HZ := 6000.0
const MUTED_KINDS := ["whiz", "bounce"]  # Tyler 10/31: no near-miss whiz, no glancing-bounce thock
const POOL_SIZE: int = 24
const POOL_NAME: String = "PaintImpactAudioPool"

## Running count of sounds played per kind (tests / diagnostics)
static var play_counts: Dictionary = {}

static func classify_surface(collider: Object) -> String:
	if collider == null or not (collider is Node):
		return "turf"
	var n: Node = collider
	var nm := String(n.name)
	if n is CharacterBody3D or n.has_method("resolve_hit_subzone") or nm.begins_with("Hitbox") or nm.contains("Player") or nm.contains("Bot"):
		return "body"
	if nm.begins_with("Heli_") or bool(n.get_meta("metal_surface", false)):
		return "metal"
	if nm == "TurfFloor" or nm.contains("Floor") or nm.contains("Ground") or nm.contains("Turf"):
		return "turf"
	if nm.begins_with("SafetyNet"):
		return "turf"
	if bool(n.get_meta("is_rigid_cover", false)) or nm.begins_with("WoodSpool") or nm.begins_with("Woods_") or nm.begins_with("Tower_") or nm.begins_with("WalkableRamp") or nm.begins_with("WalkableFloor") or nm.contains("Spool") or nm.begins_with("Snake_"):
		return "wood"
	return "vinyl"

static func play(scene_root: Node, kind: String, pos: Vector3, pitch_jitter: float = 0.12) -> void:
	## Tyler 10/31: near-miss whiz removed (the synthesized whoosh made bot fire sound like a different gun).
	if kind in MUTED_KINDS:
		return
	play_counts[kind] = int(play_counts.get(kind, 0)) + 1
	if scene_root == null or not STREAMS.has(kind):
		return
	var pool := scene_root.get_node_or_null(POOL_NAME) as Node3D
	if pool == null:
		pool = Node3D.new()
		pool.name = POOL_NAME
		scene_root.add_child(pool)
		for i in range(POOL_SIZE):
			var p := AudioStreamPlayer3D.new()
			p.unit_size = 6.0
			p.max_distance = 70.0
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p.attenuation_filter_cutoff_hz = 6000.0
			p.attenuation_filter_db = -12.0
			pool.add_child(p)
		pool.set_meta("next", 0)
	var idx: int = int(pool.get_meta("next", 0))
	pool.set_meta("next", (idx + 1) % pool.get_child_count())
	var player := pool.get_child(idx) as AudioStreamPlayer3D
	if not player.is_inside_tree():
		return
	player.stream = _pick_stream(kind)
	pitch_jitter = minf(pitch_jitter, float(MAX_PITCH_JITTER.get(kind, pitch_jitter)))
	player.volume_db = float(VOLUME_DB.get(kind, -6.0)) + randf_range(-1.5, 1.0)
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var far_fire := false
	if kind == "fire":
		var ear := scene_root.get_node_or_null("Player3D") as Node3D
		far_fire = ear != null and ear.global_position.distance_to(pos) > OWN_SHOT_RADIUS
	if far_fire:
		player.volume_db += FAR_FIRE_EXTRA_DB
	player.unit_size = FAR_FIRE_UNIT_SIZE if far_fire else 6.0
	player.attenuation_filter_cutoff_hz = FAR_FIRE_FILTER_HZ if far_fire else 6000.0
	player.global_position = pos
	player.play()

static func _pick_stream(kind: String) -> AudioStream:
	if not VARIANTS.has(kind):
		return STREAMS[kind]
	var list: Array = VARIANTS[kind]
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_variant.get(kind, -1)):
		i = (i + 1 + randi() % (list.size() - 1)) % list.size()
	_last_variant[kind] = i
	return list[i]
