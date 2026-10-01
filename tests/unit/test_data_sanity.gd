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
	const VENT_HEIGHT := 0.6  # vent openings (TestArena and the plant): 0.7 m wide, 0.6 m high
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


func test_subsystems_match_gdd() -> void:
	var tuning: PlantTuning = load(PlantSim.TUNING_PATH)
	# GDD §4 table, in index order: id, heat_weight, critical, hazard
	var table := [
		[&"rods", 3.0, true, SubsystemData.HazardKind.RADIATION],
		[&"pumps", 2.5, false, SubsystemData.HazardKind.STEAM],
		[&"valves", 2.0, false, SubsystemData.HazardKind.STEAM],
		[&"turbine", 1.5, true, SubsystemData.HazardKind.DEBRIS],
		[&"grid", 1.5, false, SubsystemData.HazardKind.ELECTRIC],
		[&"ventilation", 1.0, false, SubsystemData.HazardKind.SMOKE],
	]
	assert_eq(tuning.subsystems.size(), table.size())
	for i in table.size():
		var s := tuning.subsystems[i]
		assert_eq([s.id, s.heat_weight, s.critical, s.hazard_kind], table[i], "subsystem %d" % i)
		assert_false(s.display_name.is_empty())
		assert_between(s.short_name.length(), 1, 4)


func test_plant_tuning_matches_gdd() -> void:
	var t: PlantTuning = load(PlantSim.TUNING_PATH)
	assert_eq([t.nominal_temp, t.min_temp, t.max_temp, t.cooling_rate], [300.0, 300.0, 1000.0, 1.5])
	assert_eq([t.warning_temp, t.critical_temp], [500.0, 700.0])
	assert_eq([t.meltdown_start_temp, t.meltdown_fill_rate, t.meltdown_recover_temp, t.meltdown_decay_rate],
		[700.0, 1.0, 400.0, 0.25])
	assert_eq([t.max_health, t.sabotage_damage, t.critical_sabotage_damage], [100.0, 50.0, 100.0])
	assert_eq([t.sabotage_cooldown_s, t.sabotage_hold_s, t.critical_hold_s], [20.0, 4.0, 6.0])
	assert_eq([t.repair_amount, t.repair_hold_s, t.reboot_hold_s], [35.0, 6.0, 3.0])
	assert_eq(t.scram_heat_factor, 0.5)
	assert_true(t.min_temp <= t.nominal_temp and t.nominal_temp < t.warning_temp)
	assert_true(t.warning_temp < t.critical_temp and t.critical_temp < t.max_temp)
	assert_true(t.meltdown_recover_temp < t.meltdown_start_temp)


func test_abilities_match_gdd() -> void:
	var sup := Role.data(Role.Kind.SUPERVISOR)
	var rat := Role.data(Role.Kind.RAT)
	var broom := sup.ability(&"broom")
	assert_eq([broom.kind, broom.range, broom.cone_deg, broom.cooldown_s], [AbilityData.Kind.MELEE_STUN, 2.0, 70.0, 1.2])
	assert_eq([broom.status, broom.status_duration], [StatusComponent.Status.STUNNED, 2.0])
	var bite := rat.ability(&"bite")
	assert_eq([bite.kind, bite.range, bite.cooldown_s], [AbilityData.Kind.BITE, 1.2, 2.5])
	assert_eq([bite.status_duration, bite.extra["slow_factor"]], [3.0, 0.7])
	assert_eq([bite.extra["knockdown_bites"], bite.extra["knockdown_window_s"], bite.extra["knockdown_s"]], [3, 6.0, 4.0])
	var snap := sup.ability(&"snap_trap")
	assert_eq([snap.kind, snap.status, snap.status_duration, snap.extra["trap_kind"]],
		[AbilityData.Kind.TRAP, StatusComponent.Status.STUNNED, 3.0, "snap"])
	var lure := sup.ability(&"cheese_lure")
	assert_eq([lure.kind, lure.status, lure.status_duration, lure.extra["trap_kind"]],
		[AbilityData.Kind.TRAP, StatusComponent.Status.REVEALED, 10.0, "lure"])
	assert_null(rat.ability(&"broom"), "abilities are per role")
	assert_null(sup.ability(&"bite"))


func test_every_ability_is_sane() -> void:
	for kind: Role.Kind in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		for a in Role.data(kind).abilities:
			assert_ne(a.id, &"", "id")
			assert_false(a.display_name.is_empty(), "%s display name" % a.id)
			assert_true(a.range > 0.0 and a.cooldown_s > 0.0 and a.status_duration > 0.0, String(a.id))
			assert_true(a.input_action in [&"primary", &"secondary"], String(a.id))
			assert_true(InputMap.has_action(a.input_action), "%s: input action exists" % a.id)
			assert_between(a.cone_deg, 1.0, 360.0, String(a.id))


func test_role_combat_stats_match_gdd() -> void:
	var sup := Role.data(Role.Kind.SUPERVISOR)
	var rat := Role.data(Role.Kind.RAT)
	assert_eq([sup.carry_speed, sup.stun_immunity_s, sup.knockdown_immunity_s], [3.2, 0.0, 3.0])
	assert_eq([rat.carry_speed, rat.stun_immunity_s, rat.knockdown_immunity_s], [0.0, 1.5, 0.0])
	assert_true(sup.carry_speed < sup.walk_speed, "carrying is slower than walking")


func test_pvp_tuning_matches_gdd() -> void:
	var t := PvpTuning.load_default()
	assert_eq([t.carry_max_s, t.drop_invulnerable_s, t.free_hold_s, t.freed_invulnerable_s], [8.0, 1.5, 4.0, 3.0])
	assert_eq(t.captures_to_eliminate, 2)
	assert_eq([t.steal_hold_s, t.stolen_item_speed, t.spare_keycard_delay_s], [1.0, 0.9, 30.0])
	assert_eq([t.donut_speed, t.donut_duration_s, t.donut_cooldown_s, t.keycard_door_open_s], [1.2, 20.0, 60.0, 3.0])
	assert_eq(t.trap_charges, 3)
	assert_eq([t.cctv_break_hold_s, t.cctv_repair_hold_s], [2.0, 3.0])
	var m: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	assert_eq([m.swarm_bonus, m.swarm_cooldown_s], [15.0, 45.0])
