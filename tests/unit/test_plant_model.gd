extends GutTest
## PlantModel against the GDD §4 formulas and worked check.

const DT := 0.1  # PlantSim ticks at 10 Hz

var tuning: PlantTuning = preload("res://data/plant_tuning.tres")
var model: PlantModel
var now := 0.0


func before_each() -> void:
	model = PlantModel.new(tuning)
	now = 0.0


func _run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		now += DT
		model.tick(DT, now)


func _break(ids: Array[StringName]) -> void:
	for id in ids:
		model.healths[model.index_of(id)] = 0.0


func test_all_healthy_stays_nominal() -> void:
	_run(120.0)
	assert_eq(model.core_temp, 300.0)
	assert_eq(model.meltdown, 0.0)
	assert_eq(model.alarm_state(), PlantModel.Alarm.NORMAL)


func test_worked_check_three_systems_down_reach_700_in_about_67_s() -> void:
	_break([&"rods", &"pumps", &"valves"])
	var t := 0.0
	while model.core_temp < 700.0 and t < 200.0:
		t += DT
		model.tick(DT, t)
	assert_almost_eq(t, 67.0, 2.0, "300 -> 700 at +6 units/s")


func test_meltdown_only_rises_above_700() -> void:
	_break([&"rods", &"pumps", &"valves", &"turbine"])  # +7.5 units/s net: keeps heating
	model.core_temp = 650.0
	model.meltdown = 10.0
	_run(5.0)  # 650 -> ~687: still below 700
	assert_eq(model.meltdown, 10.0, "no change between 400 and 700")
	_run(10.0)  # well above 700 now
	assert_gt(model.meltdown, 10.0)


func test_meltdown_fill_rate_at_800_is_about_1_percent_per_s() -> void:
	model.core_temp = 800.0
	var before := model.meltdown
	# Freeze the temperature: cooling 1.5/s exactly balanced by 0.5 damage on pumps (2.5 * 0.6 = 1.5).
	model.healths[model.index_of(&"pumps")] = 40.0
	_run(1.0)
	assert_almost_eq(model.meltdown - before, 1.0, 0.01)


func test_meltdown_decays_below_400_and_never_below_0() -> void:
	model.core_temp = 350.0
	model.meltdown = 1.0
	_run(2.0)
	assert_almost_eq(model.meltdown, 0.5, 0.01, "-0.25 %/s")
	_run(10.0)
	assert_eq(model.meltdown, 0.0)


func test_meltdown_caps_at_100() -> void:
	_break([&"rods", &"pumps", &"valves", &"turbine", &"grid", &"ventilation"])
	_run(600.0)
	assert_eq(model.core_temp, 1000.0, "clamped to max")
	assert_eq(model.meltdown, 100.0)


func test_alarm_thresholds() -> void:
	for pair: Array in [[300.0, PlantModel.Alarm.NORMAL], [499.9, PlantModel.Alarm.NORMAL],
			[500.0, PlantModel.Alarm.WARNING], [699.9, PlantModel.Alarm.WARNING], [700.0, PlantModel.Alarm.CRITICAL]]:
		model.core_temp = pair[0]
		assert_eq(model.alarm_state(), pair[1], "at %s" % pair[0])


func test_sabotage_cooldown_blocks_a_second_sabotage_for_20_s() -> void:
	var i := model.index_of(&"pumps")
	assert_true(model.apply_damage(i, 50.0, 100.0))
	assert_eq(model.healths[i], 50.0)
	assert_false(model.apply_damage(i, 50.0, 110.0), "still cooling down")
	assert_almost_eq(model.cooldown_left(i, 110.0), 10.0, 0.001)
	assert_false(model.apply_damage(i, 50.0, 119.9))
	assert_eq(model.healths[i], 50.0)
	assert_true(model.apply_damage(i, 50.0, 120.0), "20 s later")
	assert_eq(model.healths[i], 0.0)
	var other := model.index_of(&"grid")
	assert_true(model.can_sabotage(other, 110.0), "the cooldown is per subsystem")


func test_repair_is_clamped_to_100() -> void:
	var i := model.index_of(&"valves")
	model.apply_damage(i, 50.0, 0.0)
	assert_true(model.apply_repair(i, 35.0))
	assert_eq(model.healths[i], 85.0)
	model.apply_repair(i, 35.0)
	assert_eq(model.healths[i], 100.0)


func test_health_0_requires_a_reboot() -> void:
	var i := model.index_of(&"rods")
	model.apply_damage(i, 100.0, 0.0)
	assert_eq(model.healths[i], 0.0)
	assert_true(model.needs_reboot(i))
	assert_false(model.can_sabotage(i, 100.0), "nothing left to break")
	assert_false(model.apply_repair(i, 35.0), "repairs don't work before the reboot")
	assert_eq(model.healths[i], 0.0)
	assert_true(model.reboot(i))
	assert_false(model.needs_reboot(i))
	assert_false(model.reboot(i), "only once")
	assert_true(model.apply_repair(i, 35.0))
	assert_eq(model.healths[i], 35.0)


func test_damage_never_goes_below_0() -> void:
	var i := model.index_of(&"grid")
	model.apply_damage(i, 250.0, 0.0)
	assert_eq(model.healths[i], 0.0)


func test_scram_halves_the_heat() -> void:
	_break([&"rods", &"pumps", &"valves"])  # 7.5 heat in, 1.5 cooling
	model.scram_until = 1000.0
	_run(10.0)
	assert_almost_eq(model.core_temp, 300.0 + (3.75 - 1.5) * 10.0, 0.5)


func test_reset() -> void:
	model.apply_damage(0, 100.0, 0.0)
	model.core_temp = 900.0
	model.meltdown = 50.0
	model.reset()
	assert_eq(model.healths[0], 100.0)
	assert_false(model.needs_reboot(0))
	assert_true(model.can_sabotage(0, 0.0))
	assert_eq([model.core_temp, model.meltdown], [300.0, 0.0])


func test_index_of() -> void:
	assert_eq(model.index_of(&"rods"), 0)
	assert_eq(model.index_of(&"ventilation"), 5)
	assert_eq(model.index_of(&"nope"), -1)


func test_add_meltdown_is_clamped() -> void:
	model.add_meltdown(15.0)
	assert_eq(model.meltdown, 15.0)
	model.add_meltdown(95.0)
	assert_eq(model.meltdown, 100.0)
