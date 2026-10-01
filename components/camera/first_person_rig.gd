class_name FirstPersonRig
extends CameraRig
## First-person head (supervisors, lobby bodies). The rig pitches up/down; mouse X turns the body.
## Adds head bob (Config.head_bob) and, for supervisors, a placeholder broom in view that swings
## on LMB. Knocked down, the view drops to the floor.

const MAX_PITCH := 1.55  ## radians, just under straight up/down
const EYE_BELOW_TOP := 0.2  ## m between the top of the capsule and the eyes
const BOB_AMPLITUDE := 0.04  ## m, at full walking speed
const BOB_RADIANS_PER_M := 4.5  ## about one up-down cycle per 1.4 m travelled
const BOB_SETTLE_RATE := 10.0
const KNOCKED_EYE_HEIGHT := 0.35  ## m
const SWING_S := 0.25

var _bob_phase := 0.0
var _eye_height := 0.0
var _swing_tween: Tween
var _arms_rest := Transform3D.IDENTITY

@onready var arms: Node3D = $Camera3D/Arms


func _place(data: RoleData) -> void:
	_eye_height = data.height - EYE_BELOW_TOP
	position.y = _eye_height


func _setup_local() -> void:
	arms.visible = body.role == Role.Kind.SUPERVISOR
	_arms_rest = arms.transform


## A quick broom swing in view (cosmetic, local).
func swing() -> void:
	if not arms.visible:
		return
	if _swing_tween != null:
		_swing_tween.kill()
	arms.transform = _arms_rest
	_swing_tween = create_tween()
	var swung := _arms_rest.rotated_local(Vector3.FORWARD, 1.1).translated_local(Vector3(-0.3, 0.05, -0.1))
	_swing_tween.tween_property(arms, "transform", swung, SWING_S * 0.4)
	_swing_tween.tween_property(arms, "transform", _arms_rest, SWING_S * 0.6)


func look_pitch() -> float:
	return rotation.x


func apply_look_pitch(pitch: float) -> void:
	rotation.x = pitch


func _look(delta: Vector2) -> void:
	body.rotate_y(-delta.x)
	rotation.x = clampf(rotation.x - delta.y, -MAX_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var target := Vector3.ZERO
	if Config.head_bob and body.is_on_floor() and speed > 0.5:
		_bob_phase = fmod(_bob_phase + speed * BOB_RADIANS_PER_M * delta, TAU * 2.0)
		var strength := BOB_AMPLITUDE * minf(speed / body.role_data.walk_speed, 1.5)
		target = Vector3(cos(_bob_phase * 0.5) * strength * 0.5, sin(_bob_phase) * strength, 0.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-BOB_SETTLE_RATE * delta))
	var knocked := body.status.has(StatusComponent.Status.KNOCKED_DOWN)
	position.y = lerpf(position.y, KNOCKED_EYE_HEIGHT if knocked else _eye_height, 1.0 - exp(-8.0 * delta))
