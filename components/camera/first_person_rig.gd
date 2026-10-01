class_name FirstPersonRig
extends Node3D
## First-person head pivot (it pitches up/down; the body handles yaw). Holds the camera, which
## only the local player uses. Captures the mouse: Esc frees it, a click captures it again.

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	if not is_multiplayer_authority():
		# Remote bodies must never take over the view (Godot makes the first camera it sees current).
		camera.queue_free()
		set_process_unhandled_input(false)
		return
	camera.make_current()
	# Only one window can grab the mouse; with several clients open, the others wait for a click.
	if get_window().has_focus():
		_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)


func _notification(what: int) -> void:
	# Otherwise the mouse stays trapped after alt-tabbing out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and is_multiplayer_authority():
		_capture_mouse(false)


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
