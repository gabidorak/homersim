extends GutTest
## M10: how many bots fill a match, and who gets which role when they do (GDD §2 Bots).

const SUP := Role.Kind.SUPERVISOR
const RAT := Role.Kind.RAT
const ANY := Role.Kind.NONE
const SPEC := Role.Kind.SPECTATOR

var base: MatchRules = preload("res://data/match_rules.tres")


func _rules(fill_to: int) -> MatchRules:
	var rules: MatchRules = base.duplicate()
	rules.bot_fill_to = fill_to
	return rules


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _prefs(list: Array) -> Dictionary[int, Role.Kind]:
	var prefs: Dictionary[int, Role.Kind] = {}
	for i in list.size():
		prefs[100 + i] = list[i]
	return prefs


func _fillers(count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(-1001 - i)
	return out


func _count(roles: Dictionary[int, Role.Kind], kind: Role.Kind) -> int:
	return roles.values().count(kind)


func test_bots_needed_for_every_human_count_and_fill() -> void:
	for fill_to in range(0, 9):
		var rules := _rules(fill_to)
		for humans in range(0, 9):
			var expected := 0
			if fill_to >= 2:
				var target := mini(fill_to, rules.seats())
				expected = maxi(0, target - humans)
			assert_eq(MatchRulesModel.bots_needed(humans, rules), expected, "fill %d, %d humans" % [fill_to, humans])


func test_fill_caps_and_off() -> void:
	assert_eq(MatchRulesModel.bots_needed(1, _rules(0)), 0, "0 = no bots")
	assert_eq(MatchRulesModel.bots_needed(1, _rules(1)), 0, "1 isn't a valid fill: no bots")
	assert_eq(MatchRulesModel.bots_needed(1, _rules(6)), 5)
	assert_eq(MatchRulesModel.bots_needed(0, _rules(6)), 6)
	assert_eq(MatchRulesModel.bots_needed(1, _rules(12)), 5, "capped at 2 supervisors + 4 rats")
	assert_eq(MatchRulesModel.bots_needed(6, _rules(6)), 0)
	assert_eq(MatchRulesModel.bots_needed(8, _rules(6)), 0)


func test_effective_min_players() -> void:
	assert_eq(MatchRulesModel.effective_min_players(_rules(0)), base.min_players)
	assert_eq(MatchRulesModel.effective_min_players(_rules(6)), 1)
	assert_true(MatchRulesModel.ready_vote_passes(1, 1, _rules(6)), "one human readies up alone")
	assert_false(MatchRulesModel.ready_vote_passes(1, 1, _rules(0)), "without bots, one is not enough")
	assert_false(MatchRulesModel.ready_vote_passes(2, 1, _rules(6)), "still a majority of the humans")


func test_one_human_plus_fill_six_gives_two_supervisors_and_four_rats() -> void:
	var rules := _rules(6)
	for pref: Role.Kind in [ANY, RAT, SUP]:
		for seed_value in 5:
			var roles := MatchRulesModel.assign_roles(_prefs([pref]), rules, _rng(seed_value), _fillers(5))
			assert_eq(roles.size(), 6)
			assert_eq(_count(roles, SUP), 2, "%s seed %d" % [Role.pref_name(pref), seed_value])
			assert_eq(_count(roles, RAT), 4)
			assert_eq(roles[100], RAT if pref == RAT else SUP, "the human gets its preference")


func test_human_preferences_are_honoured_before_bots() -> void:
	var rules := _rules(6)
	# 3 humans who all want to be rats, 3 bots: the rats are the humans, the bots fill the rest.
	for seed_value in 10:
		var roles := MatchRulesModel.assign_roles(_prefs([RAT, RAT, RAT]), rules, _rng(seed_value), _fillers(3))
		for peer in [100, 101, 102]:
			assert_eq(roles[peer], RAT, "seed %d: human %d" % [seed_value, peer])
		assert_eq(_count(roles, SUP), 2)
		assert_eq(_count(roles, RAT), 4)
	# 2 humans who want to supervise: both get it, every bot is a rat.
	var both := MatchRulesModel.assign_roles(_prefs([SUP, SUP]), rules, _rng(), _fillers(4))
	assert_eq([both[100], both[101]], [SUP, SUP])
	for bot in _fillers(4):
		assert_eq(both[bot], RAT)


func test_any_takes_a_slot_before_a_bot() -> void:
	var rules := _rules(6)
	for seed_value in 10:
		var roles := MatchRulesModel.assign_roles(_prefs([ANY, ANY]), rules, _rng(seed_value), _fillers(4))
		assert_eq(roles[100], SUP, "seed %d: Any humans take the supervisor slots first" % seed_value)
		assert_eq(roles[101], SUP)


func test_a_human_is_never_a_spectator_while_a_bot_plays() -> void:
	var rules := _rules(6)
	for humans in range(1, 9):
		for seed_value in 5:
			var list := []
			list.resize(humans)
			list.fill([ANY, RAT, SUP][(humans + seed_value) % 3])
			var fillers := _fillers(MatchRulesModel.bots_needed(humans, rules))
			var roles := MatchRulesModel.assign_roles(_prefs(list), rules, _rng(seed_value), fillers)
			var bots_playing := fillers.filter(func(b: int) -> bool: return roles.has(b)).size()
			var spectators := _count(roles, SPEC)
			assert_false(bots_playing > 0 and spectators > 0, "%d humans, seed %d" % [humans, seed_value])
			for bot in fillers:
				assert_ne(roles.get(bot, RAT), SPEC, "a bot is never a spectator")


func test_leftover_fillers_are_dropped() -> void:
	var rules := _rules(6)
	var roles := MatchRulesModel.assign_roles(_prefs([ANY, ANY, ANY, ANY, ANY]), rules, _rng(), _fillers(4))
	assert_eq(roles.size(), 6, "5 humans + 1 bot: the 3 extra bots are dropped")
	assert_eq(_count(roles, SUP), 2)
	assert_eq(_count(roles, RAT), 4)
	assert_eq(_count(roles, SPEC), 0)


func test_no_fillers_gives_the_same_result_as_before() -> void:
	var rules := _rules(0)
	for list: Array in [[ANY, ANY, ANY, ANY], [RAT, SUP, ANY, RAT, RAT], [SUP, SUP, SUP], [ANY, RAT, ANY, SUP, ANY, RAT, RAT, ANY],
			[RAT], [ANY, ANY]]:
		for seed_value in 5:
			var without := MatchRulesModel.assign_roles(_prefs(list), rules, _rng(seed_value))
			var empty := MatchRulesModel.assign_roles(_prefs(list), rules, _rng(seed_value), [] as Array[int])
			assert_eq(empty, without, "%s seed %d" % [list, seed_value])
			assert_eq(without, _pre_m10_assign(_prefs(list), rules, _rng(seed_value)), "%s seed %d vs M9" % [list, seed_value])


## assign_roles as it was before M10 (fillers), kept as the reference.
func _pre_m10_assign(prefs: Dictionary[int, Role.Kind], rules: MatchRules, rng: RandomNumberGenerator) -> Dictionary[int, Role.Kind]:
	var result: Dictionary[int, Role.Kind] = {}
	var peers: Array[int] = prefs.keys()
	peers.sort()
	for i in range(peers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := peers[i]
		peers[i] = peers[j]
		peers[j] = tmp
	var n := peers.size()
	if n == 1:
		result[peers[0]] = RAT if prefs[peers[0]] == RAT else SUP
		return result
	if n == 0:
		return result
	var supervisors := mini(rules.supervisors_for(n), n - 1)
	var rats := mini(n - supervisors, rules.max_rats)
	var remaining := MatchRulesModel._ordered_by_pref(peers, prefs, [SUP, ANY, RAT])
	for i in supervisors:
		result[remaining.pop_front()] = SUP
	remaining = MatchRulesModel._ordered_by_pref(remaining, prefs, [RAT, ANY, SUP])
	for i in rats:
		result[remaining.pop_front()] = RAT
	for peer in remaining:
		result[peer] = SPEC
	return result


func test_bots_take_every_custom_seat() -> void:
	for seats: Array in [[1, 1], [1, 6], [3, 1], [3, 6], [2, 5]]:
		var rules := _rules(seats[0] + seats[1])
		rules.max_supervisors = seats[0]
		rules.max_rats = seats[1]
		for pref: Role.Kind in [ANY, RAT, SUP]:
			var fillers := _fillers(MatchRulesModel.bots_needed(1, rules))
			assert_eq(fillers.size(), seats[0] + seats[1] - 1, "%s: every seat but the human's" % [seats])
			var roles := MatchRulesModel.assign_roles(_prefs([pref]), rules, _rng(), fillers)
			assert_eq([_count(roles, SUP), _count(roles, RAT)], seats, "%s, a human who wants %s" % [seats, Role.pref_name(pref)])
			assert_eq(roles[100], RAT if pref == RAT else SUP, "the human gets its preference")


func test_fill_never_goes_past_the_seats() -> void:
	var rules := _rules(9)
	assert_eq(MatchRulesModel.bot_target(rules), 6, "the default 2 + 4 seats")
	rules.max_supervisors = 3
	rules.max_rats = 6
	assert_eq(MatchRulesModel.bots_needed(1, rules), 8)
	rules.max_rats = 2
	assert_eq(MatchRulesModel.bots_needed(1, rules), 4)


func test_bots_only_match() -> void:
	var roles := MatchRulesModel.assign_roles(_prefs([]), _rules(6), _rng(), _fillers(6))
	assert_eq(_count(roles, SUP), 2)
	assert_eq(_count(roles, RAT), 4)
