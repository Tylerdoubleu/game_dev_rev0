extends Node
## v0.6 (Ren): attaches MovementFoley to the local player (player_controller_3d.gd) whenever one enters the
## tree, and plays the tournament air horn on NetworkLobby.break_horn (Tim's server-run break).

const HORN := preload("res://assets/audio/break/air_horn.wav")
const PLAYER_SCRIPT := "res://scripts/player/player_controller_3d.gd"
const HORN_DB := -3.0

var horn_count := 0
var _horn: AudioStreamPlayer

func _ready() -> void:
	_horn = AudioStreamPlayer.new()
	_horn.stream = HORN
	_horn.volume_db = HORN_DB
	add_child(_horn)
	get_tree().node_added.connect(_on_node_added)
	_hook_lobby.call_deferred()

func _hook_lobby() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and nl.has_signal("break_horn") and not nl.is_connected("break_horn", play_horn):
		nl.connect("break_horn", play_horn)

func play_horn(_data: Dictionary = {}) -> void:
	horn_count += 1
	if _horn != null and _horn.is_inside_tree():
		_horn.play()

static func is_local_player(n: Node) -> bool:
	var sc = n.get_script()
	return n is CharacterBody3D and sc != null and String(sc.resource_path) == PLAYER_SCRIPT

func _on_node_added(n: Node) -> void:
	if is_local_player(n):
		_attach.call_deferred(n)

func _attach(n: Node) -> void:
	if is_instance_valid(n) and n.get_node_or_null("MovementFoley") == null:
		n.add_child(MovementFoley.new(n))
