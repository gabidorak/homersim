extends GutTest

const NetScript := preload("res://autoload/net.gd")


func test_host_and_port() -> void:
	assert_eq(NetScript.parse_address("127.0.0.1:9000"), {"host": "127.0.0.1", "port": 9000})


func test_default_port() -> void:
	assert_eq(NetScript.parse_address(" example.org "), {"host": "example.org", "port": 7777})


func test_invalid_addresses() -> void:
	for bad: String in ["", ":7777", "host:", "host:abc", "host:0", "host:70000", "a b:1", "::1"]:
		assert_eq(NetScript.parse_address(bad), {}, "should reject '%s'" % bad)


func test_clock_offset_splits_the_round_trip() -> void:
	# Sent at 10.0 (our clock), the server said 105.0, the answer came back at 10.2: the server's
	# clock read 105.0 about 0.1 s before we received it, so it is 105.1 when ours is 10.2.
	assert_almost_eq(NetScript.clock_offset(10.0, 105.0, 10.2), 94.9, 0.0001)
	assert_almost_eq(NetScript.clock_offset(10.0, 10.05, 10.1), 0.0, 0.0001, "same clocks, 100 ms ping")
