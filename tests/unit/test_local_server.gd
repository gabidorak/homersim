extends GutTest
## Play solo and Host a game (client/local_server.gd): what the client writes in the server's
## server.cfg and puts on its command line, the team sizes the cards show, the LAN address the host
## sees, the leave reasons, and the checks the server uses to stop once the client is gone.

const CFG := "user://test_local_server.cfg"

const HOST_OPTIONS := {"name": "Friday night", "password": "cheese", "port": 7790, "max_players": 8, "bots": 0,
	"difficulty": 2, "lan": true, "bind": "*", "role": -1}


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


## The user args (after "--") of a server command line, parsed like the server parses them.
func _user_args(args: PackedStringArray) -> Dictionary:
	return Cli.parse(args.slice(args.find("--") + 1))


func test_solo_config_reads_back_as_a_private_server_with_bots() -> void:
	var options := LocalServer.solo_options()
	options["bots"] = 5
	options["difficulty"] = 0
	assert_eq(LocalServer.config_for(options).save(CFG), OK)
	var server := Config.load_server_config(CFG)
	assert_eq(int(server["port"]), 0, "any free port")
	assert_eq(int(server["max_players"]), 1, "nobody but you")
	assert_eq(str(server["password"]), "")
	var rules := Config.load_match_rules(CFG)
	assert_eq(rules.bot_fill_to, 5)
	assert_eq(rules.bot_difficulty, 0)
	assert_eq(MatchRulesModel.effective_min_players(rules), 1, "one human can start")


func test_host_config_reads_back() -> void:
	assert_eq(LocalServer.config_for(HOST_OPTIONS).save(CFG), OK)
	var server := Config.load_server_config(CFG)
	assert_eq(str(server["name"]), "Friday night")
	assert_eq(str(server["password"]), "cheese")
	assert_eq(int(server["port"]), 7790)
	assert_eq(int(server["max_players"]), 8)
	var rules := Config.load_match_rules(CFG)
	assert_false(MatchRulesModel.bots_enabled(rules), "no bots")
	assert_eq(rules.min_players, (load(Config.DEFAULT_MATCH_RULES) as MatchRules).min_players, "the usual rules otherwise")


func test_solo_server_args() -> void:
	var args := LocalServer.server_args(LocalServer.solo_options(), "/tmp/s.cfg", "/tmp/r.json", "/tmp/l.log", 4242, "tok")
	var engine := args.slice(0, args.find("--"))
	assert_true(engine.has("--headless"), "no window")
	assert_eq(engine[engine.find("--log-file") + 1], "/tmp/l.log", "its own log file")
	assert_eq(engine[engine.find("--max-fps") + 1], str(LocalServer.SERVER_MAX_FPS))
	var user := _user_args(args)
	assert_true(user.has("server"))
	assert_eq(user.get("config"), "/tmp/s.cfg")
	assert_eq(user.get("ready-file"), "/tmp/r.json")
	assert_eq(user.get("owner-pid"), "4242")
	assert_eq(user.get("host-token"), "tok")
	assert_eq(user.get("bind"), "127.0.0.1", "solo: this computer only")
	assert_true(user.has("no-lan"), "solo: not on the LAN")
	assert_true(user.has("no-update"), "the game already updated itself")
	assert_true(user.has("no-heatmap"))


func test_host_server_args() -> void:
	var user := _user_args(LocalServer.server_args(HOST_OPTIONS, "a", "b", "c", 1, "t"))
	assert_false(user.has("bind"), "every address")
	assert_false(user.has("no-lan"), "on the LAN")
	var hidden := HOST_OPTIONS.duplicate()
	hidden["lan"] = false
	assert_true(_user_args(LocalServer.server_args(hidden, "a", "b", "c", 1, "t")).has("no-lan"))


