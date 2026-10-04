extends GutTest
## M10: the AI's utility scores (AiScoring): what goes up, what goes down, and how the goals compare.

var tuning := BotTuning.load_default()


func test_travel_factor() -> void:
	assert_eq(AiScoring.travel_factor(0.0), 1.0)
	assert_almost_eq(AiScoring.travel_factor(AiScoring.TRAVEL_HALF_S), 0.5, 0.001)
	assert_eq(AiScoring.travel_factor(INF), 0.0, "unreachable: worthless")
	assert_true(AiScoring.travel_factor(5.0) > AiScoring.travel_factor(20.0))


func test_sabotage() -> void:
	var base := AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, 0.0)
	assert_between(base, 0.0, 1.0)
	assert_eq(AiScoring.sabotage(2.5, 0.0, 50.0, 10.0, 0.0), 0.0, "already broken")
	assert_eq(AiScoring.sabotage(2.5, 100.0, 50.0, INF, 0.0), 0.0, "unreachable")
	assert_true(AiScoring.sabotage(3.0, 100.0, 50.0, 10.0, 0.0) > AiScoring.sabotage(1.0, 100.0, 50.0, 10.0, 0.0),
		"hotter machines first")
	assert_true(AiScoring.sabotage(2.5, 100.0, 50.0, 5.0, 0.0) > AiScoring.sabotage(2.5, 100.0, 50.0, 25.0, 0.0),
		"nearer first")
	assert_true(AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, 1.0) < base, "a known supervisor near the point")
	var half_danger := AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, 0.5)
	assert_true(half_danger < base and half_danger > AiScoring.sabotage(2.5, 100.0, 50.0, 10.0, 1.0), "closer is worse")
	assert_true(AiScoring.sabotage(2.5, 50.0, 50.0, 10.0, 0.0) > AiScoring.sabotage(2.5, 50.0, 0.0, 10.0, 0.0),
		"a hit that starts the hazards (below 50) is worth more")


func test_lever_pair_needs_a_partner() -> void:
	assert_eq(AiScoring.lever_pair(3.0, 100.0, 8.0, 0.0), 0.0, "nobody to pair with")
	var maybe := AiScoring.lever_pair(3.0, 100.0, 8.0, 0.6)
	var waiting := AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15)
	assert_true(waiting > maybe and maybe > 0.0, "a partner already waiting beats a maybe")
	assert_true(AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15) > AiScoring.sabotage(2.5, 100.0, 50.0, 8.0, 0.0),
		"a waiting partner on the rods beats a lone sabotage of the pumps")


func test_flee() -> void:
	assert_eq(AiScoring.flee(4.0, false, 7.0, false), 0.0, "not closing in")
	assert_eq(AiScoring.flee(9.0, true, 7.0, false), 0.0, "far enough")
	assert_true(AiScoring.flee(2.0, true, 7.0, false) > AiScoring.flee(6.0, true, 7.0, false), "closer = more urgent")
	assert_true(AiScoring.flee(8.0, false, 7.0, true) >= 0.9, "a broom swing heard nearby")
	# A rat sabotaging with a supervisor 2 m away and closing runs, commitment bonus or not.
	var busy := AiScoring.committed(AiScoring.sabotage(3.0, 100.0, 50.0, 0.0, 1.0), true, tuning.commitment_bonus)
	assert_true(AiScoring.flee(2.0, true, 7.0, false) > busy)


func test_rescue_harass_free_lurk() -> void:
	assert_true(AiScoring.rescue(1.0, 7.0) > 0.85, "a carried friend right here")
	assert_eq(AiScoring.rescue(9.0, 7.0), 0.0, "too far to get there before the cage")
	assert_eq(AiScoring.harass(3.0, false), 0.0, "only a busy supervisor")
	assert_true(AiScoring.harass(1.0, true) > AiScoring.harass(10.0, true))
	assert_eq(AiScoring.free_caged(1, 10.0, true), 0.0, "a supervisor guards the cage")
	assert_true(AiScoring.free_caged(2, 10.0, false) > AiScoring.free_caged(1, 10.0, false), "more friends inside")
	assert_true(AiScoring.free_caged(1, 30.0, false) > AiScoring.LURK, "freeing beats lurking")
	assert_true(AiScoring.sabotage(1.0, 100.0, 50.0, 30.0, 0.0) > AiScoring.LURK, "any sabotage beats lurking")


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


func test_capture_with_the_twelve_second_carry() -> void:
	var carry := PvpTuning.load_default().carry_max_s
	assert_eq(AiScoring.capture(true, 9.0, carry, tuning.carry_spare_s), 0.95, "a cage 29 m away at 3.2 m/s")
	assert_eq(AiScoring.capture(true, 11.0, carry, tuning.carry_spare_s), 0.0, "too tight: it would wriggle free")


func test_danger_makes_rats_careful() -> void:
	assert_eq(AiScoring.careful(0.0), 1.0)
	assert_true(AiScoring.careful(1.0) < 0.5, "a supervisor right there")
	assert_true(AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15, 0.8) < AiScoring.lever_pair(3.0, 100.0, 8.0, 1.15, 0.0))
	assert_true(AiScoring.break_camera(2.0, 8.0, true, 1.0) < AiScoring.break_camera(2.0, 8.0, true, 0.0))


