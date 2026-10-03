class_name AiGoalRescueCarried
extends AiGoal
## Rat reflex: a teammate is being carried to a cage (its CARRIED status: the team always knows).
## Sprint to it and bite its carrier: one bite makes the supervisor drop the rat (GDD §5.1). The bite
## itself is AiBot's reflex (any rat bot next to a carried teammate bites); this goal gets it there.
## The carried rat hangs from its carrier's hand, so its position is where the carrier is.

var mate: Player
var _carried_since := {}  # teammate peer -> when we first saw it carried


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "RescueCarried"
	reflex = true


func score() -> float:
	if not ctx.can_act():
		return 0.0
	var best := 0.0
	mate = null
	var carry_max := ctx.session.captures.tuning.carry_max_s
	for m in ctx.teammates():
		if not m.status.has(StatusComponent.Status.CARRIED):
			_carried_since.erase(m.peer_id)
			continue
		if not _carried_since.has(m.peer_id):
			_carried_since[m.peer_id] = ctx.now
		var left := carry_max - (ctx.now - float(_carried_since[m.peer_id]))
		var seconds := m.global_position.distance_to(ctx.body.global_position) * 1.3 / ctx.body.role_data.sprint_speed
		var s := AiScoring.rescue(seconds, left)
		if s > best:
			best = s
			mate = m
	return best


func start() -> void:
	target_label = mate.display_name if mate != null else ""


func tick(_delta: float) -> Result:
	if not is_instance_valid(mate) or not mate.status.has(StatusComponent.Status.CARRIED):
		return Result.DONE
	ctx.driver.go_to(mate.global_position, true, 0.6)
	ctx.driver.face(mate.global_position)
	if ctx.driver.failed():
		return Result.FAILED
	return Result.RUNNING
