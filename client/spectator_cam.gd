class_name SpectatorCam
extends Camera3D
## The camera of a client without a body during a match: eliminated rats and late joiners.
## Free-fly (noclip) by default: mouse look, WASD, Space / C up and down, Shift faster.
## LMB / RMB cycle forward / back through the players' bodies and follow one from behind; cycling
## past the last body returns to the free camera. A click captures the mouse (Esc: the pause menu).
## Caged rats keep their own body, so they get the cage camera (ThirdPersonRig) instead.

const FLY_SPEED := 8.0
const FAST_FACTOR := 2.5
const FOLLOW_DISTANCE := 3.5
const FOLLOW_HEIGHT := 1.6
const FOLLOW_RATE := 8.0
const MAX_PITCH := 1.5

var following := 0  ## peer id we follow, 0 = free camera

var _yaw := 0.0
var _pitch := -0.4
var _active := false


func _ready() -> void:
	position = Vector3(0, 8, 14)
	var point := get_tree().get_first_node_in_group(OverviewCamera.POINT_GROUP) as Node3D
	if point != null:
		position = point.global_position
		_yaw = point.global_rotation.y
		_pitch = clampf(point.global_rotation.x, -MAX_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	var session := Session.current
	var wanted := session.match_manager.in_match() and session.get_body(session.local_peer_id) == null
	if wanted != _active:
		_active = wanted
		following = 0
		if _active:
			make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if get_window().has_focus() else Input.MOUSE_MODE_VISIBLE
		else:
			clear_current(false)
	if not _active:
		return
	if not current:
		make_current()
	var target := session.get_body(following) if following != 0 else null
	if following != 0 and target == null:
		following = 0  # that body is gone: back to the free camera
	if target != null:
		_follow(target, delta)
	else:
		_fly(delta)
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.is_pressed():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if CameraRig.is_click(event):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.is_action_pressed("primary"):
			cycle(1)
		elif event.is_action_pressed("secondary"):
			cycle(-1)
	elif event is InputEventMouseMotion and PlayerInput.has_control():
		var motion := (event as InputEventMouseMotion).relative * Config.look_speed(false)
		if Config.invert_y:
			motion.y = -motion.y
		_yaw = wrapf(_yaw - motion.x, -PI, PI)
		_pitch = clampf(_pitch - motion.y, -MAX_PITCH, MAX_PITCH)


## Follow the next (`step` = 1) or previous (-1) body; past either end: the free camera.
func cycle(step: int) -> void:
	var peers: Array[int] = []
	for node in Session.current.players_root.get_children():
		var p := node as Player
		if p != null and not p.is_queued_for_deletion():
			peers.append(p.peer_id)
	peers.sort()
	if peers.is_empty():
		following = 0
		return
	var slots: Array[int] = [0]
	slots.append_array(peers)
	var index := maxi(slots.find(following), 0)
	following = slots[posmod(index + step, slots.size())]


func _fly(delta: float) -> void:
	if not PlayerInput.has_control():
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := Input.get_action_strength("spectate_up") - Input.get_action_strength("spectate_down")
	var dir := (global_basis * Vector3(input.x, 0.0, input.y)) + Vector3.UP * up
	var speed := FLY_SPEED * (FAST_FACTOR if Input.is_action_pressed("sprint") else 1.0)
	position += dir.limit_length(1.0) * speed * delta


func _follow(target: Player, delta: float) -> void:
	var back := Vector3(0, 0, FOLLOW_DISTANCE).rotated(Vector3.RIGHT, _pitch).rotated(Vector3.UP, _yaw)
	var focus := target.global_position + Vector3.UP * minf(target.role_data.height, FOLLOW_HEIGHT)
	position = position.lerp(focus + back, 1.0 - exp(-FOLLOW_RATE * delta))
