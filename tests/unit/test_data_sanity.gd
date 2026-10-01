extends GutTest
## Every tuning resource loads and matches the GDD (§2, §3, §5). Update both together.


func test_supervisor_matches_gdd() -> void:
	var r := Role.data(Role.Kind.SUPERVISOR)
	assert_eq(r.kind, Role.Kind.SUPERVISOR)
	assert_eq([r.height, r.radius, r.walk_speed, r.sprint_speed], [1.8, 0.35, 4.0, 6.0])
	assert_eq([r.stamina_s, r.stamina_regen_s, r.stamina_regen_delay_s, r.jump_height], [5.0, 4.0, 1.0, 1.0])
	assert_false(r.can_use_vents)
	assert_eq(r.camera_kind, RoleData.CameraKind.FIRST_PERSON)


func test_rat_matches_gdd() -> void:
	var r := Role.data(Role.Kind.RAT)
	assert_eq(r.kind, Role.Kind.RAT)
	assert_eq([r.height, r.radius, r.walk_speed, r.sprint_speed], [0.5, 0.2, 5.0, 7.5])
	assert_eq([r.stamina_s, r.stamina_regen_s, r.jump_height], [3.0, 3.0, 1.6])
	assert_true(r.can_use_vents)
	assert_eq(r.camera_kind, RoleData.CameraKind.THIRD_PERSON)


func test_every_role_with_a_body_is_sane() -> void:
	for kind: Role.Kind in [Role.Kind.NONE, Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		var r := Role.data(kind)
		assert_not_null(r, Role.display_name(kind))
		assert_not_null(r.visual_scene)
		assert_true(r.height >= 2.0 * r.radius, "a capsule must be at least as tall as it is wide")
		assert_true(r.sprint_speed > r.walk_speed and r.walk_speed > 0.0)
		assert_true(r.stamina_s > 0.0 and r.stamina_regen_s > 0.0 and r.stamina_regen_delay_s >= 0.0)
	assert_null(Role.data(Role.Kind.SPECTATOR))


func test_supervisors_do_not_fit_through_vents() -> void:
	const VENT_HEIGHT := 0.6  # TestArena openings: 0.7 m wide, 0.6 m high
	assert_true(Role.data(Role.Kind.SUPERVISOR).height > VENT_HEIGHT)
	assert_true(Role.data(Role.Kind.RAT).height < VENT_HEIGHT)


func test_match_rules_match_gdd() -> void:
	var m: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	assert_eq([m.duration_s, m.duration_single_supervisor_s, m.countdown_s, m.post_match_s], [540, 480, 10, 15])
	assert_eq(m.min_players, 3)
	assert_eq(m.max_rats, 4)
	for n: int in {2: 1, 3: 1, 4: 1, 5: 2, 6: 2}:
		assert_eq(m.supervisors_for(n), {2: 1, 3: 1, 4: 1, 5: 2, 6: 2}[n], "%d players" % n)


func test_validator_allowed_distance() -> void:
	assert_almost_eq(MovementValidator.allowed_distance(6.0, 0.25), 2.75, 0.001)
	assert_almost_eq(MovementValidator.allowed_distance(0.0, 0.25), 0.5, 0.001, "frozen: only the slack")
