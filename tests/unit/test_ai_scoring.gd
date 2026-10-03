extends GutTest
## M10: the AI's utility scores (AiScoring): what goes up, what goes down, and how the goals compare.

var tuning := BotTuning.load_default()


func test_travel_factor() -> void:
	assert_eq(AiScoring.travel_factor(0.0), 1.0)
	assert_almost_eq(AiScoring.travel_factor(AiScoring.TRAVEL_HALF_S), 0.5, 0.001)
	assert_eq(AiScoring.travel_factor(INF), 0.0, "unreachable: worthless")
	assert_true(AiScoring.travel_factor(5.0) > AiScoring.travel_factor(20.0))


func test_sabotage() -> void:
	var base := AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, false)
	assert_between(base, 0.0, 1.0)
	assert_eq(AiScoring.sabotage(2.5, 0.0, 50.0, 10.0, false), 0.0, "already broken")
	assert_eq(AiScoring.sabotage(2.5, 100.0, 50.0, INF, false), 0.0, "unreachable")
	assert_true(AiScoring.sabotage(3.0, 100.0, 50.0, 10.0, false) > AiScoring.sabotage(1.0, 100.0, 50.0, 10.0, false),
		"hotter machines first")
	assert_true(AiScoring.sabotage(2.5, 100.0, 50.0, 5.0, false) > AiScoring.sabotage(2.5, 100.0, 50.0, 25.0, false),
		"nearer first")
	assert_true(AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, true) < base, "a known supervisor near the point")
	assert_true(AiScoring.sabotage(2.5, 50.0, 50.0, 10.0, false) > AiScoring.sabotage(2.5, 50.0, 0.0, 10.0, false),
		"a hit that starts the hazards (below 50) is worth more")


func test_lever_pair_needs_a_partner() -> void:
	assert_eq(AiScoring.lever_pair(3.0, 100.0, 8.0, 0.0), 0.0, "nobody to pair with")
	var maybe := AiScoring.lever_pair(3.0, 100.0, 8.0, 0.6)
	var waiting := AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15)
	assert_true(waiting > maybe and maybe > 0.0, "a partner already waiting beats a maybe")
	assert_true(AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15) > AiScoring.sabotage(2.5, 100.0, 50.0, 8.0, false),
		"a waiting partner on the rods beats a lone sabotage of the pumps")


func test_flee() -> void:
	assert_eq(AiScoring.flee(4.0, false, 7.0, false), 0.0, "not closing in")
	assert_eq(AiScoring.flee(9.0, true, 7.0, false), 0.0, "far enough")
	assert_true(AiScoring.flee(2.0, true, 7.0, false) > AiScoring.flee(6.0, true, 7.0, false), "closer = more urgent")
	assert_true(AiScoring.flee(8.0, false, 7.0, true) >= 0.9, "a broom swing heard nearby")
	# A rat sabotaging with a supervisor 2 m away and closing runs, commitment bonus or not.
	var busy := AiScoring.committed(AiScoring.sabotage(3.0, 100.0, 50.0, 0.0, true), true, tuning.commitment_bonus)
	assert_true(AiScoring.flee(2.0, true, 7.0, false) > busy)


func test_rescue_harass_free_lurk() -> void:
	assert_true(AiScoring.rescue(1.0, 7.0) > 0.85, "a carried friend right here")
	assert_eq(AiScoring.rescue(9.0, 7.0), 0.0, "too far to get there before the cage")
	assert_eq(AiScoring.harass(3.0, false), 0.0, "only a busy supervisor")
	assert_true(AiScoring.harass(1.0, true) > AiScoring.harass(10.0, true))
	assert_eq(AiScoring.free_caged(1, 10.0, true), 0.0, "a supervisor guards the cage")
	assert_true(AiScoring.free_caged(2, 10.0, false) > AiScoring.free_caged(1, 10.0, false), "more friends inside")
	assert_true(AiScoring.free_caged(1, 30.0, false) > AiScoring.LURK, "freeing beats lurking")
	assert_true(AiScoring.sabotage(1.0, 100.0, 50.0, 30.0, false) > AiScoring.LURK, "any sabotage beats lurking")


func test_repair() -> void:
	assert_eq(AiScoring.repair(2.5, 100.0, false, 0, 10.0), 0.0, "nothing to repair")
	var half := AiScoring.repair(2.5, 50.0, false, 0, 10.0)
	assert_true(AiScoring.repair(2.5, 0.0, true, 0, 10.0) > half, "offline first")
	assert_true(AiScoring.repair(2.5, 50.0, false, 2, 10.0) > half, "more urgent as the alarm rises")
	assert_true(AiScoring.repair(2.5, 50.0, false, 0, 40.0) < half, "far away")
	assert_true(AiScoring.repair(3.0, 50.0, false, 0, 10.0) > AiScoring.repair(1.0, 50.0, false, 0, 10.0), "hotter first")
	assert_eq(AiScoring.repair(2.5, 50.0, false, 0, INF), 0.0, "unreachable")
	assert_true(AiScoring.repair(1.0, 65.0, false, 0, 20.0) > AiScoring.patrol(3.0, 999.0, tuning.patrol_revisit_s),
		"any repair beats a patrol")


func test_chase_and_capture() -> void:
	var r := tuning.chase_radius
	assert_eq(AiScoring.chase(r + 1.0, r, true, false, true), 0.0, "out of range")
	assert_true(AiScoring.chase(10.0, r, true, false, true) > AiScoring.chase(3.0, r, false, false, true),
		"a rat busy sabotaging is the best target")
	assert_true(AiScoring.chase(8.0, r, false, true, true) < AiScoring.chase(8.0, r, false, false, true),
		"not one already running away")
	assert_true(AiScoring.chase(4.0, r, false, false, false) < AiScoring.chase(4.0, r, false, false, true), "heard < seen")
	assert_true(AiScoring.chase(5.0, r, true, false, true) > AiScoring.repair(2.5, 50.0, false, 0, 10.0),
		"a sabotaging rat in sight beats a half-broken machine")
	assert_eq(AiScoring.capture(true, 5.0, 8.0, 1.5), 0.95)
	assert_eq(AiScoring.capture(true, 7.0, 8.0, 1.5), 0.0, "the rat would wriggle free before the cage")
	assert_eq(AiScoring.capture(false, 1.0, 8.0, 1.5), 0.0, "not stunned")


func test_guard_and_patrol() -> void:
	assert_eq(AiScoring.guard_cages(0), 0.0)
	assert_true(AiScoring.guard_cages(2) > AiScoring.guard_cages(1))
	assert_true(AiScoring.patrol(3.0, 60.0, 60.0) > AiScoring.patrol(3.0, 5.0, 60.0), "a room not seen for a while")
	assert_true(AiScoring.patrol(3.0, 60.0, 60.0) > AiScoring.patrol(1.0, 60.0, 60.0), "hotter rooms")


func test_commitment() -> void:
	assert_almost_eq(AiScoring.committed(0.4, true, 0.15), 0.55, 0.001)
	assert_eq(AiScoring.committed(0.4, false, 0.15), 0.4)
	assert_eq(AiScoring.committed(0.0, true, 0.15), 0.0, "a goal with nothing to do gets no bonus")
