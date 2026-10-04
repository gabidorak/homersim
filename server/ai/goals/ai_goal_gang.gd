class_name AiGoalGang
extends AiGoal
## Rat, teamwork (the skill's `teamwork`): when 2 or more rat bots are within gang_radius of the same
## busy supervisor (standing at something: a repair, the CCTV, a console; or carrying a rat), they
## bite it together, going for the knockdown (3 bites within 6 s, any rats) and, with every
## supervisor down at once, the swarm bonus (GDD §2, §5.1, §5.5). Never next to a cage (gang_cage_radius):
## a stun there is a capture. Each bot marks the supervisors it knows close by on the team blackboard
## (`near`); the first to see two marks starts the gang (AiBlackboard.start_gang) and the others join
## while it lasts. Rats in the gang don't flee from its target (AiGoalFlee). Approaches from behind,
## bites when the bite is ready, circles 1.6 m off while it cools down; done once the supervisor is
## knocked down, walks off (no longer a sitting duck), is gone, or the gang broke up.

const BEHIND := 0.8
const BITE_REACH := 1.4  ## m (the server allows 1.2 + 0.5)
const CIRCLE_M := 1.6
const LOST_S := 2.0
const WALKING := 1.5  ## m/s: a supervisor moving faster than this is no longer busy

var target := 0
var _pick := 0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Gang"


func score() -> float:
	_pick = 0
	if not ctx.skill.teamwork or not ctx.can_act():
		return 0.0
	var here := ctx.body.global_position
	var best := 0.0
	for k in ctx.senses.enemies():
		if k.age(ctx.now) > 1.0 or k.pos.distance_to(here) > ctx.tuning.gang_radius:
			continue
		if not (k.busy or k.carrying != 0) or (k.carrying == 0 and _near_cage(k.pos)):
			continue
		ctx.board.mark_near(k.peer, ctx.peer, ctx.now)
		var members := ctx.board.gang_members(k.peer, ctx.now)
		var s := AiScoring.gang(members, k.knocked, true)
		if ctx.board.gang_on(k.peer, ctx.now):
			s = maxf(s, AiScoring.gang(2, k.knocked, true))  # a gang is on: join it
		if s > best:
			best = s
			_pick = k.peer
	return best


func _near_cage(pos: Vector3) -> bool:
	for cage in ctx.world.cages:
		if cage.global_position.distance_to(pos) < ctx.tuning.gang_cage_radius:
			return true
	return false


## A gang is biting `sup` and this bot is in it (Flee leaves its target alone).
func in_gang_on(sup: int) -> bool:
	return ctx.bot.current == self and target == sup and ctx.board.gang_on(sup, ctx.now)


func start() -> void:
	target = _pick
	if target != 0:
		ctx.board.start_gang(target, ctx.now, ctx.tuning.gang_s)
	target_label = ctx.session.name_of(target) if target != 0 else ""


func tick(_delta: float) -> Result:
	if target == 0:
		return Result.FAILED
	var k := ctx.senses.get_known(target)
	if k == null or k.age(ctx.now) > LOST_S:
		return Result.DONE  # it got away
	if k.knocked:
		ctx.log_line("the gang knocked %s down" % ctx.session.name_of(target))
		return Result.DONE
	if k.visible and not k.busy and k.carrying == 0 and k.velocity.length() > WALKING:
		return Result.DONE  # it walked off: no longer a sitting duck
	var here := ctx.body.global_position
	ctx.board.mark_near(target, ctx.peer, ctx.now)
	if ctx.board.gang_members(target, ctx.now, 1.5) >= 2:
		ctx.board.start_gang(target, ctx.now, ctx.tuning.gang_s)  # renewed while we stay together
	elif not ctx.board.gang_on(target, ctx.now):
		return Result.DONE  # the others left
	var back := Vector3(sin(k.facing), 0.0, cos(k.facing))
	var driver := ctx.driver
	if ctx.body.abilities.server_ready(&"bite"):
		driver.go_to(ctx.nav.snap(Role.Kind.RAT, k.pos + back * BEHIND), true, 0.35)
		if here.distance_to(k.pos) <= BITE_REACH:
			driver.face(k.pos)
			if driver.use(&"bite", k.pos - here) == "":
				ctx.log_line("gang bite on %s" % ctx.session.name_of(target))
	else:
		var side := Vector3(-back.z, 0.0, back.x) * (1.0 if ctx.peer % 2 == 0 else -1.0)
		driver.go_to(ctx.nav.snap(Role.Kind.RAT, k.pos + (back + side).normalized() * CIRCLE_M), true, 0.5)
	if driver.failed():
		return Result.FAILED
	return Result.RUNNING
