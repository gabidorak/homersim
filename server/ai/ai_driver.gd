class_name AiDriver
extends RefCounted
## An AI bot's hands and feet (M10, ARCHITECTURE §6 AI bots). Goals ask for actions; every physics
## tick the driver turns them into the body's MoveIntent (read by MovementComponent right after) and
## into the same server calls a player's requests end in. The actions:
##   go_to(pos)         walk (or sprint) there along an AiNav path (AiPathFollower), with keycard
##                      doors (press the reader, then cross while it's open) and stuck handling
##   face(pos)          turn toward a point this tick, at the skill's turn rate
##   hold(target)       stop, wait until slower than hold_still_speed (a hold cancels after 0.5 m),
##                      InteractionService.ai_start, then a heartbeat every HEARTBEAT_S until the
##                      hold ends (hold_state, hold_reason)
##   press(target)      an instant interaction ("" = done, else why not)
##   use(id, aim)       AbilityService.ai_use; place_trap(id, spot) ItemService.ai_place_trap
##   emote()            the squeak everyone sees (sync_anim FLAG_EMOTE)
##   stand_up()         CctvConsole.stand_up
## It also fills Player.sync_anim (AnimationController.flags_for), so bot bodies animate on clients.
## Bots never teleport: when stuck they jump, sidestep, repath, and after stuck_fail_s give up
## (move_state FAILED, logged by AiDirector.log_stuck). A bot on a scrap of mesh that leads nowhere
## (the top of a duct or a crate it jumped onto) walks off it before planning again.
## Hazards (AiHazards, phase E), whatever the goal: a bot waits at the edge of a steam jet or a
## puddle that is live (or about to be), never starts a hold inside one, steps away from a debris
## warning circle (a hold in progress ends with hold_reason "dodged"), and leaves the radiation zone
## once its exposure passes radiation_limit_s unless it is just walking through. Rats walk around the
## traps they noticed (a waypoint beside the trap).

enum Move { IDLE, MOVING, ARRIVED, FAILED }
enum Hold { NONE, SETTLING, HOLDING, ENDED }

const REPATH_MOVED := 0.75  ## m: a destination that moved this much gets a new path at once…
const REPATH_NUDGED := 0.5  ## …and one that moved this much at the next chance
const REPATH_MIN_S := 0.3  ## …at most this often
const ARRIVE_DY := 1.2  ## m of height difference still counted as arrived
const SETTLE_MAX_S := 1.5  ## a hold starts after this even if the body still drifts a little
const READER_PRESS_EVERY_S := 0.8
const SIDESTEP_S := 0.5
const DOOR_NEAR := 2.5  ## m: an auto door this close and not fully open grants a stuck grace
const VENT_CHECK_S := 0.2
const MAX_END_GAP := 1.0  ## m: a path ending this far from the destination still reaches it
const MAX_END_RISE := 0.6  ## m: …and this close in height (not on a prop above or below it)
const ESCAPE_S := 1.0  ## walking off a scrap of mesh: this long in one direction, then plan again
const MAX_ESCAPES := 4
const HAZARD_LOOKAHEAD := 0.9  ## m ahead of a moving bot checked for a live jet or puddle
const DODGE_EARLY_S := 1.3  ## step away from debris landing sooner than this…
const DODGE_AFTER_S := 0.25  ## …and keep away this long after the impact
const RADIATION_PASSING_S := 2.0  ## walking through may take this much longer than the limit
const TRAP_DETOURS := 4  ## at most this many waypoints around traps per path
const HAZARD_CHECK_S := 0.1  ## hazards, the jets ahead and the doors are looked at this often

var ctx: AiContext
var intent := MoveIntent.new()
var follower := AiPathFollower.new()
var stuck := AiPathFollower.Stuck.new()

var move_state := Move.IDLE
var fail_reason := ""
var destination := Vector3.INF
var hold_state := Hold.NONE
var hold_reason := ""
var hold_target: Interactable
var distance := 0.0  ## metres walked (report)
var path_failures := 0

