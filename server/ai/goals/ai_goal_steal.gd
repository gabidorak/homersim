class_name AiGoalSteal
extends AiGoal
## Rat: steal a supervisor's keycard (GDD §5.2). Only from one this bot sees standing still (repairing,
## at the CCTV, at a console) and facing away from it, within steal_radius, that still has its keycard
## (as far as we know: AiSenses sees it from close up). Sneaks behind it, holds its StealHandle 1 s
## (the server re-checks the facing every tick: turning around cancels it), then runs to the nearest
## vent with the keycard. One bot per supervisor (claim "steal:<peer>").

const BEHIND := 0.7  ## m behind the supervisor's centre (its StealHandle is 0.3 m behind)
const STILL_SPEED := 0.6  ## m/s: slower than this counts as standing still
const BACK_ARC := 0.25  ## cos: we are behind it when its facing · (us − it) is below −this…
const LOST_S := 1.5

var target: AiSenses.Known
var _pick: AiSenses.Known
var _holding := false
var _stolen := false
var _escape := Vector3.INF


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Steal"


func score() -> float:
	_pick = null
	if ctx.body.inventory.stolen_item != &"":
		return 0.95 if ctx.bot.current == self and _stolen else 0.0  # (getting away with it)
	var here := ctx.body.global_position
	var best := 0.0
	for k in ctx.senses.enemies():
		if not k.visible or k.knocked or k.carrying != 0 or ctx.blacklisted("steal:%d" % k.peer) \
				or ctx.board.claimed_by_other("steal:%d" % k.peer, ctx.peer, ctx.now):
			continue
		var still := k.busy or k.velocity.length() < STILL_SPEED
		var s := AiScoring.steal(k.pos.distance_to(here), ctx.tuning.steal_radius, still, _facing_away(k), k.keycard)
		if s > best:
			best = s
			_pick = k
	return best


## The supervisor faces away from us (or sits: the CCTV chair faces the screens).
func _facing_away(k: AiSenses.Known) -> bool:
	var forward := Vector2(-sin(k.facing), -cos(k.facing))
	var to_us := Vector2(ctx.body.global_position.x - k.pos.x, ctx.body.global_position.z - k.pos.z)
	return to_us.length() < 0.3 or forward.dot(to_us.normalized()) < BACK_ARC


func start() -> void:
	target = _pick
	_holding = false
	_stolen = false
	_escape = Vector3.INF
	target_label = ctx.session.name_of(target.peer) if target != null else ""


func tick(_delta: float) -> Result:
	var driver := ctx.driver
	if _stolen or ctx.body.inventory.stolen_item != &"":
		return _get_away()
	if target == null:
		return Result.FAILED
	var key := "steal:%d" % target.peer
	var k := ctx.senses.get_known(target.peer)
	if k == null or k.age(ctx.now) > LOST_S or not k.keycard or k.knocked:
		return Result.FAILED
	if not claim(key):
		return Result.FAILED
	if not _holding:
		var back := Vector3(sin(k.facing), 0.0, cos(k.facing))  # behind its facing (-Z is forward)
		var spot := ctx.nav.snap(Role.Kind.RAT, k.pos + back * BEHIND)
		driver.go_to(spot, false, 0.25)
		if driver.failed():
			ctx.blacklist(key)
			return Result.FAILED
		if not _facing_away(k) and ctx.body.global_position.distance_to(k.pos) < 2.0:
			return Result.FAILED  # it turned around: not now
		if driver.arrived() or ctx.body.global_position.distance_to(spot) < 0.3:
			var handle := ctx.senses.steal_handle_of(target.peer)
			if handle == null:
				return Result.RUNNING
			driver.hold(handle)
			_holding = true
		return Result.RUNNING
	if driver.hold_state != AiDriver.Hold.ENDED:
		return Result.RUNNING
	_holding = false
	if driver.hold_reason == "completed" or ctx.body.inventory.stolen_item != &"":
		_stolen = true
		ctx.log_line("stole %s's keycard" % ctx.session.name_of(target.peer))
		return Result.RUNNING
	ctx.blacklist(key)
	return Result.FAILED


## With the keycard: sprint to the nearest vent.
func _get_away() -> Result:
	var driver := ctx.driver
	if _escape == Vector3.INF:
		_escape = _nearest_vent()
		if _escape == Vector3.INF:
			return Result.DONE
	driver.go_to(_escape, true, 0.6)
	if driver.failed() or driver.arrived() or driver.in_vent():
		return Result.DONE
	return Result.RUNNING


func _nearest_vent() -> Vector3:
	var here := ctx.body.global_position
	var best := Vector3.INF
	var best_d := INF
	for p: Vector3 in ctx.world.hideouts(ctx.nav) + ctx.world.vent_spots:
		var d := p.distance_to(here)
		if d < best_d and d < ctx.tuning.flee_search_radius * 1.5:
			best_d = d
			best = p
	return best


func stop() -> void:
	super()
	if target != null:
		release("steal:%d" % target.peer)
