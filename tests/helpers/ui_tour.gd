extends Node
## Visual check of the menus and the in-game UI (M8), windowed: opens every screen with made-up data
## and saves a screenshot of each.
##   godot tests/helpers/UiTour.tscn -- --settings /tmp/ui_tour.cfg --out /tmp/ui [--only NAME] [--lang fr] [--bots]
##     [--big] [--local solo|host]
## --bots (M10): the server fills its matches with AI bots, and two of the made-up rats are bots.
## --big: the biggest teams (3 supervisors and 6 rats): three more bots in the match.
## --local: the made-up game is one this game started (LocalServer): the solo or the host's lobby and menu.
## Always pass --settings with a throwaway file: the tour changes settings (name, favourites…).
## Shots: menu, welcome, browser_lan, browser_online_key, browser_online, browser_online_error, browser_fav,
## setup_solo, setup_host, setup_host_online, starting, settings_video, settings_controls,
## settings_audio, settings_gameplay, howto_supervisor, howto_rat, howto_controls, credits, error,
## error_host_left, error_online, password, lobby, scoreboard, pause, feed, minimap_supervisor,
## minimap_rat, map_supervisor, map_rat, hotbar_supervisor, hotbar_rat, postmatch, hint.

const MENU := "res://client/MainMenu.tscn"

var _out := ""
var _only := ""


func _ready() -> void:
	if get_tree().current_scene == self:
		# The tour changes scenes, which frees the current one: run it from a node directly under root.
		var runner: Node = (get_script() as GDScript).new()
		runner.name = "UiTourRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	_out = Cli.get_str("out", "user://ui_tour")
	_only = Cli.get_str("only")
	DirAccess.make_dir_recursive_absolute(_out)
	if Cli.has_arg("lang"):
		Config.set_value("language", Cli.get_str("lang"))
	await _menus()
	await _in_game()
	Log.info("tour", "done: %s" % _out)
	get_tree().quit()


func _wanted(shot: String) -> bool:
	return _only == "" or shot.begins_with(_only)


func _shot(shot: String, settle: float = 0.6) -> void:
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, shot]
	get_viewport().get_texture().get_image().save_png(path)
	Log.info("tour", "saved %s" % path)


