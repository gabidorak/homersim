class_name MainMenu
extends Control
## The main menu (M8): Join a game (the server browser), Play solo, Host a game, How to play, Settings,
## Credits, Quit, over a little 3D diorama (MenuBackground). It also runs the joining itself:
## connect_to() creates the Session, connects, and shows "Connecting…" with a Cancel button; the menu
## frees itself once the server accepts us.
## Play solo and Host a game open a card of choices (GameSetup), then start_local() starts a server on
## this computer (LocalServer), waits for it ("Starting…" with Cancel), and joins it.
## When a session ends (refused, kicked, connection lost, the player left), Session sets leave_code and
## comes back here, and the menu explains what happened in a box, or asks for the password and tries
## again.
## The first start asks for a name (Config.player_name). `--name X` plays as X without saving it;
## `--connect host:port` joins straight away (once: not again after a disconnect).

const SESSION_SCENE: PackedScene = preload("res://common/Session.tscn")
const BROWSER_SCENE: PackedScene = preload("res://client/ServerBrowser.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://client/Settings.tscn")
const HOW_TO_SCENE: PackedScene = preload("res://client/HowToPlay.tscn")
const CREDITS_SCENE: PackedScene = preload("res://client/Credits.tscn")
const SETUP_SCENE: PackedScene = preload("res://client/GameSetup.tscn")

## Why the last session ended (Session sets it before coming back); shown once.
static var leave_code := LeaveReason.Code.NONE
static var leave_detail := ""
## The last server we tried (to retry it with a password), and whether the browser was open.
static var last_address := ""
static var last_server_name := ""
static var reopen_browser := false
static var _auto_connect_used := false

var _screen: Control  # the open sub-screen (browser, settings…), or null on the home screen
var _opener: Button  # the button that opened it, focused again when it closes
var _connecting: MessageDialog

