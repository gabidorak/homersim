class_name MoveIntent
extends RefCounted
## What an AI bot wants its body to do this physics tick (M10). The server's AI writes it before
## MovementComponent runs (physics priority −10 vs 0), and MovementComponent reads it instead of the
## keyboard, so a bot moves with exactly the same physics, speeds and stamina as a player.

var direction := Vector3.ZERO  ## world space, horizontal; its length (0..1) is the share of full speed
var sprint := false
var jump := false  ## one press: MovementComponent consumes it (take_jump)
var face_yaw := NAN  ## turn the body toward this yaw (radians); NAN = face where it moves
var turn_rate := TAU  ## radians per second (BotSkill.turn_rate_deg)


## The jump press, once.
func take_jump() -> bool:
	var pressed := jump
	jump = false
	return pressed


## Stand still (and keep the facing).
func stop() -> void:
	direction = Vector3.ZERO
	sprint = false
