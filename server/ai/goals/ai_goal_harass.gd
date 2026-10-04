class_name AiGoalHarass
extends AiGoal
## Rat: bite a supervisor that is busy standing still (repairing, seated at the CCTV), seen by this
## bot. Approach from behind, bite when the bite is ready, keep harass_keep_away metres off while it
## cools down. Three bites within 6 s knock a supervisor down (GDD §5.1). Stops once the supervisor
## moves on or is out of sight for a moment.

const BEHIND := 0.8  ## m behind the supervisor to bite from
const BITE_REACH := 1.4  ## m: bite from this close (the server allows 1.2 + 0.5)
const LOST_S := 2.0
const MAX_BITES := 4

var target: AiSenses.Known
var _bites := 0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Harass"


func score() -> float:
	target = null
	var best := 0.0
	for k in ctx.senses.enemies():
		if not k.visible or not k.busy or k.knocked or k.pos.distance_to(ctx.body.global_position) > 18.0:
			continue
		var s := AiScoring.harass(ctx.path_time(k.pos, "harass%d" % k.peer), true)
		if s > best:
			best = s
			target = k
	return best


func start() -> void:
	_bites = 0
	target_label = ctx.session.name_of(target.peer) if target != null else ""


func tick(_delta: float) -> Result:
	if target == null:
		return Result.FAILED
	var k := ctx.senses.get_known(target.peer)
	if k == null or k.age(ctx.now) > LOST_S or k.knocked or (k.visible and not k.busy) or _bites >= MAX_BITES:
		return Result.DONE
	var back := Vector3(sin(k.facing), 0.0, cos(k.facing))  # behind its facing (-Z is forward)
	var here := ctx.body.global_position
	if ctx.body.abilities.server_ready(&"bite"):
		ctx.driver.go_to(ctx.nav.snap(Role.Kind.RAT, k.pos + back * BEHIND), true, 0.35)
		if here.distance_to(k.pos) <= BITE_REACH:
			ctx.driver.face(k.pos)
			if ctx.driver.use(&"bite", k.pos - here) == "":
				_bites += 1
	else:
		ctx.driver.go_to(ctx.nav.snap(Role.Kind.RAT, k.pos + back * ctx.tuning.harass_keep_away), false, 0.6)
	if ctx.driver.failed():
		return Result.FAILED
	return Result.RUNNING
