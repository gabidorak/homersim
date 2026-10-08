class_name MovementComponent
extends Node
## Character controller for every role: walk, sprint with stamina, jump (with coyote time and a
## jump buffer) and gravity, using the player's RoleData. Runs only on the owning client;
## BodySync replicates the result. WASD is relative to CameraRig.move_yaw(): where you look in
## first person, where the camera looks in third person (and the body turns to face its movement).
## An AI bot's body (M10) runs on the server instead, and reads `intent` (a MoveIntent the AI writes
## every tick) where a player's reads the keyboard: same physics, speeds and stamina.
##
## The server imposes movement through the RPCs at the bottom (freeze, teleport, knockback,
## hanging from a carrier's hand); for a bot it calls their do_* halves directly. Speed = role speed × status (slows, donut) × inventory (a
## stolen item); a supervisor carrying a rat walks at the role's carry speed and can't sprint.
##
## Gliding (glide_to(), owner): the body slides into a spot and turns to a yaw, eased in and out, unless
## the player moves (a rat settling in front of the sabotage box it started on).
##
## Ladders (Ladder volumes): pushing toward the ladder climbs, pushing away in the air climbs down,
## no input hangs on, jump lets go. Out of bounds (an OutOfBounds volume, or below KILL_Y): back to
## the last spot we stood on safely (sampled every SAFE_SAMPLE_S while on the floor).

const COYOTE_S := 0.1  ## you can still jump this long after walking off a ledge
const JUMP_BUFFER_S := 0.1  ## a jump pressed this long before landing still happens
const TURN_RATE := 12.0  ## third person: how fast the body turns toward its movement
const KILL_Y := -20.0  ## fell out of the world: back to the last safe spot
const SAFE_SAMPLE_S := 0.5  ## how often the last safe spot is remembered
const LADDER_GRAB_DOT := 0.3  ## how directly you must push toward / away from a ladder
const LADDER_SIDE_FACTOR := 0.5  ## horizontal speed while climbing, as a fraction of walking
const LADDER_JUMP_OFF := Vector3(0, 2.0, 0)  ## plus 3 m/s away from the ladder
const LADDER_REGRAB_S := 0.4  ## after jumping off, ignore ladders this long
const GLIDE_S := 0.35  ## a glide takes this long (longer if walking speed couldn't keep up)
const GLIDE_GIVE_UP_S := 0.3  ## blocked on the way: stop where we are this long after the end

@export var ground_accel := 12.0  ## how quickly velocity reaches the target speed
@export var air_accel := 3.0

var stamina: Stamina
var sprinting := false
## Server, AI bots (M10): what the bot wants this tick, read instead of the keyboard. null = keyboard.
var intent: MoveIntent
## Set by the server through set_locked(); the LOCKED status (countdown) freezes the body too.
var locked := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _since_on_floor := INF
var _since_jump_pressed := INF
var _last_safe := Vector3.ZERO  # where we last stood on the floor, inside the map
var _since_safe_sample := 0.0
var _since_jump_off := INF
var climbing := false  ## on a ladder right now (HUD, camera)
var _anchor: Node3D  # set by attach_to(): we are carried, the body follows this node
var _debug_speed := 1.0  # test-only: --debug-speed N (a fake speed hack for the validator)
var _debug_auto_move := false  # test-only: --auto-move (walk forward without input)
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.INF  # INF = not gliding
var _glide_from_yaw := 0.0
var _glide_yaw := 0.0
var _glide_s := 0.0  # how long this glide takes
var _glide_t := 0.0  # seconds into it

@onready var body: Player = get_parent()
@onready var status: StatusComponent = $"../StatusComponent"


func _ready() -> void:
	var data := body.role_data
	stamina = Stamina.new(data.stamina_s, data.stamina_regen_s, data.stamina_regen_delay_s)
	_last_safe = body.position
	set_physics_process(is_multiplayer_authority())
	if OS.is_debug_build():
		_debug_speed = Cli.get_float("debug-speed", 1.0)
		_debug_auto_move = Cli.has_arg("auto-move")


