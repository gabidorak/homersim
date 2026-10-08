extends GutTest
## Online games (common/online_api.gd, server/launcher/launcher.gd): what the launcher accepts from a
## request, how it parses HTTP, the friends key, the port pool, the list entries, and the addresses
## the game joins.


func _bytes(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()


# --- Options ---------------------------------------------------------------------

func test_options_are_clamped_like_the_host_card() -> void:
	var clean := OnlineApi.sanitize_options({"name": "  Friday [b]night[/b]  ", "password": " cheese ", "max_players": 99.0,
		"supervisors": 3.0, "rats": 99, "bots": 5.0, "difficulty": -3})
	assert_eq(clean["name"], ChatService.clean("Friday [b]night[/b]").strip_edges(), "cleaned like chat")
	assert_false(str(clean["name"]).contains("[b]"), "no BBCode")
	assert_eq(clean["password"], "cheese")
	assert_eq(clean["max_players"], Config.HOST_MAX_PLAYERS)
	assert_eq(clean["supervisors"], 3)
	assert_eq(clean["rats"], MatchRules.RATS_LIMIT)
	assert_eq(clean["bots"], 5)
	assert_eq(clean["difficulty"], 0)


func test_options_fall_back_on_anything_unusable() -> void:
	var clean := OnlineApi.sanitize_options({"name": 12, "max_players": "8", "supervisors": 0, "rats": "3", "bots": 1,
		"difficulty": [2]})
	assert_eq(clean["name"], "12")
	assert_eq(clean["max_players"], 6, "a string is not a number")
	assert_eq(clean["bots"], 0, "fewer than 2 = no bots (as Config's host_bots)")
	assert_eq(clean["difficulty"], 1)
	assert_eq([clean["supervisors"], clean["rats"]], [1, 4], "at least one supervisor; a string is not a number")
	assert_eq(OnlineApi.sanitize_options({})["name"], "Online game")
	assert_eq([OnlineApi.sanitize_options({})["supervisors"], OnlineApi.sanitize_options({})["rats"]], [2, 4], "the default seats")
	assert_eq(OnlineApi.sanitize_options({"bots": 40})["bots"], 6, "bots never fill past the seats")
	assert_eq(OnlineApi.sanitize_options({"supervisors": 1, "rats": 2, "bots": 40})["bots"], 3)
	assert_eq(str(OnlineApi.sanitize_options({"password": "x".repeat(100)})["password"]).length(), OnlineApi.MAX_PASSWORD)
	assert_eq(str(OnlineApi.sanitize_options({"name": "y".repeat(100)})["name"]).length(), LanDiscovery.MAX_NAME)


# --- HTTP ----------------------------------------------------------------------

func test_parse_a_whole_request() -> void:
	var body := '{"name": "Chloé"}'
	var raw := "POST /games?x=1 HTTP/1.1\r\nHost: homersim.mooo.com\r\nAuthorization: Bearer abc\r\nContent-Length: %d\r\n\r\n%s" \
		% [body.to_utf8_buffer().size(), body]
	var got := OnlineApi.parse_request(_bytes(raw))
	assert_true(got.get("done", false))
	assert_eq(got["method"], "POST")
	assert_eq(got["path"], "/games", "no query string")
	assert_eq(got["headers"]["authorization"], "Bearer abc", "lower-case header names")
	assert_eq(got["body"], body, "UTF-8 body")
	assert_eq(OnlineApi.bearer_key(got["headers"]), "abc")


func test_parse_waits_for_the_rest() -> void:
	assert_eq(OnlineApi.parse_request(_bytes("GET /games HTTP/1.1\r\nHost: x\r\n")), {"done": false}, "headers not over")
	assert_eq(OnlineApi.parse_request(_bytes("POST /games HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345")), {"done": false},
		"body not all there")
	assert_true(OnlineApi.parse_request(_bytes("GET / HTTP/1.1\r\n\r\n")).get("done", false), "no headers at all is fine")


func test_parse_refuses_bad_requests() -> void:
	assert_eq(OnlineApi.parse_request(_bytes("NONSENSE\r\n\r\n")), {"error": 400})
	assert_eq(OnlineApi.parse_request(_bytes("GET games HTTP/1.1\r\n\r\n")), {"error": 400}, "path must start with /")
	assert_eq(OnlineApi.parse_request(_bytes("GET / HTTP/1.1\r\nno colon\r\n\r\n")), {"error": 400})
	assert_eq(OnlineApi.parse_request(_bytes("POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n")), {"error": 400})
	assert_eq(OnlineApi.parse_request(_bytes("POST / HTTP/1.1\r\nContent-Length: 99999\r\n\r\n")), {"error": 413})
	assert_eq(OnlineApi.parse_request(_bytes("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")), {"error": 411})
	assert_eq(OnlineApi.parse_request(_bytes("GET / HTTP/1.1\r\nX: " + "a".repeat(9000))), {"error": 431},
		"endless headers")


func test_response_is_valid_http() -> void:
	var text := OnlineApi.response(503, {"error": "full"}).get_string_from_utf8()
	assert_true(text.begins_with("HTTP/1.1 503 Service Unavailable\r\n"))
	assert_string_contains(text, "Content-Length: 16\r\n")
	assert_string_contains(text, "Connection: close\r\n")
	assert_true(text.ends_with('\r\n\r\n{"error":"full"}'))


func test_friends_key() -> void:
	assert_true(OnlineApi.keys_match("s3cret-key", "s3cret-key"))
	assert_false(OnlineApi.keys_match("s3cret-kez", "s3cret-key"))
	assert_false(OnlineApi.keys_match("", ""), "no key set = nobody gets in")
	assert_eq(OnlineApi.bearer_key({"authorization": "bearer  abc "}), "abc", "case-insensitive scheme")
	assert_eq(OnlineApi.bearer_key({"authorization": "Basic abc"}), "")
	assert_eq(OnlineApi.bearer_key({}), "")


# --- Ports, list, addresses -------------------------------------------------------

func test_port_range() -> void:
	assert_eq(OnlineApi.parse_port_range("7800-7803"), [7800, 7801, 7802, 7803] as Array[int])
	assert_eq(OnlineApi.parse_port_range(" 7800 "), [7800] as Array[int])
	for bad in ["", "abc", "7803-7800", "80-90", "7800-99999", "1-2-3", "7000-9000"]:
		assert_eq(OnlineApi.parse_port_range(bad), [] as Array[int], "'%s' is refused" % bad)


func test_next_port_goes_round() -> void:
	var pool: Array[int] = [7800, 7801, 7802]
	assert_eq(OnlineApi.next_port(pool, [], 0), 7800, "the first one to start with")
	assert_eq(OnlineApi.next_port(pool, [], 7800), 7801, "not the one just used")
	assert_eq(OnlineApi.next_port(pool, [7801], 7800), 7802, "skips taken ones")
	assert_eq(OnlineApi.next_port(pool, [], 7802), 7800, "wraps around")
	assert_eq(OnlineApi.next_port(pool, [7800, 7801, 7802], 0), 0, "all taken")
	assert_eq(OnlineApi.next_port([] as Array[int], [], 0), 0)


func test_list_entries_have_the_right_types() -> void:
	var entry := OnlineApi.game_entry({"name": "Plant", "players": 3.0, "max": 6.0, "state": "playing", "locked": true,
		"version": "0.1.0", "port": 1}, 7801)
	assert_eq(entry, {"id": 7801, "name": "Plant", "players": 3, "max": 6, "state": "playing", "locked": true,
		"version": "0.1.0", "port": 7801})
	var games := OnlineApi.parse_games({"games": [entry, {"name": "no port"}, "junk", {"port": 7802.0, "locked": "yes"}]})
	assert_eq(games.size(), 2, "malformed games left out")
	assert_eq(games[1]["port"], 7802)
	assert_false(games[1]["locked"], "only true is true")
	assert_eq(OnlineApi.parse_games({"games": "nope"}), [] as Array[Dictionary])


func test_addresses() -> void:
	assert_eq(OnlineApi.host_of("https://homersim.mooo.com"), "homersim.mooo.com")
	assert_eq(OnlineApi.host_of("http://127.0.0.1:27790/"), "127.0.0.1")
	assert_eq(OnlineApi.host_of("localhost:7790"), "localhost")
	assert_eq(OnlineApi.host_of("http://[::1]:7790"), "::1")
	assert_eq(OnlineApi.base_url("localhost:7790/"), "http://localhost:7790")
	assert_eq(OnlineApi.base_url(OnlineApi.DEFAULT_URL), "https://homersim.mooo.com")
	assert_eq(OnlineApi.game_address({"host": "", "port": 7803.0}, OnlineApi.DEFAULT_URL), "homersim.mooo.com:7803",
		"the launcher's own host by default")
	assert_eq(OnlineApi.game_address({"host": "203.0.113.5", "port": 7803}, OnlineApi.DEFAULT_URL), "203.0.113.5:7803")


func test_launcher_settings() -> void:
	var path := ProjectSettings.globalize_path("user://test_launcher.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value("launcher", "key", "  abc  ")
	cfg.set_value("launcher", "max_games", 500)
	cfg.set_value("launcher", "idle_quit_s", 1)
	cfg.save(path)
	var settings := Launcher.load_settings(path)
	assert_eq(settings["key"], "abc")
	assert_eq(settings["max_games"], 32)
	assert_eq(settings["idle_quit_s"], 5)
	assert_eq(settings["port"], OnlineApi.DEFAULT_PORT, "defaults for the rest")
	assert_eq(settings["game_ports"], "7800-7809")
	DirAccess.remove_absolute(path)
	var example := Launcher.load_settings(ProjectSettings.globalize_path("res://launcher.cfg.example"))
	for key: String in Launcher.DEFAULTS:
		assert_eq(example[key], Launcher.DEFAULTS[key], "launcher.cfg.example has the defaults (%s)" % key)
