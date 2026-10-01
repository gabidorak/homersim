class_name StatusComponent
extends Node
## Status effects (GDD §5.4), owned by the server. The rules live in StatusRules (pure logic,
## unit-tested); this node runs them on the server's clock and publishes the result:
##   flags         bit i = Status i active
##   speed_factor  the movement multiplier from slows and boosts
##   carrier       rat: the supervisor carrying it (0 = none)
##   carrying      supervisor: the rat it carries (0 = none)
## StatusSync (authority = server) replicates them; clients only read them.
## The spawn function also applies LOCKED on clients, so a body is frozen from its first frame.

enum Status { LOCKED, STUNNED, SLOWED, KNOCKED_DOWN, CARRIED, CAGED, ELIMINATED, INVULNERABLE, REVEALED, BOOSTED }

## Server: a status turned on (the body listens: dropping a stolen item, validator grace).
signal applied(status: Status)
## Server: a status ended (expired or cleared).
signal ended(status: Status)
## Any replicated value changed (flags, speed factor, carry links), on the server and on clients.
signal changed

# --- Replicated by StatusSync ------------------------------------------------------------
var flags := 0:
	set(value):
		if value != flags:
			flags = value
			changed.emit()
var speed_factor := 1.0:
	set(value):
		if value != speed_factor:
			speed_factor = value
			changed.emit()
var carrier := 0:
	set(value):
		if value != carrier:
			carrier = value
			changed.emit()
var carrying := 0:
	set(value):
		if value != carrying:
			carrying = value
			changed.emit()

var rules := StatusRules.new()


func _ready() -> void:
	set_physics_process(Net.is_server)


## Called by the spawn function with the role's immunity windows.
func setup(data: RoleData) -> void:
	rules.stun_immunity_s = data.stun_immunity_s
	rules.knockdown_immunity_s = data.knockdown_immunity_s


## Server: turn a status on for `duration` seconds (INF = until clear()). Returns false if a rule
## refused it (invulnerable, immune, already stunned…).
func apply(status: Status, duration: float = INF) -> bool:
	if not rules.apply(status, duration, _now()):
		return false
	_publish()
	applied.emit(status)
	return true


## Server: turn a status off now.
func clear(status: Status) -> void:
	if not rules.has(status, _now()):
		return
	rules.clear(status, _now())
	_publish()
	ended.emit(status)


## Server: a named speed factor (see StatusRules.set_speed_factor).
func set_speed_factor(source: StringName, factor: float, duration: float) -> void:
	rules.set_speed_factor(source, factor, duration, _now())
	_publish()


## Server: one bite with the bite ability's numbers. Returns a StatusRules.Bite.
func bite(data: AbilityData) -> StatusRules.Bite:
	var result := rules.bite(_now(), data.extra.get("slow_factor", 0.7), data.status_duration,
		data.extra.get("knockdown_bites", 3), data.extra.get("knockdown_window_s", 6.0),
		data.extra.get("knockdown_s", 4.0))
	_publish()
	if result == StatusRules.Bite.KNOCKED_DOWN:
		applied.emit(Status.KNOCKED_DOWN)
	return result


## Short placeholder labels with colours for the active statuses (until M7's icons):
## [[text, Color], …], most important first. Used above heads and in the HUD.
static func describe(bits: int) -> Array:
	var out: Array = []
	for entry: Array in [
		[Status.CAGED, "CAGED", Color(0.7, 0.7, 0.75)],
		[Status.CARRIED, "CAUGHT!", Color(1, 0.5, 0.2)],
		[Status.KNOCKED_DOWN, "KNOCKED DOWN", Color(1, 0.3, 0.25)],
		[Status.STUNNED, "* STUNNED *", Color(1, 0.9, 0.2)],
		[Status.SLOWED, "slowed", Color(0.45, 0.7, 1)],
		[Status.BOOSTED, "donut rush", Color(1, 0.6, 0.85)],
		[Status.INVULNERABLE, "safe", Color(1, 1, 1)],
		[Status.REVEALED, "revealed", Color(1, 0.85, 0.1)],
	]:
		if bits & (1 << (entry[0] as int)) != 0:
			out.append([entry[1], entry[2]])
	return out


func has(status: Status) -> bool:
	return flags & (1 << status) != 0


func can_act() -> bool:
	return not StatusRules.blocks_actions(flags)


## Multiplies movement speed (slows and boosts).
func speed_multiplier() -> float:
	return speed_factor


func _physics_process(_delta: float) -> void:
	var gone := rules.tick(_now())
	var bits := rules.flags(_now())
	var factor := rules.speed_factor(_now())
	if bits != flags or not is_equal_approx(factor, speed_factor):
		_publish()
	for status in gone:
		ended.emit(status)


func _publish() -> void:
	speed_factor = snappedf(rules.speed_factor(_now()), 0.001)
	flags = rules.flags(_now())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