var _radius := 0.5
var _sprint := false
var _keycard_path := false
var _repath_at := 0.0
var _dirty := false  # the destination moved: a new path is due
var _path_doors: Array = []  # per segment: the Door of a keycard link, else null
var _face_point := Vector3.INF
var _sidestep_until := 0.0
var _sidestep_dir := Vector3.ZERO
var _settle_since := 0.0
var _next_beat := 0.0
var _next_reader_press := 0.0
var _emote_until := 0.0
var _vent_check := 0.0
var _in_vent := false
var _last_pos := Vector3.INF
var _end_retries := 0
var _escape_until := 0.0
var _escape_dir := Vector3.ZERO
var _escapes := 0
var _dodge_until := 0.0  # debris coming down, or leaving the radiation zone: walk _dodge_dir until then
var _dodge_dir := Vector3.ZERO
var _dodge_from := Vector3.INF  # the debris impact we step away from (INF: just walk _dodge_dir)
var _dodge_clear := 0.0
var _exposure := 0.0  ## seconds of radiation exposure (the server's model, estimated the same way)
var hazard_waits := 0  ## times this bot waited for a jet or a puddle (report)
var _traps_planned := 0  # rats: how many noticed traps the current path went around
var _waiting_hazard := false
var _hazard_check := 0.0  # until the next look at hazards and doors (HAZARD_CHECK_S)
var _hazard_dt := 0.0  # time since the last look (radiation exposure)
var _blocked_ahead := false
var _looking := false  # this tick looks at hazards and doors


func setup(p_ctx: AiContext) -> void:
	ctx = p_ctx
	intent.turn_rate = deg_to_rad(ctx.skill.turn_rate_deg)
	follower.arrive_radius = ctx.tuning.arrive_rat if ctx.role == Role.Kind.RAT else ctx.tuning.arrive_supervisor
	follower.slow_radius = ctx.tuning.slow_radius
	stuck.check_s = ctx.tuning.stuck_check_s
	stuck.min_progress = ctx.tuning.stuck_min_progress
	stuck.fail_s = ctx.tuning.stuck_fail_s


# --- Actions ---------------------------------------------------------------------------------

## Walk to `pos` (sprint if `sprint`), arriving within `radius` (flat metres). Call it every tick
## with the same or an updated point: the path is only recomputed when the point moved.
func go_to(pos: Vector3, sprint: bool = false, radius: float = 0.5) -> void:
	_sprint = sprint
	_radius = radius
	if hold_state in [Hold.SETTLING, Hold.HOLDING]:
		return  # finish (or stop) the hold first
	var moved := destination == Vector3.INF or destination.distance_to(pos) > REPATH_MOVED
	if not moved and move_state != Move.IDLE:
		if destination.distance_to(pos) > REPATH_NUDGED and move_state == Move.MOVING:
			destination = pos  # (a stand spot moved beside a trap, a target edging away)
			_dirty = true
		return  # the same place: walking there, there already, or given up on it (the goal decides)
	var was_moving := move_state == Move.MOVING
	destination = pos
	move_state = Move.MOVING
	fail_reason = ""
	_end_retries = 0
	_escapes = 0
	_dirty = true
	if not was_moving:
		stuck.reset(ctx.now)
	if not was_moving or ctx.now >= _repath_at:
		_repath()


func arrived() -> bool:
	return move_state == Move.ARRIVED


func failed() -> bool:
	return move_state == Move.FAILED


## Stop walking (the destination is forgotten).
func stop() -> void:
	move_state = Move.IDLE
	destination = Vector3.INF
	follower.clear()


## Turn toward `pos` this tick.
func face(pos: Vector3) -> void:
	_face_point = pos


## Start holding `target` (stops walking first). Watch hold_state: ENDED with hold_reason
## "completed" is a success.
func hold(target: Interactable) -> void:
	if hold_target == target and hold_state in [Hold.SETTLING, Hold.HOLDING]:
		return
	stop_hold()
	stop()
	hold_target = target
	hold_state = Hold.SETTLING
	hold_reason = ""
	_settle_since = ctx.now


## Let go of the current hold (if any).
func stop_hold() -> void:
	if hold_state == Hold.HOLDING:
		ctx.session.interactions.ai_stop(ctx.peer)
	hold_state = Hold.NONE
	hold_target = null


func holding() -> bool:
	return hold_state in [Hold.SETTLING, Hold.HOLDING]


## An instant interaction (grab, cage, pickups, readers, consoles): "" = done, else why not.
func press(target: Interactable) -> String:
	return ctx.session.interactions.ai_start(ctx.peer, target)


## AbilityService.ai_use: "" = used, else why not.
func use(id: StringName, aim: Vector3) -> String:
	return ctx.session.abilities.ai_use(ctx.peer, id, aim)


