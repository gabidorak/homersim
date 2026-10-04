class_name AiGoalCapture
extends AiGoal
## Supervisor: a rat this bot sees is stunned: grab it (its GrabHandle), walk it to a cage that isn't
## full and cage it (GDD §5.1, §5.3). Only when that cage is reachable before the carry runs out
## (carry_max_s at the carry speed, with carry_spare_s to spare): otherwise the rat would wriggle free.

const GRAB_FROM := 1.6  ## m: press the grab handle this close
const PRESS_EVERY_S := 0.2

var rat: AiSenses.Known
var cage: Cage
var _carrying := false
var _next_press := 0.0
var _pick_rat: AiSenses.Known  # score()'s choice, which start() takes
var _pick_cage: Cage


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Capture"


func score() -> float:
	if ctx.body.status.carrying != 0:
		return 0.99 if _carrying else 0.0  # finish the job
	_pick_rat = null
	_pick_cage = null
	var here := ctx.body.global_position
	var capture := ctx.session.captures.tuning
	for k in ctx.senses.enemies():
		if not k.visible or not k.stunned or k.pos.distance_to(here) > 6.0:
			continue
		var best_c: Cage = null
		var best_s := INF
		for c in ctx.world.cages:
			if c.is_full():
				continue
			var path := ctx.nav.path(Role.Kind.SUPERVISOR, k.pos, ctx.world.stand(c, Role.Kind.SUPERVISOR), ctx.has_keycard())
			if path.is_empty():
				continue
			var seconds := (path.length + here.distance_to(k.pos)) / ctx.body.role_data.carry_speed
			if seconds < best_s:
				best_s = seconds
				best_c = c
		if AiScoring.capture(true, best_s, capture.carry_max_s, ctx.tuning.carry_spare_s) > 0.0:
			_pick_rat = k
			_pick_cage = best_c
			return 0.95
	return 0.0


func start() -> void:
	rat = _pick_rat
	cage = _pick_cage
	_carrying = false
	target_label = ctx.session.name_of(rat.peer) if rat != null else ""


func tick(_delta: float) -> Result:
	if rat == null or cage == null:
		return Result.FAILED
	var driver := ctx.driver
	var here := ctx.body.global_position
	if not _carrying:
		var k := ctx.senses.get_known(rat.peer)
		if k == null or not k.visible or not k.stunned:
			return Result.FAILED  # it got away
		driver.go_to(ctx.nav.snap(Role.Kind.SUPERVISOR, k.pos), true, 1.0)  # (it may be mid-air)
		driver.face(k.pos)
		if here.distance_to(k.pos) <= GRAB_FROM and ctx.can_act() and ctx.now >= _next_press:
			_next_press = ctx.now + PRESS_EVERY_S
			var handle := ctx.senses.grab_handle_of(rat.peer)
			if handle != null and driver.press(handle) == "":
				_carrying = true
				driver.stop()
		return Result.RUNNING
	if ctx.body.status.carrying == 0:
		return Result.FAILED  # dropped it (bitten, wriggled free)
	if cage.is_full():
		return Result.FAILED
	var stand := ctx.world.stand(cage, Role.Kind.SUPERVISOR)
	driver.go_to(stand, false, 0.5)
	if driver.failed():
		return Result.FAILED
	if (here.distance_to(stand) < 1.2 or driver.arrived()) and ctx.now >= _next_press:
		_next_press = ctx.now + PRESS_EVERY_S
		driver.face(cage.global_position)
		if driver.press(cage) == "":
			return Result.DONE
	return Result.RUNNING
