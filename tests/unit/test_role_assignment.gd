extends GutTest

const SUP := Role.Kind.SUPERVISOR
const RAT := Role.Kind.RAT
const ANY := Role.Kind.NONE
const SPEC := Role.Kind.SPECTATOR

## GDD §2 balance table: players -> [supervisors, rats]
const TABLE := {2: [1, 1], 3: [1, 2], 4: [1, 3], 5: [2, 3], 6: [2, 4]}

var rules: MatchRules = preload("res://data/match_rules.tres")


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _prefs(list: Array) -> Dictionary[int, Role.Kind]:
	var prefs: Dictionary[int, Role.Kind] = {}
	for i in list.size():
		prefs[100 + i] = list[i]
	return prefs


func _count(roles: Dictionary[int, Role.Kind], kind: Role.Kind) -> int:
	return roles.values().count(kind)


## The default rules with other seats (the host's choice).
func _seats(supervisors: int, rats: int) -> MatchRules:
	var custom: MatchRules = rules.duplicate()
	custom.max_supervisors = supervisors
	custom.max_rats = rats
	return custom


func _all_any(n: int) -> Dictionary[int, Role.Kind]:
	var list := []
	list.resize(n)
	list.fill(ANY)
	return _prefs(list)


func _assert_table(roles: Dictionary[int, Role.Kind], n: int, label: String) -> void:
	assert_eq(roles.size(), n, "%s: everyone gets a role" % label)
	assert_eq(_count(roles, SUP), TABLE[n][0], "%s: supervisors for %d players" % [label, n])
	assert_eq(_count(roles, RAT), TABLE[n][1], "%s: rats for %d players" % [label, n])


func test_balance_table_for_every_player_count_and_uniform_preference() -> void:
	for n: int in TABLE:
		for pref: Role.Kind in [ANY, RAT, SUP]:
			var list := []
			list.resize(n)
			list.fill(pref)
			for seed_value in 5:
				_assert_table(MatchRulesModel.assign_roles(_prefs(list), rules, _rng(seed_value)), n,
					"all-%s seed %d" % [Role.pref_name(pref), seed_value])


func test_mixed_preferences_are_honoured_when_they_fit() -> void:
	# 4 players: 1 supervisor slot, 3 rat slots
	var prefs := _prefs([RAT, SUP, ANY, RAT])
	for seed_value in 10:
		var roles := MatchRulesModel.assign_roles(prefs, rules, _rng(seed_value))
		_assert_table(roles, 4, "mixed seed %d" % seed_value)
		assert_eq(roles[101], SUP, "the only supervisor fan gets it")
		assert_eq(roles[100], RAT)
		assert_eq(roles[103], RAT)


func test_any_fills_supervisor_before_rat_fans() -> void:
	var prefs := _prefs([RAT, RAT, ANY, RAT, RAT])  # 5 players: 2 supervisors, 3 rats
	for seed_value in 10:
		var roles := MatchRulesModel.assign_roles(prefs, rules, _rng(seed_value))
		_assert_table(roles, 5, "seed %d" % seed_value)
		assert_eq(roles[102], SUP, "'Any' is drafted before a rat fan")


func test_too_many_supervisor_fans_some_become_rats() -> void:
	var prefs := _prefs([SUP, SUP, SUP, ANY])
	var roles := MatchRulesModel.assign_roles(prefs, rules, _rng())
	_assert_table(roles, 4, "3 supervisor fans")
	assert_eq(roles[103], RAT, "'Any' takes a rat slot before a supervisor fan is moved")


func test_same_seed_same_result_and_seeds_vary_the_pick() -> void:
	var prefs := _prefs([ANY, ANY, ANY, ANY])
	var a := MatchRulesModel.assign_roles(prefs, rules, _rng(42))
	var b := MatchRulesModel.assign_roles(prefs, rules, _rng(42))
	assert_eq(a, b)
	var supervisors := {}
	for seed_value in 40:
		var roles := MatchRulesModel.assign_roles(prefs, rules, _rng(seed_value))
		for peer: int in roles:
			if roles[peer] == SUP:
				supervisors[peer] = true
	assert_eq(supervisors.size(), 4, "over many seeds, anyone can end up supervisor")


func test_lone_player_gets_their_preference() -> void:
	assert_eq(MatchRulesModel.assign_roles(_prefs([RAT]), rules, _rng())[100], RAT)
	assert_eq(MatchRulesModel.assign_roles(_prefs([ANY]), rules, _rng())[100], SUP)


func test_extra_players_beyond_the_rat_cap_spectate() -> void:
	var list := []
	list.resize(8)
	list.fill(ANY)
	var roles := MatchRulesModel.assign_roles(_prefs(list), rules, _rng())
	assert_eq(_count(roles, SUP), 2)
	assert_eq(_count(roles, RAT), 4)
	assert_eq(_count(roles, SPEC), 2)


func test_custom_seats_split_fewer_players_in_proportion() -> void:
	# seats -> {players: [supervisors, rats, spectators]}
	var cases := {
		[3, 6]: {2: [1, 1, 0], 3: [1, 2, 0], 4: [1, 3, 0], 5: [2, 3, 0], 6: [2, 4, 0], 8: [3, 5, 0], 9: [3, 6, 0], 11: [3, 6, 2]},
		[2, 2]: {2: [1, 1, 0], 3: [1, 2, 0], 4: [2, 2, 0], 5: [2, 2, 1]},  # a half goes to the rats
		[1, 6]: {3: [1, 2, 0], 7: [1, 6, 0], 8: [1, 6, 1]},
		[3, 1]: {2: [1, 1, 0], 3: [2, 1, 0], 4: [3, 1, 0], 5: [3, 1, 1]},  # always at least one rat
		[1, 1]: {2: [1, 1, 0], 3: [1, 1, 1]},
	}
	for seats: Array in cases:
		for n: int in cases[seats]:
			var roles := MatchRulesModel.assign_roles(_all_any(n), _seats(seats[0], seats[1]), _rng())
			var expected: Array = cases[seats][n]
			assert_eq([_count(roles, SUP), _count(roles, RAT), _count(roles, SPEC)], expected,
				"%d supervisor + %d rat seats, %d players" % [seats[0], seats[1], n])


func test_seats_outside_the_limits_are_clamped() -> void:
	var big := _seats(99, 99)
	assert_eq([big.supervisor_seats(), big.rat_seats()], [MatchRules.SUPERVISORS_LIMIT, MatchRules.RATS_LIMIT])
	var roles := MatchRulesModel.assign_roles(_all_any(30), big, _rng())
	assert_eq([_count(roles, SUP), _count(roles, RAT), _count(roles, SPEC)], [8, 16, 6])
	var none := _seats(0, -2)
	assert_eq([none.supervisor_seats(), none.rat_seats()], [1, 1], "at least one of each")


func test_empty_lobby() -> void:
	assert_eq(MatchRulesModel.assign_roles(_prefs([]), rules, _rng()).size(), 0)


func test_ready_vote() -> void:
	assert_false(MatchRulesModel.ready_vote_passes(2, 2, rules), "below min players")
	assert_true(MatchRulesModel.ready_vote_passes(2, 2, _seats(1, 1)), "1 vs 1: two players are a full match")
	assert_false(MatchRulesModel.ready_vote_passes(4, 2, rules), "exactly half is not a majority")
	assert_true(MatchRulesModel.ready_vote_passes(4, 3, rules))
	assert_true(MatchRulesModel.ready_vote_passes(3, 2, rules))
