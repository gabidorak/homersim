extends GutTest

const NetScript := preload("res://autoload/net.gd")


func test_host_and_port() -> void:
	assert_eq(NetScript.parse_address("127.0.0.1:9000"), {"host": "127.0.0.1", "port": 9000})


func test_default_port() -> void:
	assert_eq(NetScript.parse_address(" example.org "), {"host": "example.org", "port": 7777})


func test_invalid_addresses() -> void:
	for bad: String in ["", ":7777", "host:", "host:abc", "host:0", "host:70000", "a b:1", "::1"]:
		assert_eq(NetScript.parse_address(bad), {}, "should reject '%s'" % bad)
