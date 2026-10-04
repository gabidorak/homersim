class_name AiGoalGuardCages
extends AiGoal
## Supervisor: rats sit in a cage (on the map for everyone): watch the Cage Room's approaches, so
## rescuers meet a broom. One supervisor bot at a time (claim "guard_cages"). Walks between a few spots
## around the occupied cages, facing the nearest vent exits, where rescuers come from.
## A shift lasts guard_cages_max_s on watch (from the first spot reached); then no bot of the team
## guards for guard_cages_rest_s (AiBlackboard.guard_rest_until), so the rats get their chance to free
## their friends and the machines get repaired: without it, bots camped the cages for the rest of the
## match. Spots off the supervisors' floor (on a crate, behind a wall) are left out; a bot that can
## reach none of them leaves the cages to the others for a while (blacklist).

const SPOT_S := 4.0  ## stay at each spot this long
const RING_M := 3.5  ## the spots are this far in front of the cages
const SPOT_GAP := 1.0  ## m (flat): the supervisors' floor comes this close to a spot, or it is left out…
const SPOT_RISE := 0.6  ## …and lies this close to the cage's floor in height (not on a crate)

var _spots: Array[Vector3] = []
var _i := 0
var _arrived_at := -1.0
var _failures := 0  # spots in a row the driver couldn't get to
var _on_watch := false  # reached a spot since start(): the shift's clock runs
var _guarded_s := 0.0  # on watch this shift
var _spots_of: Dictionary = {}  # Cage -> its spots on the supervisors' floor (cages don't move)


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "GuardCages"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	if ctx.now < ctx.board.guard_rest_until or ctx.blacklisted("guard_cages") \
			or ctx.board.claimed_by_other("guard_cages", ctx.peer, ctx.now):
		return 0.0
	var occupants := 0
	for c in ctx.world.cages:
		if not _cage_spots(c).is_empty():
			occupants += c.occupants.size()
	if occupants == 0:
		_guarded_s = 0.0  # (the next shift starts afresh)
	return AiScoring.guard_cages(occupants)


func start() -> void:
	_spots.clear()
	for c in ctx.world.cages:
		if not c.occupants.is_empty():
			_spots.append_array(_cage_spots(c))
	_i = 0
	_arrived_at = -1.0
	_failures = 0
	_on_watch = false


func tick(delta: float) -> Result:
	if _spots.is_empty():
		return Result.DONE
	if _failures >= _spots.size():
		ctx.blacklist("guard_cages")  # can't get to any of them from here
		return Result.FAILED
	claim("guard_cages")
	if _on_watch:
		_guarded_s += delta
		if _guarded_s >= ctx.tuning.guard_cages_max_s:
			_guarded_s = 0.0
			ctx.board.guard_rest_until = ctx.now + ctx.tuning.guard_cages_rest_s
			ctx.log_line("leaves the cages (shift over)")
			return Result.DONE
	var spot := _spots[_i % _spots.size()]
	ctx.driver.go_to(spot, false, 0.6)
	if ctx.driver.failed():
		_failures += 1
		_i += 1
		return Result.RUNNING
	if ctx.driver.arrived():
		_failures = 0
		_on_watch = true
		if _arrived_at < 0.0:
			_arrived_at = ctx.now
		ctx.driver.face(_nearest_vent_exit(spot))
		if ctx.now - _arrived_at > SPOT_S:
			_i += 1
			_arrived_at = -1.0
	return Result.RUNNING


## The spots in front of `c` on the supervisors' floor (worked out once per cage).
func _cage_spots(c: Cage) -> Array[Vector3]:
	if _spots_of.has(c):
		return _spots_of[c]
	var out: Array[Vector3] = []
	var front := Vector3(c.global_basis.z.x, 0.0, c.global_basis.z.z).normalized()
	var floor_y := c.door_position().y
	for angle in [0.0, 0.7, -0.7]:
		var want := c.global_position + front.rotated(Vector3.UP, angle) * RING_M
		var spot := ctx.nav.closest_point(Role.Kind.SUPERVISOR, want)
		if Vector2(spot.x - want.x, spot.z - want.z).length() <= SPOT_GAP and absf(spot.y - floor_y) <= SPOT_RISE:
			out.append(spot)
	_spots_of[c] = out
	return out


func _nearest_vent_exit(from: Vector3) -> Vector3:
	var best := from + Vector3.FORWARD
	var best_d := INF
	for p in ctx.world.vent_exits:
		if absf(p.y - from.y) < 2.0 and p.distance_to(from) < best_d:
			best_d = p.distance_to(from)
			best = p
	return best


func stop() -> void:
	super()
	release("guard_cages")
