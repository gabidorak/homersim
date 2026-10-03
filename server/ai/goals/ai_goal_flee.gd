class_name AiGoalFlee
extends AiGoal
## Rat reflex: run from a known supervisor closing in within flee_radius, or from a broom swing heard
## nearby (AiScoring.flee). Picks the best of up to flee_candidates escape spots: vents and vent exits
## within flee_search_radius, plus spots away from the threat; best = the largest head start ("the
## supervisor's path time − mine"; a vent is out of a supervisor's reach). Sprints there. In a vent
## already, a rat is safe: no fleeing.

const AWAY_M := 9.0  ## the spots away from the threat are this far
const BROOM_HEARD_S := 1.5
const THREAT_MEMORY_S := 2.0  ## a threat heard or seen this recently still counts

var _threat: AiSenses.Known
var _spot := Vector3.INF
var _since := 0.0
var _last_distance := {}  # threat peer -> distance at the last score


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Flee"
	reflex = true


func score() -> float:
	if ctx.driver.in_vent() or not ctx.can_act():
		return 0.0
	var here := ctx.body.global_position
	var best := 0.0
	_threat = null
	var broom := ctx.senses.heard_recently("broom", ctx.tuning.flee_radius, BROOM_HEARD_S)
	for k in ctx.senses.enemies():
		if k.age(ctx.now) > THREAT_MEMORY_S or k.knocked or k.carrying != 0 and k.carrying != ctx.peer:
			continue
		var d := k.pos.distance_to(here)
		var closing := d < float(_last_distance.get(k.peer, INF)) - 0.05 \
			or (k.velocity.length() > 0.5 and k.velocity.normalized().dot((here - k.pos).normalized()) > 0.3)
		_last_distance[k.peer] = d
		var s := AiScoring.flee(d, closing, ctx.tuning.flee_radius, broom)
		if ctx.bot.current == self and ctx.now - _since < ctx.tuning.flee_min_s and d < ctx.tuning.flee_radius * 1.5:
			s = maxf(s, 0.7)  # keep running a moment
		if s > best:
			best = s
			_threat = k
	return best


func start() -> void:
	_since = ctx.now
	_spot = _pick_spot()
	target_label = "from %s" % ctx.session.name_of(_threat.peer) if _threat != null else ""


func tick(_delta: float) -> Result:
	if _spot == Vector3.INF:
		return Result.FAILED
	ctx.driver.go_to(_spot, true, 0.6)
	if ctx.driver.failed():
		_spot = _pick_spot([_spot])
		return Result.RUNNING if _spot != Vector3.INF else Result.FAILED
	if ctx.driver.arrived():
		if ctx.driver.in_vent() or ctx.now - _since >= ctx.tuning.flee_min_s:
			return Result.DONE
		_spot = _pick_spot([_spot])
	return Result.RUNNING


## The escape spot with the biggest head start over the threat.
func _pick_spot(exclude: Array = []) -> Vector3:
	var here := ctx.body.global_position
	var threat_pos := _threat.pos if _threat != null else here + Vector3.FORWARD
	var candidates: Array[Vector3] = []
	var near: Array[Vector3] = []
	for p in ctx.world.vent_exits + ctx.world.vent_spots:
		if p.distance_to(here) <= ctx.tuning.flee_search_radius:
			near.append(p)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(here) < b.distance_to(here))
	candidates.append_array(near.slice(0, maxi(ctx.tuning.flee_candidates - 3, 1)))
	var away := Vector3(here.x - threat_pos.x, 0.0, here.z - threat_pos.z).normalized()
	if away == Vector3.ZERO:
		away = Vector3.FORWARD
	for angle in [0.0, 0.8, -0.8]:
		candidates.append(ctx.nav.closest_point(Role.Kind.RAT, here + away.rotated(Vector3.UP, angle) * AWAY_M))
	var rat_speed := ctx.body.role_data.sprint_speed
	var sup_speed := Role.data(Role.Kind.SUPERVISOR).sprint_speed
	var best := Vector3.INF
	var best_margin := -INF
	for spot in candidates:
		if exclude.any(func(e: Vector3) -> bool: return e.distance_to(spot) < 1.0) or spot.distance_to(here) < 2.0:
			continue
		var mine := ctx.nav.path(Role.Kind.RAT, here, spot)
		if mine.is_empty() or mine.end().distance_to(spot) > 0.6:
			continue  # (a scrap of mesh on a prop, or out of reach)
		var theirs := ctx.nav.path(Role.Kind.SUPERVISOR, threat_pos, spot, true)
		var their_time := INF
		if not theirs.is_empty() and theirs.end().distance_to(spot) < 1.0:
			their_time = theirs.length / sup_speed
		var margin := minf(their_time, 30.0) - mine.length / rat_speed
		# Running past the threat is no escape.
		if (spot - here).normalized().dot((threat_pos - here).normalized()) > 0.5 and mine.length < here.distance_to(threat_pos) * 2.5:
			margin -= 10.0
		if margin > best_margin:
			best_margin = margin
			best = spot
	return best
