class_name PlantModel
extends RefCounted
## The plant simulation (GDD §4) as pure logic: no nodes, no network, so GUT can test it.
## PlantSim wraps it on the server and replicates the results.
##
## Subsystems are addressed by index (the order of PlantTuning.subsystems). Times (`now`) are
## seconds on the caller's clock; PlantSim uses the server's.

enum Alarm { NORMAL, WARNING, CRITICAL }

var tuning: PlantTuning
var healths := PackedFloat32Array()
var core_temp := 0.0
var meltdown := 0.0  ## 0..100 %
## Per subsystem: time from which it can be sabotaged again.
var cooldowns := PackedFloat32Array()
## Per subsystem: health hit 0, so it must be rebooted before repairs work.
var offline: Array[bool] = []
## SCRAM halves the heat while now < scram_until (control room, later milestone).
var scram_until := 0.0


func _init(p_tuning: PlantTuning) -> void:
	tuning = p_tuning
	reset()


## Back to a healthy plant at nominal temperature.
func reset() -> void:
	var n := count()
	healths.resize(n)
	healths.fill(tuning.max_health)
	cooldowns.resize(n)
	cooldowns.fill(0.0)
	offline.resize(n)
	offline.fill(false)
	core_temp = tuning.nominal_temp
	meltdown = 0.0
	scram_until = 0.0


func count() -> int:
	return tuning.subsystems.size()


## Index of the subsystem with this id, or -1.
func index_of(id: StringName) -> int:
	for i in count():
		if tuning.subsystems[i].id == id:
			return i
	return -1


## Adds `amount` % to the meltdown meter (swarm bonus), clamped to 0..100.
func add_meltdown(amount: float) -> void:
	meltdown = clampf(meltdown + amount, 0.0, 100.0)


## Advances the simulation by `dt` seconds.
func tick(dt: float, now: float) -> void:
	var heat_in := 0.0
	for i in count():
		var damage := (tuning.max_health - healths[i]) / tuning.max_health
		heat_in += damage * tuning.subsystems[i].heat_weight
	if now < scram_until:
		heat_in *= tuning.scram_heat_factor
	var cooling := tuning.cooling_rate if core_temp > tuning.nominal_temp else 0.0
	core_temp = clampf(core_temp + (heat_in - cooling) * dt, tuning.min_temp, tuning.max_temp)

	if core_temp > tuning.meltdown_start_temp:
		meltdown += tuning.meltdown_fill_rate * (core_temp - tuning.meltdown_start_temp) / 100.0 * dt
	elif core_temp < tuning.meltdown_recover_temp:
		meltdown -= tuning.meltdown_decay_rate * dt
	meltdown = clampf(meltdown, 0.0, 100.0)


## True if subsystem `i` can be sabotaged now: off cooldown, and not already at 0.
func can_sabotage(i: int, now: float) -> bool:
	return now >= cooldowns[i] and healths[i] > 0.0


## Seconds until subsystem `i` can be sabotaged again (0 if it can).
func cooldown_left(i: int, now: float) -> float:
	return maxf(cooldowns[i] - now, 0.0)


## A successful sabotage: removes `amount` health and starts the cooldown. Returns false (and
## changes nothing) if the subsystem can't be sabotaged right now.
func apply_damage(i: int, amount: float, now: float) -> bool:
	if not can_sabotage(i, now):
		return false
	healths[i] = maxf(healths[i] - amount, 0.0)
	if healths[i] <= 0.0:
		offline[i] = true
	cooldowns[i] = now + tuning.sabotage_cooldown_s
	return true


## Adds `amount` health (capped at max). Returns false if the subsystem needs a reboot first.
func apply_repair(i: int, amount: float) -> bool:
	if offline[i]:
		return false
	healths[i] = minf(healths[i] + amount, tuning.max_health)
	return true


func needs_reboot(i: int) -> bool:
	return offline[i]


## Brings an offline subsystem back so it can be repaired (its health stays at 0).
func reboot(i: int) -> bool:
	if not offline[i]:
		return false
	offline[i] = false
	return true


func alarm_state() -> Alarm:
	return alarm_for(core_temp, tuning)


static func alarm_for(temp: float, p_tuning: PlantTuning) -> Alarm:
	if temp >= p_tuning.critical_temp:
		return Alarm.CRITICAL
	if temp >= p_tuning.warning_temp:
		return Alarm.WARNING
	return Alarm.NORMAL
