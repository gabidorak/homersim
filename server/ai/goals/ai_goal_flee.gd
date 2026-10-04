class_name AiGoalFlee
extends AiGoal
## Rat reflex: run from a known supervisor closing in within flee_radius, or from a broom swing heard
## nearby (AiScoring.flee). Picks the best of up to flee_candidates escape spots: bolt-holes just inside
## the vents (AiDirector.World.hideouts) within flee_search_radius, plus spots away from the threats;
## best = the largest head start ("the nearest supervisor's path time − mine"; inside a vent, no
## supervisor can follow). Sprints there, and on while it is still chased. In a vent
## already, a rat is safe: no fleeing. A rat biting a supervisor with its gang (AiGoalGang) doesn't
## run from that one, nor from its broom.

const AWAY_M := 12.0  ## the spots away from the threat are this far
const VENT_BONUS_S := 3.0  ## a spot inside a duct counts as this much more head start
const MAX_THREATS := 2  ## the nearest supervisors a flight plans around (each costs a path per spot)
const BROOM_HEARD_S := 1.5
const THREAT_MEMORY_S := 2.0  ## a threat heard or seen this recently still counts
const FACING_M := 7.0  ## a supervisor this close looking our way is a threat even standing still…
const TOO_CLOSE_M := 4.0  ## …and one this close whatever it looks at (unless it is busy at something)
const HEARD_CLOSE_M := 6.5  ## a supervisor heard walking this close (±2 m) is a threat too

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
	var gang := _gang_target()
	var broom := gang == 0 and ctx.senses.heard_recently("broom", ctx.tuning.flee_radius, BROOM_HEARD_S)
	for k in ctx.senses.enemies():
		if k.age(ctx.now) > THREAT_MEMORY_S or k.knocked or k.carrying != 0 and k.carrying != ctx.peer or k.peer == gang:
			continue
		var d := k.pos.distance_to(here)
		var closing := d < float(_last_distance.get(k.peer, INF)) - 0.05 \
			or (k.velocity.length() > 0.5 and k.velocity.normalized().dot((here - k.pos).normalized()) > 0.3) \
			or (k.visible and not k.busy and (d < TOO_CLOSE_M or (d < FACING_M and _faces(k, here)))) \
			or (k.heard and k.age(ctx.now) < 0.5 and d < HEARD_CLOSE_M)  # footsteps right next to us
		_last_distance[k.peer] = d
		var s := AiScoring.flee(d, closing, ctx.tuning.flee_radius, broom)
		if ctx.bot.current == self and ctx.now - _since < ctx.tuning.flee_min_s and d < ctx.tuning.flee_radius * 1.5:
			s = maxf(s, 0.7)  # keep running a moment
		if s > best:
			best = s
			_threat = k
	return best


## The threat is still close and was seen (or heard) a moment ago.
func _still_after_us() -> bool:
	if _threat == null:
		return false
	var k := ctx.senses.get_known(_threat.peer)
	return k != null and k.age(ctx.now) < THREAT_MEMORY_S and not k.knocked \
		and k.pos.distance_to(ctx.body.global_position) < ctx.tuning.flee_radius


## `k` looks toward `pos` (within 60°).
func _faces(k: AiSenses.Known, pos: Vector3) -> bool:
	var forward := Vector2(-sin(k.facing), -cos(k.facing))
	var to := Vector2(pos.x - k.pos.x, pos.z - k.pos.z)
	return to.length() < 0.3 or forward.dot(to.normalized()) > 0.5


## The supervisor this bot is biting with its gang (0 = none).
func _gang_target() -> int:
	var gang := ctx.bot.current as AiGoalGang
	return gang.target if gang != null and gang.in_gang_on(gang.target) else 0


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
		if ctx.driver.in_vent() or (ctx.now - _since >= ctx.tuning.flee_min_s and not _still_after_us()):
			return Result.DONE
		_spot = _pick_spot([_spot])  # it is still after us: keep running
	return Result.RUNNING


## The escape spot with the biggest head start over the threat.
func _pick_spot(exclude: Array = []) -> Vector3:
	var here := ctx.body.global_position
	var threats := _threats()
	var threat_pos := _threat.pos if _threat != null else (threats[0] if not threats.is_empty() else here + Vector3.FORWARD)
	var candidates: Array[Vector3] = []
	var near: Array[Vector3] = []
	var holes := ctx.world.hideouts(ctx.nav)
	for p: Vector3 in holes:
		if p.distance_to(here) <= ctx.tuning.flee_search_radius:
			near.append(p)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(here) < b.distance_to(here))
	candidates.append_array(near.slice(0, maxi(ctx.tuning.flee_candidates - 3, 1)))
	var away := Vector3.ZERO
	for t in threats:  # away from all of them, the nearest counting most
		var off := Vector3(here.x - t.x, 0.0, here.z - t.z)
		away += off.normalized() / maxf(off.length(), 1.0)
	away = away.normalized() if away.length() > 0.001 else Vector3(here.x - threat_pos.x, 0.0, here.z - threat_pos.z).normalized()
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
		var my_time := mine.length / rat_speed
		var margin := 30.0
		for t in threats:  # the supervisor who gets there first decides
			var theirs := ctx.nav.path(Role.Kind.SUPERVISOR, t, spot, true)
			var their_time := INF
			if not theirs.is_empty() and theirs.end().distance_to(spot) < 1.0:
				their_time = theirs.length / sup_speed
			var m := minf(their_time, 30.0) - my_time
			# Running past a supervisor is no escape.
			if (spot - here).normalized().dot((t - here).normalized()) > 0.5 and mine.length < here.distance_to(t) * 2.5:
				m -= 10.0
			margin = minf(margin, m)
		if spot in holes:
			margin += VENT_BONUS_S  # in a duct: no supervisor can follow
		if margin > best_margin:
			best_margin = margin
			best = spot
	return best


## Where the supervisors we know of were last (seen or heard lately): the flight avoids all of them.
func _threats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in ctx.senses.enemies():  # (nearest first)
		if k.age(ctx.now) < THREAT_MEMORY_S * 3.0 and not k.knocked and out.size() < MAX_THREATS:
			out.append(k.pos)
	return out