func place_trap(id: StringName, spot: Vector3) -> String:
	return ctx.session.items.ai_place_trap(ctx.peer, id, spot)


## The emote (a rat's squeak): everyone sees and hears it through sync_anim.
func emote() -> void:
	if ctx.now >= _emote_until + 0.4:
		_emote_until = ctx.now + AnimationController.EMOTE_S


## In a vent right now (rats; checked every VENT_CHECK_S).
func in_vent() -> bool:
	return _in_vent


func stand_up() -> void:
	var console := ctx.body.seated_console()
	if console != null:
		console.stand_up(ctx.peer)


## InteractionService.hold_ended, for this bot (AiBot forwards it).
func on_hold_ended(path: NodePath, reason: String) -> void:
	if hold_target == null or not is_instance_valid(hold_target) or hold_target.get_path() != path:
		return  # about an older hold
	if hold_state in [Hold.SETTLING, Hold.HOLDING]:
		hold_state = Hold.ENDED
		hold_reason = reason


## Everything stops (the match ended, the body can't act…).
func halt() -> void:
	stop_hold()
	stop()
	intent.stop()


# --- Every tick ------------------------------------------------------------------------------

func tick(_delta: float) -> void:
	var body := ctx.body
	var pos := body.global_position
	if _last_pos != Vector3.INF:
		distance += minf(pos.distance_to(_last_pos), 1.0)  # (a server-imposed move isn't walking)
	_last_pos = pos
	intent.jump = false
	_hazard_check -= _delta
	_hazard_dt += _delta
	_looking = _hazard_check <= 0.0
	if _looking:
		_hazard_check = HAZARD_CHECK_S
		_watch_hazards(pos, _hazard_dt)
		_hazard_dt = 0.0
	if ctx.now < _dodge_until and ctx.can_act():
		# Out of the warning circle: wait there until the debris has landed.
		var out := _dodge_from != Vector3.INF and _flat(pos - _dodge_from).length() > _dodge_clear
		intent.direction = Vector3.ZERO if out else _dodge_dir
		intent.sprint = not out
		stuck.reset(ctx.now)
	elif hold_state in [Hold.SETTLING, Hold.HOLDING]:
		intent.stop()
		_tick_hold()
	elif move_state == Move.MOVING and ctx.can_act():
		_tick_move(pos)
	else:
		intent.stop()
		stuck.reset(ctx.now)
	if _face_point != Vector3.INF:
		var to := _face_point - pos
		if Vector2(to.x, to.z).length() > 0.05:
			intent.face_yaw = atan2(-to.x, -to.z)
		if body.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON:
			var eye := pos + Vector3.UP * (body.role_data.height - 0.2)
			var d := _face_point - eye
			body.rig.apply_look_pitch(clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2))
	else:
		intent.face_yaw = NAN
	_face_point = Vector3.INF
	_vent_check -= _delta
	if _vent_check <= 0.0:
		_vent_check = VENT_CHECK_S
		_in_vent = body.role == Role.Kind.RAT and VentVolume.contains(body)
	body.sync_anim = AnimationController.flags_for(body, hold_state == Hold.HOLDING, ctx.now < _emote_until, _in_vent)


func _tick_hold() -> void:
	var body := ctx.body
	if not is_instance_valid(hold_target):
		hold_state = Hold.ENDED
		hold_reason = "gone"
		return
	_face_point = hold_target.global_position
	if hold_state == Hold.SETTLING:
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if (speed > ctx.tuning.hold_still_speed or not body.is_on_floor()) and ctx.now - _settle_since < SETTLE_MAX_S:
			return
		if ctx.world.hazards.blocking(body.global_position, ctx.tuning.hazard_cross_s) != null:
			_settle_since = ctx.now  # never start a hold in a live jet or puddle: wait for its off phase
			return
		var reason := ctx.session.interactions.ai_start(ctx.peer, hold_target)
		if reason != "":
			hold_state = Hold.ENDED
			hold_reason = "refused: %s" % reason
		elif hold_target.kind_for(body) == "instant":
			hold_state = Hold.ENDED
			hold_reason = "completed"
		elif hold_state == Hold.SETTLING:  # (an instant completion may have ended it already)
			hold_state = Hold.HOLDING
			_next_beat = ctx.now + InteractionService.HEARTBEAT_S
		return
	if ctx.now >= _next_beat:
		_next_beat = ctx.now + InteractionService.HEARTBEAT_S
		ctx.session.interactions.ai_heartbeat(ctx.peer)


