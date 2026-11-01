extends RefCounted
## v0.7 client-side buffer for the server's 20 Hz batched snapshots (NetworkLobby.cl_snapshot).
## Every remote entity is rendered INTERP_DELAY_MS behind the estimated server clock, interpolated between the two
## buffered samples around that time. Past the newest sample it extrapolates along the sample's velocity for at most
## EXTRAPOLATE_MAX_MS, then holds. When fresh data arrives after extrapolating, the visual error is blended out over
## ~CORRECTION_TAU_S instead of snapping. Pure logic (no nodes), so headless tests drive it with synthetic clocks.
## Sample: {"pos": Vector3, "yaw": float, "pitch": float, "lean": float, "stance": int, "vel": Vector3, "elim": bool}

const INTERP_DELAY_MS: int = 100 # == NetworkLobby.REMOTE_INTERP_DELAY_MS (the lag-comp rewind uses the same value)
const EXTRAPOLATE_MAX_MS: int = 150
const BUFFER_MS: int = 1000
const TELEPORT_SPEED_MPS: float = 20.0 # == NetworkLobby.TELEPORT_SPEED_MPS (respawns are never interpolated)
const TELEPORT_MIN_DIST: float = 2.0
const CORRECTION_TAU_S: float = 0.1
const OFFSET_SLEW_MS: float = 2.0 # max clock-offset change per snapshot (about 4% time warp at 20 Hz)
const OFFSET_RESET_MS: float = 1000.0 # a bigger jump (reconnect, server restart) re-syncs at once

var offset_ms: float = 0.0 # server_ms - local_ms, smoothed
var has_offset: bool = false
var _buf: Dictionary = {} # id -> Array of [t_server_ms, sample]
var _vis: Dictionary = {} # id -> {"out": Vector3, "err": Vector3, "extrap": bool}

func note_server_time(server_ms: int, local_ms: int) -> void:
	var s := float(server_ms - local_ms)
	if not has_offset or absf(s - offset_ms) > OFFSET_RESET_MS:
		offset_ms = s
		has_offset = true
		return
	# Follows late arrivals quickly and early ones slowly, so the render clock sits near the slow edge of the
	# delivery jitter and the 100 ms buffer rarely runs dry.
	var k := 0.1 if s < offset_ms else 0.01
	offset_ms += clampf((s - offset_ms) * k, -OFFSET_SLEW_MS, OFFSET_SLEW_MS)

func render_time(local_ms: int) -> float:
	return float(local_ms) + offset_ms - float(INTERP_DELAY_MS)

## Adds a sample stamped with server time t; returns false for a repeat (unchanged state) or an older one.
func push(id: int, t: int, sample: Dictionary) -> bool:
	var b: Array = _buf.get(id, [])
	if b.size() > 0 and t <= int(b[b.size() - 1][0]):
		if t == int(b[b.size() - 1][0]):
			b[b.size() - 1][1]["elim"] = bool(sample["elim"]) # the server may flag an elimination between states
		return false
	b.append([t, sample])
	while b.size() > 2 and t - int(b[0][0]) > BUFFER_MS:
		b.pop_front()
	_buf[id] = b
	return true

func ids() -> Array:
	return _buf.keys()

func has(id: int) -> bool:
	return _buf.has(id)

func latest(id: int) -> Dictionary:
	var b: Array = _buf.get(id, [])
	return {} if b.is_empty() else (b[b.size() - 1][1] as Dictionary)

func erase(id: int) -> void:
	_buf.erase(id)
	_vis.erase(id)

func clear() -> void:
	_buf.clear()
	_vis.clear()
	has_offset = false

static func _is_teleport(a: Array, b: Array) -> bool:
	var d := Vector3(a[1]["pos"]).distance_to(Vector3(b[1]["pos"]))
	var dt := maxf(0.001, float(int(b[0]) - int(a[0])) / 1000.0)
	return d > TELEPORT_MIN_DIST and d / dt > TELEPORT_SPEED_MPS

## Raw pose at render time rt (server ms), before visual error smoothing. Adds "extrapolated": bool.
func pose_at(id: int, rt: float) -> Dictionary:
	var b: Array = _buf.get(id, [])
	if b.is_empty():
		return {}
	var first: Array = b[0]
	if rt <= float(first[0]):
		var o: Dictionary = (first[1] as Dictionary).duplicate()
		o["extrapolated"] = false
		return o
	for i in range(1, b.size()):
		var bb: Array = b[i]
		if rt <= float(bb[0]):
			var aa: Array = b[i - 1]
			var sa: Dictionary = aa[1]
			var sb: Dictionary = bb[1]
			if _is_teleport(aa, bb):
				var held: Dictionary = sa.duplicate()
				held["extrapolated"] = false
				return held
			var w := (rt - float(aa[0])) / maxf(1.0, float(int(bb[0]) - int(aa[0])))
			return {
				"pos": Vector3(sa["pos"]).lerp(Vector3(sb["pos"]), w),
				"yaw": lerp_angle(float(sa["yaw"]), float(sb["yaw"]), w),
				"pitch": lerpf(float(sa["pitch"]), float(sb["pitch"]), w),
				"lean": lerpf(float(sa["lean"]), float(sb["lean"]), w),
				"vel": Vector3(sa.get("vel", Vector3.ZERO)).lerp(Vector3(sb.get("vel", Vector3.ZERO)), w),
				"stance": int(sa["stance"]) if w < 0.5 else int(sb["stance"]),
				"elim": bool(sa["elim"]) if w < 0.5 else bool(sb["elim"]),
				"extrapolated": false,
			}
	var last: Array = b[b.size() - 1]
	var sl: Dictionary = (last[1] as Dictionary).duplicate()
	var ahead := minf(rt - float(last[0]), float(EXTRAPOLATE_MAX_MS)) / 1000.0
	if not bool(sl["elim"]):
		sl["pos"] = Vector3(sl["pos"]) + Vector3(sl.get("vel", Vector3.ZERO)) * ahead
	sl["extrapolated"] = true
	return sl

## The pose to draw this frame (local clock local_ms, frame time dt): pose_at(render_time) plus the decaying
## correction left over from an extrapolation that turned out wrong.
func sample(id: int, local_ms: int, dt: float) -> Dictionary:
	var p := pose_at(id, render_time(local_ms))
	if p.is_empty():
		return p
	var v: Dictionary = _vis.get(id, {})
	var raw := Vector3(p["pos"])
	var err := Vector3.ZERO
	if not v.is_empty():
		err = Vector3(v["err"]) * exp(-maxf(dt, 0.0) / CORRECTION_TAU_S)
		var newest := int(_buf[id][_buf[id].size() - 1][0])
		if bool(v["extrap"]) and (not bool(p["extrapolated"]) or newest != int(v["newest"])):
			err = Vector3(v["out"]) - raw
		if err.length() > TELEPORT_MIN_DIST:
			err = Vector3.ZERO # a respawn: snap, never glide across the field
	var out := raw + err
	_vis[id] = {"out": out, "err": err, "extrap": bool(p["extrapolated"]), "newest": int(_buf[id][_buf[id].size() - 1][0])}
	p["pos"] = out
	return p
