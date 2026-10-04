class_name AiGoalConsole
extends AiGoal
## Supervisor: the Control Room's emergency buttons (GDD §4.5). The core temperature is on the status
## board and the HUD's alarm, the cooldowns on the consoles' screens.
##   coolant  core_temp above coolant_temp, the console ready and the grid at 25 or more: core −150
##   scram    core_temp above scram_temp or meltdown above scram_meltdown, ready: lift the cover, then
##            press the button within its 5 s (heat ×0.5 for 30 s, but +30 s of shift: only when
##            it's critical)
## One bot per console (claim "console:<action>").

var action: ConsoleAction
var _pick: ConsoleAction


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Console"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = null
	if ctx.body.status.carrying != 0:
		return 0.0
	var plant := ctx.plant()
	var best := 0.0
	var coolant := ctx.world.coolant
	if coolant != null and plant.core_temp > ctx.tuning.coolant_temp and _free(coolant):  # (the path only when hot)
		var usable := coolant.cooldown_left() <= 0.0 and coolant.has_power()
		var s := AiScoring.coolant(plant.core_temp, ctx.tuning.coolant_temp, usable, _time_to(coolant) if usable else INF)
		if s > best:
			best = s
			_pick = coolant
	var scram := ctx.world.scram
	var critical := plant.core_temp > ctx.tuning.scram_temp or plant.meltdown > ctx.tuning.scram_meltdown
	if scram != null and critical and scram.cooldown_left() <= 0.0 and plant.scram_left <= 0.0 and _free(scram):
		var s := AiScoring.scram(plant.core_temp, plant.meltdown, ctx.tuning.scram_temp, ctx.tuning.scram_meltdown,
			true, _time_to(scram))
		if s > best:
			best = s
			_pick = scram
	return best


func _free(console: ConsoleAction) -> bool:
	var key := "console:%s" % console.action
	return not ctx.board.claimed_by_other(key, ctx.peer, ctx.now) and not ctx.blacklisted(key)


func _time_to(console: ConsoleAction) -> float:
	return ctx.path_time(ctx.world.stand(console, Role.Kind.SUPERVISOR), "console:%s" % console.action)


func start() -> void:
	action = _pick
	target_label = action.action if action != null else ""


func tick(_delta: float) -> Result:
	if action == null:
		return Result.FAILED
	var key := "console:%s" % action.action
	if not claim(key):
		return Result.FAILED
	if action.cooldown_left() > 0.0:
		return Result.DONE  # used (by us, or by a teammate)
	var stand := ctx.world.stand(action, Role.Kind.SUPERVISOR)
	var driver := ctx.driver
	driver.go_to(stand, true, 0.5)
	if driver.failed():
		ctx.blacklist(key)
		return Result.FAILED
	if not driver.arrived() and ctx.body.global_position.distance_to(stand) > 0.9:
		return Result.RUNNING
	driver.face(action.global_position)
	var lifting := action.action == "scram" and not action.cover_open()
	var reason := driver.press(action)
	if reason != "":
		ctx.blacklist(key)
		return Result.FAILED
	if lifting:
		return Result.RUNNING  # the cover is up: press again for the button
	ctx.log_line("used the %s" % ("emergency coolant" if action.action == "coolant" else "SCRAM"))
	return Result.DONE


func stop() -> void:
	super()
	if action != null:
		release("console:%s" % action.action)
