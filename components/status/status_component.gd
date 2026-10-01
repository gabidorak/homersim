class_name StatusComponent
extends Node
## Status effects (GDD §5.4), owned by the server. The server keeps each status's expiry time
## privately and publishes only the `flags` bitmask, which StatusSync (authority = server)
## replicates to everyone. Clients read it through has() / can_act() / speed_multiplier().
##
## Only LOCKED (frozen during the countdown) is used in M2; the rest arrive with PvP and hazards.

enum Status { LOCKED, STUNNED, SLOWED, KNOCKED_DOWN, CARRIED, CAGED, ELIMINATED, INVULNERABLE, REVEALED }

## Statuses that stop movement and actions.
const BLOCKING: Array[Status] = [
	Status.LOCKED, Status.STUNNED, Status.KNOCKED_DOWN, Status.CARRIED, Status.CAGED, Status.ELIMINATED,
]

signal changed

## Bit i set = Status i active. Replicated by StatusSync.
var flags := 0:
	set(value):
		if value != flags:
			flags = value
			changed.emit()

var _expiry: Dictionary[int, float] = {}  # server: status -> expiry in seconds (INF = until cleared)


func _ready() -> void:
	set_physics_process(Net.is_server)


## Server: turn a status on for `duration` seconds (INF = until clear()). Re-applying extends it.
func apply(status: Status, duration: float = INF) -> void:
	var until := _now() + duration
	_expiry[status] = maxf(until, _expiry.get(status, 0.0))
	_publish()


## Server: turn a status off now.
func clear(status: Status) -> void:
	if _expiry.erase(status):
		_publish()


func has(status: Status) -> bool:
	return flags & (1 << status) != 0


func can_act() -> bool:
	for status in BLOCKING:
		if has(status):
			return false
	return true


## Multiplies movement speed. Slows arrive in M4; for now it is always 1.
func speed_multiplier() -> float:
	return 1.0


func _physics_process(_delta: float) -> void:
	var now := _now()
	var expired := false
	for status: int in _expiry.keys():
		if _expiry[status] <= now:
			_expiry.erase(status)
			expired = true
	if expired:
		_publish()


func _publish() -> void:
	var bits := 0
	for status: int in _expiry:
		bits |= 1 << status
	flags = bits


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
