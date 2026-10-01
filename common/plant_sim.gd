class_name PlantSim
extends Node
## The networked plant. On the server it owns a PlantModel, ticks it at 10 Hz while `running`
## (MatchManager turns that on for PLAYING), and copies the results into the synced properties
## below after every tick or change. PlantSync replicates them to clients at about 5 Hz.
## Clients only read them (health(), cooldown_left()…), so their HUD and props can show the plant.

## Server: a sabotage / repair / reboot happened. `peers` = the players credited for it.
signal subsystem_changed(index: int, what: String, peers: Array[int], before: float, after: float)
signal alarm_changed(alarm: PlantModel.Alarm)

const TUNING_PATH := "res://data/plant_tuning.tres"
const TICK_S := 0.1

var tuning: PlantTuning = load(TUNING_PATH)
## Server: simulate only while true.
var running := false

# --- Replicated by PlantSync (server → clients) -------------------------------------
# Always assign whole new arrays: a synchronizer can't see an element changed in place.
var healths := PackedFloat32Array()
var core_temp := 300.0
var meltdown := 0.0
var cooldowns := PackedFloat32Array()  ## seconds left, not absolute times (clocks differ per machine)
var offline_mask := 0  ## bit i = subsystem i needs a reboot
var alarm := PlantModel.Alarm.NORMAL:
	set(value):
		if value != alarm:
			alarm = value
			alarm_changed.emit(alarm)
			if not Net.is_server:
				Events.plant_alarm_changed.emit(alarm)

# Exists on clients too (index_of, the initial values), but only the server's is ticked.
var _model := PlantModel.new(tuning)


func _ready() -> void:
	_publish()
	if not Net.is_server:
		return
	var timer := Timer.new()
	timer.name = "TickTimer"
	timer.wait_time = TICK_S
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()


func count() -> int:
	return tuning.subsystems.size()


func index_of(id: StringName) -> int:
	return _model.index_of(id)


func data(index: int) -> SubsystemData:
	return tuning.subsystems[index]


# --- Readable on every peer ------------------------------------------------------------

func health(index: int) -> float:
	return healths[index] if index >= 0 and index < healths.size() else 0.0


func needs_reboot(index: int) -> bool:
	return offline_mask & (1 << index) != 0


func cooldown_left(index: int) -> float:
	if Net.is_server:
		return _model.cooldown_left(index, _now())
	return cooldowns[index] if index >= 0 and index < cooldowns.size() else 0.0


func can_sabotage(index: int) -> bool:
	if Net.is_server:
		return _model.can_sabotage(index, _now())
	return cooldown_left(index) <= 0.0 and health(index) > 0.0


# --- Server API --------------------------------------------------------------------------

## Back to a healthy plant (match start).
func reset() -> void:
	_model.reset()
	_publish()


## A sabotage by `peers`. Returns false if the subsystem can't be sabotaged right now.
func apply_damage(index: int, amount: float, peers: Array[int] = []) -> bool:
	var before := _model.healths[index]
	if not _model.apply_damage(index, amount, _now()):
		return false
	_publish()
	subsystem_changed.emit(index, "sabotage", peers, before, _model.healths[index])
	return true


func apply_repair(index: int, amount: float, peers: Array[int] = []) -> bool:
	var before := _model.healths[index]
	if not _model.apply_repair(index, amount):
		return false
	_publish()
	subsystem_changed.emit(index, "repair", peers, before, _model.healths[index])
	return true


func reboot(index: int, peers: Array[int] = []) -> bool:
	if not _model.reboot(index):
		return false
	_publish()
	subsystem_changed.emit(index, "reboot", peers, 0.0, _model.healths[index])
	return true


## The swarm bonus (MatchManager): straight onto the meltdown meter.
func add_meltdown(amount: float) -> void:
	_model.add_meltdown(amount)
	_publish()


func _on_tick() -> void:
	if running:
		_model.tick(TICK_S, _now())
	_publish()  # even when stopped, so cooldowns keep counting down on clients


func _publish() -> void:
	healths = _model.healths.duplicate()
	core_temp = _model.core_temp
	meltdown = _model.meltdown
	var left := PackedFloat32Array()
	var mask := 0
	for i in _model.count():
		left.append(snappedf(_model.cooldown_left(i, _now()), 0.1))
		if _model.needs_reboot(i):
			mask |= 1 << i
	cooldowns = left
	offline_mask = mask
	alarm = _model.alarm_state()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