func _tick_move(pos: Vector3) -> void:
	if _arrived_at(pos):
		move_state = Move.ARRIVED
		intent.stop()
		stuck.reset(ctx.now)
		return
	if ctx.now < _escape_until:
		# Walking off a scrap of mesh: straight on (jumping at walls), then plan again.
		intent.direction = _escape_dir
		intent.sprint = false
		intent.jump = ctx.body.is_on_wall()
		if ctx.now + ctx.body.get_physics_process_delta_time() >= _escape_until:
			_dirty = true
		return
	if ctx.role == Role.Kind.RAT and ctx.senses.traps_noticed.size() != _traps_planned:
		_dirty = true  # a trap we just noticed may be on the way
	if _dirty and ctx.now >= _repath_at:
		_repath()
	if move_state != Move.MOVING:
		return
	# Keycard doors: stop at the link's start, press the reader, cross once it's open.
	if follower.current_link() == AiPathFollower.LinkKind.KEYCARD:
		var door := _path_doors[follower.index - 1] as Door if follower.index - 1 < _path_doors.size() else null
		if door != null and not door.is_fully_open():
			intent.stop()
			stuck.reset(ctx.now)
			if not ctx.has_keycard():
				_repath()  # lost the keycard on the way: around, without keycard doors
				return
			if not door.open and ctx.now >= _next_reader_press:
				_next_reader_press = ctx.now + READER_PRESS_EVERY_S
				var reader := _reader_on_our_side(door, pos)
				if reader != null:
					_face_point = reader.global_position
					press(reader)
			return
	var body := ctx.body
	var flat_speed := Vector2(body.velocity.x, body.velocity.z).length()
	var blocked := body.is_on_wall() and flat_speed < 0.5
	var steer := follower.steer(pos, ctx.now, body.is_on_floor(), blocked)
	var dir: Vector3 = steer["dir"]
	if follower.is_done():
		if _flat(pos - destination).length() <= maxf(_radius, MAX_END_GAP) and absf(pos.y - destination.y) < ARRIVE_DY:
			move_state = Move.ARRIVED
			intent.stop()
			return
		_end_retries += 1
		if _end_retries > 3:
			_fail("the path ends short of it")
			return
		_repath()
		return
	dir = _avoid_teammates(pos, dir)
	if ctx.now < _sidestep_until:
		dir = _sidestep_dir
	if _looking:
		_blocked_ahead = _hazard_ahead(pos, dir)
	if _blocked_ahead:
		intent.stop()
		stuck.reset(ctx.now)
		return
	_grace_near_doors(pos)
	match stuck.sample(pos, ctx.now):
		AiPathFollower.Unstick.JUMP:
			intent.jump = true
		AiPathFollower.Unstick.SIDESTEP:
			var side := Vector3(-dir.z, 0.0, dir.x) * (1.0 if ctx.rng.randf() < 0.5 else -1.0)
			_sidestep_dir = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
			_sidestep_until = ctx.now + SIDESTEP_S
			intent.jump = true
		AiPathFollower.Unstick.REPATH:
			_repath(true)
		AiPathFollower.Unstick.FAIL:
			ctx.director.log_stuck(ctx.bot, "no progress for %.0f s" % ctx.tuning.stuck_fail_s)
			ctx.bot.stats["stuck_hard"] += 1
			_fail("stuck")
			return
	intent.direction = dir
	intent.sprint = _sprint and steer["sprint_ok"]
	intent.jump = intent.jump or steer["jump"]


func _arrived_at(pos: Vector3) -> bool:
	return _flat(pos - destination).length() <= _radius and absf(pos.y - destination.y) < ARRIVE_DY


func _fail(reason: String) -> void:
	move_state = Move.FAILED
	fail_reason = reason
	follower.clear()
	intent.stop()
	ctx.log_line("can't get to %s from %s: %s" % [destination.snapped(Vector3.ONE * 0.1),
		ctx.body.global_position.snapped(Vector3.ONE * 0.1), reason])


