extends Node
## Visual check of the menus and the in-game UI (M8), windowed: opens every screen with made-up data
## and saves a screenshot of each.
##   godot tests/helpers/UiTour.tscn -- --settings /tmp/ui_tour.cfg --out /tmp/ui [--only NAME] [--lang fr] [--bots]
## --bots (M10): the server fills its matches with AI bots, and two of the made-up rats are bots.
## Always pass --settings with a throwaway file: the tour changes settings (name, favourites…).
## Shots: menu, welcome, browser_lan, browser_fav, settings_video, settings_controls, settings_audio,
## settings_gameplay, howto_supervisor, howto_rat, howto_controls, credits, error, password,
## lobby, scoreboard, pause, feed, minimap_supervisor, minimap_rat, map_supervisor, map_rat, postmatch, hint.

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
		await _shot("browser_lan")
		(browser.get_node("%Tabs") as TabContainer).current_tab = 1
		await _shot("browser_fav")
		menu._close_screen()
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
	if _wanted("password"):
		MainMenu.last_address = "192.168.1.31:7777"
		MainMenu.last_server_name = "Night shift"
		menu._ask_password(MainMenu.last_address, MainMenu.last_server_name, true)
		await _shot("password")
		_close_dialogs(menu)


func _close_dialogs(root: Node) -> void:
	for child in root.get_children():
		if child is MessageDialog:
			child.queue_free()


## The in-game screens, on an offline Session filled with made-up players.
func _in_game() -> void:
	if not (_wanted("lobby") or _wanted("scoreboard") or _wanted("pause") or _wanted("feed")
			or _wanted("postmatch") or _wanted("hint") or _wanted("minimap") or _wanted("map")):
		return
	get_tree().unload_current_scene()  # the menu goes; this runner lives on under root
	await get_tree().create_timer(0.2).timeout
	var session: Session = (load("res://common/Session.tscn") as PackedScene).instantiate()
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
	mm.server_info = {"name": "Sunny Acres #1", "max_players": 6, "duration_s": 540, "duration_single_s": 480,
		"min_players": 1 if bots else 3, "locked": false, "bot_fill_to": 6 if bots else 0}
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
