class_name AiGoalRefill
extends AiGoal
## Supervisor: a kind of trap is used up and the plant is calm (AiContext.calm): refill it at its box
## in Storage (GDD §5.1: the trap box for snap traps, the cheese box for cheese lures; instant, that
## kind back to full). Snap traps first when both are used up.

var _trap: StringName = &""  ## the running goal's trap kind
var _pick: StringName = &""  # score()'s choice, which start() takes
var _stand := Vector3.INF


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Refill"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = &""
	if ctx.body.status.carrying != 0 or ctx.blacklisted("refill"):
		return 0.0
	for trap: StringName in [Inventory.SNAP_TRAP, Inventory.CHEESE_LURE]:
		if ctx.world.refills.has(trap) and ctx.body.inventory.charges(trap) <= 0:
			_pick = trap
			break
	if _pick == &"":
		return 0.0  # (checked first: calm() and the path cost more)
	var box := ctx.world.refills[_pick]
	return AiScoring.refill(0, ctx.calm(), ctx.path_time(ctx.world.stand(box, Role.Kind.SUPERVISOR), "refill"))


func start() -> void:
	_trap = _pick
	_stand = ctx.world.stand(ctx.world.refills[_trap], Role.Kind.SUPERVISOR) if ctx.world.refills.has(_trap) \
		else Vector3.INF


func tick(_delta: float) -> Result:
	var box: Pickup = ctx.world.refills.get(_trap)
	if box == null or _stand == Vector3.INF or ctx.body.inventory.charges(_trap) > 0:
		return Result.DONE
	var driver := ctx.driver
	driver.go_to(_stand, false, 0.6)
	if driver.failed():
		ctx.blacklist("refill")
		return Result.FAILED
	if driver.arrived() or ctx.body.global_position.distance_to(_stand) < 0.8:
		driver.face(box.global_position)
		var reason := driver.press(box)
		if reason == "":
			ctx.log_line("refilled the %s" % ("snap traps" if _trap == Inventory.SNAP_TRAP else "cheese lures"))
			return Result.DONE
		ctx.blacklist("refill")
		return Result.FAILED
	return Result.RUNNING
