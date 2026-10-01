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
