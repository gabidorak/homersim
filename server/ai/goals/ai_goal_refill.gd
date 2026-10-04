class_name AiGoalRefill
extends AiGoal
## Supervisor: all traps are used and the plant is calm (AiContext.calm): refill them at Storage
## (GDD §5.1, the TrapRefill pickup: instant, charges back to full).

var _stand := Vector3.INF


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Refill"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	var refill := ctx.world.refill
	if refill == null or ctx.body.status.carrying != 0 or ctx.blacklisted("refill"):
		return 0.0
	var charges := ctx.body.inventory.trap_charges
	if charges > 0:
		return 0.0  # (checked first: calm() and the path cost more)
	return AiScoring.refill(charges, ctx.calm(), ctx.path_time(ctx.world.stand(refill, Role.Kind.SUPERVISOR), "refill"))


func start() -> void:
	_stand = ctx.world.stand(ctx.world.refill, Role.Kind.SUPERVISOR)


func tick(_delta: float) -> Result:
	var refill := ctx.world.refill
	if refill == null or ctx.body.inventory.trap_charges > 0:
		return Result.DONE
	var driver := ctx.driver
	driver.go_to(_stand, false, 0.6)
	if driver.failed():
		ctx.blacklist("refill")
		return Result.FAILED
	if driver.arrived() or ctx.body.global_position.distance_to(_stand) < 0.8:
		driver.face(refill.global_position)
		var reason := driver.press(refill)
		if reason == "":
			ctx.log_line("refilled the traps")
			return Result.DONE
		ctx.blacklist("refill")
		return Result.FAILED
	return Result.RUNNING
