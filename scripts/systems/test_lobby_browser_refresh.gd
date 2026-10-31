extends SceneTree
## v0.6.4 (Tim): the lobby browser never calls HTTPRequest.request() while one is in flight (leave_room used to log
## "HTTPRequest is processing a request"), a refresh asked for mid-flight runs once afterwards, and unready players
## on the NOT READY bench count toward the 10-player cap but not toward a team.
## Run: godot --headless --path . -s scripts/systems/test_lobby_browser_refresh.gd
const BODY := '{"lobbies":[{"id":"lobby_02","name":"Lobby 02","map":"woodsball_crash","mode":"deathmatch","players":{"red":0,"blue":0,"bench":1},"max_per_team":5,"status":"waiting","bots":false,"join_url":"https://x/?room=lobby_02"}]}'

class ErrorCatcher extends Logger:
	var busy_errors := 0
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if (code + " " + rationale).contains("processing a request"):
			busy_errors += 1
	func _log_message(message: String, _error: bool) -> void:
		if message.contains("processing a request"):
			busy_errors += 1

var b: LobbyBrowser
var srv := TCPServer.new()
var conns: Array[StreamPeerTCP] = []
var held: Array[StreamPeerTCP] = []
var hits := 0
var release_at := -1
var catcher := ErrorCatcher.new()
var f := 0
var fails: Array[String] = []

func _check(c: bool, m: String) -> void:
	print("  [%s] %s" % ["ok" if c else "FAIL", m])
	if not c: fails.append(m)

func _initialize() -> void:
	OS.add_logger(catcher)
	var port := 0
	for p in range(28761, 28800):
		if srv.listen(p, "127.0.0.1") == OK:
			port = p
			break
	_check(port != 0, "local /api/lobbies stub listening")
	b = LobbyBrowser.new()
	b.api_base = "http://127.0.0.1:%d" % port
	root.add_child(b) # _ready() -> refresh() #1 (in flight)

func _serve() -> void:
	while srv.is_connection_available():
		conns.append(srv.take_connection())
	for c in conns.duplicate():
		c.poll()
		if c.get_available_bytes() > 0:
			var req: String = c.get_utf8_string(c.get_available_bytes())
			if req.contains("GET /api/lobbies"):
				hits += 1
				conns.erase(c)
				held.append(c)
	if release_at >= 0 and f >= release_at:
		for c in held:
			var body := BODY.to_utf8_buffer()
			c.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer())
			c.put_data(body)
			c.disconnect_from_host()
		held.clear()

func _process(_d: float) -> bool:
	f += 1
	_serve()
	if f == 2:
		_check(b.http_busy, "first refresh is in flight")
		b.refresh() # leave_room -> open_browser -> refresh while busy
		b.refresh()
		b.refresh()
		_check(b.refresh_queued, "refresh while busy is queued, not sent")
	if f == 40:
		_check(hits == 1, "only one request reached the server while the first was in flight (hits=%d)" % hits)
		release_at = f # answer the held request
	if f == 120:
		_check(hits == 2, "the queued refresh ran exactly once after the first completed (hits=%d)" % hits)
		release_at = f
	if f == 200:
		_check(not b.http_busy and not b.refresh_queued, "idle again after both answers")
		_check(catcher.busy_errors == 0, "no 'HTTPRequest is processing a request' errors (%d)" % catcher.busy_errors)
		var e := {"players": {"red": 0, "blue": 0, "bench": 1}, "max_per_team": 5, "status": "waiting"}
		_check(LobbyBrowser.player_total(e) == 1 and LobbyBrowser.has_room(e), "bench player counts toward occupancy")
		var benchful := {"players": {"red": 2, "blue": 2, "bench": 6}, "max_per_team": 5, "status": "waiting"}
		_check(not LobbyBrowser.has_room(benchful), "2 + 2 + 6 bench = 10 -> no room")
		_check(LobbyBrowser.pick_quick_join([benchful, e]).get("players") == e["players"], "quick-join skips the bench-full lobby")
		# Rows are matched by content: a re-refresh renames same-named rows while the old ones are still queued for free.
		var labels: Array[String] = []
		for l in b.find_children("*", "Label", true, false):
			if not (l as Label).is_queued_for_deletion() and not l.get_parent().is_queued_for_deletion():
				labels.append((l as Label).text)
		var joined := " | ".join(labels)
		_check(joined.contains("Lobby 02") or joined.to_upper().contains("LOBBY 02"), "lobby_02 row built from the stub response")
		_check(not joined.contains("1/5"), "row does not show 1/5 on a team for a bench-only lobby (%s)" % [joined])
		OS.remove_logger(catcher)
		print("=== [PASS] lobby browser refresh/bench ===" if fails.is_empty() else "=== [FAIL] lobby browser refresh/bench: %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	return false