func _menus() -> void:
	Config.set_value("player_name", "")
	get_tree().change_scene_to_file(MENU)
	await get_tree().create_timer(0.3).timeout
	var menu := get_tree().current_scene as MainMenu
	if _wanted("welcome"):
		await _shot("welcome", 2.0)
	for child in menu.get_children():
		if child is MessageDialog:
			(child as MessageDialog).field.text = "Gabriel"
			(child as MessageDialog).ok_button.pressed.emit()
	if _wanted("menu"):
		await _shot("menu", 1.5)
	if _wanted("browser"):
		Config.add_favourite("Friday night plant", "plant.example.net:7777")
		Config.add_favourite("Office LAN", "192.168.1.20:7777")
		menu._open(MainMenu.BROWSER_SCENE, menu.play_button)
		var browser := menu._screen
		var lan: LanBrowser = browser.get_node("LanBrowser")
		var now := Net.local_time()
		var fake := [
			{"id": 1, "name": "Sunny Acres #1", "players": 3, "max": 6, "port": 7777, "version": Session.game_version(), "state": "lobby", "locked": false},
			{"id": 2, "name": "Night shift (password)", "players": 5, "max": 6, "port": 7777, "version": Session.game_version(), "state": "playing", "locked": true},
			{"id": 3, "name": "Old build server", "players": 1, "max": 6, "port": 7790, "version": "0.0.9", "state": "lobby", "locked": false},
			{"id": 4, "name": "Full house", "players": 6, "max": 6, "port": 7777, "version": Session.game_version(), "state": "lobby", "locked": false},
		]
		var ips := ["192.168.1.20", "192.168.1.31", "192.168.1.44", "192.168.1.50"]
		for i in fake.size():
			fake[i]["kind"] = "announce"
			lan.list.heard(fake[i], ips[i], 50000 + i, now + 1000.0)
			lan.list.got_pong(fake[i]["id"], [0.012, 0.085, 0.2, 0.03][i])
		browser.call("_refresh_lan")
		var tabs := browser.get_node("%Tabs") as TabContainer
		tabs.current_tab = ServerBrowser.TAB_LAN
		await _shot("browser_lan")
		await _online_shots(browser, tabs)
		tabs.current_tab = ServerBrowser.TAB_FAVOURITES
		await _shot("browser_fav")
		menu._close_screen()
	if _wanted("setup"):
		for card: String in ["setup_solo", "setup_host", "setup_host_online"]:
			Config.set_value("host_online", card == "setup_host_online")
			menu._open(MainMenu.SETUP_SCENE, menu.play_button, {"hosting": card != "setup_solo"})
			await _shot(card)
			menu._close_screen()
		Config.set_value("host_online", false)
	if _wanted("starting"):
		MessageDialog.inform(menu, tr("Starting..."), tr("Getting the plant ready..."), tr("Cancel"))
		await _shot("starting")
		_close_dialogs(menu)
	if _wanted("settings"):
		menu._open(MainMenu.SETTINGS_SCENE, menu.play_button)
		var tabs := menu._screen.get_node("%Tabs") as TabContainer
		for i in 4:
			tabs.current_tab = i
			await _shot("settings_" + ["video", "controls", "audio", "gameplay"][i])
		# Switch the language with the screen open: it rebuilds in the other language.
		var before := Config.language
		Config.set_value("language", "fr" if Config.current_language() != "fr" else "en")
		await _shot("settings_language_switched")
		Config.set_value("language", before)
		await get_tree().create_timer(0.2).timeout
		menu._close_screen()
	if _wanted("howto"):
		menu._open(MainMenu.HOW_TO_SCENE, menu.play_button)
		var tabs := menu._screen.get_node("%Tabs") as TabContainer
		for i in 3:
			tabs.current_tab = i
			await _shot("howto_" + ["supervisor", "rat", "controls"][i])
		menu._close_screen()
	if _wanted("credits"):
		menu._open(MainMenu.CREDITS_SCENE, menu.play_button)
		await _shot("credits")
		menu._close_screen()
	if _wanted("error"):
		menu._show_error(LeaveReason.Code.VERSION, "0.2.0+master.41|0.1.0+master.40")
		await _shot("error")
		_close_dialogs(menu)
		menu._show_error(LeaveReason.Code.HOST_LEFT, "")
		await _shot("error_host_left")
		_close_dialogs(menu)
		menu._show_error(LeaveReason.Code.ONLINE, OnlineApi.ERR_KEY)
		await _shot("error_online")
		_close_dialogs(menu)
	if _wanted("password"):
		MainMenu.last_address = "192.168.1.31:7777"
		MainMenu.last_server_name = "Night shift"
		menu._ask_password(MainMenu.last_address, MainMenu.last_server_name, true)
		await _shot("password")
		_close_dialogs(menu)


## The Online tab with no key, with made-up games, and when the server can't be reached. Its
## OnlineClient is cut off first, so the tour never asks a real server.
func _online_shots(browser: Control, tabs: TabContainer) -> void:
	Config.set_value("online_key", "")
	tabs.current_tab = ServerBrowser.TAB_ONLINE
	await _shot("browser_online_key")
	var online := browser.get_node("OnlineClient") as OnlineClient
	for signal_name: StringName in [&"listed", &"failed"]:
		for connection: Dictionary in online.get_signal_connection_list(signal_name):
			online.disconnect(signal_name, connection["callable"])
	for child in browser.get_children():
		if child is Timer:
			(child as Timer).stop()
	Config.set_value("online_key", "tour-key")
	(browser.get_node("%KeyEdit") as LineEdit).text = "tour-key"
	browser.set("_online_answered", true)
	browser.set("_online_games", [
		OnlineApi.game_entry({"name": "Gabriel's plant", "players": 3, "max": 6, "state": "playing", "locked": false,
			"version": Session.game_version()}, 7800),
		OnlineApi.game_entry({"name": "Late shift", "players": 1, "max": 4, "state": "lobby", "locked": true,
			"version": Session.game_version()}, 7801),
		OnlineApi.game_entry({"name": "Old build game", "players": 2, "max": 6, "state": "lobby", "locked": false,
			"version": "0.0.9"}, 7802),
	] as Array[Dictionary])
	browser.call("_show_online")
	await _shot("browser_online")
	browser.set("_online_error", LeaveReason.message(LeaveReason.Code.ONLINE, "%s|%s" % [OnlineApi.ERR_UNREACHABLE,
		OnlineClient.host_label()]))
	browser.set("_online_games", [] as Array[Dictionary])
	browser.call("_show_online")
	await _shot("browser_online_error")
	Config.set_value("online_key", "")


