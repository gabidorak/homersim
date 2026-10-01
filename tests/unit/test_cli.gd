extends GutTest

var cli: Node


func before_each() -> void:
	cli = autofree(preload("res://autoload/cli.gd").new())


func test_empty_args() -> void:
	assert_eq(cli.parse(PackedStringArray()), {})


func test_flag() -> void:
	assert_eq(cli.parse(PackedStringArray(["--server"])), {"server": true})


func test_key_value() -> void:
	assert_eq(cli.parse(PackedStringArray(["--port", "7777"])), {"port": "7777"})


func test_key_equals_value() -> void:
	assert_eq(cli.parse(PackedStringArray(["--name=Bob"])), {"name": "Bob"})


func test_mixed() -> void:
	var argv := PackedStringArray(["--server", "--port", "9000", "--debug-start", "--connect", "127.0.0.1:7777"])
	assert_eq(cli.parse(argv), {"server": true, "port": "9000", "debug-start": true, "connect": "127.0.0.1:7777"})


func test_flag_followed_by_flag_is_not_a_value() -> void:
	assert_eq(cli.parse(PackedStringArray(["--server", "--debug-start"])), {"server": true, "debug-start": true})


func test_negative_number_is_a_value() -> void:
	assert_eq(cli.parse(PackedStringArray(["--offset", "-5"])), {"offset": "-5"})


func test_stray_values_are_ignored() -> void:
	assert_eq(cli.parse(PackedStringArray(["oops", "--bot", "rat", "extra", "--"])), {"bot": "rat"})


func test_last_value_wins() -> void:
	assert_eq(cli.parse(PackedStringArray(["--port", "1", "--port", "2"])), {"port": "2"})


func test_getters() -> void:
	cli.args = cli.parse(PackedStringArray(["--port", "9000", "--name", "Al", "--server", "--bad", "x1"]))
	assert_true(cli.has_arg("server"))
	assert_false(cli.has_arg("connect"))
	assert_eq(cli.get_int("port", 7777), 9000)
	assert_eq(cli.get_int("missing", 7777), 7777)
	assert_eq(cli.get_int("bad", 7777), 7777)
	assert_eq(cli.get_str("name"), "Al")
	assert_eq(cli.get_str("server", "def"), "def")


func test_get_float() -> void:
	cli.args = cli.parse(PackedStringArray(["--speed", "2.5", "--n", "3", "--bad", "x"]))
	assert_eq(cli.get_float("speed"), 2.5)
	assert_eq(cli.get_float("n"), 3.0)
	assert_eq(cli.get_float("bad", 1.0), 1.0)
	assert_eq(cli.get_float("missing", 1.0), 1.0)
