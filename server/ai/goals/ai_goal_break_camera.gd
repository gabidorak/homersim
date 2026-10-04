class_name AiGoalBreakCamera
extends AiGoal
## Rat: break a CCTV camera near its way (GDD §5.2, a 2 s hold at the camera's junction box), above all
## while a supervisor watches the cameras (one a teammate bot saw seated in the chair recently). A
## camera's state shows from close up (camera_seen_radius): the bot only goes for cameras near it.
## No supervisor known near the camera. One bot per camera (claim "camera:<n>").

const WATCHED_S := 25.0  ## a supervisor seen in the chair this recently is probably still there

var camera: CctvCamera
var _pick: CctvCamera
var _holding := false


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "BreakCamera"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = null
	var here := ctx.body.global_position
	var watched := ctx.board.seated_supervisor(ctx.now, WATCHED_S) != 0 or _seen_seated()
	var best := 0.0
	for c in ctx.world.cameras:
		var key := "camera:%d" % c.number
		if c.broken or c.global_position.distance_to(here) > ctx.tuning.camera_seen_radius \
				or ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key) \
				or ctx.senses.enemy_near(c.global_position, ctx.tuning.sabotage_supervisor_radius):
			continue
		var stand := ctx.stand_for(c)
		if stand == Vector3.INF:
			continue
		var s := AiScoring.break_camera(ctx.path_time(stand, key), ctx.tuning.camera_detour_s, watched, ctx.danger_at(stand))
		if s > best:
			best = s
			_pick = c
	return best


func _seen_seated() -> bool:
	for k in ctx.senses.enemies():
		if k.seated and k.age(ctx.now) < WATCHED_S:
			return true
	return false


func start() -> void:
	camera = _pick
	_holding = false
	target_label = str(camera.number) if camera != null else ""


func tick(_delta: float) -> Result:
	if camera == null:
		return Result.FAILED
	if camera.broken:
		return Result.DONE
	var key := "camera:%d" % camera.number
	if not claim(key):
		return Result.FAILED
	var driver := ctx.driver
	if not _holding:
		var stand := ctx.stand_for(camera)
		if stand == Vector3.INF:
			ctx.blacklist(key)
			return Result.FAILED
		driver.go_to(stand, false, 0.3)
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
		ctx.log_line("broke camera %d" % camera.number)
		return Result.DONE
	if driver.hold_reason.begins_with("refused"):
		ctx.blacklist(key)
	return Result.FAILED


func stop() -> void:
	super()
	if camera != null:
		release("camera:%d" % camera.number)
