class_name StatusRules
extends RefCounted
## The status rules (GDD §5.4) as pure logic: no nodes, no network, so GUT can test them.
## StatusComponent wraps it on the server and publishes the result. Times (`now`) are seconds
## on the caller's clock.
##
## Rules:
##   - each status has an expiry time (INF = until cleared); re-applying extends it, except
##     STUNNED and KNOCKED_DOWN, which can't be re-applied while active (no stun-lock chains)
##   - STUNNED, KNOCKED_DOWN and bites are ignored while INVULNERABLE
##   - when a stun ends, the body is immune to stuns for `stun_immunity_s` (rats: 1.5 s);
##     when a knockdown ends, immune to knockdowns for `knockdown_immunity_s` (supervisors: 3 s)
##   - speed factors come from named sources and multiply; the slows (< 1) together never go
##     below SLOW_FLOOR, boosts (> 1) apply on top. SLOWED / BOOSTED follow the active factors.
##   - bites: each one slows; `knockdown_bites` bites within `knockdown_window_s` knock down.
##     Bites on a knocked-down body are ignored; bites during knockdown immunity slow but don't count.

## Statuses that stop movement and actions.
const BLOCKING: Array[StatusComponent.Status] = [
	StatusComponent.Status.LOCKED, StatusComponent.Status.STUNNED, StatusComponent.Status.KNOCKED_DOWN,
	StatusComponent.Status.CARRIED, StatusComponent.Status.CAGED, StatusComponent.Status.ELIMINATED,
]
const SLOW_FLOOR := 0.4

## Bite outcomes.
enum Bite { IGNORED, SLOWED, KNOCKED_DOWN }

var stun_immunity_s := 0.0
var knockdown_immunity_s := 0.0

var _expiry: Dictionary[int, float] = {}  # status -> expiry (INF = until cleared)
var _immune_until: Dictionary[int, float] = {}  # status -> end of its immunity window
var _speed: Dictionary[StringName, Vector2] = {}  # source -> (factor, expiry)
var _bites: Array[float] = []  # times of the bites that count toward a knockdown


func has(status: StatusComponent.Status, now: float) -> bool:
	return _expiry.has(status) and _expiry[status] > now


## Turns `status` on for `duration` seconds. Returns false if a rule refused it.
func apply(status: StatusComponent.Status, duration: float, now: float) -> bool:
	if status == StatusComponent.Status.STUNNED or status == StatusComponent.Status.KNOCKED_DOWN:
		if has(StatusComponent.Status.INVULNERABLE, now) or has(status, now) or is_immune(status, now):
			return false
	var until := now + duration
	_expiry[status] = maxf(until, _expiry.get(status, -INF))
	return true


## Turns `status` off now (an ended stun or knockdown starts its immunity window).
func clear(status: StatusComponent.Status, now: float) -> void:
	if _expiry.has(status):
		_end(status, now)


## True while `status` can't be applied because one just ended.
func is_immune(status: StatusComponent.Status, now: float) -> bool:
	return _immune_until.get(status, -INF) > now


## A named speed factor (bite slow 0.7, donut 1.2…) for `duration` seconds. Same source = replaced.
func set_speed_factor(source: StringName, factor: float, duration: float, now: float) -> void:
	_speed[source] = Vector2(factor, now + duration)


func clear_speed_factor(source: StringName) -> void:
	_speed.erase(source)


## Every active factor multiplied: slows floored at SLOW_FLOOR, then boosts on top.
func speed_factor(now: float) -> float:
	var slows := 1.0
	var boosts := 1.0
	for entry: Vector2 in _speed.values():
		if entry.y <= now:
			continue
		if entry.x < 1.0:
			slows *= entry.x
		else:
			boosts *= entry.x
	return maxf(slows, SLOW_FLOOR) * boosts


## One bite at `now`: slows by `slow_factor` for `slow_s`, and knocks down for `knockdown_s` on
## the `knockdown_bites`-th bite within `window_s`.
func bite(now: float, slow_factor: float, slow_s: float, knockdown_bites: int, window_s: float,
		knockdown_s: float) -> Bite:
	if has(StatusComponent.Status.INVULNERABLE, now) or has(StatusComponent.Status.KNOCKED_DOWN, now):
		return Bite.IGNORED
	set_speed_factor(&"bite", slow_factor, slow_s, now)
	if is_immune(StatusComponent.Status.KNOCKED_DOWN, now):
		return Bite.SLOWED
	_bites = _bites.filter(func(t: float) -> bool: return now - t < window_s)
	_bites.append(now)
	if _bites.size() >= knockdown_bites and apply(StatusComponent.Status.KNOCKED_DOWN, knockdown_s, now):
		_bites.clear()
		return Bite.KNOCKED_DOWN
	return Bite.SLOWED


## Removes what expired. Returns the statuses that ended (for the "ended" signals).
func tick(now: float) -> Array[StatusComponent.Status]:
	var ended: Array[StatusComponent.Status] = []
	for status: int in _expiry.keys():
		if _expiry[status] <= now:
			_end(status as StatusComponent.Status, _expiry[status])
			ended.append(status as StatusComponent.Status)
	for source: StringName in _speed.keys():
		if _speed[source].y <= now:
			_speed.erase(source)
	return ended


## The bitmask of active statuses (bit i = Status i), including SLOWED / BOOSTED from the factors.
func flags(now: float) -> int:
	var bits := 0
	for status: int in _expiry:
		if _expiry[status] > now:
			bits |= 1 << status
	for entry: Vector2 in _speed.values():
		if entry.y > now:
			bits |= 1 << (StatusComponent.Status.SLOWED if entry.x < 1.0 else StatusComponent.Status.BOOSTED)
	return bits


## Forget everything (a new body, a new match).
func reset() -> void:
	_expiry.clear()
	_immune_until.clear()
	_speed.clear()
	_bites.clear()


static func blocks_actions(bits: int) -> bool:
	for status in BLOCKING:
		if bits & (1 << status) != 0:
			return true
	return false


func _end(status: StatusComponent.Status, at: float) -> void:
	_expiry.erase(status)
	if status == StatusComponent.Status.STUNNED and stun_immunity_s > 0.0:
		_immune_until[status] = at + stun_immunity_s
	elif status == StatusComponent.Status.KNOCKED_DOWN and knockdown_immunity_s > 0.0:
		_immune_until[status] = at + knockdown_immunity_s
