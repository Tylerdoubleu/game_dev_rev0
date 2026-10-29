class_name PaintImpactAudio
extends RefCounted
## v0.5 (Ren): positional paint audio. Wet splats tuned per surface (inflatable vinyl, wood/spools/timber,
## heli metal, turf, player padding), a hollow rubbery "thock" when a ball bounces without breaking,
## a pneumatic marker pop, and a near-miss whiz. Sounds are procedurally synthesized WAVs in
## res://assets/audio/paint/. Played through a small round-robin pool of AudioStreamPlayer3D nodes.

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
const VOLUME_DB := {"vinyl": -4.0, "wood": -4.0, "metal": -6.0, "turf": -9.0, "body": -2.0, "bounce": -5.0, "fire": -8.0, "whiz": -7.0}
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
	player.stream = STREAMS[kind]
	player.volume_db = float(VOLUME_DB.get(kind, -6.0)) + randf_range(-1.5, 1.0)
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.global_position = pos
	player.play()