func _close_dialogs(root: Node) -> void:
	for child in root.get_children():
		if child is MessageDialog:
			child.queue_free()


## The in-game screens, on an offline Session filled with made-up players.
func _in_game() -> void:
	if not (_wanted("lobby") or _wanted("scoreboard") or _wanted("pause") or _wanted("feed")
			or _wanted("postmatch") or _wanted("hint") or _wanted("minimap") or _wanted("map") or _wanted("hotbar")):
		return
	get_tree().unload_current_scene()  # the menu goes; this runner lives on under root
	await get_tree().create_timer(0.2).timeout
	var session: Session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	if Cli.has_arg("local"):  # a game this game started: a pretend LocalServer serves it (no process)
		var local := LocalServer.new()
		local.mode = LocalServer.Mode.SOLO if Cli.get_str("local") == "solo" else LocalServer.Mode.HOST
		local.state = LocalServer.State.RUNNING
		local.port = Net.DEFAULT_PORT
		LocalServer.current = local
		get_tree().root.add_child(local)
		local.serve(session)
	get_tree().root.add_child(session)
	await get_tree().create_timer(1.0).timeout
	var mm := session.match_manager
	session.local_peer_id = 11
	var bots := Cli.has_arg("bots")
	var names := {11: "Gabriel", 12: "Alice", 13: "Bob the Rat", 14: "Chloé", 15: "Dmitri", 16: "Eve"}
	if bots:  # two rats are AI bots: not in the lobby, no ping
		names = _as_bots(names)
		names[-1001] = "Gus"
		names[-1002] = "Nibbles"
	var roster := {}
	for peer: int in names:
		if Session.is_ai_id(peer):
			continue
		session.players[peer] = PlayerInfo.new(peer, names[peer])
		roster[peer] = {"name": names[peer], "pref": [Role.Kind.SUPERVISOR, Role.Kind.NONE, Role.Kind.RAT, Role.Kind.RAT,
			Role.Kind.NONE, Role.Kind.SUPERVISOR][peer - 11], "ready": peer % 2 == 1, "role": Role.Kind.NONE, "eliminated": false}
	var big := Cli.has_arg("big")
	mm.server_info = {"name": "Sunny Acres #1", "max_players": 6, "duration_s": 540, "duration_single_s": 480,
		"min_players": 1 if bots or big else 3, "locked": false, "supervisors": 3 if big else 2, "rats": 6 if big else 4,
		"bot_fill_to": 9 if big else 6 if bots else 0}
	mm.min_players = mm.server_info["min_players"]
	mm.pings = _as_bots({11: 18, 12: 42, 13: 95, 14: 160, 15: 33, 16: 61}) if bots else {11: 18, 12: 42, 13: 95, 14: 160, 15: 33, 16: 61}
	mm.roster = roster
	mm.state = MatchManager.State.LOBBY
	if _wanted("lobby"):
		for i in 3:
			session.chat.message_received.emit("", tr("%s joined") % names[12 + i], ChatService.Channel.SYSTEM)
		session.chat.message_received.emit("Alice", "who wants to be the boss?", ChatService.Channel.ALL)
		session.chat.message_received.emit("Bob the Rat", "not me, I want cheese", ChatService.Channel.ALL)
		await _shot("lobby", 1.0)
	# A match under way.
	var roles := {11: Role.Kind.SUPERVISOR, 12: Role.Kind.SUPERVISOR, 13: Role.Kind.RAT, 14: Role.Kind.RAT, 15: Role.Kind.RAT,
		16: Role.Kind.RAT}
	if bots:
		roles = _as_bots(roles)
	if big:
		for i in 3:
			names[-1003 - i] = ["Big Earl", "Crumbs", "Fuzzbucket"][i]
			roles[-1003 - i] = Role.Kind.SUPERVISOR if i == 0 else Role.Kind.RAT
	var playing := roster.duplicate(true)
	for peer: int in roles:
		if not playing.has(peer):
			playing[peer] = {"name": names[peer], "pref": Role.Kind.NONE, "ready": false, "role": Role.Kind.NONE,
				"eliminated": false, "bot": true}
		playing[peer]["role"] = roles[peer]
	playing[-1002 if bots else 16]["eliminated"] = true
	mm.roster = playing
	mm.state = MatchManager.State.PLAYING
	mm.time_left = 312
	mm.live_stats = {11: {"repairs": 4, "bonks": 3, "catches": 2}, 12: {"repairs": 2, "donuts": 3},
		13: {"sabotages": 5, "bites": 2}, 14: {"sabotages": 2, "frees": 1, "caught": 1}, 15: {"bites": 4, "knockdowns": 1},
		16: {"caught": 2, "sabotages": 1}}
	if bots:
		mm.live_stats = _as_bots(mm.live_stats)
	if big:
		mm.live_stats.merge({-1003: {"repairs": 3, "catches": 1}, -1004: {"sabotages": 3}, -1005: {"bites": 2, "frees": 2}})
	session.plant.meltdown = 46.0
	if _wanted("feed") or _wanted("scoreboard"):
		for line: Array in [["sabotaged", "turbine", ""], ["bonk", "Gabriel", "Bob the Rat"], ["caged", "Gabriel", "Chloé"],
				["freed", "Dmitri", "Chloé"], ["knockdown", "Alice", ""], ["offline", "rods", ""], ["stolen", "Alice", ""],
				["eliminated", "Gabriel", "Eve"]]:
			Events.feed_event.emit(line[0], line[1], line[2])
		await _shot("feed", 0.5)
	if _wanted("scoreboard"):
		var board := session.client_only.get_node_or_null("Scoreboard")
		if board != null:
			board.call("set_forced", true)
			await _shot("scoreboard")
			board.call("set_forced", false)
	if _wanted("pause"):
		var pause := session.client_only.get_node_or_null("PauseMenu")
		if pause != null:
			await get_tree().create_timer(0.3).timeout  # (the spectator camera grabs the mouse when it starts)
			pause.call("open")
			await _shot("pause")
			# The settings from the pause menu, and a language switch while they are open.
			pause.call("_open_sub", PauseMenu.SETTINGS_SCENE)
			var before := Config.language
			Config.set_value("language", "fr" if Config.current_language() != "fr" else "en")
			await _shot("pause_settings_switched")
			Config.set_value("language", before)
			await get_tree().create_timer(0.3).timeout
			pause.call("close")
	if _wanted("hint"):
		var hints := session.client_only.get_node_or_null("Hints")
		if hints != null:
			Config.reset_hints()
			hints.call("show_hint", "role_rat")
			await _shot("hint", 0.8)
	if _wanted("minimap") or _wanted("map"):
		await _map_shots(session, names, roles)
	if _wanted("hotbar"):
		await _hotbar_shots(session, names, roles)
	if _wanted("postmatch"):
		var stats: Array = []
		for peer: int in roles:
			var row := {"peer": peer, "name": names[peer], "role": roles[peer], "bot": Session.is_ai_id(peer)}
			for key in MatchManager.STAT_KEYS:
				row[key] = mm.live_stats[peer].get(key, 0)
			stats.append(row)
		mm.result = {"winner": MatchRulesModel.Team.SUPERVISORS, "reason": "The shift is over: the plant survived", "stats": stats}
		mm.state = MatchManager.State.POST_MATCH
		mm.countdown_left = 12
		await _shot("postmatch", 2.0)
	session.queue_free()
	await get_tree().create_timer(0.3).timeout


