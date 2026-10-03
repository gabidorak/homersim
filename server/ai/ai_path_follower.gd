class_name AiPathFollower
extends RefCounted
## Follows an AiNav path for one AI bot (M10). Pure logic: it is fed the body's position every tick
## and answers where to steer, whether to jump, and when the path is done, so GUT can test it with
## made-up positions (tests/unit/test_ai_path_follower.gd).
##   - A waypoint is reached within arrive_radius (0.3 m rats, 0.4 m supervisors) and MAX_DY in
##     height, or once the body is past it along the next segment.
##   - Ladders: line up with the ladder (its foot and up direction come with the link), push along
##     its up direction until the top, then keep going to step off. Down a ladder: walk off the top
##     along the ladder's line (MovementComponent climbs down while we push away from the wall),
##     then on to the bottom point.
##   - Drops: walk off. Keycard doors: the driver presses the reader first (the follower just
##     steers through).
##   - Steps: CharacterBody3D has no step-up, so jump when the next point is STEP_MIN..STEP_MAX
##     higher within STEP_REACH, or when the body is blocked against a wall. (Lower steps are tried
##     on foot first, jumping only if blocked: jumping at a duct's mouth landed rats on top of it.)
##   - No sprinting over the last slow_radius metres, and a gentle stop at the very end.
## Stuck (below) watches the progress and escalates: jump, sidestep, repath, then give up.

enum LinkKind { NONE, WALK, LADDER, DROP, KEYCARD }
enum Unstick { NONE, JUMP, SIDESTEP, REPATH, FAIL }

const MAX_DY := 1.0  ## m: a waypoint only counts as reached within this height
const PASSED_RADIUS := 1.0  ## m: a waypoint we went past (along the next segment) this close counts
const LINK_ARRIVE := 0.6  ## m (flat): the end of a ladder or a drop counts as reached this close
const LADDER_TOP_MARGIN := 0.3  ## m below the top: keep pushing into the ladder until then
const LADDER_ALIGN := 0.15  ## m off the ladder's line: walk to its foot first
const LADDER_APPROACH := 0.25  ## m in front of the ladder: where the climb starts
const LADDER_STEER := 2.0  ## how hard the steering pulls back onto the ladder's line
const LADDER_BOTTOM := 0.6  ## m above the bottom: the climb down is over, walk on
const STEP_MIN := 0.35  ## jump when the next point is this much higher…
const STEP_MAX := 1.4  ## …up to this…
const STEP_REACH := 1.5  ## …within this horizontal distance
const JUMP_COOLDOWN_S := 0.6
const STOP_RADIUS := 0.6  ## m: ease off the speed this close to the end


## Watches a bot's progress while it wants to move (M10 stuck handling). Every check_s, less than
## min_progress metres of movement escalates: JUMP, SIDESTEP (and jump), REPATH, and again, until
## fail_s without progress gives FAIL. Real progress (or a grace window, an opening door) resets it.
class Stuck:
	var check_s := 0.5
	var min_progress := 0.15
	var fail_s := 6.0
	var level := 0  ## checks in a row without progress
	var since := -1.0  ## when the progress stopped (-1 = it is progressing)

	var _last_pos := Vector3.INF
	var _next_check := 0.0
	var _grace_until := -INF

	func reset(now: float) -> void:
		level = 0
		since = -1.0
		_last_pos = Vector3.INF
		_next_check = now + check_s

	## No escalation before `until` (a door sliding open in front of the bot).
	func grace(until: float) -> void:
		_grace_until = maxf(_grace_until, until)

	## Seconds without progress so far (0 while progressing).
	func stalled_for(now: float) -> float:
		return 0.0 if since < 0.0 else now - since

	## Called every tick while the bot wants to move: what to do about being stuck (an Unstick),
	## at most once per check.
	func sample(pos: Vector3, now: float) -> int:
		if _last_pos == Vector3.INF:
			_last_pos = pos
			_next_check = now + check_s
			return Unstick.NONE
		if now < _next_check:
			return Unstick.NONE
		_next_check = now + check_s
		var moved := pos.distance_to(_last_pos)
		_last_pos = pos
		if moved >= min_progress or now < _grace_until:
			level = 0
			since = -1.0
			return Unstick.NONE
		if since < 0.0:
			since = now - check_s
		level += 1
		if now - since >= fail_s:
			return Unstick.FAIL
		return [Unstick.JUMP, Unstick.SIDESTEP, Unstick.REPATH][(level - 1) % 3]


var points := PackedVector3Array()
var kinds := PackedInt32Array()  ## per segment i (points[i] → points[i + 1]): a LinkKind
var ups := PackedVector3Array()  ## per segment: a ladder's up direction (else zero)
var feet := PackedVector3Array()  ## per segment: a ladder's foot (its node's position; else zero)
var index := 0  ## the waypoint we head for
var arrive_radius := 0.4
var slow_radius := 1.5

