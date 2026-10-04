class_name AiGoalFixCamera
extends AiGoal
## Supervisor: repair a broken CCTV camera (GDD §5.2, a 3 s hold at its junction box), above all one on
## the way. Only cameras this bot knows are broken (AiSenses.broken_cameras: seen from close up, on the
## Control Room's screens or from the chair). One bot per camera (claim "camera:<n>").

var camera: CctvCamera
var _pick: CctvCamera
var _holding := false


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "FixCamera"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = null
	if ctx.body.status.carrying != 0:
		return 0.0
	var best := 0.0
	for c: CctvCamera in ctx.senses.broken_cameras:
		var key := "camera:%d" % c.number
		if not ctx.senses.broken_cameras[c] or ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key):
			continue
		var s := AiScoring.fix_camera(ctx.path_time(ctx.world.stand(c, Role.Kind.SUPERVISOR), key))
		if s > best:
			best = s
			_pick = c
	return best


func start() -> void:
	camera = _pick
	_holding = false
	target_label = str(camera.number) if camera != null else ""


func tick(_delta: float) -> Result:
	if camera == null:
		return Result.FAILED
	var key := "camera:%d" % camera.number
	if not camera.broken:
		ctx.senses.broken_cameras[camera] = false
		return Result.DONE
	if not claim(key):
		return Result.FAILED
	var driver := ctx.driver
	if not _holding:
		driver.go_to(ctx.world.stand(camera, Role.Kind.SUPERVISOR), false, 0.4)
		if driver.failed():
			ctx.blacklist(key)
			return Result.FAILED
		if driver.arrived():
			driver.hold(camera)
			_holding = true
		return Result.RUNNING
	if driver.hold_state != AiDriver.Hold.ENDED:
		return Result.RUNNING
	if driver.hold_reason == "completed":
		ctx.senses.broken_cameras[camera] = false
		ctx.log_line("fixed camera %d" % camera.number)
		return Result.DONE
	if driver.hold_reason.begins_with("refused"):
		ctx.blacklist(key)
	return Result.FAILED


func stop() -> void:
	super()
	if camera != null:
		release("camera:%d" % camera.number)
