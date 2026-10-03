class_name AiGoalChase
extends AiGoal
## Supervisor: chase a known rat within chase_radius (AiScoring.chase): very worth it while the rat is
## busy sabotaging (it stands still), hardly when it runs away already far (rats are faster). Steers
## toward where the rat is heading; the broom swing is AiBot's reflex, and a stunned rat is Capture's.
## A rat lost from sight is followed to its last known position, then given up. A rat where no
## supervisor can go (in a vent: its known spot is far from the supervisors' mesh) isn't chased.

const LEAD_S := 0.5  ## aim this far ahead of a moving rat
const LOST_S := 3.0
const OFF_MESH := 2.5  ## m from the supervisors' mesh: out of reach (a heard spot has ±2 m of noise)

var target: AiSenses.Known
var _key := ""


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Chase"


func score() -> float:
	target = null
	if ctx.body.status.carrying != 0:
		return 0.0
	var best := 0.0
	var here := ctx.body.global_position
	for k in ctx.senses.enemies():
		if k.age(ctx.now) > 1.5 or k.stunned or not _reachable(k.pos):
			continue
		var d := k.pos.distance_to(here)
		var away := k.velocity.length() > 1.0 and k.velocity.normalized().dot((k.pos - here).normalized()) > 0.5
		var s := AiScoring.chase(d, ctx.tuning.chase_radius, k.busy, away and d > ctx.tuning.chase_give_up, k.visible)
		if ctx.board.claimed_by_other("chase:%d" % k.peer, ctx.peer, ctx.now):
			s *= 0.6  # a teammate is on it: still worth cornering it
		if s > best:
			best = s
			target = k
	return best


func _reachable(pos: Vector3) -> bool:
	var on_mesh := ctx.nav.closest_point(Role.Kind.SUPERVISOR, pos)
	return Vector2(on_mesh.x - pos.x, on_mesh.z - pos.z).length() < OFF_MESH and absf(on_mesh.y - pos.y) < 1.5


func start() -> void:
	_key = "chase:%d" % target.peer
	target_label = ctx.session.name_of(target.peer)


func tick(_delta: float) -> Result:
	if target == null:
		return Result.FAILED
	var k := ctx.senses.get_known(target.peer)
	if k == null or k.stunned or ctx.body.status.carrying != 0:
		return Result.DONE
	claim(_key)
	var here := ctx.body.global_position
	if not _reachable(k.pos):
		return Result.DONE  # into a vent
	var aim := ctx.nav.closest_point(Role.Kind.SUPERVISOR, k.pos + k.velocity * LEAD_S if k.visible else k.pos)
	ctx.driver.go_to(aim, true, 0.9 if k.visible else 0.6)
	if k.visible and here.distance_to(k.pos) < 4.0:
		ctx.driver.face(k.pos)
	if ctx.driver.failed():
		return Result.FAILED
	if not k.visible and (ctx.driver.arrived() or k.age(ctx.now) > LOST_S):
		return Result.DONE  # lost it
	return Result.RUNNING


func stop() -> void:
	super()
	release(_key)
