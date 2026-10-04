class_name AiGoalSabotage
extends AiGoal
## Rat: sabotage a normal machine (GDD §4.3). Scores every sabotage point whose machine can be
## sabotaged now (off cooldown, not broken: what the HUD shows) and that no teammate bot claimed:
## AiScoring.sabotage (heat weight × health, the hazard bonus, a known supervisor nearby, the walk).
## Walks to the point's stand position (or a spot beside it, AiContext.stand_for: a trap it noticed
## or a live hazard there), stops, holds 4 s; sometimes squeaks afterwards, then rests
## sabotage_rest_s.

var point: SabotagePoint
var _key := ""
var _holding := false
var _rest_until := 0.0  # after a sabotage (BotTuning.sabotage_rest_s)


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Sabotage"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	point = null
	if ctx.now < _rest_until:
		return 0.0
	var best := 0.0
	var plant := ctx.plant()
	for p in ctx.world.sabotage_points:
		if p.index == -1 or not plant.can_sabotage(p.index):
			continue
		var key := "sabotage:%s" % p.subsystem_id
		if ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key):
			continue
		var stand := ctx.stand_for(p)
		if stand == Vector3.INF:
			continue  # a trap we noticed, or a live hazard, on every spot
		var t := ctx.path_time(stand, "sab%d" % p.get_instance_id())
		var s := AiScoring.sabotage(plant.data(p.index).heat_weight, plant.health(p.index),
			plant.tuning.sabotage_damage, t, ctx.danger_at(stand))
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
		var stand := ctx.stand_for(point)
		if stand == Vector3.INF:
			ctx.blacklist(_key)
			return Result.FAILED
		driver.go_to(stand, false, 0.3)
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
		_rest_until = ctx.now + ctx.tuning.sabotage_rest_s
		return Result.DONE
	if driver.hold_reason.begins_with("refused"):
		ctx.blacklist(_key)
	return Result.FAILED


func stop() -> void:
	super()
	release(_key)
