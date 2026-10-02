class_name HazardRules
extends RefCounted
## Hazard timing and activation as pure functions (no nodes), so GUT can test them.
## Times are seconds; "elapsed" is measured from a hazard's synced start_time on the server clock.


## Hysteresis (GDD §6): a subsystem's hazards switch on when its health drops below `on_below` and
## only switch off again once it is back to `off_at` or more, so they don't flicker around 50.
static func next_active(active: bool, health: float, on_below: float, off_at: float) -> bool:
	if active:
		return health < off_at
	return health < on_below


## A repeating cycle: live for `on_s`, then off for `off_s`, starting `phase` seconds into the cycle
## at elapsed = 0. Nothing is live before the start (elapsed < 0).
static func cycle_live(elapsed: float, on_s: float, off_s: float, phase: float = 0.0) -> bool:
	if elapsed < 0.0 or on_s <= 0.0:
		return false
	var period := on_s + off_s
	if period <= 0.0:
		return true
	return fposmod(elapsed + phase, period) < on_s


## Which cycle `elapsed` falls in (0, 1, 2…), counting from the same phase; -1 before the start.
## A hazard hits each body at most once per live window: it remembers the window's index.
static func cycle_index(elapsed: float, on_s: float, off_s: float, phase: float = 0.0) -> int:
	if elapsed < 0.0:
		return -1
	var period := on_s + off_s
	if period <= 0.0:
		return 0
	return floori((elapsed + phase) / period)


## Seconds until the next change between live and off (for sounds and particle timing).
static func time_to_switch(elapsed: float, on_s: float, off_s: float, phase: float = 0.0) -> float:
	var period := on_s + off_s
	if elapsed < 0.0:
		return -elapsed
	if period <= 0.0:
		return INF
	var t := fposmod(elapsed + phase, period)
	return on_s - t if t < on_s else period - t


## Radiation exposure: builds up 1 s per second inside, drains as fast outside, capped at `max_s`.
static func exposure_step(exposure: float, inside: bool, dt: float, max_s: float) -> float:
	return clampf(exposure + (dt if inside else -dt), 0.0, max_s)


## Knockback away from a jet: mostly along its axis `jet_dir`, plus a little away from the axis line
## through `nozzle`, plus `lift` up. The horizontal part has length `speed`.
static func knockback(jet_dir: Vector3, nozzle: Vector3, body_pos: Vector3, speed: float, lift: float) -> Vector3:
	var axis := Vector3(jet_dir.x, 0.0, jet_dir.z).normalized()
	if axis == Vector3.ZERO:
		axis = Vector3.FORWARD
	var to_body := Vector3(body_pos.x - nozzle.x, 0.0, body_pos.z - nozzle.z)
	var side := to_body - axis * to_body.dot(axis)
	var push := (axis + side.normalized() * 0.4).normalized() if side.length() > 0.05 else axis
	return push * speed + Vector3.UP * lift
