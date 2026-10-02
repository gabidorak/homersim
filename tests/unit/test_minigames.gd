extends GutTest
## The repair minigames' rules, driven through the same methods as the mouse (and the test bots).
## Real time only enters through advance(delta), so these run in a single frame.

const WRENCH := preload("res://minigames/wrench_rhythm/WrenchRhythm.tscn")
const BREAKERS := preload("res://minigames/breaker_sequence/BreakerSequence.tscn")
const VALVE := preload("res://minigames/valve_rotate/ValveRotate.tscn")


func _make(scene: PackedScene, seed_value: int = 42, difficulty: float = 0.5) -> Minigame:
	# A fixed-size parent, like the host's panel: the minigame's anchors make it fill it.
	var frame := Control.new()
	frame.size = Vector2(800, 500)
	add_child_autofree(frame)
	var game: Minigame = scene.instantiate()
	frame.add_child(game)
	game.set_process(false)  # time only moves when the test says so
	game.start(seed_value, difficulty)
	return game


## Runs autoplay + advance at 60 Hz until the game ends or `limit` seconds pass.
func _autoplay(game: Minigame, limit: float) -> void:
	var t := 0.0
	while not game.done and t < limit:
		game.autoplay(1.0 / 60.0)
		game.advance(1.0 / 60.0)
		t += 1.0 / 60.0


func test_same_seed_same_puzzle() -> void:
	var a := _make(BREAKERS, 7) as BreakerSequence
	var b := _make(BREAKERS, 7) as BreakerSequence
	var c := _make(BREAKERS, 8) as BreakerSequence
	assert_eq(a.sequence, b.sequence)
	assert_ne(a.sequence, c.sequence, "another seed, another sequence (almost surely)")


func test_wrench_three_hits_in_a_row_win() -> void:
	var game := _make(WRENCH) as WrenchRhythm
	for i in 3:
		game.marker = game.zone_center
		game.press()
	assert_true(game.done and game.success)


func test_wrench_a_miss_resets_the_streak_and_three_lose() -> void:
	var game := _make(WRENCH) as WrenchRhythm
	game.marker = game.zone_center
	game.press()
	assert_eq(game.streak, 1)
	for i in 3:
		game.marker = fposmod(game.zone_center + 0.5, 1.0)
		game.press()
	assert_eq(game.streak, 0)
	assert_true(game.done)
	assert_false(game.success)


func test_wrench_runs_out_of_time() -> void:
	var game := _make(WRENCH)
	game.advance(WrenchRhythm.TIME_LIMIT_S + 0.1)
	assert_true(game.done and not game.success)


func test_wrench_marker_moves_with_time_not_frames() -> void:
	var a := _make(WRENCH) as WrenchRhythm
	var b := _make(WRENCH) as WrenchRhythm
	a.advance(0.5)
	for i in 50:
		b.advance(0.01)
	assert_almost_eq(a.marker, b.marker, 0.001)


func test_wrench_autoplay_takes_a_few_seconds() -> void:
	var game := _make(WRENCH)
	_autoplay(game, 12.0)
	assert_true(game.success, "autoplay wins")
	assert_between(game.elapsed, 0.5, 8.0)


func test_breakers_ignore_clicks_while_showing() -> void:
	var game := _make(BREAKERS) as BreakerSequence
	game.press_breaker(game.sequence[0])
	assert_eq(game.next_index, 0)
	assert_eq(game.phase, BreakerSequence.Phase.SHOW)


func test_breakers_right_order_wins() -> void:
	var game := _make(BREAKERS) as BreakerSequence
	game.advance(game.show_duration() + 0.01)
	assert_eq(game.phase, BreakerSequence.Phase.INPUT)
	for index in game.sequence:
		game.press_breaker(index)
	assert_true(game.done and game.success)
	assert_between(game.sequence.size(), 4, 5)


func test_breakers_wrong_breaker_loses() -> void:
	var game := _make(BREAKERS) as BreakerSequence
	game.advance(game.show_duration() + 0.01)
	game.press_breaker(game.sequence[0])
	game.press_breaker((game.sequence[1] + 1) % BreakerSequence.COUNT)
	assert_true(game.done and not game.success)


func test_breaker_rects_fit_any_size() -> void:
	var game := _make(BREAKERS) as BreakerSequence
	for s: Vector2 in [Vector2(300, 200), Vector2(1920, 1080), Vector2(500, 900)]:
		(game.get_parent() as Control).size = s
		for i in BreakerSequence.COUNT:
			assert_true(Rect2(Vector2.ZERO, s).encloses(game.breaker_rect(i)), "breaker %d inside %s" % [i, s])


func test_valve_needs_the_band_for_a_second() -> void:
	var game := _make(VALVE) as ValveRotate
	game.rotate_by(game.target)
	game.advance(0.5)
	assert_false(game.done)
	game.rotate_by(PI)  # overshoot: out of the band, the hold restarts
	game.advance(0.6)
	assert_eq(game.held, 0.0)
	game.rotate_by(-PI)
	game.advance(0.5)
	game.advance(0.55)
	assert_true(game.done and game.success)


func test_valve_runs_out_of_time() -> void:
	var game := _make(VALVE)
	game.advance(ValveRotate.TIME_LIMIT_S + 0.1)
	assert_true(game.done and not game.success)


func test_valve_and_breaker_autoplay_win_in_about_4_to_6_s() -> void:
	for scene: PackedScene in [VALVE, BREAKERS]:
		var game := _make(scene)
		_autoplay(game, 15.0)
		assert_true(game.success, scene.resource_path)
		assert_between(game.elapsed, 2.0, 8.0, scene.resource_path)
