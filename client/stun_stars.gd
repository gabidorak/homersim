extends Node3D
## Spins and bobs the stun stars made by Vfx.stun_stars().

const SPIN := 4.0  ## radians per second
const BOB := 0.03  ## m

var _base_y := 0.0


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	rotation.y += SPIN * delta
	position.y = _base_y + sin(Time.get_ticks_msec() / 160.0) * BOB
