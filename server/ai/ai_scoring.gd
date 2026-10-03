class_name AiScoring
extends RefCounted
## The AI bots' utility scores (M10, ARCHITECTURE §6 AI bots): pure functions, so GUT can test them
## (tests/unit/test_ai_scoring.gd). Every goal scores about 0..1: 0 = not now, ~0.1 = something to
## do when there's nothing better (lurk, patrol), ~0.5 = a good job, 0.9+ = drop everything (a reflex).
## Times are in seconds of walking along the navigation mesh (INF = unreachable).

const MAX_HEAT_WEIGHT := 3.0  ## the control rods, the most valuable machine
const TRAVEL_HALF_S := 12.0  ## a target this many seconds away is worth half as much (rats)
const REPAIR_TRAVEL_HALF_S := 30.0  ## supervisors cross the plant to repair: distance matters less
const HAZARD_LINE := 50.0  ## health below this starts a machine's hazards (GDD §6)
const LURK := 0.1
const PATROL_BASE := 0.05


## How much a target `path_time` seconds away is worth compared to one right here (1 → 0.5 at `half`).
static func travel_factor(path_time: float, half: float = TRAVEL_HALF_S) -> float:
	if path_time == INF or is_nan(path_time):
		return 0.0
	return half / (half + maxf(path_time, 0.0))


## `score` with the running goal's commitment bonus (so bots don't flip-flop between close scores).
static func committed(score: float, running: bool, bonus: float) -> float:
	return score + bonus if running and score > 0.0 else score


# --- Rats --------------------------------------------------------------------------------------------

## Sabotage a normal machine: its heat weight × its health, more when the hit drops it below the
## hazard line, less with a known supervisor near the point, divided down by the walk.
static func sabotage(heat_weight: float, health: float, damage: float, path_time: float, supervisor_near: bool) -> float:
	if health <= 0.0 or path_time == INF:
		return 0.0
	var value := heat_weight / MAX_HEAT_WEIGHT * health / 100.0
	if health - damage < HAZARD_LINE:
		value *= 1.5
	if supervisor_near:
		value *= 0.4
	return clampf(0.2 + 0.7 * value * travel_factor(path_time), 0.0, 0.9)


## A critical lever pair: worth twice a sabotage (100 damage), times how likely a partner is
## (1 = one is waiting, about 0.6 = a free teammate could come, 0 = nobody).
static func lever_pair(heat_weight: float, health: float, path_time: float, partner: float) -> float:
	if health <= 0.0 or path_time == INF or partner <= 0.0:
		return 0.0
	var value := heat_weight / MAX_HEAT_WEIGHT * health / 100.0 * 1.5
	return clampf((0.2 + 0.7 * value * travel_factor(path_time)) * minf(partner, 1.2), 0.0, 0.9)


## Flee from a supervisor `distance` m away: only when it is closing in, or a broom swing was heard.
static func flee(distance: float, closing: bool, flee_radius: float, broom_heard: bool) -> float:
	if broom_heard and distance < flee_radius * 1.5:
		return 0.92
	if distance >= flee_radius or not closing:
		return 0.0
	return 0.6 + 0.3 * (1.0 - clampf(distance / flee_radius, 0.0, 1.0))


## Rescue a carried teammate `seconds_away` from us (at a sprint) before its carrier cages it.
static func rescue(seconds_away: float, carry_left_s: float) -> float:
	if seconds_away == INF or seconds_away > carry_left_s:
		return 0.0
	return 0.5 + 0.45 * travel_factor(seconds_away, 4.0)


## Bite a supervisor busy standing still (repairing, at the CCTV).
static func harass(path_time: float, busy: bool) -> float:
	if not busy or path_time == INF:
		return 0.0
	return 0.3 + 0.3 * travel_factor(path_time, 6.0)


## Free the rats in a cage, when no supervisor is known nearby.
static func free_caged(occupants: int, path_time: float, supervisor_near: bool) -> float:
	if occupants <= 0 or supervisor_near or path_time == INF:
		return 0.0
	return clampf(0.35 + 0.35 * travel_factor(path_time, 20.0) + 0.1 * (occupants - 1), 0.0, 0.85)


# --- Supervisors -------------------------------------------------------------------------------------

## Repair a machine: how broken it is × its heat weight, ×2 offline, more as the alarm rises (0, 1, 2),
## divided down a little by the walk.
static func repair(heat_weight: float, health: float, offline: bool, alarm: int, path_time: float) -> float:
	if (health >= 100.0 and not offline) or path_time == INF:
		return 0.0
	var value := (100.0 - health) / 100.0 * heat_weight / MAX_HEAT_WEIGHT
	if offline:
		value = maxf(value, 0.5) * 2.0
	value *= 1.0 + 0.5 * clampi(alarm, 0, 2)
	return clampf(0.15 + 0.75 * clampf(value, 0.0, 1.0) * travel_factor(path_time, REPAIR_TRAVEL_HALF_S), 0.0, 0.9)


## Chase a rat `distance` m away: very worth it while it sabotages (it stands still), hardly when it
## runs away already far (rats are faster), less when only heard.
static func chase(distance: float, chase_radius: float, busy: bool, fleeing_far: bool, visible: bool) -> float:
	if distance > chase_radius:
		return 0.0
	var s := 0.85 if busy else (0.12 if fleeing_far else 0.3 + 0.4 * (1.0 - distance / chase_radius))
	return s if visible else s * 0.7


## Grab a stunned rat, but only if a cage is reachable before it wriggles free.
static func capture(stunned: bool, cage_seconds: float, carry_max_s: float, spare_s: float) -> float:
	if not stunned or cage_seconds == INF or cage_seconds + spare_s > carry_max_s:
		return 0.0
	return 0.95


## Watch over caged rats.
static func guard_cages(occupants: int) -> float:
	return 0.0 if occupants <= 0 else minf(0.25 + 0.08 * occupants, 0.45)


## Walk the machine rooms: the most valuable one not visited for longest.
static func patrol(heat_weight: float, since_visit_s: float, revisit_s: float) -> float:
	return PATROL_BASE + 0.15 * clampf(since_visit_s / maxf(revisit_s, 1.0), 0.0, 1.0) * heat_weight / MAX_HEAT_WEIGHT