## The inventory at the bottom of the HUD: a supervisor in the Break Room with a donut (selected, so
## its caption shows), one trap left and their keycard stolen; then a rat carrying that keycard.
func _hotbar_shots(session: Session, names: Dictionary, roles: Dictionary) -> void:
	var bodies: Array[Player] = []
	for peer: int in [11, 13]:
		var body := session._spawn_player({"peer": peer, "name": names[peer], "role": roles[peer],
			"pos": Vector3(-22 - (peer - 11), 0, 12), "yaw": 0.0, "locked": false}) as Player
		session.players_root.add_child(body)
		bodies.append(body)
	await get_tree().create_timer(0.3).timeout
	var supervisor := session.get_body(11)
	supervisor.inventory.snap_charges = 1
	supervisor.inventory.lure_charges = 2
	supervisor.inventory.donuts = 1
	supervisor.inventory.keycard = false
	supervisor.inventory.spare_wait_left = 12
	var rat := session.get_body(13)
	rat.inventory.stolen_item = &"keycard"
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(-21, 1.6, 11), Vector3(-15.5, 1.0, 14.5))
	camera.make_current()
	session.local_peer_id = 11
	Events.local_player_spawned.emit(supervisor)
	await get_tree().process_frame  # (the hotbar shows a caption when the selection *changes*)
	await get_tree().process_frame
	supervisor.hotbar.select(supervisor.hotbar.slots().find(Hotbar.DONUT))
	await _shot("hotbar_supervisor", 0.5)
	session.local_peer_id = 13
	Events.local_player_spawned.emit(rat)
	await _shot("hotbar_rat", 0.5)
	session.local_peer_id = 11
	camera.queue_free()
	for body in bodies:
		body.queue_free()
	await get_tree().create_timer(0.2).timeout


