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

enum Move { IDLE, MOVING, ARRIVED, FAILED }
enum Hold { NONE, SETTLING, HOLDING, ENDED }

const REPATH_MOVED := 0.75  ## m: a destination that moved this much gets a new path…
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
	if hold_state in [Hold.SETTLING, Hold.HOLDING]:
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


## A door sliding open in front of us isn't being stuck.
func _grace_near_doors(pos: Vector3) -> void:
	for door in ctx.world.doors:
		if not door.is_fully_open() and _flat(door.global_position - pos).length() < DOOR_NEAR:
			stuck.grace(ctx.now + ctx.tuning.door_grace_s)
			return


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
