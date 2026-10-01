class_name ThirdPersonRig
extends CameraRig
## Third-person orbit camera (rats). The mouse orbits the camera around a pivot above the body;
## the body itself turns toward where it moves (MovementComponent). A SpringArm3D pulls the camera
## in front of walls so it never clips through them. In vents the arm shortens and the pivot drops
## under the low ceiling.

const PIVOT_ABOVE_HEAD := 0.3  ## m
const ARM_LENGTH := 2.5  ## m
const VENT_ARM_LENGTH := 1.1
const SHOULDER := 0.35  ## m, sideways offset of the view
const VENT_SHOULDER := 0.1
const CEILING_GAP := 0.15  ## m kept between the pivot and a low ceiling
const MIN_PITCH := -1.2
const MAX_PITCH := 0.6
const ADJUST_RATE := 10.0

var in_vent := false
var _yaw := 0.0  ## world yaw of the camera; independent of the body, which faces its movement

@onready var arm: SpringArm3D = $SpringArm3D


func _place(data: RoleData) -> void:
	position.y = data.height + PIVOT_ABOVE_HEAD


func _setup_local() -> void:
	_yaw = body.rotation.y
	arm.add_excluded_object(body.get_rid())
	camera.h_offset = SHOULDER


func move_yaw() -> float:
	return _yaw


func _look(delta: Vector2) -> void:
	_yaw = wrapf(_yaw - delta.x, -PI, PI)
	arm.rotation.x = clampf(arm.rotation.x - delta.y, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	# The rig is a child of the body, so cancel the body's own turning to keep the camera's yaw.
	rotation.y = _yaw - body.rotation.y
	in_vent = VentVolume.contains(body)
	var weight := 1.0 - exp(-ADJUST_RATE * delta)
	arm.spring_length = lerpf(arm.spring_length, VENT_ARM_LENGTH if in_vent else ARM_LENGTH, weight)
	camera.h_offset = lerpf(camera.h_offset, VENT_SHOULDER if in_vent else SHOULDER, weight)
	# A pivot inside the ceiling would start the spring arm inside a wall: drop under it at once,
	# rise back smoothly.
	var target := _pivot_height_under_ceiling(body.role_data.height + PIVOT_ABOVE_HEAD)
	position.y = target if target < position.y else lerpf(position.y, target, weight)


func _pivot_height_under_ceiling(wanted: float) -> float:
	var low := body.role_data.height * 0.5
	var from := body.global_position + Vector3.UP * low
	var query := PhysicsRayQueryParameters3D.create(
		from, body.global_position + Vector3.UP * (wanted + CEILING_GAP), PhysicsLayers.WORLD, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wanted
	return maxf((hit["position"] as Vector3).y - body.global_position.y - CEILING_GAP, low)
