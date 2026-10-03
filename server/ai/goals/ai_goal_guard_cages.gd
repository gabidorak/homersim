class_name AiGoalGuardCages
extends AiGoal
## Supervisor: rats sit in a cage (on the map for everyone): watch the Cage Room's approaches, so
## rescuers meet a broom. One supervisor bot at a time (claim "guard_cages"). Walks between a few spots
## around the occupied cages, facing the nearest vent exits, where rescuers come from.

const SPOT_S := 4.0  ## stay at each spot this long
const RING_M := 3.5  ## the spots are this far in front of the cages

var _spots: Array[Vector3] = []
var _i := 0
var _arrived_at := -1.0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "GuardCages"


func score() -> float:
	if ctx.board.claimed_by_other("guard_cages", ctx.peer, ctx.now):
		return 0.0
	var occupants := 0
	for c in ctx.world.cages:
		occupants += c.occupants.size()
	return AiScoring.guard_cages(occupants)


func start() -> void:
	_spots.clear()
	for c in ctx.world.cages:
		if c.occupants.is_empty():
			continue
		var out := Vector3(c.global_basis.z.x, 0.0, c.global_basis.z.z).normalized()
		for angle in [0.0, 0.7, -0.7]:
			_spots.append(ctx.nav.closest_point(Role.Kind.SUPERVISOR, c.global_position + out.rotated(Vector3.UP, angle) * RING_M))
	_i = 0
	_arrived_at = -1.0


func tick(_delta: float) -> Result:
	if _spots.is_empty():
		return Result.DONE
	claim("guard_cages")
	var spot := _spots[_i % _spots.size()]
	ctx.driver.go_to(spot, false, 0.6)
	if ctx.driver.failed():
		_i += 1
		return Result.RUNNING
	if ctx.driver.arrived():
		if _arrived_at < 0.0:
			_arrived_at = ctx.now
		ctx.driver.face(_nearest_vent_exit(spot))
		if ctx.now - _arrived_at > SPOT_S:
			_i += 1
			_arrived_at = -1.0
	return Result.RUNNING


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
