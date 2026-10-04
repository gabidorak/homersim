class_name AiGoalPatrol
extends AiGoal
## Supervisor, the default: tour the machine rooms, picking the one with the best heat weight × time
## since a supervisor bot last visited it (shared on the blackboard as claims "visit:<sub>" whose
## time is kept in visited). Walks to its repair point and looks around a moment.

const LOOK_S := 2.5

var point: RepairPoint
var _arrived_at := -1.0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Patrol"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	point = null
	var best := 0.0
	for rp in ctx.world.repair_points:
		if rp.index == -1 or ctx.blacklisted("patrol:%s" % rp.subsystem_id):
			continue
		var since := ctx.now - float(ctx.board.visited.get(rp.subsystem_id, -ctx.tuning.patrol_revisit_s))
		var s := AiScoring.patrol(ctx.plant().data(rp.index).heat_weight, since, ctx.tuning.patrol_revisit_s)
		if ctx.board.claimed_by_other("patrol:%s" % rp.subsystem_id, ctx.peer, ctx.now):
			s *= 0.3
		if s > best:
			best = s
			point = rp
	return best


func start() -> void:
	target_label = String(point.subsystem_id) if point != null else ""
	_arrived_at = -1.0


func tick(_delta: float) -> Result:
	if point == null:
		return Result.FAILED
	claim("patrol:%s" % point.subsystem_id)
	ctx.driver.go_to(ctx.world.stand(point, Role.Kind.SUPERVISOR), false, 1.5)
	if ctx.driver.failed():
		ctx.blacklist("patrol:%s" % point.subsystem_id)
		return Result.FAILED
	if ctx.driver.arrived():
		if _arrived_at < 0.0:
			_arrived_at = ctx.now
			ctx.board.visited[point.subsystem_id] = ctx.now
		ctx.driver.face(point.global_position)
		if ctx.now - _arrived_at > LOOK_S:
			return Result.DONE
	return Result.RUNNING


func stop() -> void:
	super()
	if point != null:
		release("patrol:%s" % point.subsystem_id)
