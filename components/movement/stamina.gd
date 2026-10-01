class_name Stamina
extends RefCounted
## Sprint stamina (pure logic, unit-tested). Sprinting drains one second of stamina per second.
## After sprinting stops, the bar waits `regen_delay_s` and then refills in `regen_s`.
## Running it dry "exhausts" you: no sprinting until the bar is back to EXHAUSTED_UNTIL.

const EXHAUSTED_UNTIL := 0.25  ## fraction of the bar

var max_s: float
var regen_s: float
var regen_delay_s: float
var current: float
var exhausted := false

var _since_sprint := INF


func _init(p_max_s: float = 5.0, p_regen_s: float = 4.0, p_regen_delay_s: float = 1.0) -> void:
	max_s = p_max_s
	regen_s = p_regen_s
	regen_delay_s = p_regen_delay_s
	current = max_s


## Advances by `delta` seconds. `wants_sprint` = the player holds sprint while moving.
## Returns true if they actually sprint this tick.
func tick(delta: float, wants_sprint: bool) -> bool:
	var sprinting := wants_sprint and not exhausted and current > 0.0
	if sprinting:
		current -= delta
		_since_sprint = 0.0
		if current < 0.001:  # float steps never land exactly on 0
			current = 0.0
			exhausted = true
	else:
		_since_sprint += delta
		if _since_sprint >= regen_delay_s:
			current = minf(current + delta * max_s / regen_s, max_s)
		if exhausted and current >= max_s * EXHAUSTED_UNTIL:
			exhausted = false
	return sprinting


func fraction() -> float:
	return current / max_s if max_s > 0.0 else 0.0