@onready var home: Control = %Home
@onready var screens: Control = %Screens
@onready var play_button: Button = %PlayButton
@onready var name_label: Label = %NameLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PlayerInput.blocked = false
	%Version.text = "v" + Session.game_version()
	play_button.pressed.connect(func() -> void: _open(BROWSER_SCENE, play_button))
	%SoloButton.pressed.connect(func() -> void: _open(SETUP_SCENE, %SoloButton, {"hosting": false}))
	%HostButton.pressed.connect(func() -> void: _open(SETUP_SCENE, %HostButton, {"hosting": true}))
	%HowToButton.pressed.connect(func() -> void: _open(HOW_TO_SCENE, %HowToButton))
	%SettingsButton.pressed.connect(func() -> void: _open(SETTINGS_SCENE, %SettingsButton))
	%CreditsButton.pressed.connect(func() -> void: _open(CREDITS_SCENE, %CreditsButton))
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%NameButton.pressed.connect(ask_name)
	Config.changed.connect(func(key: String) -> void:
		if key == "player_name" or key == "language":
			_update_name())
	_update_name()
	if MenuTestHooks.wanted():
		add_child(MenuTestHooks.new())
	if reopen_browser:
		_open(BROWSER_SCENE, play_button)
	else:
		play_button.grab_focus()
	if show_leave_reason():
		return
	if Cli.has_arg("connect") and not _auto_connect_used:
		_auto_connect_used = true
		connect_to.call_deferred(Cli.get_str("connect"))
	elif player_name() == "":
		ask_name.call_deferred(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_name()


## The name we join with: `--name` for this run, else the saved one ("" = not chosen yet).
static func player_name() -> String:
	return JoinRules.sanitize_name(Cli.get_str("name")) if Cli.has_arg("name") else Config.player_name


func _update_name() -> void:
	var current := player_name()
	name_label.text = tr("Playing as %s") % (current if current != "" else "?")


## Asks for the player's name (`first`: the welcome version, which can't be skipped).
func ask_name(first: bool = false) -> void:
	var suggestion := player_name()
	if suggestion == "":
		suggestion = JoinRules.sanitize_name(OS.get_environment("USER") if OS.has_environment("USER")
			else OS.get_environment("USERNAME"))
	var title := tr("Welcome to the plant!") if first else tr("Your name")
	var text := tr("What should the others call you?")
	var box := MessageDialog.ask(self, title, text, suggestion, false, "", JoinRules.MAX_NAME_LENGTH)
	if first:
		box.cancel_button.visible = false
	box.closed.connect(func(accepted: bool, typed: String) -> void:
		if accepted or first:
			var clean := typed.strip_edges()
			Config.set_value("player_name", clean if clean != "" else suggestion)
		if not is_instance_valid(_screen):
			(play_button if first else %NameButton as Button).grab_focus())


# --- Screens -------------------------------------------------------------------

## Opens a sub-screen; `props` are set on it before it enters the tree.
func _open(scene: PackedScene, opener: Button, props: Dictionary = {}) -> void:
	_close_screen()
	_opener = opener
	_screen = scene.instantiate()
	for key: String in props:
		_screen.set(key, props[key])
	screens.add_child(_screen)
	home.visible = false
	%Shade.visible = scene != BROWSER_SCENE and scene != SETTINGS_SCENE  # those have their own panel
	_screen.connect("closed", _close_screen)
	if _screen.has_signal("join_requested"):
		_screen.connect("join_requested", _on_join_requested)
	if _screen.has_signal("start_requested"):
		_screen.connect("start_requested", start_local)
	reopen_browser = scene == BROWSER_SCENE


func _close_screen() -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	reopen_browser = false
	home.visible = true
	%Shade.visible = true
	if is_instance_valid(_opener):
		_opener.grab_focus()


# --- Joining -------------------------------------------------------------------

func _on_join_requested(address: String, server_name: String, locked: bool) -> void:
	if locked:
		_ask_password(address, server_name, false)
	else:
		connect_to(address, "", server_name)


## Starts a server on this computer (Play solo, Host a game; `options` from LocalServer), then joins it.
func start_local(mode: LocalServer.Mode, options: Dictionary) -> void:
	if Session.current != null or is_instance_valid(_connecting):
		return  # already joining
	if player_name() == "":
		Config.set_value("player_name", JoinRules.DEFAULT_NAME)
	var server := LocalServer.new()
	server.name = "LocalServer"
	get_tree().root.add_child(server)
	server.started.connect(func(port: int) -> void:
		_close_connecting()
		connect_to("127.0.0.1:%d" % port, str(options["password"]), str(options["name"]), server))
	server.failed.connect(func(code: LeaveReason.Code, detail: String) -> void:
		_close_connecting()
		_show_error(code, detail))
	server.start(mode, options)
	if server.state != LocalServer.State.STARTING:
		return  # (failed already: the error box is up)
	_connecting = MessageDialog.inform(self, tr("Starting..."), tr("Getting the plant ready..."), tr("Cancel"))
	_connecting.ok_button.theme_type_variation = &""
	_connecting.closed.connect(func(_ok: bool, _t: String) -> void:
		_connecting = null
		Log.info("menu", "start cancelled")
		server.stop())


func _close_connecting() -> void:
	if is_instance_valid(_connecting):
		_connecting.queue_free()
	_connecting = null


## Joins `address` ("host" or "host:port"). Creates the Session first: the server starts replicating
## (spawning the other players) as soon as the connection is up. `local`: the server this game started
## (start_local), which then serves this session.
func connect_to(address: String, password: String = "", server_name: String = "", local: LocalServer = null) -> void:
	if Session.current != null:
		return  # already connecting
	var addr := Net.parse_address(address)
	if addr.is_empty():
		_show_error(LeaveReason.Code.BAD_ADDRESS, address.strip_edges())
		return
	if player_name() == "":
		Config.set_value("player_name", JoinRules.DEFAULT_NAME)
	last_address = address.strip_edges()
	last_server_name = server_name
	var session: Session = SESSION_SCENE.instantiate()
	session.desired_name = player_name()
	session.desired_password = password
	session.joined.connect(queue_free)
	if local != null:
		local.serve(session)  # (before the session's UI is built: it adapts to a game we host)
	get_tree().root.add_child(session)
	var err := Net.join(addr["host"], addr["port"])
	if err != OK:
		get_tree().root.remove_child(session)
		session.queue_free()
		_show_error(LeaveReason.Code.CANNOT_CONNECT, error_string(err))
		return
	var shown := server_name if server_name != "" else "%s:%d" % [addr["host"], addr["port"]]
	Log.info("menu", "connecting to %s:%d" % [addr["host"], addr["port"]])
	_connecting = MessageDialog.inform(self, tr("Connecting..."), tr("Joining %s") % shown, tr("Cancel"))
	_connecting.ok_button.theme_type_variation = &""
	_connecting.closed.connect(func(_ok: bool, _t: String) -> void:
		_connecting = null
		if Session.current != null:
			Log.info("menu", "connection cancelled")
			Session.current.leave())


## Called by Session when it ended while this menu was still open (a failed or cancelled join), and
## by _ready after a session ended in game. Returns true if it showed something.
func show_leave_reason() -> bool:
	_close_connecting()
	var code := leave_code
	var detail := leave_detail
	leave_code = LeaveReason.Code.NONE
	leave_detail = ""
	match code:
		LeaveReason.Code.NONE:
			return false
		LeaveReason.Code.PASSWORD_REQUIRED, LeaveReason.Code.WRONG_PASSWORD:
			_ask_password(last_address, last_server_name, code == LeaveReason.Code.WRONG_PASSWORD)
		_:
			_show_error(code, detail)
	return true


func _show_error(code: LeaveReason.Code, detail: String) -> void:
	Log.info("menu", "error box: %s" % LeaveReason.log_text(code, detail))
	Ui.play("ui_error")
	MessageDialog.inform(self, LeaveReason.title(code), LeaveReason.message(code, detail), tr("Back to menu"))


func _ask_password(address: String, server_name: String, wrong: bool) -> void:
	var text := tr("That password is not the right one. Try again?") if wrong \
		else tr("%s needs a password.") % (server_name if server_name != "" else address)
	Log.info("menu", "asking for the password of %s (%s)" % [address, "wrong password" if wrong else "required"])
	if wrong:
		Ui.play("ui_error")
	var box := MessageDialog.ask(self, tr("Wrong password") if wrong else tr("Password"), text, "", true, tr("Join"))
	box.closed.connect(func(accepted: bool, typed: String) -> void:
		if accepted:
			connect_to(address, typed, server_name))