## `d` with the made-up players 15 and 16 turned into bots -1001 and -1002 (--bots).
func _as_bots(d: Dictionary) -> Dictionary:
	var out := {}
	for peer: int in d:
		if peer == 15 or peer == 16:
			out[-1001 - (peer - 15)] = d[peer]
		else:
			out[peer] = d[peer]
	return out


## The minimap and the full map (M), seen by a supervisor and by a rat, with bodies around the plant: a
## revealed rat (the supervisor sees it), a caged one, one in the South Corridor, a damaged plant.
func _map_shots(session: Session, names: Dictionary, roles: Dictionary) -> void:
	var cage := get_tree().get_first_node_in_group(Cage.CAGE_GROUP) as Cage
	var spots := {11: Vector3(-30, 0, 3), 12: Vector3(4, 0, -9), 13: Vector3(-46, 0, -16),
		14: cage.global_position if cage != null else Vector3(37, 0, 2), 15: Vector3(-20, 0, 23)}
	if Cli.has_arg("bots"):
		spots = _as_bots(spots)
	var bodies: Array[Player] = []
	for peer: int in spots:
		var body := session._spawn_player({"peer": peer, "name": names[peer], "role": roles[peer], "pos": spots[peer],
			"yaw": 0.0, "locked": false}) as Player
		body.is_bot = Session.is_ai_id(peer)  # (the badge; offline, a server-owned body would be "local")
		session.players_root.add_child(body)
		bodies.append(body)
	await get_tree().create_timer(0.3).timeout
	session.get_body(13).status.flags |= 1 << StatusComponent.Status.REVEALED
	session.get_body(14).status.flags |= 1 << StatusComponent.Status.CAGED
	if cage != null:
		cage.occupants = PackedInt32Array([14])
	session.plant.healths = PackedFloat32Array([0, 35, 100, 50, 80, 15])
	session.plant.offline_mask = 1
	var camera := Camera3D.new()
	add_child(camera)
	var overlay := session.client_only.get_node("MapOverlay") as MapOverlay
	for view: Array in [[11, "supervisor", Vector3(1, -0.1, -0.5)], [13, "rat", Vector3(0.3, -0.2, 1)]]:
		session.local_peer_id = view[0]
		var eye := session.get_body(view[0]).global_position + Vector3.UP * 1.6
		camera.look_at_from_position(eye, eye + (view[2] as Vector3))
		camera.make_current()
		Events.local_player_spawned.emit(session.get_body(view[0]))  # (the HUD shows that player's lines)
		if _wanted("minimap"):
			await _shot("minimap_" + view[1], 0.8)
		if _wanted("map"):
			overlay.set_open(true)
			await _shot("map_" + view[1], 0.8)
			overlay.set_open(false)
	session.local_peer_id = 11
	camera.queue_free()
	for body in bodies:
		body.queue_free()
	if cage != null:
		cage.occupants = PackedInt32Array()
