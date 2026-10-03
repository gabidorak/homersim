class_name CameraRig
extends Node3D
## Base for the camera rigs (FirstPersonRig, ThirdPersonRig), instanced into the player at spawn
## by role. Only the local player's rig is live: on remote bodies it drops its camera and stays idle.
## Also captures the mouse on a click in the 3D view (Esc opens the pause menu, which frees it).

var body: Player
var camera: Camera3D

const SHAKE_DECAY := 6.0  ## per second
const SHAKE_MAX_ANGLE := 0.035  ## radians at strength 1
var _shake := 0.0


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
	Config.changed.connect(_on_setting_changed)
	_setup_local()
	camera.make_current()
	# Only one window can grab the mouse; with several clients open, the others wait for a click.
	if get_window().has_focus():
		_capture_mouse(true)


## Local only: a short camera shake (Vfx.shake), strength 0..1, decaying quickly. It only turns the
## camera node itself a little (the rigs never rotate it), so aiming and the rigs are untouched.
func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


func _apply_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake <= 0.001:
		if camera.rotation != Vector3.ZERO:
			camera.rotation = Vector3.ZERO
		return
	_shake = maxf(_shake - SHAKE_DECAY * delta * _shake - delta * 0.2, 0.0)
	var t := Time.get_ticks_msec() / 1000.0
	var k := _shake * _shake * SHAKE_MAX_ANGLE
	camera.rotation = Vector3(sin(t * 53.0) * k, cos(t * 41.0) * k * 0.6, sin(t * 47.0) * k)


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
	if is_click(event) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)
	elif event is InputEventMouseMotion and PlayerInput.has_control() and body.seated_console() == null:
		# event.relative is in pixels, so the look speed doesn't depend on the frame rate.
		var motion := (event as InputEventMouseMotion).relative * Config.look_speed(_third_person())
		if Config.invert_y:
			motion.y = -motion.y
		_look(motion)


## A real click: wheel ticks are button presses too, and a menu's scroll list at its end lets them
## through unhandled, which would grab the mouse while the menu is still open.
static func is_click(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.pressed and button.button_index not in [
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]


## Which mouse sensitivity setting this rig uses.
func _third_person() -> bool:
	return false


func _on_setting_changed(key: String) -> void:
	if key == "fov" and camera != null:
		camera.fov = Config.fov


func _notification(what: int) -> void:
	# Otherwise the mouse stays trapped after alt-tabbing out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and is_multiplayer_authority():
		_capture_mouse(false)


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
