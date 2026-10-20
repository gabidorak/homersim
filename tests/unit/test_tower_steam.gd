extends GutTest
## The cooling tower's steam (levels/tower_steam.gd): its puffs never pop (they come out of the mouth
## as nothing, end as nothing, and move smoothly between), they rise and drift down the wind, the
## plume speeds up and swells with the core's heat and turns green with the meltdown meter, the
## coolant's sigh is told from the plant's own cooling, and the tower in the Yard has its steam.
## How it looks: tests/helpers/TowerSteamShots.tscn.

const YARD := "res://levels/plant/pois/Yard.tscn"
const WIND := Vector3(0, 0, -1)
const STEPS := 600  ## phase samples per puff cycle

var tuning: PlantTuning = preload("res://data/plant_tuning.tres")


func test_puffs_start_and_end_as_nothing() -> void:
	for p_heat in [0.0, 0.5, 1.0]:
		for i in TowerSteam.PUFFS:
			var born := -float(i) / TowerSteam.PUFFS  # the phase at which puff i's age is 0
			assert_almost_eq(TowerSteam.puff(i, born + 0.0001, p_heat, WIND)[1] as float, 0.0, 0.05, "puff %d is born small" % i)
			assert_almost_eq(TowerSteam.puff(i, born - 0.0001, p_heat, WIND)[1] as float, 0.0, 0.05, "puff %d dies small" % i)


func test_puffs_never_jump() -> void:
	# Over a whole cycle (and its wrap), a visible puff moves and grows a little per step, never more.
	for p_heat in [0.0, 1.0]:
		for i in TowerSteam.PUFFS:
			var last: Array = TowerSteam.puff(i, 0.0, p_heat, WIND)
			for k in range(1, STEPS + 1):
				var now: Array = TowerSteam.puff(i, float(k) / STEPS, p_heat, WIND)
				if (now[1] as float) > 0.5 and (last[1] as float) > 0.5:
					assert_lt((now[0] as Vector3).distance_to(last[0]), 0.5, "puff %d moves smoothly" % i)
				assert_lt(absf((now[1] as float) - (last[1] as float)), 0.5, "puff %d swells smoothly" % i)
				last = now


func test_puffs_rise_and_drift_with_the_wind() -> void:
	for i in TowerSteam.PUFFS:
		var born := -float(i) / TowerSteam.PUFFS
		var young: Vector3 = TowerSteam.puff(i, born + 0.2, 0.0, WIND)[0]
		var old: Vector3 = TowerSteam.puff(i, born + 0.8, 0.0, WIND)[0]
		assert_gt(young.y, 0.0, "above the mouth")
		assert_gt(old.y, young.y, "rises")
		assert_gt(old.dot(WIND), young.dot(WIND), "drifts down the wind")


func test_a_hot_core_puffs_faster_bigger_and_higher() -> void:
	assert_almost_eq(TowerSteam.period(0.0), TowerSteam.CALM_PERIOD, 0.001)
	assert_lt(TowerSteam.period(1.0), TowerSteam.period(0.5))
	assert_lt(TowerSteam.period(0.5), TowerSteam.period(0.0))
	assert_gt(_biggest(1.0), _biggest(0.0) * 1.2, "fatter puffs")
	assert_gt(_highest(1.0), _highest(0.0) + 5.0, "a taller plume")


func test_heat_follows_the_core() -> void:
	assert_eq(TowerSteam.heat_for(tuning.nominal_temp, tuning), 0.0, "a cool core: calm")
	assert_eq(TowerSteam.heat_for(tuning.min_temp - 50.0, tuning), 0.0)
	var warning := TowerSteam.heat_for(tuning.warning_temp, tuning)
	var critical := TowerSteam.heat_for(tuning.critical_temp, tuning)
	assert_between(warning, 0.2, 0.6, "the warning shows")
	assert_almost_eq(critical, 0.8, 0.001, "the critical alarm: chugging")
	assert_eq(TowerSteam.heat_for(tuning.max_temp, tuning), 1.0)
	var last := -1.0
	for t in range(int(tuning.min_temp), int(tuning.max_temp) + 1, 10):
		var h := TowerSteam.heat_for(t, tuning)
		assert_true(h >= last, "never cooler for a hotter core (%d°)" % t)
		last = h


func test_the_meltdown_turns_it_green() -> void:
	assert_eq(TowerSteam.goo_tint(0.0), 0.0)
	assert_eq(TowerSteam.goo_tint(0.15), 0.0, "a little meltdown doesn't show yet")
	assert_gt(TowerSteam.goo_tint(0.6), TowerSteam.goo_tint(0.4))
	assert_almost_eq(TowerSteam.goo_tint(1.0), TowerSteam.GOO_MAX, 0.001, "green, but not the cough's full green")
	assert_lt(TowerSteam.GOO_MAX, 1.0)


func test_the_coolant_sighs_not_the_plant_cooling() -> void:
	assert_true(TowerSteam.is_coolant(800.0, 800.0 - tuning.coolant_amount, tuning))
	# The plant's own cooling, over one replication tick (generous: a whole second).
	assert_false(TowerSteam.is_coolant(800.0, 800.0 - tuning.cooling_rate, tuning))
	assert_false(TowerSteam.is_coolant(500.0, 520.0, tuning), "heating up")


func test_the_sigh_bursts_then_goes() -> void:
	for i in TowerSteam.SIGH_BALLS:
		assert_eq(TowerSteam.sigh_puff(i, INF, WIND)[1], 0.0, "nothing before any coolant")
		assert_eq(TowerSteam.sigh_puff(i, 0.0, WIND)[1], 0.0, "nothing at the very start")
		assert_gt(TowerSteam.sigh_puff(i, TowerSteam.SIGH_LIFE * 0.3, WIND)[1] as float, 5.0, "a big round puff")
		assert_eq(TowerSteam.sigh_puff(i, TowerSteam.SIGH_LIFE + 0.2, WIND)[1], 0.0, "gone after its life")


func test_headless_builds_nothing() -> void:
	var steam := TowerSteam.new()
	add_child_autofree(steam)
	if Art.headless():
		assert_eq(steam.get_child_count(), 0, "the server builds no puffs")
		assert_false(steam.is_processing())
	else:
		assert_eq(steam.get_child_count(), TowerSteam.PUFFS + TowerSteam.SIGH_BALLS)


func test_the_yard_tower_steams_from_its_mouth() -> void:
	var yard := (load(YARD) as PackedScene).instantiate()
	var steam := yard.get_node_or_null("TowerSteam") as TowerSteam
	var tower := yard.get_node_or_null("CoolingTower") as Node3D
	assert_not_null(steam, "the Yard has its tower's steam")
	assert_not_null(tower)
	if steam != null and tower != null:
		assert_almost_eq(steam.position, tower.position + Vector3(0, 22, 0), Vector3.ONE * 0.5,
			"at the top of the 22 m tower")
	yard.free()


func _biggest(p_heat: float) -> float:
	var best := 0.0
	for k in STEPS:
		best = maxf(best, TowerSteam.puff(0, float(k) / STEPS, p_heat, WIND)[1])
	return best


func _highest(p_heat: float) -> float:
	var best := 0.0
	for k in STEPS:
		var p: Array = TowerSteam.puff(0, float(k) / STEPS, p_heat, WIND)
		if (p[1] as float) > 0.5:
			best = maxf(best, (p[0] as Vector3).y)
	return best