## A new path to the destination. `from_mesh`: start from the closest point of the navigation mesh
## (stuck: we may be standing just off it).
func _repath(from_mesh: bool = false) -> void:
	_repath_at = ctx.now + REPATH_MIN_S
	_dirty = false
	var from := ctx.body.global_position
	if from_mesh:
		from = ctx.nav.closest_point(ctx.role, from)
	_keycard_path = ctx.has_keycard()
	var path := ctx.nav.path(ctx.role, from, destination, _keycard_path)
	if not _reaches(path) and not from_mesh:
		# We may stand on a scrap of mesh cut off from the rest (a prop, a duct's lip): from the
		# closest point of the mesh instead, which the follower walks to first.
		path = ctx.nav.path(ctx.role, ctx.nav.closest_point(ctx.role, from), destination, _keycard_path)
	if not _reaches(path):
		path_failures += 1
		if _escapes < MAX_ESCAPES and _on_a_scrap(from):
			# We're on a bit of mesh cut off from the rest: walk off it, then try again.
			_escapes += 1
			var away := _flat(destination - from).normalized()
			_escape_dir = (away if away != Vector3.ZERO else Vector3.FORWARD).rotated(Vector3.UP, PI * 0.5 * (_escapes - 1))
			_escape_until = ctx.now + ESCAPE_S
			follower.clear()
			ctx.log_line("off a scrap of mesh at %s, walking off it" % from.snapped(Vector3.ONE * 0.1))
			return
		_fail("no path")
		return
	if ctx.role == Role.Kind.RAT:
		_traps_planned = ctx.senses.traps_noticed.size()
		_around_traps(path)
	var kinds := PackedInt32Array()
	var ups := PackedVector3Array()
	var feet := PackedVector3Array()
	_path_doors.clear()
	for link: AiNav.Link in path.links:
		kinds.append(link.kind if link != null else AiPathFollower.LinkKind.NONE)
		ups.append(link.up if link != null else Vector3.ZERO)
		feet.append(link.foot if link != null else Vector3.ZERO)
		_path_doors.append(link.door if link != null else null)
	follower.set_path(path.points, kinds, ups, feet)


func _reaches(path: AiNav.Path) -> bool:
	return not path.is_empty() and _flat(path.end() - destination).length() <= MAX_END_GAP + _radius \
		and absf(path.end().y - destination.y) <= MAX_END_RISE


## True when `from` can't reach the role's spawn (which reaches everything): a scrap of mesh.
func _on_a_scrap(from: Vector3) -> bool:
	var anchor := ctx.director.anchor(ctx.role)
	var path := ctx.nav.path(ctx.role, ctx.nav.closest_point(ctx.role, from), anchor, ctx.has_keycard())
	return path.is_empty() or path.end().distance_to(anchor) > 1.5


func _reader_on_our_side(door: Door, pos: Vector3) -> KeycardReader:
	var best: KeycardReader = null
	var best_d := INF
	for child in door.get_children():
		var reader := child as KeycardReader
		if reader != null and reader.global_position.distance_to(pos) < best_d:
			best_d = reader.global_position.distance_to(pos)
			best = reader
	return best