func test_traps() -> void:
	assert_eq(AiScoring.place_trap(1.0, 5.0, 0), 0.0, "no charges")
	assert_true(AiScoring.place_trap(1.0, 5.0, 3) > AiScoring.place_trap(0.3, 5.0, 3), "valuable machines first")
	assert_true(AiScoring.place_trap(1.0, 5.0, 3) > AiScoring.patrol(3.0, 60.0, tuning.patrol_revisit_s), "beats a patrol")
	assert_true(AiScoring.place_trap(1.0, 5.0, 3) < AiScoring.repair(2.5, 50.0, false, 0, 10.0), "a broken machine first")
	assert_eq(AiScoring.refill(1, true, 10.0), 0.0, "charges left")
	assert_eq(AiScoring.refill(0, false, 10.0), 0.0, "not while the plant needs us")
	assert_true(AiScoring.refill(0, true, 10.0) > AiScoring.PATROL_BASE)


func test_investigate() -> void:
	assert_eq(AiScoring.investigate("snap", 30.0, 25.0), 0.0, "too far to hear")
	assert_true(AiScoring.investigate("snap", 10.0, 25.0) > AiScoring.repair(2.5, 50.0, false, 0, 10.0), "a trapped rat first")
	assert_true(AiScoring.investigate("rat", 10.0, 35.0, true) > AiScoring.investigate("rat", 10.0, 35.0, false), "a saboteur")
	assert_true(AiScoring.investigate("rat", 10.0, 35.0) > AiScoring.investigate("search", 10.0, 35.0), "fresh beats old")
	assert_true(AiScoring.investigate("rat", 5.0, 35.0) > AiScoring.investigate("rat", 30.0, 35.0), "nearer first")


func test_keycard_donut_cctv_camera() -> void:
	assert_eq(AiScoring.keycard(false, false, 5.0), 0.0, "the spare isn't ready")
	assert_true(AiScoring.keycard(true, false, 5.0) > AiScoring.keycard(false, true, 5.0), "a dropped one is better")
	assert_eq(AiScoring.donut(false, 0.0, 12.0), 0.0, "not ready")
	assert_eq(AiScoring.donut(true, 20.0, 12.0), 0.0, "too far out of the way")
	assert_true(AiScoring.donut(true, 2.0, 12.0) > AiScoring.donut(true, 10.0, 12.0))
	assert_eq(AiScoring.cctv(false, true, true, 5.0), 0.0, "only when calm")
	assert_eq(AiScoring.cctv(true, false, true, 5.0), 0.0, "the chair is taken")
	assert_eq(AiScoring.cctv(true, true, false, 5.0), 0.0, "not again so soon")
	assert_true(AiScoring.cctv(true, true, true, 5.0) < AiScoring.repair(1.0, 80.0, false, 0, 20.0), "repairs come first")
	assert_true(AiScoring.cctv(true, true, true, 5.0) > AiScoring.PATROL_BASE, "beats walking around")
	assert_true(AiScoring.fix_camera(2.0) > AiScoring.fix_camera(30.0), "on the way")


func test_control_room() -> void:
	assert_eq(AiScoring.coolant(600.0, 650.0, true, 5.0), 0.0, "not hot enough")
	assert_eq(AiScoring.coolant(700.0, 650.0, false, 5.0), 0.0, "cooling down or no power")
	assert_true(AiScoring.coolant(800.0, 650.0, true, 5.0) > AiScoring.coolant(660.0, 650.0, true, 5.0), "hotter: more urgent")
	assert_true(AiScoring.coolant(700.0, 650.0, true, 10.0) > AiScoring.repair(2.5, 50.0, false, 2, 10.0), "beats a repair")
	assert_eq(AiScoring.scram(700.0, 20.0, 760.0, 50.0, true, 5.0), 0.0, "costs 30 s of shift: only when critical")
	assert_true(AiScoring.scram(780.0, 20.0, 760.0, 50.0, true, 5.0) > 0.7)
	assert_true(AiScoring.scram(700.0, 60.0, 760.0, 50.0, true, 5.0) > 0.7, "or the meltdown past half")


func test_steal_camera_gang() -> void:
	assert_eq(AiScoring.steal(3.0, 10.0, true, false, true), 0.0, "it faces us")
	assert_eq(AiScoring.steal(3.0, 10.0, false, true, true), 0.0, "it walks")
	assert_eq(AiScoring.steal(3.0, 10.0, true, true, false), 0.0, "no keycard left")
	assert_true(AiScoring.steal(1.0, 10.0, true, true, true) > AiScoring.harass(1.0, true), "steal first, bite after")
	assert_true(AiScoring.break_camera(2.0, 8.0, true) > AiScoring.break_camera(2.0, 8.0, false), "someone watches")
	assert_true(AiScoring.break_camera(2.0, 8.0, false) > AiScoring.LURK, "beats lurking on the way")
	assert_eq(AiScoring.gang(1, false, true), 0.0, "alone")
	assert_eq(AiScoring.gang(3, false, false), 0.0, "easy bots don't")
	assert_eq(AiScoring.gang(2, true, true), 0.0, "already down")
	assert_true(AiScoring.gang(3, false, true) >= AiScoring.gang(2, false, true))
