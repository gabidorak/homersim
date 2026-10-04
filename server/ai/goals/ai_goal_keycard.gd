class_name AiGoalKeycard
extends AiGoal
## Supervisor whose keycard was stolen (GDD §5.2): pick up a dropped keycard in sight (a stunned or
## caught thief drops it), else collect the spare at Storage once it is ready (30 s after the loss:
## the HUD counts it down). Chasing a known thief is Chase's (it scores thieves higher).

var pickup: Pickup


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Keycard"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	pickup = null
	var inv := ctx.body.inventory
	if inv.keycard or ctx.body.status.carrying != 0:
		return 0.0
	var best := 0.0
	for p in ctx.senses.keycards_seen:
		if not is_instance_valid(p) or ctx.blacklisted("keycard:%d" % p.get_instance_id()):
			continue
		var s := AiScoring.keycard(true, false, ctx.path_time(ctx.world.stand(p, Role.Kind.SUPERVISOR)))
		if s > best:
			best = s
			pickup = p
	var spare := ctx.world.spare
	if spare != null and inv.spare_ready() and not ctx.blacklisted("keycard:spare"):
		var s := AiScoring.keycard(false, true, ctx.path_time(ctx.world.stand(spare, Role.Kind.SUPERVISOR), "spare"))
		if s > best:
			best = s
			pickup = spare
	return best


func start() -> void:
	target_label = "spare" if pickup == ctx.world.spare else "dropped"


func tick(_delta: float) -> Result:
	if ctx.body.inventory.keycard:
		return Result.DONE
	if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		return Result.FAILED  # someone else took it
	var key := "keycard:spare" if pickup == ctx.world.spare else "keycard:%d" % pickup.get_instance_id()
	var stand := pickup.global_position if pickup != ctx.world.spare else ctx.world.stand(pickup, Role.Kind.SUPERVISOR)
	var driver := ctx.driver
	driver.go_to(ctx.nav.snap(Role.Kind.SUPERVISOR, stand), false, 0.8)
	if driver.failed():
		ctx.blacklist(key)
		return Result.FAILED
	if ctx.body.global_position.distance_to(pickup.global_position) <= pickup.reach_for(Role.Kind.SUPERVISOR) + 0.3:
		driver.face(pickup.global_position)
		var reason := driver.press(pickup)
		if reason == "":
			ctx.log_line("got a keycard back (%s)" % target_label)
			return Result.DONE
		if not reason.begins_with("too far") and not reason.begins_with("no line"):
			ctx.blacklist(key)
			return Result.FAILED
	return Result.RUNNING