var _last_jump := -INF


## A new path. `p_kinds`, `p_ups` and `p_feet` have one entry per segment (they may be empty:
## plain walking).
func set_path(p_points: PackedVector3Array, p_kinds: PackedInt32Array = PackedInt32Array(),
		p_ups: PackedVector3Array = PackedVector3Array(), p_feet: PackedVector3Array = PackedVector3Array()) -> void:
	points = p_points
	var segments := maxi(points.size() - 1, 0)
	kinds = p_kinds.duplicate()
	kinds.resize(segments)
	ups = p_ups.duplicate()
	ups.resize(segments)
	feet = p_feet.duplicate()
	feet.resize(segments)
	index = 0


func clear() -> void:
	set_path(PackedVector3Array())


func is_done() -> bool:
	return index >= points.size()


func end() -> Vector3:
	return points[points.size() - 1] if not points.is_empty() else Vector3.INF


## The kind of the segment we are on (the one ending at the waypoint we head for).
func current_link() -> int:
	return kinds[index - 1] if index > 0 and index - 1 < kinds.size() else LinkKind.NONE


## The kind of the next segment, once the waypoint we head for is reached.
func next_link() -> int:
	return kinds[index] if index < kinds.size() else LinkKind.NONE


## Path metres left from `pos`.
func remaining(pos: Vector3) -> float:
	if is_done():
		return 0.0
	var left := pos.distance_to(points[index])
	for i in range(index, points.size() - 1):
		left += points[i].distance_to(points[i + 1])
	return left


## {"dir": Vector3 (flat, length 0..1), "sprint_ok": bool, "jump": bool, "link": LinkKind}.
## `blocked`: the body pushes against a wall without moving.
func steer(pos: Vector3, now: float, on_floor: bool, blocked: bool = false) -> Dictionary:
	_advance(pos)
	if is_done():
		return {"dir": Vector3.ZERO, "sprint_ok": false, "jump": false, "link": LinkKind.NONE}
	var target := points[index]
	var link := current_link()
	var dir := _flat(target - pos).normalized()
	if link == LinkKind.LADDER:
		dir = _ladder_dir(pos, target, on_floor)
	var jump := false
	if on_floor and link in [LinkKind.NONE, LinkKind.WALK] and now - _last_jump >= JUMP_COOLDOWN_S:
		var rise := target.y - pos.y
		if blocked or (rise >= STEP_MIN and rise <= STEP_MAX and _flat(target - pos).length() < STEP_REACH):
			jump = true
			_last_jump = now
	var left := remaining(pos)
	if index == points.size() - 1 and left < STOP_RADIUS:
		dir *= clampf(left / STOP_RADIUS, 0.3, 1.0)
	return {"dir": dir, "sprint_ok": left > slow_radius and link == LinkKind.NONE, "jump": jump, "link": link}


## On a ladder segment: where to push.
func _ladder_dir(pos: Vector3, target: Vector3, on_floor: bool) -> Vector3:
	var up := ups[index - 1]
	var foot := feet[index - 1]
	if up == Vector3.ZERO:
		return _flat(target - pos).normalized()
	var along := _flat(pos - foot)
	var lateral := along - up * along.dot(up)  # how far off the ladder's line we are
	if target.y > points[index - 1].y:  # going up
		if pos.y >= target.y - LADDER_TOP_MARGIN:
			return _flat(target - pos).normalized()  # at the top: step off
		if on_floor and lateral.length() > LADDER_ALIGN:
			return _flat(foot - up * LADDER_APPROACH - pos).normalized()  # line up at the foot first
		return (up - lateral * LADDER_STEER).normalized()
	if on_floor and pos.y <= target.y + LADDER_BOTTOM:
		return _flat(target - pos).normalized()  # down: walk on from the bottom
	# Off the top along the ladder, then climb down (pushing away from the wall) to the floor: pushing
	# sideways in the air would hang on to the ladder.
	return (-up - lateral * LADDER_STEER).normalized()


func _advance(pos: Vector3) -> void:
	while index < points.size() and _reached(pos, index):
		index += 1


func _reached(pos: Vector3, i: int) -> bool:
	var p := points[i]
	if absf(pos.y - p.y) >= MAX_DY:
		return false
	var flat := _flat(p - pos).length()
	var arriving := kinds[i - 1] if i > 0 and i - 1 < kinds.size() else LinkKind.NONE
	if arriving == LinkKind.LADDER or arriving == LinkKind.DROP:
		return flat < LINK_ARRIVE
	if flat < arrive_radius:
		return true
	# Went past it: closer than PASSED_RADIUS and already on the far side, along the next segment.
	# (Not at the end of the path, nor at the start of a link, which must be reached properly.)
	if i + 1 >= points.size() or kinds[i] != LinkKind.NONE or flat >= PASSED_RADIUS:
		return false
	return _flat(points[i + 1] - p).dot(_flat(pos - p)) > 0.0


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
