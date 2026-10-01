extends GutTest


func _run(stamina: Stamina, seconds: float, sprint: bool, step: float = 0.05) -> int:
	var sprinted := 0
	for i in roundi(seconds / step):
		if stamina.tick(step, sprint):
			sprinted += 1
	return sprinted


func test_full_bar_lasts_stamina_seconds() -> void:
	var s := Stamina.new(5.0, 4.0, 1.0)
	assert_eq(_run(s, 5.5, true), 100, "5 s of sprint at 20 ticks/s")
	assert_true(s.exhausted)
	assert_eq(s.current, 0.0)


func test_no_regen_during_the_delay_then_full_in_regen_seconds() -> void:
	var s := Stamina.new(5.0, 4.0, 1.0)
	_run(s, 5.0, true)
	_run(s, 0.95, false)
	assert_eq(s.current, 0.0, "still waiting for the 1 s delay")
	_run(s, 4.1, false)
	assert_almost_eq(s.current, 5.0, 0.01)


func test_exhausted_until_a_quarter_of_the_bar() -> void:
	var s := Stamina.new(4.0, 4.0, 0.0)
	_run(s, 4.0, true)
	assert_true(s.exhausted)
	assert_false(s.tick(0.05, true), "can't sprint while exhausted")
	_run(s, 1.1, false)  # refills 1 unit per second -> past 25 %
	assert_false(s.exhausted)
	assert_true(s.tick(0.05, true))


func test_short_sprints_restart_the_delay() -> void:
	var s := Stamina.new(3.0, 3.0, 1.0)
	_run(s, 1.0, true)
	_run(s, 0.5, false)
	_run(s, 0.05, true)
	_run(s, 0.9, false)
	assert_almost_eq(s.current, 1.95, 0.01, "no refill yet: the delay restarted")


func test_jump_velocity_reaches_the_height() -> void:
	var v := MovementComponent.jump_velocity(1.0, 9.8)
	assert_almost_eq(v * v / (2.0 * 9.8), 1.0, 0.001)
