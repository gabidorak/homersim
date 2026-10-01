class_name MovementComponent
extends Node
## Basic first-person controller: WASD, mouse look, sprint, jump, gravity.
## Runs only on the owning client; BodySync replicates the result to everyone else.

const MAX_PITCH := 1.55  ## radians, just under straight up/down
const KILL_Y := -20.0  ## fell out of the world: put the player back

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var ground_accel := 12.0  ## how quickly velocity reaches the target speed
@export var air_accel := 3.0
@export var mouse_sensitivity := 0.0025  ## radians per pixel (a setting from M8)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var body: CharacterBody3D = get_parent()
@onready var head: Node3D = $"../CameraRig"


func _ready() -> void:
	var mine := is_multiplayer_authority()
	set_physics_process(mine)
	set_process_unhandled_input(mine)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		body.rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * mouse_sensitivity, -MAX_PITCH, MAX_PITCH)


func _physics_process(delta: float) -> void:
	# No input while the mouse is free (menu-like state, or the window lost focus).
	var has_control := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var on_floor := body.is_on_floor()

	if not on_floor:
		body.velocity.y -= _gravity * delta
	elif has_control and Input.is_action_just_pressed("jump"):
		body.velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if has_control else Vector2.ZERO
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := (body.transform.basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	var accel := ground_accel if on_floor else air_accel
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).lerp(target, 1.0 - exp(-accel * delta))
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	body.move_and_slide()

	if body.position.y < KILL_Y:
		body.position = Vector3(0.0, 1.0, 0.0)
		body.velocity = Vector3.ZERO
