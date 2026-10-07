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
## hazard line, less the more `danger` (0..1, AiContext.danger_at: a known supervisor close to the
## point), divided down by the walk.
static func sabotage(heat_weight: float, health: float, damage: float, path_time: float, danger: float) -> float:
	if health <= 0.0 or path_time == INF:
		return 0.0
	var value := heat_weight / MAX_HEAT_WEIGHT * health / 100.0
	if health - damage < HAZARD_LINE:
		value *= 1.5
	return clampf((0.2 + 0.7 * value * travel_factor(path_time)) * careful(danger), 0.0, 0.9)


## How much a rat still wants a target with `danger` (0..1) around it: a supervisor right there
## takes most of the appeal away.
static func careful(danger: float) -> float:
	return 1.0 - 0.85 * clampf(danger, 0.0, 1.0)


## A critical lever pair: worth twice a sabotage (100 damage), times how likely a partner is
## (1 = one is waiting, about 0.6 = a free teammate could come, 0 = nobody).
static func lever_pair(heat_weight: float, health: float, path_time: float, partner: float, danger: float = 0.0) -> float:
	if health <= 0.0 or path_time == INF or partner <= 0.0:
		return 0.0
	var value := heat_weight / MAX_HEAT_WEIGHT * health / 100.0 * 1.5
	return clampf((0.2 + 0.7 * value * travel_factor(path_time)) * minf(partner, 1.2) * careful(danger), 0.0, 0.9)


## Flee from a supervisor `distance` m away: only when it is closing in, or a broom swing was heard.
static func flee(distance: float, closing: bool, flee_radius: float, broom_heard: bool) -> float:
	if broom_heard and distance < flee_radius * 1.5:
		return 0.92
	if distance >= flee_radius or not closing:
		return 0.0
	return 0.76 + 0.16 * (1.0 - clampf(distance / flee_radius, 0.0, 1.0))  # (a reflex: it interrupts at once)


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


# --- Phase E: supervisors ------------------------------------------------------------------------

## Lay a trap at a spot worth `value` (0..1: the machine's heat weight, a vent exit), `path_time` away.
static func place_trap(value: float, path_time: float, charges: int) -> float:
	if charges <= 0 or path_time == INF:
		return 0.0
	return 0.16 + 0.2 * clampf(value, 0.0, 1.0) * travel_factor(path_time, 20.0)


## Refill a kind of trap at its box in Storage: only once it is all used and the plant is calm.
static func refill(charges: int, calm: bool, path_time: float) -> float:
	if charges > 0 or not calm or path_time == INF:
		return 0.0
	return 0.12 + 0.12 * travel_factor(path_time, 30.0)


## Go and look at a spot `distance` m away: "snap" (a trap went off: a stunned rat), "rat" (heard,
## called out or seen on the CCTV; `busy`: it was sabotaging) or "search" (an old trace).
static func investigate(kind: String, distance: float, radius: float, busy: bool = false) -> float:
	if distance > radius or is_nan(distance):
		return 0.0
	var near := 1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0)
	match kind:
		"snap":
			return 0.6 + 0.25 * near
		"rat":
			return (0.4 if busy else 0.26) + 0.14 * near
		"search":
			return 0.1 + 0.08 * near
	return 0.0


## A supervisor without its keycard: pick up a dropped one (better), or the spare once it is ready.
static func keycard(dropped: bool, spare_ready: bool, path_time: float) -> float:
	if path_time == INF or not (dropped or spare_ready):
		return 0.0
	return (0.3 if dropped else 0.15) + 0.15 * travel_factor(path_time, 20.0)


## Eat a donut: ready, and `detour_m` out of the way at most `max_detour_m`.
static func donut(ready: bool, detour_m: float, max_detour_m: float) -> float:
	if not ready or detour_m > max_detour_m or is_nan(detour_m):
		return 0.0
	return 0.3 + 0.12 * (1.0 - clampf(detour_m / maxf(max_detour_m, 1.0), 0.0, 1.0))


## Sit at the CCTV: only when the plant is calm, the chair free, and not again too soon.
static func cctv(calm: bool, free: bool, rested: bool, path_time: float) -> float:
	if not (calm and free and rested) or path_time == INF:
		return 0.0
	return 0.1 + 0.08 * travel_factor(path_time, 20.0)


## Fix a broken camera: worth more when it is on the way.
static func fix_camera(path_time: float) -> float:
	return 0.0 if path_time == INF else 0.12 + 0.2 * travel_factor(path_time, 10.0)


## Emergency coolant (core_temp −150): when the core runs hotter than `threshold`.
static func coolant(core_temp: float, threshold: float, usable: bool, path_time: float) -> float:
	if not usable or core_temp <= threshold or path_time == INF:
		return 0.0
	return clampf(0.62 + (core_temp - threshold) / 400.0, 0.62, 0.9) * (0.85 + 0.15 * travel_factor(path_time, 20.0))


## SCRAM (heat ×0.5 for 30 s, but +30 s of shift): only when it's critical.
static func scram(core_temp: float, meltdown: float, temp_threshold: float, meltdown_threshold: float,
		usable: bool, path_time: float) -> float:
	if not usable or path_time == INF or (core_temp <= temp_threshold and meltdown <= meltdown_threshold):
		return 0.0
	return 0.86 * (0.85 + 0.15 * travel_factor(path_time, 20.0))


# --- Phase E: rats -------------------------------------------------------------------------------

## Steal the keycard of a supervisor `distance` m away: only one that stands still, faces away and
## still has it.
static func steal(distance: float, radius: float, still: bool, facing_away: bool, has_keycard: bool) -> float:
	if not (still and facing_away and has_keycard) or distance > radius:
		return 0.0
	return 0.4 + 0.26 * (1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0))


## Break a camera `path_time` away (on the way): much more while a supervisor watches the CCTV.
static func break_camera(path_time: float, half_s: float, watched: bool, danger: float = 0.0) -> float:
	if path_time == INF:
		return 0.0
	return (0.14 + (0.34 if watched else 0.0)) * travel_factor(path_time, half_s) * careful(danger)


## Bite a supervisor together: `members` rat bots (this one included) are close to it.
static func gang(members: int, knocked: bool, teamwork: bool) -> float:
	if not teamwork or knocked or members < 2:
		return 0.0
	return minf(0.72 + 0.05 * (members - 2), 0.85)