## Local avoidance, kept simple: a teammate within avoid_radius ahead shifts us avoid_shift sideways.
func _avoid_teammates(pos: Vector3, dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.01:
		return dir
	var forward := dir.normalized()
	for mate in ctx.teammates():
		var to := _flat(mate.global_position - pos)
		if to.length() > ctx.tuning.avoid_radius or to.length() < 0.01 or forward.dot(to.normalized()) < 0.5:
			continue
		var right := Vector3(-forward.z, 0.0, forward.x)
		var side := -1.0 if right.dot(to) > 0.0 else 1.0  # away from the teammate
		return (forward * maxf(to.length(), 0.3) + right * side * ctx.tuning.avoid_shift).normalized() * dir.length()
	return dir


## A door sliding open in front of us isn't being stuck (checked with the hazards, 10 times a second).
func _grace_near_doors(pos: Vector3) -> void:
	if not _looking:
		return
	for door in ctx.world.doors:
		if not door.is_fully_open() and _flat(door.global_position - pos).length() < DOOR_NEAR:
			stuck.grace(ctx.now + ctx.tuning.door_grace_s)
			return


# --- Hazards and traps (phase E) ---------------------------------------------------------------

## Debris warning circles and the radiation zone, every tick: they can interrupt any goal.
func _watch_hazards(pos: Vector3, delta: float) -> void:
	var hazards := ctx.world.hazards
	var zone := hazards.radiation_at(pos)
	_exposure = HazardRules.exposure_step(_exposure, zone != null, delta, hazards.tuning.radiation_exposure_s)
	if ctx.now < _dodge_until or not ctx.can_act():
		return
	var tuning := hazards.tuning
	var clear := tuning.debris_radius + ctx.tuning.debris_margin
	var impact := hazards.impact_near(pos, clear)
	if not impact.is_empty():
		var left := float(impact["at"]) - Net.server_time()
		if left < DODGE_EARLY_S:
			var away := _flat(pos - (impact["pos"] as Vector3))
			if away.length() < 0.1:
				away = Vector3(-sin(ctx.body.rotation.y), 0.0, -cos(ctx.body.rotation.y))
			_dodge(away.normalized(), maxf(left, 0.0) + DODGE_AFTER_S, "debris coming down")
			_dodge_from = impact["pos"]
			_dodge_clear = clear
			return
	if zone != null and _exposure >= ctx.tuning.radiation_limit_s:
		var passing := move_state == Move.MOVING and hold_state == Hold.NONE \
			and _exposure < ctx.tuning.radiation_limit_s + RADIATION_PASSING_S
		if not passing:
			var out := _flat(AiHazards.way_out(zone, pos) - pos)
			_dodge(out.normalized() if out.length() > 0.1 else Vector3.FORWARD, 0.5, "out of the radiation")


## Walk `dir` for `seconds`, whatever the goal wants (a hold in progress ends: "dodged").
func _dodge(dir: Vector3, seconds: float, why: String) -> void:
	if hold_state in [Hold.SETTLING, Hold.HOLDING]:
		if hold_state == Hold.HOLDING:
			ctx.session.interactions.ai_stop(ctx.peer)
		hold_state = Hold.ENDED
		hold_reason = "dodged"
	_dodge_dir = dir
	_dodge_until = ctx.now + seconds
	_dodge_from = Vector3.INF
	_dirty = true  # plan again from wherever we end up
	ctx.log_line(why)


## A live (or about to be) jet or puddle just ahead: wait at its edge. Already inside one: keep going.
func _hazard_ahead(pos: Vector3, dir: Vector3) -> bool:
	var hazards := ctx.world.hazards
	if hazards.cyclic.is_empty() or dir.length_squared() < 0.01:
		_waiting_hazard = false
		return false
	var cross := ctx.tuning.hazard_cross_s
	if hazards.blocking(pos, cross) != null:
		_waiting_hazard = false
		return false  # inside: get out
	var ahead := pos + _flat(dir).normalized() * HAZARD_LOOKAHEAD
	var waiting := hazards.blocking(ahead, cross) != null
	if waiting and not _waiting_hazard:
		hazard_waits += 1
		ctx.log_line("waiting for a hazard at %s" % ahead.snapped(Vector3.ONE * 0.1))
	_waiting_hazard = waiting
	return waiting


## Rats: a path segment that runs over a noticed trap gets a waypoint beside it (on the mesh). A trap
## on the destination itself is the goal's business (AiContext.stand_for picks another spot).
func _around_traps(path: AiNav.Path) -> void:
	var traps := ctx.senses.traps()
	if traps.is_empty():
		return
	var clear := ctx.tuning.trap_clearance
	var detours := 0
	var i := 0
	while i < path.points.size() - 1 and detours < TRAP_DETOURS:
		if path.links[i] != null:
			i += 1
			continue
		var a := path.points[i]
		var b := path.points[i + 1]
		var inserted := false
		for trap in traps:
			var t := trap.global_position
			if absf(t.y - a.y) > 1.0 or _flat(t - destination).length() < clear:
				continue
			var c := Geometry3D.get_closest_point_to_segment(t, a, b)
			if _flat(c - t).length() >= clear or _flat(c - a).length() < 0.05 or _flat(c - b).length() < 0.05:
				continue
			var along := _flat(b - a).normalized()
			var side := Vector3(-along.z, 0.0, along.x)
			if side.dot(_flat(c - t)) < 0.0:
				side = -side  # the side the path already leans to
			for offset in [side, -side]:
				var want: Vector3 = t + offset * (clear + 0.25)
				var spot := ctx.nav.closest_point(ctx.role, want)
				if _flat(spot - want).length() < 0.2 and absf(spot.y - t.y) < 0.6:
					path.points.insert(i + 1, spot)
					path.links.insert(i + 1, null)
					detours += 1
					inserted = true
					break
			if inserted:
				break
		if not inserted:
			i += 1


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
