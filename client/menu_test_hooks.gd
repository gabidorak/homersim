class_name MenuTestHooks
extends Node
## Test-only automation of the main menu (M8, debug builds), so headless clients can go through the
## real server browser and dialogs in integration tests (tests/integration/menus_smoke.sh):
##   --lan-join NAME          open the server browser and press Join on the LAN server called NAME
##                            as soon as it shows up
##   --auto-password A,B,...  answer each password prompt with the next password of the list
##   --dismiss-errors         press the error box's button (logs what it said)
##   --solo [any|supervisor|rat]  open the Play solo card (with that role) and press Start
##   --host-game NAME [--host-port N] [--host-bots 0|1]  open the Host a game card with these choices
##                            (--host-bots 0: no bots) and press Host
##   --host-online NAME [--host-bots 0|1]  the same with "Online server" chosen (the friends key and
##                            the launcher's address come from --online-key / --online-url)
##   --teams S,R              with --solo / --host-*: S supervisors and R rats on the card
##   --online-join NAME       open the server browser's Online tab and press Join on the game called
##                            NAME as soon as it shows up
## (Headless clients don't save their settings, so the choices made here don't stick.)

const FLAGS: Array[String] = ["lan-join", "auto-password", "dismiss-errors", "solo", "host-game", "host-online",
	"online-join"]

static var _lan_join_used := false  # once per run: not again when the menu comes back after a session
static var _local_used := false  # --solo / --host-game / --host-online: once per run too
static var _online_join_used := false

var _menu: MainMenu
var _passwords: PackedStringArray = []
var _lan_target := ""
var _online_target := ""


static func wanted() -> bool:
	return OS.is_debug_build() and FLAGS.any(Cli.has_arg)


func _ready() -> void:
	_menu = get_parent() as MainMenu
	_passwords = Cli.get_str("auto-password").split(",", false)
	if not _lan_join_used:
		_lan_join_used = true
		_lan_target = Cli.get_str("lan-join")
	_menu.child_entered_tree.connect(_on_menu_child)
	if not _online_join_used:
		_online_join_used = true
		_online_target = Cli.get_str("online-join")
	if _lan_target != "":
		_open_browser.call_deferred()
	elif _online_target != "":
		_open_online.call_deferred()
	if not _local_used and (Cli.has_arg("solo") or Cli.has_arg("host-game") or Cli.has_arg("host-online")):
		_local_used = true
		_start_local.call_deferred()


func _start_local() -> void:
	var online := Cli.has_arg("host-online")
	var hosting := Cli.has_arg("host-game") or online
	Config.set_value("host_online", online)
	if hosting:
		Config.set_value("host_name", Cli.get_str("host-online" if online else "host-game"))
		Config.set_value("host_port", Cli.get_int("host-port", Net.DEFAULT_PORT))
		if Cli.has_arg("host-bots"):
			Config.set_value("host_bots", Cli.get_int("host-bots") != 0)
	else:
		Config.set_value("solo_role", Role.from_text(Cli.get_str("solo", "any")))
	var teams := Cli.get_str("teams").split(",", false)
	if teams.size() == 2:
		var prefix := "host_" if hosting else "solo_"
		Config.set_value(prefix + "supervisors", teams[0].to_int())
		Config.set_value(prefix + "rats", teams[1].to_int())
	var opener: Button = _menu.get_node("%HostButton" if hosting else "%SoloButton")
	_menu._open(MainMenu.SETUP_SCENE, opener, {"hosting": hosting})
	await get_tree().process_frame
	Log.info("test", "pressing %s on the %s card" % [(_menu._screen.get_node("%StartButton") as Button).text,
		"online host" if online else "host" if hosting else "solo"])
	(_menu._screen.get_node("%StartButton") as Button).pressed.emit()


func _open_browser() -> void:
	if not is_instance_valid(_menu._screen) or not _menu._screen.has_node("LanBrowser"):
		_menu._open(MainMenu.BROWSER_SCENE, _menu.play_button)
	var lan := _menu._screen.get_node("LanBrowser") as LanBrowser
	Log.info("test", "browsing the LAN for '%s' (listening on UDP %d)" % [_lan_target, lan.port])
	lan.changed.connect(_check_lan.bind(lan))


func _open_online() -> void:
	_menu._open(MainMenu.BROWSER_SCENE, _menu.play_button)
	(_menu._screen.get_node("%Tabs") as TabContainer).current_tab = ServerBrowser.TAB_ONLINE
	var online := _menu._screen.get_node("OnlineClient") as OnlineClient
	Log.info("test", "looking for '%s' on the online server %s" % [_online_target, OnlineClient.url()])
	online.listed.connect(_check_online)


func _check_online(games: Array[Dictionary]) -> void:
	for game in games:
		if game["name"] == _online_target:
			Log.info("test", "found '%s' online on port %d (%d/%d), joining" % [game["name"], game["port"], game["players"], game["max"]])
			(_menu._screen.get_node("OnlineClient") as OnlineClient).listed.disconnect(_check_online)
			_online_target = ""
			var row: Control = (_menu._screen.get("_online_rows") as Dictionary)[game["id"]]  # (the browser built it first)
			(row.get_child(0).get_node("Join") as Button).pressed.emit()
			return


func _check_lan(lan: LanBrowser) -> void:
	for entry: Dictionary in lan.list.servers.values():
		if entry["name"] == _lan_target:
			Log.info("test", "found '%s' at %s (%d/%d, ping %d ms), joining" % [entry["name"], LanDiscovery.address_of(entry),
				entry["players"], entry["max"], entry["ping_ms"]])
			lan.changed.disconnect(_check_lan)
			_lan_target = ""
			_menu._screen.emit_signal("join_requested", LanDiscovery.address_of(entry), entry["name"], entry["locked"])
			return


func _on_menu_child(node: Node) -> void:
	var box := node as MessageDialog
	if box == null:
		return
	await get_tree().process_frame  # (built, but not shown yet)
	if not is_instance_valid(box) or box == _menu._connecting:
		return
	if box.field != null and box.field.secret and not _passwords.is_empty():
		var password := _passwords[0]
		_passwords.remove_at(0)
		Log.info("test", "typing a password at the prompt")
		box.field.text = password
		box.ok_button.pressed.emit()
	elif box.field == null and box.cancel_button == null and Cli.has_arg("dismiss-errors"):
		Log.info("test", "dismissing the error box")
		box.ok_button.pressed.emit()
