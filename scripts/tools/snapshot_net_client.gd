extends SceneTree
## v0.7 multi-process probe (manual): one headless NetworkLobby client against a real dedicated server.
## Sends srv_player_state at 20 Hz (running a circle), optionally relays a bot elimination, and after SECS prints
## cl_snapshot rate, which remote ids it buffered/spawned, and bot eliminations received.
## Run: godot --headless --path . -- --server --port=N   then per client:
##      godot --headless --path . -s res://scripts/tools/snapshot_net_client.gd -- --port=N --room=lobby_01 --name=AAA [--bot]
var L: Node
var args := {}
var t0 := 0
var sent := 0
var bot_hits := 0
var did_bot := false
var scene: Node3D
var first_snap := -1

class FakeBot extends Node3D:
	var hits := 0
	func eliminate_from_network() -> void:
		hits += 1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	scene = Node3D.new()
	scene.name = "Arena"
	root.add_child(scene)
	current_scene = scene
	var bot := FakeBot.new()
	bot.name = "Bot_7"
	scene.add_child(bot)

func _process(_d: float) -> bool:
	if L == null:
		L = root.get_node("NetworkLobby")
		L.active_room = String(args.get("room", "lobby_01"))
		L.local_callsign = String(args.get("name", "PROBE"))
		L.connect_to_lobby("ws://127.0.0.1:%s" % args.get("port", "19399"))
		t0 = Time.get_ticks_msec()
		return false
	var now := Time.get_ticks_msec()
	if L.is_online_client() and L.active_room != "":
		var want := int((now - t0) / 50)
		while sent < want:
			sent += 1
			var a := float(sent) * 0.05
			L.send_local_player_state(Vector3(cos(a) * 6.0, 0.0, sin(a) * 6.0), a, 0.0, 0.0, 0, false)
		if args.has("bot") and not did_bot and now - t0 > 2500:
			did_bot = true
			L.broadcast_bot_eliminated("Bot_7")
	if L.snapshots_received > 0 and first_snap < 0:
		first_snap = now
	if now - t0 > int(args.get("secs", "6")) * 1000:
		var secs := maxf(0.001, float(now - first_snap) / 1000.0) if first_snap >= 0 else 1.0
		var spawned: Array = []
		for k in L.remote_player_nodes.keys():
			spawned.append(int(k))
		spawned.sort()
		var buffered: Array = L.remote_snapshots.ids()
		buffered.sort()
		print("NETPROBE name=%s room=%s me=%d snapshots=%d rate=%.2fHz buffered=%s spawned=%s bot_elims=%d offset_ms=%.0f" % [args.get("name"), L.active_room, L._my_peer_id(), L.snapshots_received, L.snapshots_received / secs, buffered, spawned, (scene.get_node("Bot_7") as FakeBot).hits, L.remote_snapshots.offset_ms])
		quit(0)
		return true
	return false
