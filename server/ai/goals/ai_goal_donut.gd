class_name AiGoalDonut
extends AiGoal
## Supervisor: eat a donut (GDD §5.1: +20% speed for 20 s, then 60 s until the next) when it is ready
## and the Break Room is close, or nearly on the way to where the bot is walking (a long trip):
## at most donut_detour_m out of the way. The counter's prompt shows the donut wait, so the bot may
## read it. Humans carry the donut and eat it later; a bot eats it on the spot (a donut left over,
## when eating failed, is eaten at the next chance).

const LONG_TRIP_M := 25.0  ## a walk this long is worth a detour for a donut

var _stand := Vector3.INF


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Donut"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	if ctx.body.inventory.donuts > 0:
		return AiScoring.donut(true, 0.0, ctx.tuning.donut_detour_m)
	var donuts := ctx.world.donuts
	if donuts == null or ctx.body.status.carrying != 0 or not ctx.body.inventory.can_take_donut() or ctx.blacklisted("donut"):
		return 0.0
	var stand := ctx.world.stand(donuts, Role.Kind.SUPERVISOR)
	var to_donut := ctx.path_length(stand, "donut")
	var detour := to_donut
	var going := ctx.driver.destination
	if ctx.bot.current != self and ctx.driver.move_state == AiDriver.Move.MOVING and going != Vector3.INF:
		var here := ctx.body.global_position
		var trip := here.distance_to(going)
		if trip >= LONG_TRIP_M:
			detour = minf(detour, to_donut + stand.distance_to(going) - trip)
	return AiScoring.donut(true, detour, ctx.tuning.donut_detour_m)


func start() -> void:
	if ctx.world.donuts != null:
		_stand = ctx.world.stand(ctx.world.donuts, Role.Kind.SUPERVISOR)


func tick(_delta: float) -> Result:
	if ctx.body.inventory.donuts > 0:
		return _eat()
	var donuts := ctx.world.donuts
	if donuts == null or not ctx.body.inventory.can_take_donut():
		return Result.DONE
	var driver := ctx.driver
	driver.go_to(_stand, true, 0.6)
	if driver.failed():
		ctx.blacklist("donut")
		return Result.FAILED
	if driver.arrived() or ctx.body.global_position.distance_to(_stand) < 0.8:
		driver.face(donuts.global_position)
		if driver.press(donuts) == "":
			return _eat()
		ctx.blacklist("donut")
		return Result.FAILED
	return Result.RUNNING


func _eat() -> Result:
	var reason := ctx.driver.eat_donut()
	if reason == "":
		ctx.log_line("ate a donut")
		return Result.DONE
	ctx.log_line("can't eat its donut: %s" % reason)
	return Result.FAILED
