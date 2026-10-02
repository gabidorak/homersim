extends GutTest
## HazardRules: activation hysteresis, cycle phase math, radiation exposure, jet knockback (GDD §6).


func test_hysteresis_switches_on_below_50() -> void:
	assert_false(HazardRules.next_active(false, 50.0, 50.0, 60.0), "exactly 50 is not below 50")
	assert_true(HazardRules.next_active(false, 49.9, 50.0, 60.0))
	assert_true(HazardRules.next_active(false, 0.0, 50.0, 60.0))


func test_hysteresis_stays_on_until_60() -> void:
	assert_true(HazardRules.next_active(true, 50.0, 50.0, 60.0), "a repair to 50 doesn't stop it")
	assert_true(HazardRules.next_active(true, 59.9, 50.0, 60.0))
	assert_false(HazardRules.next_active(true, 60.0, 50.0, 60.0))
	assert_false(HazardRules.next_active(true, 100.0, 50.0, 60.0))


func test_hysteresis_sequence() -> void:
	# A sabotage, a small repair, another, a big one: on, on, on, off.
	var active := false
	var seen: Array[bool] = []
	for health: float in [100.0, 0.0, 10.0, 55.0, 59.0, 85.0, 52.0]:
		active = HazardRules.next_active(active, health, 50.0, 60.0)
		seen.append(active)
	assert_eq(seen, [false, true, true, true, true, false, false])


func test_cycle_steam_3_on_3_off() -> void:
	for t: float in [0.0, 1.0, 2.99, 6.0, 8.5]:
		assert_true(HazardRules.cycle_live(t, 3.0, 3.0), "live at %.2f" % t)
	for t: float in [3.0, 4.5, 5.99, 9.0]:
		assert_false(HazardRules.cycle_live(t, 3.0, 3.0), "off at %.2f" % t)


func test_cycle_nothing_before_the_start() -> void:
	assert_false(HazardRules.cycle_live(-0.1, 3.0, 3.0))
	assert_eq(HazardRules.cycle_index(-0.1, 3.0, 3.0), -1)


func test_cycle_phase_shifts_the_cycle() -> void:
	# A jet with phase 3 is half a period ahead: off first, then live.
	assert_false(HazardRules.cycle_live(0.0, 3.0, 3.0, 3.0))
	assert_true(HazardRules.cycle_live(3.0, 3.0, 3.0, 3.0))
	# Two jets with phases 0 and 3 are never live together.
	for i in 120:
		var t := i * 0.1
		assert_false(HazardRules.cycle_live(t, 3.0, 3.0, 0.0) and HazardRules.cycle_live(t, 3.0, 3.0, 3.0), "t=%.1f" % t)


func test_puddle_2_s_every_5() -> void:
	var live := 0
	for i in 500:  # 50 s at 0.1 s steps
		if HazardRules.cycle_live(i * 0.1 + 0.05, 2.0, 3.0):
			live += 1
	assert_eq(live, 200, "live 40% of the time")


func test_cycle_index_counts_live_windows() -> void:
	assert_eq(HazardRules.cycle_index(0.5, 3.0, 3.0), 0)
	assert_eq(HazardRules.cycle_index(5.9, 3.0, 3.0), 0)
	assert_eq(HazardRules.cycle_index(6.0, 3.0, 3.0), 1)
	assert_eq(HazardRules.cycle_index(13.0, 3.0, 3.0), 2)


func test_time_to_switch() -> void:
	assert_almost_eq(HazardRules.time_to_switch(1.0, 3.0, 3.0), 2.0, 0.001, "live: 2 s to go")
	assert_almost_eq(HazardRules.time_to_switch(5.5, 3.0, 3.0), 0.5, 0.001, "off: 0.5 s to the next blast")
	assert_almost_eq(HazardRules.time_to_switch(-0.4, 3.0, 3.0), 0.4, 0.001, "before the start")


func test_always_live_without_an_off_time() -> void:
	assert_true(HazardRules.cycle_live(0.0, 1.0, 0.0))
	assert_true(HazardRules.cycle_live(123.4, 1.0, 0.0))


func test_radiation_exposure_builds_and_drains() -> void:
	var exposure := 0.0
	for i in 60:  # 6 s inside at 0.1 s steps
		exposure = HazardRules.exposure_step(exposure, true, 0.1, 5.0)
	assert_almost_eq(exposure, 5.0, 0.001, "capped at the 5 s threshold")
	for i in 20:  # 2 s outside
		exposure = HazardRules.exposure_step(exposure, false, 0.1, 5.0)
	assert_almost_eq(exposure, 3.0, 0.001)
	for i in 50:
		exposure = HazardRules.exposure_step(exposure, false, 0.1, 5.0)
	assert_eq(exposure, 0.0, "never negative")


func test_knockback_pushes_along_the_jet_and_up() -> void:
	var v := HazardRules.knockback(Vector3(0, 0, 1), Vector3.ZERO, Vector3(0, 0, 2), 6.0, 3.0)
	assert_almost_eq(Vector2(v.x, v.z).length(), 6.0, 0.001, "6 m/s horizontally")
	assert_almost_eq(v.y, 3.0, 0.001)
	assert_almost_eq(v.z, 6.0, 0.001, "straight down the axis when on it")


func test_knockback_also_pushes_off_the_axis() -> void:
	var v := HazardRules.knockback(Vector3(0, 0, 1), Vector3.ZERO, Vector3(0.5, 0, 2), 6.0, 0.0)
	assert_gt(v.x, 0.5, "a body right of the axis goes right")
	assert_gt(v.z, 5.0, "but mostly along the jet")
	assert_almost_eq(Vector2(v.x, v.z).length(), 6.0, 0.001)
