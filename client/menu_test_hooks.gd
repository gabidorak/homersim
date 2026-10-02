class_name MenuTestHooks
extends Node
## Test-only automation of the main menu (M8, debug builds), so headless clients can go through the
## real server browser and dialogs in integration tests (tests/integration/menus_smoke.sh):
##   --lan-join NAME          open the server browser and press Join on the LAN server called NAME
##                            as soon as it shows up
##   --auto-password A,B,...  answer each password prompt with the next password of the list
##   --dismiss-errors         press the error box's button (logs what it said)

static var _lan_join_used := false  # once per run: not again when the menu comes back after a session

var _menu: MainMenu
var _passwords: PackedStringArray = []
var _lan_target := ""


static func wanted() -> bool:
	return OS.is_debug_build() and (Cli.has_arg("lan-join") or Cli.has_arg("auto-password") or Cli.has_arg("dismiss-errors"))


func _ready() -> void:
	_menu = get_parent() as MainMenu
	_passwords = Cli.get_str("auto-password").split(",", false)
	if not _lan_join_used:
		_lan_join_used = true
		_lan_target = Cli.get_str("lan-join")
	_menu.child_entered_tree.connect(_on_menu_child)
	if _lan_target != "":
		_open_browser.call_deferred()


func _open_browser() -> void:
	if not is_instance_valid(_menu._screen) or not _menu._screen.has_node("LanBrowser"):
		_menu._open(MainMenu.BROWSER_SCENE, _menu.play_button)
	var lan := _menu._screen.get_node("LanBrowser") as LanBrowser
	Log.info("test", "browsing the LAN for '%s' (listening on UDP %d)" % [_lan_target, lan.port])
	lan.changed.connect(_check_lan.bind(lan))


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
