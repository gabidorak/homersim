class_name BodyFx
extends Node
## A body's sounds and particles (M7), on every client but the headless ones, driven by its
## AnimationController (what the body is doing) and StatusComponent:
##   footsteps paced by distance walked (supervisors' boots, rats' pitter-patter), a landing thump
##   and dust, the vent crawl rattle, the gnawing loop or wrench clinks while interacting,
##   emotes (whistle, squeak), voices (a supervisor's "ow!" when knocked down, a rat's squeak when
##   stunned, grabbed or lured by cheese), a "yoink" when a rat steals a keycard, stun stars over the
##   head, donut crumbs, hit-stop on a BONK.

const STRIDE := {Role.Kind.SUPERVISOR: 1.15, Role.Kind.RAT: 0.38, Role.Kind.NONE: 1.15}  ## m per step
const STEP_SOUND := {Role.Kind.SUPERVISOR: "step_supervisor", Role.Kind.RAT: "step_rat", Role.Kind.NONE: "step_supervisor"}
const WRENCH_EVERY_S := 0.6
const HIT_STOP_S := 0.08

var body: Player

var _walked := 0.0
var _last_pos := Vector3.ZERO
var _loop: AudioStreamPlayer3D
var _loop_sound := ""
var _wrench_in := 0.0
var _stars: Node3D
var _was_stunned := false
var _was_knocked := false
var _was_carried := false
var _was_revealed := false
var _had_stolen := false


func setup(p_body: Player) -> void:
	body = p_body


func _ready() -> void:
	_last_pos = body.global_position
	_loop = Sfx.loop_player(body, "gnaw")
	_stars = Vfx.stun_stars(0.22 if body.role == Role.Kind.RAT else 0.4)
	if _stars != null:
		_stars.position.y = body.role_data.height + 0.1
		_stars.visible = false
		body.add_child(_stars)
	body.anim.one_shot.connect(_on_one_shot)
	body.anim.landed.connect(_on_landed)
	Session.current.abilities.broom_swung.connect(_on_broom)


func _process(delta: float) -> void:
	var anim := body.anim
	var pos := body.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	if moved > 2.0:
		moved = 0.0  # a teleport
	# Footsteps on the ground, a rattle in the vents.
	var walking := anim.state == "ground" and anim.speed > 0.4
	if walking:
		_walked += moved
		if _walked >= STRIDE.get(body.role, 1.0):
			_walked = 0.0
			Sfx.play_at(body, STEP_SOUND.get(body.role, "step_supervisor"), pos, -2.0 if body.is_local() else 0.0)
	# Loops: gnawing (rats at a sabotage point), the vent rattle (moving in a duct).
	var want := ""
	if anim.state == "interact" and body.role == Role.Kind.RAT:
		want = "gnaw"
	elif anim.state == "crawl" and anim.speed > 0.3:
		want = "crawl"
	if want != _loop_sound:
		_loop_sound = want
		_loop.stop()
		if want != "":
			_loop.stream = Sfx.get_stream(want)
			_loop.volume_db = Sfx.volume_of(want)
			_loop.play()
	# Supervisors working on a panel: wrench clinks.
	if anim.state == "interact" and body.role == Role.Kind.SUPERVISOR:
		_wrench_in -= delta
		if _wrench_in <= 0.0:
			_wrench_in = WRENCH_EVERY_S * randf_range(0.8, 1.3)
			Sfx.play_at(body, "wrench", pos + Vector3.UP * 1.0)
	_update_status()


func _update_status() -> void:
	var st := body.status
	var stunned := st.has(StatusComponent.Status.STUNNED)
	var knocked := st.has(StatusComponent.Status.KNOCKED_DOWN)
	var carried := st.has(StatusComponent.Status.CARRIED)
	if _stars != null:
		_stars.visible = stunned or knocked
		_stars.position.y = (0.5 if knocked and body.role != Role.Kind.RAT else body.role_data.height + 0.1)
	var head := body.global_position + Vector3.UP * body.role_data.height
	if knocked and not _was_knocked:
		Sfx.play_at(body, "ow", head)
		Vfx.puff(body, body.global_position, Vfx.DUST, 12, 0.7)
		if body.is_local():
			Vfx.shake(0.8)
	if stunned and not _was_stunned and body.role == Role.Kind.RAT:
		Sfx.play_at(body, "squeak", head)
	if carried and not _was_carried:
		Sfx.play_at(body, "squeak", head, 2.0)
	# A rat that fell for a cheese lure (revealed), a rat that just stole a keycard.
	var revealed := st.has(StatusComponent.Status.REVEALED)
	if revealed and not _was_revealed and body.role == Role.Kind.RAT:
		Sfx.play_at(body, "squeak", head, 2.0)
		Vfx.sparks(body, head, 10, Color(1.0, 0.85, 0.3))
	var stolen := body.inventory.stolen_item != &""
	if stolen and not _had_stolen:
		Sfx.play_at(body, "keycard_ok", head)
		Vfx.puff(body, head, Color(1, 1, 1, 0.8), 6, 0.3)
	_was_stunned = stunned
	_was_knocked = knocked
	_was_carried = carried
	_was_revealed = revealed
	_had_stolen = stolen


func _on_one_shot(clip: String) -> void:
	var head := body.global_position + Vector3.UP * body.role_data.height
	match clip:
		"emote":
			Sfx.play_at(body, "whistle_emote", head)
		"squeak":
			Sfx.play_at(body, "squeak", head, 3.0)
		"eat":
			Sfx.play_at(body, "munch", head)
			Sfx.play_at(body, "powerup", head, -4.0)
			Vfx.crumbs(body, head - Vector3.UP * 0.2)
		"place":
			Sfx.play_at(body, "trap_place", body.global_position)


func _on_landed(fall_speed: float) -> void:
	if fall_speed < 2.0:
		return
	Sfx.play_at(body, "land", body.global_position)
	Vfx.puff(body, body.global_position + Vector3.UP * 0.05, Vfx.DUST, 6, 0.35 if body.role == Role.Kind.RAT else 0.6)


## A BONK freezes the attacker's and the victim's animations for a blink (hit-stop).
func _on_broom(attacker: int, victim: int, stunned: bool) -> void:
	if not stunned or not Config.camera_shake:
		return
	if body.peer_id == attacker or body.peer_id == victim:
		body.anim.hit_stop(HIT_STOP_S)
