class_name AiGoalCctv
extends AiGoal
## Supervisor: watch the cameras from the CCTV chair (GDD §4.5) when the plant is calm (AiContext.calm)
## and the chair is free (claim "cctv_chair"). Seated, AiSenses sees rats near every unbroken camera.
## Stands up after cctv_max_s, when a camera shows a rat (Chase or Investigate take it from there),
## when a machine gets damaged, or when bitten; not again for cctv_rest_s.

var _sat_at := -1.0
var _health_sum := 0.0
var _last_sat := -INF


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Cctv"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	var console := ctx.world.console
	if console == null or ctx.body.status.carrying != 0 or ctx.blacklisted("cctv_chair"):
		return 0.0
	var free := (console.user == 0 or console.user == ctx.peer) \
		and not ctx.board.claimed_by_other("cctv_chair", ctx.peer, ctx.now)
	var rested := ctx.bot.current == self or ctx.now - _last_sat >= ctx.tuning.cctv_rest_s
	if not free or not rested or not _any_camera_works():
		return 0.0
	var t := ctx.path_time(ctx.world.stand(console, Role.Kind.SUPERVISOR), "cctv")
	return AiScoring.cctv(ctx.calm() or _seated(), true, true, t)


## Not every camera we know of is broken.
func _any_camera_works() -> bool:
	for camera in ctx.world.cameras:
		if not ctx.senses.broken_cameras.get(camera, false):
			return true
	return false


func _seated() -> bool:
	return ctx.body.seated_console() != null


func start() -> void:
	_sat_at = -1.0
	target_label = ""


func tick(_delta: float) -> Result:
	var console := ctx.world.console
	if console == null or not claim("cctv_chair"):
		return Result.FAILED
	var driver := ctx.driver
	if not _seated():
		if _sat_at >= 0.0:
			return Result.DONE  # stood up (stunned, knocked down, pushed off)
		if console.user != 0:
			return Result.FAILED
		var stand := ctx.world.stand(console, Role.Kind.SUPERVISOR)
		driver.go_to(stand, false, 0.6)
		if driver.failed():
			ctx.blacklist("cctv_chair")
			return Result.FAILED
		if driver.arrived() or ctx.body.global_position.distance_to(stand) < 0.8:
			driver.face(console.global_position)
			if driver.press(console) == "":
				_sat_at = ctx.now
				_last_sat = ctx.now
				_health_sum = _plant_health()
				ctx.log_line("sat down at the CCTV")
		return Result.RUNNING
	var why := ""
	if ctx.now - _sat_at > ctx.tuning.cctv_max_s:
		why = "seen enough"
	elif ctx.senses.cctv_spotted_at > _sat_at:
		why = "a rat on camera"
	elif _plant_health() < _health_sum - 1.0:
		why = "a machine got damaged"
	elif ctx.now - ctx.senses.bitten_at < 1.0:
		why = "bitten"
	if why == "":
		return Result.RUNNING
	driver.stand_up()
	ctx.log_line("stood up from the CCTV (%s)" % why)
	return Result.DONE


func _plant_health() -> float:
	var plant := ctx.plant()
	var total := 0.0
	for i in plant.count():
		total += plant.health(i)
	return total


func stop() -> void:
	super()
	if _seated():
		ctx.driver.stand_up()
	release("cctv_chair")
