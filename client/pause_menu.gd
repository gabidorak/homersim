class_name PauseMenu
extends CanvasLayer
## The in-game menu (M8, ClientOnly): Esc opens it, Esc or Resume closes it. It doesn't pause anything
## (the match goes on for everyone, so it is really a "free the mouse" menu): Resume, How to play,
## Settings, Leave. In a game this game started (LocalServer), Leave ends it: "Quit the solo game", or
## "Close the game" for the host (everyone goes back to their menu). While it is open the mouse is free, so the lobby panel can be clicked too;
## clicking the 3D view captures the mouse again, which closes the menu.
## The chat and the repair minigames take Esc first while they are open (they handle it in _input).

const SETTINGS_SCENE: PackedScene = preload("res://client/Settings.tscn")
const HOW_TO_SCENE: PackedScene = preload("res://client/HowToPlay.tscn")

var is_open := false

var _root: Control
var _panel: Control
var _resume: Button
var _server_label: Label
var _sub: Control  # settings / how to play, opened from here


func _ready() -> void:
	layer = 20
	_build()
	_root.visible = false


func _notification(what: int) -> void:
	# The language changed (from the settings opened here): rebuild in the new one, a moment later
	# (children can't change while the notification goes down the tree).
	if what == NOTIFICATION_TRANSLATION_CHANGED and _root != null:
		_rebuild.call_deferred()


func _rebuild() -> void:
	remove_child(_root)
	_root.queue_free()
	_build()
	_root.visible = is_open
	if is_open:
		_server_label.text = str(Session.current.match_manager.server_info.get("name", ""))
	if is_instance_valid(_sub):
		_panel.visible = false
		move_child(_sub, -1)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.03, 0.04, 0.08, 0.85), Color(0.03, 0.04, 0.08, 0.5), Color(0.03, 0.04, 0.08, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1, 0)
	texture.width = 256
	texture.height = 4
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.anchor_bottom = 1.0
	shade.offset_right = 620
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(320, 0)
	margin.add_child(col)
	_panel = col
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = tr("Menu")
	col.add_child(title)
	_server_label = Label.new()
	_server_label.theme_type_variation = &"MutedLabel"
	_server_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_server_label)
	_resume = _button(col, tr("Resume"), &"AccentButton", close)
	_button(col, tr("How to play"), &"", _open_sub.bind(HOW_TO_SCENE))
	_button(col, tr("Settings"), &"", _open_sub.bind(SETTINGS_SCENE))
	var local := LocalServer.for_session()
	_button(col, tr("Leave the server") if local == null else tr("Quit the solo game") if local.mode == LocalServer.Mode.SOLO
		else tr("Close the game"), &"DangerButton", _ask_leave)
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.text = tr("The game goes on while this menu is open.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	col.add_child(note)


func _button(parent: Control, text: String, variation: StringName, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 50)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true
	var info: Dictionary = Session.current.match_manager.server_info
	_server_label.text = str(info.get("name", ""))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()
	Ui.play("ui_open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_close_sub()
	_root.visible = false
	if get_window().has_focus() and _wants_captured_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A body to steer, or a spectator camera to fly: the mouse goes back to the game.
func _wants_captured_mouse() -> bool:
	var session := Session.current
	if session == null:
		return false
	return session.get_body(session.local_peer_id) != null or session.match_manager.in_match()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Something captured the mouse again (a click in the 3D view): back to the game.
	if is_open and _sub == null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		close()


func _open_sub(scene: PackedScene) -> void:
	_close_sub()
	_sub = scene.instantiate()
	_sub.set("in_game", true)
	_sub.connect("closed", func() -> void:
		_close_sub()
		_resume.grab_focus())
	add_child(_sub)
	_panel.visible = false
	var role := Session.current.match_manager.local_role()
	if _sub.has_method("show_role") and role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		_sub.call("show_role", role)


func _close_sub() -> void:
	if is_instance_valid(_sub):
		_sub.queue_free()
	_sub = null
	if is_instance_valid(_panel):
		_panel.visible = true


func _ask_leave() -> void:
	var in_match := Session.current.match_manager.in_match()
	var local := LocalServer.for_session()
	var box: MessageDialog
	if local != null and local.mode == LocalServer.Mode.SOLO:
		box = MessageDialog.confirm(_root, tr("Quit the solo game?"), tr("The match ends and you go back to the main menu."),
			tr("Quit"), tr("Stay"), true)
	elif local != null:
		box = MessageDialog.confirm(_root, tr("Close the game?"), tr("You are the host: the game ends for everyone."),
			tr("Close"), tr("Stay"), true)
	else:
		box = MessageDialog.confirm(_root, tr("Leave the server?"),
			tr("The match goes on without you.") if in_match else tr("You can come back from the server browser."),
			tr("Leave"), tr("Stay"), true)
	box.closed.connect(func(ok: bool, _t: String) -> void:
		if ok:
			Session.current.leave()
		else:
			_resume.grab_focus())
