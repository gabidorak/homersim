extends GutTest
## MatchRulesModel.check_winner priority order (GDD §2, ARCHITECTURE §6).

const T := MatchRulesModel.Team

var rules: MatchRules = preload("res://data/match_rules.tres")


## A running 1 supervisor vs 3 rats match; `changes` overrides keys.
func _state(changes: Dictionary = {}) -> Dictionary:
	var s := {
		"meltdown": 0.0, "time_left": 300.0,
		"supervisors": 1, "rats": 3, "rats_free": 3,
		"supervisors_started": 1, "rats_started": 3,
	}
	s.merge(changes, true)
	return s


func test_running_match_has_no_winner() -> void:
	assert_eq(MatchRulesModel.check_winner(_state()), T.NONE)
	assert_eq(MatchRulesModel.check_winner(_state({"meltdown": 99.9})), T.NONE)


func test_meltdown_rats_win() -> void:
	assert_eq(MatchRulesModel.check_winner(_state({"meltdown": 100.0})), T.RATS)


func test_time_out_supervisors_win() -> void:
	assert_eq(MatchRulesModel.check_winner(_state({"time_left": 0.0})), T.SUPERVISORS)


func test_all_rats_caught_supervisors_win() -> void:
	assert_eq(MatchRulesModel.check_winner(_state({"rats_free": 0})), T.SUPERVISORS)


func test_meltdown_beats_everything_else() -> void:
	assert_eq(MatchRulesModel.check_winner(_state({"meltdown": 100.0, "rats_free": 0, "time_left": 0.0})), T.RATS)


func test_caught_beats_time_out() -> void:
	var r := MatchRulesModel.evaluate(_state({"rats_free": 0, "time_left": 0.0}))
	assert_eq(r["team"], T.SUPERVISORS)
	assert_eq(r["reason"], "Every rat is caught")


func test_empty_team_loses() -> void:
	assert_eq(MatchRulesModel.check_winner(_state({"rats": 0, "rats_free": 0})), T.SUPERVISORS)
	assert_eq(MatchRulesModel.check_winner(_state({"supervisors": 0})), T.RATS)


func test_a_team_that_never_had_players_does_not_lose() -> void:
	var solo := {"meltdown": 0.0, "time_left": 30.0, "supervisors": 1, "rats": 0, "rats_free": 0,
		"supervisors_started": 1, "rats_started": 0}
	assert_eq(MatchRulesModel.check_winner(solo), T.NONE, "solo debug match keeps going")
	solo["time_left"] = 0.0
	assert_eq(MatchRulesModel.check_winner(solo), T.SUPERVISORS)


func test_match_duration() -> void:
	assert_eq(MatchRulesModel.match_duration(rules, 1), 480, "8 min with one supervisor")
	assert_eq(MatchRulesModel.match_duration(rules, 2), 540)
