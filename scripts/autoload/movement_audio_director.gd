extends Node
## v0.6 (Ren): attaches MovementFoley to the local player (player_controller_3d.gd) whenever one enters the
## tree, and plays the tournament air horn on NetworkLobby.break_horn (Tim's server-run break).
## Also loops Tyler's menu track while the lobby browser / waiting room (LobbyEntryFlow) is open and fades it
## out when a match starts.

const HORN := preload("res://assets/audio/break/air_horn.wav")
const PLAYER_SCRIPT := "res://scripts/player/player_controller_3d.gd"
const HORN_DB := -3.0
## Tyler's 3-2-1 lead-in: a short horn beep on 2 and on 1, then the full air horn on GO (break_horn).
const COUNTDOWN_BEEPS := {2: preload("res://assets/audio/break/countdown_beep_1.wav"), 1: preload("res://assets/audio/break/countdown_beep_2.wav")}
const BEEP_DB := -8.0
## Tyler's player-hit sound, played only on the server's confirmed player_eliminated (bounces, pre-horn and
## recap hits never trigger it). Full volume when you're the one hit, positional at the victim otherwise.
const PLAYER_HIT := preload("res://assets/audio/paint/player_hit.wav")
const PLAYER_HIT_DB := -2.0
const PLAYER_HIT_3D_DB := 2.0
var player_hit_count := 0
const MENU_MUSIC := preload("res://assets/audio/music/menu_loop.ogg")
const MENU_MUSIC_DB := -12.0
const MUSIC_FADE_DB_PER_SEC := 30.0   # ~1 s fade in / out
const SILENT_DB := -60.0

var horn_count := 0
var _horn: AudioStreamPlayer
var _beep: AudioStreamPlayer
var beep_count := 0
var _beeped: Dictionary = {}   # seconds_left values already beeped this break (snapshots resend them)
var music: AudioStreamPlayer
## Tests can force the menu state instead of opening the real lobby UI (null = ask LobbyEntryFlow).
var debug_menu_open = null

func _ready() -> void:
	_horn = AudioStreamPlayer.new()
	_horn.stream = HORN
	_horn.volume_db = HORN_DB
	add_child(_horn)
	_beep = AudioStreamPlayer.new()
	_beep.volume_db = BEEP_DB
	add_child(_beep)
	music = AudioStreamPlayer.new()
	music.name = "MenuMusic"
	var stream := MENU_MUSIC.duplicate() as AudioStreamOggVorbis
	stream.loop = true
	music.stream = stream
	music.volume_db = SILENT_DB
	add_child(music)
	get_tree().node_added.connect(_on_node_added)
	_hook_lobby.call_deferred()

func _hook_lobby() -> void:
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and nl.has_signal("break_horn") and not nl.is_connected("break_horn", play_horn):
		nl.connect("break_horn", play_horn)
	if nl != null and nl.has_signal("room_event") and not nl.is_connected("room_event", _on_room_event):
		nl.connect("room_event", _on_room_event)
	if nl != null and nl.has_signal("break_countdown") and not nl.is_connected("break_countdown", play_countdown_beep):
		nl.connect("break_countdown", play_countdown_beep)

func play_countdown_beep(seconds_left: int, _data: Dictionary = {}) -> void:
	if not COUNTDOWN_BEEPS.has(seconds_left) or _beeped.has(seconds_left):
		return
	_beeped[seconds_left] = true
	beep_count += 1
	if _beep != null and _beep.is_inside_tree():
		_beep.stream = COUNTDOWN_BEEPS[seconds_left]
		_beep.play()

func _on_room_event(event_name: String, data: Dictionary) -> void:
	if event_name == "player_eliminated":
		play_player_hit(data)

func play_player_hit(data: Dictionary = {}) -> void:
	player_hit_count += 1
	if not is_inside_tree():
		return
	var nl := get_node_or_null("/root/NetworkLobby")
	var victim := int(data.get("victim", 0))
	var my_id := int(nl.call("_my_peer_id")) if nl != null and nl.has_method("_my_peer_id") else 0
	var avatar: Node3D = null
	if nl != null and victim != my_id and "remote_player_nodes" in nl:
		var n = nl.remote_player_nodes.get(victim)
		if n is Node3D and is_instance_valid(n) and n.is_inside_tree():
			avatar = n
	if avatar != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = PLAYER_HIT
		p3.volume_db = PLAYER_HIT_3D_DB
		p3.unit_size = 8.0
		p3.max_distance = 90.0
		var host: Node = avatar.get_tree().current_scene
		(host if host != null else self).add_child(p3)
		p3.global_position = avatar.global_position + Vector3(0, 1.2, 0)
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = PLAYER_HIT
		p.volume_db = PLAYER_HIT_DB if victim == my_id else PLAYER_HIT_DB - 8.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()

func play_horn(_data: Dictionary = {}) -> void:
	horn_count += 1
	_beeped.clear()
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

func is_menu_open() -> bool:
	if debug_menu_open != null:
		return bool(debug_menu_open)
	var flow := get_node_or_null("/root/LobbyEntryFlow")
	return flow != null and flow.has_method("is_open") and bool(flow.call("is_open"))

func _process(delta: float) -> void:
	if music == null:
		return
	var nl := get_node_or_null("/root/NetworkLobby")
	if nl != null and bool(nl.get("is_dedicated_server")):
		return
	if is_menu_open():
		if not music.playing:
			music.volume_db = SILENT_DB
			music.play()
		music.volume_db = minf(MENU_MUSIC_DB, music.volume_db + MUSIC_FADE_DB_PER_SEC * delta)
	elif music.playing:
		music.volume_db -= MUSIC_FADE_DB_PER_SEC * 1.4 * delta
		if music.volume_db <= SILENT_DB:
			music.stop()
