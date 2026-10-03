extends GutTest
## M10: the pure parts of AiSenses (fair play): the field of view, hearing radii, the reaction time.

var tuning := BotTuning.load_default()


func test_can_notice_in_front_within_range() -> void:
	var eye := Vector3(0, 1.6, 0)
	# yaw 0 faces -Z (Godot's forward)
	assert_true(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(0, 0.25, -10)), "straight ahead")
	assert_false(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(0, 0.25, -30)), "too far")
	assert_false(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(0, 0.25, 10)), "behind")
	assert_true(AiSenses.can_notice(eye, PI, 110.0, 22.0, Vector3(0, 0.25, 10)), "turned around")
	assert_true(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(5, 0.25, -5)), "45° to the side: inside 110°")
	assert_false(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(10, 0.25, -1)), "84° to the side: outside 110°")


func test_rats_see_around_them_but_not_straight_behind() -> void:
	var eye := Vector3(0, 0.8, 0)
	assert_true(AiSenses.can_notice(eye, 0.0, tuning.fov_rat_deg, 22.0, Vector3(10, 1, 1)), "95° to the side")
	assert_false(AiSenses.can_notice(eye, 0.0, tuning.fov_rat_deg, 22.0, Vector3(0, 1, 10)), "straight behind")
	assert_true(AiSenses.can_notice(eye, 0.0, 360.0, 22.0, Vector3(0, 1, 10)), "360°: anywhere")
	assert_true(AiSenses.can_notice(eye, 0.0, 110.0, 22.0, Vector3(0.1, 0.5, 0.1)), "point blank counts")


func test_hearing_radius() -> void:
	var rat_walk := Role.data(Role.Kind.RAT).walk_speed
	assert_eq(AiSenses.hearing_radius(Role.Kind.RAT, 0.2, rat_walk, tuning), 0.0, "standing still is silent")
	assert_eq(AiSenses.hearing_radius(Role.Kind.RAT, rat_walk, rat_walk, tuning), tuning.hear_rat_walk)
	assert_eq(AiSenses.hearing_radius(Role.Kind.RAT, Role.data(Role.Kind.RAT).sprint_speed, rat_walk, tuning),
		tuning.hear_rat_sprint, "sprinting is louder")
	assert_eq(AiSenses.hearing_radius(Role.Kind.SUPERVISOR, 4.0, 4.0, tuning), tuning.hear_supervisor)


func test_reaction_time() -> void:
	assert_false(AiSenses.seen_long_enough(-1.0, 5.0, 0.4), "not in sight")
	assert_false(AiSenses.seen_long_enough(4.8, 5.0, 0.4), "0.2 s of sight: not yet")
	assert_true(AiSenses.seen_long_enough(4.6, 5.0, 0.4), "0.4 s: seen")
	var easy := tuning.skill(0)
	var hard := tuning.skill(2)
	assert_true(AiSenses.seen_long_enough(4.7, 5.0, hard.reaction_s) and not AiSenses.seen_long_enough(4.7, 5.0, easy.reaction_s),
		"hard bots react faster than easy ones")
