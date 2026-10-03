class_name AiGoalFreeCaged
extends AiGoal
## Rat: free a caged teammate (cage occupants are on the map and the cage label for everyone), when
## no supervisor is known within free_safe_radius of the cage. Holds 4 s at the cage (GDD §5.3).
## One bot per cage (claim "free:<cage>").

var cage: Cage
var _key := ""
var _holding := false


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "FreeCaged"


func score() -> float:
	cage = null
	var best := 0.0
	for c in ctx.world.cages:
		var key := "free:%s" % c.name
		if c.occupants.is_empty() or ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key):
			continue
		var stand := ctx.world.stand(c, Role.Kind.RAT)
		var near := ctx.senses.enemy_near(c.global_position, ctx.tuning.free_safe_radius)
		var s := AiScoring.free_caged(c.occupants.size(), ctx.path_time(stand, "cage%d" % c.get_instance_id()), near)
		if s > best:
			best = s
			cage = c
	return best


func start() -> void:
	_key = "free:%s" % cage.name
	target_label = String(cage.name)
	_holding = false


func tick(_delta: float) -> Result:
	if cage == null or cage.occupants.is_empty():
		return Result.DONE
	if not claim(_key):
		return Result.FAILED
	if ctx.senses.enemy_near(cage.global_position, ctx.tuning.free_safe_radius * 0.6):
		return Result.FAILED  # a supervisor showed up: come back later
	var driver := ctx.driver
	if not _holding:
		driver.go_to(ctx.world.stand(cage, Role.Kind.RAT), false, 0.35)
		if driver.failed():
			ctx.blacklist(_key)
			return Result.FAILED
		if driver.arrived():
			driver.hold(cage)
			_holding = true
		return Result.RUNNING
	if driver.hold_state != AiDriver.Hold.ENDED:
		return Result.RUNNING
	return Result.DONE if driver.hold_reason == "completed" else Result.FAILED


func stop() -> void:
	super()
	release(_key)
