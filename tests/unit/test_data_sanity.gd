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
	assert_eq([t.scram_heat_factor, t.scram_duration_s, t.scram_cooldown_s, t.scram_time_penalty_s], [0.5, 30.0, 120.0, 30])
	assert_eq([t.coolant_amount, t.coolant_cooldown_s, t.coolant_min_grid_health], [150.0, 90.0, 25.0])
	assert_eq([t.minigame_repair_amount, t.minigame_fail_amount, t.minigame_lockout_s, t.minigame_min_s],
		[50.0, 10.0, 3.0, 3.0])
	assert_true(t.minigame_max_s > t.minigame_min_s)
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


func test_hazard_tuning_matches_gdd() -> void:
	var h := HazardTuning.load_default()
	assert_eq([h.on_below_health, h.off_at_health], [50.0, 60.0])
	assert_eq([h.steam_on_s, h.steam_off_s, h.steam_knockback, h.steam_stun_s], [3.0, 3.0, 6.0, 1.0])
	assert_eq([h.puddle_live_s, h.puddle_period_s, h.puddle_stun_s, h.puddle_slow, h.puddle_slow_s], [2.0, 5.0, 1.5, 0.5, 2.0])
	assert_eq([h.radiation_exposure_s, h.radiation_slow, h.radiation_reveal_after_s], [5.0, 0.8, 5.0])
	assert_eq([h.debris_interval_s, h.debris_warning_s, h.debris_knockdown_s, h.debris_stun_s], [8.0, 1.0, 3.0, 2.0])
	assert_eq(h.smoke_visibility, 6.0)
	assert_true(h.off_at_health > h.on_below_health, "hysteresis: off above on")
	assert_true(h.puddle_live_s < h.puddle_period_s)


func test_every_subsystem_has_a_minigame() -> void:
	var tuning: PlantTuning = load(PlantSim.TUNING_PATH)
	var expected := {&"pumps": "wrench_rhythm", &"turbine": "wrench_rhythm", &"grid": "breaker_sequence",
		&"ventilation": "breaker_sequence", &"valves": "valve_rotate", &"rods": "valve_rotate"}
	for s in tuning.subsystems:
		assert_eq(s.minigame, expected[s.id], String(s.id))
		assert_true(MinigameHost.SCENES.has(s.minigame), "%s: the host knows %s" % [s.id, s.minigame])


func test_bot_tuning_matches_gdd() -> void:
	var t := BotTuning.load_default()
	assert_eq(t.skills.size(), 3, "easy, normal, hard")
	# GDD §5.5 table: reaction, aim error, turn rate, view range, decisions/s, trap notice, teamwork
	var table := [
		[0.7, 30.0, 250.0, 15.0, 3.0, 0.4, false],
		[0.4, 15.0, 400.0, 22.0, 5.0, 0.75, true],
		[0.2, 6.0, 600.0, 30.0, 6.0, 0.95, true],
	]
	for i in t.skills.size():
		var s := t.skills[i]
		assert_eq([s.reaction_s, s.aim_error_deg, s.turn_rate_deg, s.view_range, s.think_hz, s.trap_notice, s.teamwork],
			table[i], s.label)
	assert_eq(t.skill(-3), t.skills[0], "clamped")
	assert_eq(t.skill(9), t.skills[2], "clamped")


func test_bot_skills_are_sane_and_harder_is_better() -> void:
	var t := BotTuning.load_default()
	for s in t.skills:
		assert_between(s.reaction_s, 0.05, 2.0, s.label)
		assert_between(s.aim_error_deg, 0.0, 45.0, s.label)
		assert_between(s.turn_rate_deg, 90.0, 1440.0, s.label)
		assert_between(s.view_range, 5.0, 60.0, s.label)
		assert_between(s.think_hz, 1.0, 20.0, s.label)
		assert_between(s.trap_notice, 0.0, 1.0, s.label)
	for i in range(1, t.skills.size()):
		var easier := t.skills[i - 1]
		var harder := t.skills[i]
		assert_true(harder.reaction_s <= easier.reaction_s, "%s reacts at least as fast" % harder.label)
		assert_true(harder.aim_error_deg <= easier.aim_error_deg, "%s aims at least as well" % harder.label)
		assert_true(harder.turn_rate_deg >= easier.turn_rate_deg, "%s turns at least as fast" % harder.label)
		assert_true(harder.view_range >= easier.view_range, "%s sees at least as far" % harder.label)
		assert_true(harder.think_hz >= easier.think_hz, "%s thinks at least as often" % harder.label)
		assert_true(harder.trap_notice >= easier.trap_notice, "%s notices traps at least as often" % harder.label)
		assert_true(harder.teamwork or not easier.teamwork, "%s keeps teamwork" % harder.label)


func test_bot_names_and_numbers_are_sane() -> void:
	var t := BotTuning.load_default()
	assert_true(t.names.size() >= 6, "enough names for a bots-only match")
	var seen := {}
	for n in t.names:
		assert_false(n.strip_edges().is_empty(), "no empty name")
		assert_false(n.to_lower().contains("bot"), "%s: the badge already says Bot" % n)
		assert_true(n.length() <= JoinRules.MAX_NAME_LENGTH, "%s fits a player name" % n)
		assert_false(seen.has(n), "%s is unique" % n)
		seen[n] = true
	assert_between(t.fov_supervisor_deg, 60.0, 180.0)
	assert_between(t.fov_rat_deg, 90.0, 360.0)
	assert_true(t.hear_rat_walk < t.hear_rat_sprint, "sprinting is louder")
	assert_true(t.memory_s > 0.0 and t.share_delay_s >= 0.0 and t.commitment_bonus >= 0.0)
	assert_true(t.blacklist_min_s <= t.blacklist_max_s)
	assert_true(t.stuck_check_s > 0.0 and t.stuck_fail_s > t.stuck_check_s * 3.0)
	assert_true(t.chase_give_up < t.chase_radius)


func test_bot_fill_is_off_or_a_real_match_size() -> void:
	var m: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	assert_eq(m.bot_fill_to, 0, "bots are off by default")
	assert_true(m.bot_fill_to == 0 or (m.bot_fill_to >= 2 and m.bot_fill_to <= 6))
	assert_between(m.bot_difficulty, 0, 2)
