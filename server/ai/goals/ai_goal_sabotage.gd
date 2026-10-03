class_name AiGoalSabotage
extends AiGoal
## Rat: sabotage a normal machine (GDD §4.3). Scores every sabotage point whose machine can be
## sabotaged now (off cooldown, not broken: what the HUD shows) and that no teammate bot claimed:
## AiScoring.sabotage (heat weight × health, the hazard bonus, a known supervisor nearby, the walk).
## Walks to the point's stand position, stops, holds 4 s; sometimes squeaks afterwards.

var point: SabotagePoint
var _key := ""
var _holding := false


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Sabotage"


func score() -> float:
	point = null
	var best := 0.0
	var plant := ctx.plant()
	for p in ctx.world.sabotage_points:
		if p.index == -1 or not plant.can_sabotage(p.index):
			continue
		var key := "sabotage:%s" % p.subsystem_id
		if ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key):
			continue
		var stand := ctx.world.stand(p, Role.Kind.RAT)
		var t := ctx.path_time(stand, "sab%d" % p.get_instance_id())
		var near := ctx.senses.enemy_near(stand, ctx.tuning.sabotage_supervisor_radius)
		var s := AiScoring.sabotage(plant.data(p.index).heat_weight, plant.health(p.index),
			plant.tuning.sabotage_damage, t, near)
		if s > best:
			best = s
			point = p
	return best


func start() -> void:
	_key = "sabotage:%s" % point.subsystem_id
	target_label = String(point.subsystem_id)
	_holding = false


func tick(_delta: float) -> Result:
	if point == null:
		return Result.FAILED
	if not claim(_key):
		return Result.FAILED  # a teammate got there first
	var driver := ctx.driver
	if not _holding:
		if not ctx.plant().can_sabotage(point.index):
			return Result.DONE  # sabotaged by someone else, or on cooldown now
		driver.go_to(ctx.world.stand(point, Role.Kind.RAT), false, 0.3)
		if driver.failed():
			ctx.blacklist(_key)
			return Result.FAILED
		if driver.arrived():
			driver.hold(point)
			_holding = true
		return Result.RUNNING
	if driver.hold_state != AiDriver.Hold.ENDED:
		return Result.RUNNING
	if driver.hold_reason == "completed":
		if ctx.rng.randf() < ctx.tuning.squeak_chance:
			driver.emote()
		return Result.DONE
	if driver.hold_reason.begins_with("refused"):
		ctx.blacklist(_key)
	return Result.FAILED


func stop() -> void:
	super()
	release(_key)
