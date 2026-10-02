class_name FirstPersonRig
extends CameraRig
## First-person head (supervisors, lobby bodies). The rig pitches up/down; mouse X turns the body.
## Adds head bob (Config.head_bob) and, for supervisors, the first-person arms and broom
## (assets/generated/fp_arms.glb, M7): idle, swing on LMB, interact while repairing, carry while
## holding a rat, eat and place as one-shots. The arms are drawn at ARMS_SCALE around the camera:
## the picture is the same, but they stay inside the capsule and never poke through walls.
## Knocked down, the view drops to the floor.

const MAX_PITCH := 1.55  ## radians, just under straight up/down
const EYE_BELOW_TOP := 0.2  ## m between the top of the capsule and the eyes
const BOB_AMPLITUDE := 0.04  ## m, at full walking speed
const BOB_RADIANS_PER_M := 4.5  ## about one up-down cycle per 1.4 m travelled
const BOB_SETTLE_RATE := 10.0
const KNOCKED_EYE_HEIGHT := 0.35  ## m
const ARMS_SCALE := 0.35
const ARMS_OUTLINE_WIDTH := 0.0035
const ARMS_SWAY := 0.012  ## m (scaled) the arms lag behind turns
const BLEND_S := 0.15

var _bob_phase := 0.0
var _eye_height := 0.0
var _arms_player: AnimationPlayer
var _one_shot_until := 0.0
var _sway := Vector2.ZERO
var _listening := false

@onready var arms: Node3D = $Camera3D/Arms


func _place(data: RoleData) -> void:
	_eye_height = data.height - EYE_BELOW_TOP
	position.y = _eye_height


func _setup_local() -> void:
	arms.visible = body.role == Role.Kind.SUPERVISOR
	if not arms.visible:
		return
	var model := Art.add(arms, "fp_arms", Transform3D.IDENTITY.scaled(Vector3.ONE * ARMS_SCALE), false)
	if model == null:
		return
	var outline := (load("res://shaders/materials/outline.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	outline.set_shader_parameter("outline_width", ARMS_OUTLINE_WIDTH)
	outline.set_shader_parameter("min_scale", 1.0)
	outline.set_shader_parameter("max_scale", 1.0)
	var toon := (load("res://shaders/materials/toon_palette.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	toon.next_pass = outline
	for mesh in Art.meshes(model):
		mesh.material_override = toon
	var players := model.find_children("*", "AnimationPlayer", true, false)
	_arms_player = players[0] as AnimationPlayer if not players.is_empty() else null
	if _arms_player != null:
		_arms_player.play("idle")


## A broom swing in view (cosmetic, local).
func swing() -> void:
	play_arms("swing")


## Plays a short arms clip, then goes back to whatever the arms were doing.
func play_arms(clip: String) -> void:
	if _arms_player == null or not _arms_player.has_animation(clip) or not arms.visible:
		return
	_arms_player.play(clip, 0.05)
	_one_shot_until = Time.get_ticks_msec() / 1000.0 + _arms_player.get_animation(clip).length


func _update_arms(delta: float) -> void:
	if _arms_player == null:
		return
	if not _listening and body.anim != null:  # the body's AnimationController arrives after us
		_listening = true
		body.anim.one_shot.connect(func(clip: String) -> void:
			if clip in ["eat", "place"]:
				play_arms(clip))
	if Time.get_ticks_msec() / 1000.0 >= _one_shot_until:
		var base := "idle"
		if body.status.carrying != 0:
			base = "carry"
		elif body.sync_anim & AnimationController.FLAG_INTERACT:
			base = "interact"
		if _arms_player.current_animation != base:
			_arms_player.play(base, BLEND_S)
	# A little lag behind the view (sway), and the arms drop away while knocked down.
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var down := 0.3 if body.status.has(StatusComponent.Status.KNOCKED_DOWN) else 0.0
	arms.position = Vector3(_sway.x, _sway.y - down, 0.0)


func look_pitch() -> float:
	return rotation.x


func apply_look_pitch(pitch: float) -> void:
	rotation.x = pitch


func _look(delta: Vector2) -> void:
	body.rotate_y(-delta.x)
	rotation.x = clampf(rotation.x - delta.y, -MAX_PITCH, MAX_PITCH)
	_sway += Vector2(delta.x, -delta.y) * ARMS_SWAY * 4.0
	_sway = _sway.limit_length(ARMS_SWAY)


func _process(delta: float) -> void:
	_apply_shake(delta)
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var target := Vector3.ZERO
	if Config.head_bob and body.is_on_floor() and speed > 0.5:
		_bob_phase = fmod(_bob_phase + speed * BOB_RADIANS_PER_M * delta, TAU * 2.0)
		var strength := BOB_AMPLITUDE * minf(speed / body.role_data.walk_speed, 1.5)
		target = Vector3(cos(_bob_phase * 0.5) * strength * 0.5, sin(_bob_phase) * strength, 0.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-BOB_SETTLE_RATE * delta))
	var knocked := body.status.has(StatusComponent.Status.KNOCKED_DOWN)
	position.y = lerpf(position.y, KNOCKED_EYE_HEIGHT if knocked else _eye_height, 1.0 - exp(-8.0 * delta))
	_update_arms(delta)