func test_command_from_source_adds_the_project_folder() -> void:
	var cmd := LocalServer.command(PackedStringArray(["--headless", "--", "--server"]))
	assert_eq(cmd[0], Updater.exe_path, "this executable")
	var args: PackedStringArray = cmd[1]
	assert_false(OS.has_feature("template"), "(the tests run from source)")
	assert_eq(args[0], "--path")
	assert_eq(args[1], ProjectSettings.globalize_path("res://"))
	assert_eq(args.slice(2), PackedStringArray(["--headless", "--", "--server"]))


func test_team_sizes_follow_the_rules() -> void:
	var rules: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	assert_eq(LocalServer.teams_for(4, rules), [1, 3] as Array[int])
	assert_eq(LocalServer.teams_for(5, rules), [2, 3] as Array[int])
	assert_eq(LocalServer.teams_for(6, rules), [2, 4] as Array[int])


func test_lan_addresses_skip_virtual_interfaces() -> void:
	var interfaces := [
		{"name": "lo", "friendly": "lo", "addresses": ["127.0.0.1", "0:0:0:0:0:0:0:1"]},
		{"name": "docker0", "friendly": "docker0", "addresses": ["172.17.0.1"]},
		{"name": "br-fb9d52371d54", "friendly": "br-fb9d52371d54", "addresses": ["172.19.0.1"]},
		{"name": "virbr0", "friendly": "virbr0", "addresses": ["192.168.122.1"]},
		{"name": "wlo1", "friendly": "wlo1", "addresses": ["10.202.21.226", "2a01:cb06::1"]},
		{"name": "{4A1B}", "friendly": "vEthernet (WSL)", "addresses": ["172.25.80.1"]},
		{"name": "{77C2}", "friendly": "VirtualBox Host-Only Network", "addresses": ["192.168.56.1"]},
		{"name": "{0F3D}", "friendly": "Wi-Fi", "addresses": ["192.168.1.20"]},
		{"name": "eth9", "friendly": "eth9", "addresses": ["8.8.8.8"]},
	]
	assert_eq(LocalServer.lan_addresses(interfaces), PackedStringArray(["192.168.1.20", "10.202.21.226"]),
		"real interfaces only, 192.168 first, no public or loopback address")
	assert_eq(LocalServer.lan_addresses([]), PackedStringArray())


func test_default_host_name() -> void:
	assert_string_contains(LocalServer.default_host_name("Chloé"), "Chloé")
	assert_string_contains(LocalServer.default_host_name(""), JoinRules.DEFAULT_NAME)


func test_new_leave_reasons_explain_themselves() -> void:
	for code in [LeaveReason.Code.HOST_LEFT, LeaveReason.Code.SERVER_START]:
		assert_ne(LeaveReason.title(code), "", "a title for %s" % LeaveReason.Code.keys()[code])
		assert_ne(LeaveReason.message(code), "")
	assert_string_contains(LeaveReason.message(LeaveReason.Code.SERVER_START, "port|7790"), "7790")
	assert_string_contains(LeaveReason.message(LeaveReason.Code.SERVER_START, "exit|/tmp/x.log"), "/tmp/x.log")
	assert_eq(LeaveReason.log_text(LeaveReason.Code.SERVER_START, "port|7790"), "Could not start the server: UDP port 7790 is in use")
	assert_eq(LeaveReason.log_text(LeaveReason.Code.HOST_LEFT), "The host left")


func test_process_watch() -> void:
	var own := ProcessWatch.new(OS.get_process_id())
	assert_true(own.alive(), "this process runs")
	own.finish()
	if OS.get_name() != "Linux":
		return
	var pid := OS.create_process("true", [])
	var deadline := Time.get_ticks_msec() + 5000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:  # (also reaps it)
		await get_tree().process_frame
	assert_false(ProcessWatch.new(pid).alive(), "a process that ended")


func test_net_hosts_on_loopback_with_any_free_port() -> void:
	assert_eq(Net.host(0, 4, "127.0.0.1"), OK)
	assert_gt(Net.port, 0, "the port it got")
	Net.leave()
	assert_eq(Net.host(0, 4, "not an address"), ERR_INVALID_PARAMETER)
	Net.leave()
