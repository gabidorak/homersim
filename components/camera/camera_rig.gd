class_name CameraRig
extends Node3D
## Base for the camera rigs (FirstPersonRig, ThirdPersonRig), instanced into the player at spawn
## by role. Only the local player's rig is live: on remote bodies it drops its camera and stays idle.
## Also owns mouse capture: Esc frees the mouse, a click captures it again.

var body: Player
var camera: Camera3D


func _ready() -> void:
	body = get_parent()
	camera = find_child("Camera3D") as Camera3D
	_place(body.role_data)
	if not is_multiplayer_authority():
		# Remote bodies must never take over the view (Godot makes the first camera it sees current).
		camera.queue_free()
		camera = null
		set_process(false)
		set_process_unhandled_input(false)
		return
	camera.fov = Config.fov
	_setup_local()
	camera.make_current()
	# Only one window can grab the mouse; with several clients open, the others wait for a click.
	if get_window().has_focus():
		_capture_mouse(true)


## Yaw (radians, world) that WASD is relative to.
func move_yaw() -> float:
	return body.rotation.y


## Head pitch to replicate (first person only).
func look_pitch() -> float:
	return 0.0


func apply_look_pitch(_pitch: float) -> void:
	pass


## Called on every peer: position the rig for the role's size.
func _place(_data: RoleData) -> void:
	pass


## Called only for the local player.
func _setup_local() -> void:
	pass


## Mouse motion in radians (already scaled by sensitivity).
func _look(_delta: Vector2) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)
	elif event is InputEventMouseMotion and PlayerInput.has_control():
		# event.relative is in pixels, so the look speed doesn't depend on the frame rate.
		_look((event as InputEventMouseMotion).relative * Config.mouse_sensitivity)


func _notification(what: int) -> void:
	# Otherwise the mouse stays trapped after alt-tabbing out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and is_multiplayer_authority():
		_capture_mouse(false)


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
