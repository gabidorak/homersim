class_name MovementComponent
extends Node
## Character controller for every role: walk, sprint with stamina, jump (with coyote time and a
## jump buffer) and gravity, using the player's RoleData. Runs only on the owning client;
## BodySync replicates the result. WASD is relative to CameraRig.move_yaw(): where you look in
## first person, where the camera looks in third person (and the body turns to face its movement).
##
## The server imposes movement through the RPCs at the bottom (freeze, teleport, knockback,
## hanging from a carrier's hand). Speed = role speed × status (slows, donut) × inventory (a
## stolen item); a supervisor carrying a rat walks at the role's carry speed and can't sprint.

const COYOTE_S := 0.1  ## you can still jump this long after walking off a ledge
const JUMP_BUFFER_S := 0.1  ## a jump pressed this long before landing still happens
const TURN_RATE := 12.0  ## third person: how fast the body turns toward its movement
const KILL_Y := -20.0  ## fell out of the world: back to the spawn point

@export var ground_accel := 12.0  ## how quickly velocity reaches the target speed
@export var air_accel := 3.0

var stamina: Stamina
var sprinting := false
## Set by the server through set_locked(); the LOCKED status (countdown) freezes the body too.
var locked := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _since_on_floor := INF
var _since_jump_pressed := INF
var _spawn_position := Vector3.ZERO
var _anchor: Node3D  # set by attach_to(): we are carried, the body follows this node
var _debug_speed := 1.0  # test-only: --debug-speed N (a fake speed hack for the validator)
var _debug_auto_move := false  # test-only: --auto-move (walk forward without input)

@onready var body: Player = get_parent()
@onready var status: StatusComponent = $"../StatusComponent"


func _ready() -> void:
	var data := body.role_data
	stamina = Stamina.new(data.stamina_s, data.stamina_regen_s, data.stamina_regen_delay_s)
	_spawn_position = body.position
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
	var control := free and PlayerInput.has_control()
	var on_floor := body.is_on_floor()

	_since_on_floor = 0.0 if on_floor else _since_on_floor + delta
	if control and Input.is_action_just_pressed("jump"):
		_since_jump_pressed = 0.0
	else:
		_since_jump_pressed += delta

	if not on_floor:
		body.velocity.y -= _gravity * delta
	if free and _since_jump_pressed <= JUMP_BUFFER_S and _since_on_floor <= COYOTE_S:
		body.velocity.y = jump_velocity(data.jump_height, _gravity)
		_since_jump_pressed = INF  # one press, one jump
		_since_on_floor = INF  # no second jump from the coyote window

	var input := Vector2.ZERO
	if control:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	elif free and _debug_auto_move:
		input = Vector2.UP
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, body.rig.move_yaw())
	var carrying := status.carrying != 0
	sprinting = stamina.tick(delta, control and not carrying and input != Vector2.ZERO and Input.is_action_pressed("sprint"))
	var base := data.carry_speed if carrying else (data.sprint_speed if sprinting else data.walk_speed)
	var speed := base * status.speed_multiplier() * body.inventory.speed_multiplier() * _debug_speed
	var target := dir * speed

	var accel := ground_accel if on_floor else air_accel
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).lerp(target, 1.0 - exp(-accel * delta))
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if data.camera_kind == RoleData.CameraKind.THIRD_PERSON and dir.length_squared() > 0.01:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * delta))
	body.move_and_slide()

	if body.position.y < KILL_Y:
		body.position = _spawn_position
		body.velocity = Vector3.ZERO


# --- Server → owner ------------------------------------------------------------
# "any_peer" because this node's authority is the owning client, not the server; each handler
# checks that the call really came from the server (peer 1). Call them through the Player's
# server_* helpers, which also give the movement validator a grace window.

@rpc("any_peer", "reliable")
func set_locked(value: bool) -> void:
	if _from_server():
		locked = value


@rpc("any_peer", "reliable")
func force_position(pos: Vector3) -> void:
	if _from_server():
		body.position = pos
		body.velocity = Vector3.ZERO


@rpc("any_peer", "reliable")
func apply_impulse(impulse: Vector3) -> void:
	if _from_server():
		body.velocity += impulse


## Follow the node at `path` (a carrier's HandSocket); an empty path lets go.
@rpc("any_peer", "reliable")
func attach_to(path: NodePath) -> void:
	if _from_server():
		_anchor = get_node_or_null(path) as Node3D if not path.is_empty() else null
		body.velocity = Vector3.ZERO


func _from_server() -> bool:
	return multiplayer.get_remote_sender_id() == 1
