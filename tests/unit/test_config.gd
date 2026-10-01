extends GutTest

const PATH := "user://test_server.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_missing_file_gives_defaults() -> void:
	assert_eq(Config.load_server_config("user://does_not_exist.cfg"), Config.SERVER_DEFAULTS)


func test_values_override_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "port", 9100)
	cfg.set_value("server", "name", "Test plant")
	cfg.save(PATH)
	var result := Config.load_server_config(PATH)
	assert_eq(result["port"], 9100)
	assert_eq(result["name"], "Test plant")
	assert_eq(result["max_players"], Config.SERVER_DEFAULTS["max_players"])


func test_match_rules_default_without_config() -> void:
	var rules := Config.load_match_rules("user://does_not_exist.cfg")
	assert_eq(rules.countdown_s, 10)
	assert_eq(rules.min_players, 3)


func test_match_rules_overrides_are_applied_to_a_copy() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("match", "min_players", 2)
	cfg.set_value("match", "countdown_s", 3)
	cfg.save(PATH)
	var rules := Config.load_match_rules(PATH)
	assert_eq(rules.min_players, 2)
	assert_eq(rules.countdown_s, 3)
	assert_eq(rules.duration_s, 540, "keys not in the file keep the resource value")
	assert_eq((load(Config.DEFAULT_MATCH_RULES) as MatchRules).min_players, 3, "the shared resource is untouched")