## v = sqrt(2 g h): the take-off speed that peaks at `height` metres.
static func jump_velocity(height: float, gravity: float) -> float:
	return sqrt(2.0 * gravity * height)


func can_move() -> bool:
	return not locked and status.can_act()


func _physics_process(delta: float) -> void:
	if _anchor != null:
		if is_instance_valid(_anchor):
			body.global_position = _anchor.global_position
			body.velocity = Vector3.ZERO
			return
		_anchor = null  # the carrier vanished: fall from where we are
	var data := body.role_data
	var free := can_move()
	var ai := intent != null
	var control := free and (ai or PlayerInput.has_control())
	var on_floor := body.is_on_floor()

	_since_on_floor = 0.0 if on_floor else _since_on_floor + delta
	var jump_pressed := intent.take_jump() if ai else Input.is_action_just_pressed("jump")
	if control and jump_pressed:
		_since_jump_pressed = 0.0
	else:
		_since_jump_pressed += delta

	if not on_floor:
		body.velocity.y -= _gravity * delta
	if free and _since_jump_pressed <= JUMP_BUFFER_S and _since_on_floor <= COYOTE_S:
		body.velocity.y = jump_velocity(data.jump_height, _gravity)
		_since_jump_pressed = INF  # one press, one jump
		_since_on_floor = INF  # no second jump from the coyote window

	var dir := Vector3.ZERO
	var wants_sprint := false
	if ai:
		if control:
			dir = Vector3(intent.direction.x, 0.0, intent.direction.z).limit_length(1.0)
		wants_sprint = intent.sprint
	else:
		var input := Vector2.ZERO
		if control:
			input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		elif free and _debug_auto_move:
			input = Vector2.UP
		dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, body.rig.move_yaw())
		wants_sprint = Input.is_action_pressed("sprint")
	var carrying := status.carrying != 0
	sprinting = stamina.tick(delta, control and not carrying and dir.length_squared() > 0.0001 and wants_sprint)
	var base := data.carry_speed if carrying else (data.sprint_speed if sprinting else data.walk_speed)
	var speed := base * status.speed_multiplier() * body.inventory.speed_multiplier() * _debug_speed
	var target := dir * speed
	if gliding() and (dir.length_squared() > 0.0001 or not free):
		stop_glide()  # the player takes over (or a stun stops it)

	_since_jump_off += delta
	var ladder := Ladder.find(body) if free and _since_jump_off > LADDER_REGRAB_S else null
	var climb := _ladder_climb(ladder, dir, on_floor)
	if climb != 0 and free and _since_jump_pressed <= JUMP_BUFFER_S:
		# Let go: a little hop away from the ladder.
		body.velocity = -ladder.up_direction() * 3.0 + LADDER_JUMP_OFF
		_since_jump_pressed = INF
		_since_jump_off = 0.0
		climb = 0
	climbing = climb != 0
	if climbing:
		body.velocity.y = ladder.climb_speed * (climb if climb != 2 else 0)
		target = dir * speed * LADDER_SIDE_FACTOR

	var accel := ground_accel if on_floor or climbing else air_accel
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).lerp(target, 1.0 - exp(-accel * delta))
	if gliding():
		horizontal = _glide_step(speed, delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if ai:
		_turn_toward_intent(dir, delta)
	elif data.camera_kind == RoleData.CameraKind.THIRD_PERSON and dir.length_squared() > 0.01:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * delta))
	body.move_and_slide()
	_check_bounds(delta)


## Owner: slide the body to `spot` and turn it to `yaw` (radians), eased in and out over about GLIDE_S.
## Moving, or being stunned or locked, ends it early.
func glide_to(spot: Vector3, yaw: float) -> void:
	_glide_from = body.global_position
	_glide_to = spot
	_glide_from_yaw = body.rotation.y
	_glide_yaw = yaw
	# Smoothstep peaks at 1.5× the average speed: never faster than walking (the validator watches).
	var walk := body.role_data.walk_speed * status.speed_multiplier() * body.inventory.speed_multiplier()
	_glide_s = maxf(GLIDE_S, 1.5 * _flat(spot - _glide_from).length() / maxf(walk, 0.1))
	_glide_t = 0.0


func stop_glide() -> void:
	_glide_to = Vector3.INF


func gliding() -> bool:
	return _glide_to != Vector3.INF


## This tick's horizontal velocity along the glide (and the body's turn). Collisions still apply
## (move_and_slide): a body held back catches up at up to `speed`, or gives up after GLIDE_GIVE_UP_S.
func _glide_step(speed: float, delta: float) -> Vector3:
	_glide_t += delta
	var w := smoothstep(0.0, 1.0, _glide_t / _glide_s)
	body.rotation.y = lerp_angle(_glide_from_yaw, _glide_yaw, w)
	var to := _flat(_glide_from.lerp(_glide_to, w) - body.global_position)
	if (w >= 1.0 and to.length() < 0.01) or _glide_t > _glide_s + GLIDE_GIVE_UP_S:
		stop_glide()
		return Vector3.ZERO
	return (to / delta).limit_length(speed)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## AI bots: turn toward intent.face_yaw, or toward where the body moves, at the bot's turn rate.
func _turn_toward_intent(dir: Vector3, delta: float) -> void:
	var target := intent.face_yaw
	if is_nan(target):
		if dir.length_squared() < 0.01 or climbing:
			return
		target = atan2(-dir.x, -dir.z)
	body.rotation.y = rotate_toward(body.rotation.y, target, intent.turn_rate * delta)


## 1 = climb up, -1 = climb down, 2 = hang on, 0 = not climbing (walk / fall normally).
func _ladder_climb(ladder: Ladder, dir: Vector3, on_floor: bool) -> int:
	if ladder == null:
		return 0
	var push := dir.dot(ladder.up_direction()) if dir.length_squared() > 0.01 else 0.0
	if push > LADDER_GRAB_DOT:
		return 1
	if on_floor:
		return 0
	if push < -LADDER_GRAB_DOT:
		return -1
	return 2 if climbing else 0


## Out of the map: back to the last safe spot. Otherwise remember where we stand now and then.
func _check_bounds(delta: float) -> void:
	if body.position.y < KILL_Y or OutOfBounds.contains(body):
		Log.info("move", "out of bounds at %s, back to %s" % [body.position, _last_safe])
		body.position = _last_safe
		body.velocity = Vector3.ZERO
		_since_safe_sample = 0.0
		return
	_since_safe_sample += delta
	if _since_safe_sample >= SAFE_SAMPLE_S and body.is_on_floor():
		_since_safe_sample = 0.0
		_last_safe = body.position


# --- Server → owner ------------------------------------------------------------
# "any_peer" because this node's authority is the owning client, not the server; each handler
# checks that the call really came from the server (peer 1), then does the work in its do_* half.
# Call them through the Player's server_* helpers, which also give the movement validator a grace
# window, and which call the do_* half directly for a bot (its body runs on the server).

@rpc("any_peer", "reliable")
func set_locked(value: bool) -> void:
	if _from_server():
		do_set_locked(value)


@rpc("any_peer", "reliable")
func force_position(pos: Vector3) -> void:
	if _from_server():
		do_force_position(pos)


@rpc("any_peer", "reliable")
func apply_impulse(impulse: Vector3) -> void:
	if _from_server():
		do_apply_impulse(impulse)


## Follow the node at `path` (a carrier's HandSocket); an empty path lets go.
@rpc("any_peer", "reliable")
func attach_to(path: NodePath) -> void:
	if _from_server():
		do_attach_to(path)


func do_set_locked(value: bool) -> void:
	locked = value


func do_force_position(pos: Vector3) -> void:
	body.position = pos
	body.velocity = Vector3.ZERO
	_last_safe = pos


func do_apply_impulse(impulse: Vector3) -> void:
	body.velocity += impulse


func do_attach_to(path: NodePath) -> void:
	_anchor = get_node_or_null(path) as Node3D if not path.is_empty() else null
	body.velocity = Vector3.ZERO


func _from_server() -> bool:
	return multiplayer.get_remote_sender_id() == 1
