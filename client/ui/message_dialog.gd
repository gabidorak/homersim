class_name MessageDialog
extends Control
## A modal box over the current screen (M8): a title, a message, an optional text field, and one or
## two buttons. Enter accepts, Esc cancels (or accepts when there is a single button). It frees
## itself when closed and reports `closed(accepted, text)`.
##   MessageDialog.inform(self, "Server full", "Try again later.", "Back to menu")
##   var box := MessageDialog.ask(self, "Password", "This server needs a password.", "", true)
##   box.closed.connect(func(ok: bool, text: String) -> void: ...)

signal closed(accepted: bool, text: String)

var field: LineEdit
var ok_button: Button
var cancel_button: Button

var _done := false


## A message with a single button.
static func inform(parent: Node, title: String, text: String, ok_text: String = "") -> MessageDialog:
	return _make(parent, title, text, ok_text if ok_text != "" else TranslationServer.translate("OK"), "", false, "", false)


## A question with OK and Cancel.
static func confirm(parent: Node, title: String, text: String, ok_text: String, cancel_text: String = "",
		danger: bool = false) -> MessageDialog:
	var box := _make(parent, title, text, ok_text,
		cancel_text if cancel_text != "" else TranslationServer.translate("Cancel"), false, "", false)
	if danger:
		box.ok_button.theme_type_variation = &"DangerButton"
	return box


## A question with a text field (`secret` hides what is typed), OK and Cancel.
static func ask(parent: Node, title: String, text: String, initial: String = "", secret: bool = false,
		ok_text: String = "", max_length: int = 64) -> MessageDialog:
	var box := _make(parent, title, text, ok_text if ok_text != "" else TranslationServer.translate("OK"),
		TranslationServer.translate("Cancel"), true, initial, secret)
	box.field.max_length = max_length
	return box


static func _make(parent: Node, title: String, text: String, ok_text: String, cancel_text: String,
		with_field: bool, initial: String, secret: bool) -> MessageDialog:
	var box := MessageDialog.new()
	box._build(title, text, ok_text, cancel_text, with_field, initial, secret)
	parent.add_child(box)
	return box


func _build(title: String, text: String, ok_text: String, cancel_text: String, with_field: bool,
		initial: String, secret: bool) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Panel.new()
	dim.theme_type_variation = &"DimPanel"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var heading := Label.new()
	heading.theme_type_variation = &"HeaderLabel"
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(heading)
	if text != "":
		var body := Label.new()
		body.text = text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(480, 0)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(body)
	if with_field:
		field = LineEdit.new()
		field.text = initial
		field.secret = secret
		field.select_all_on_focus = true
		field.text_submitted.connect(func(_t: String) -> void: _close(true))
		col.add_child(field)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	if cancel_text != "":
		cancel_button = Button.new()
		cancel_button.text = cancel_text
		cancel_button.custom_minimum_size = Vector2(150, 0)
		cancel_button.pressed.connect(_close.bind(false))
		row.add_child(cancel_button)
	ok_button = Button.new()
	ok_button.text = ok_text
	ok_button.theme_type_variation = &"AccentButton"
	ok_button.custom_minimum_size = Vector2(150, 0)
	ok_button.pressed.connect(_close.bind(true))
	row.add_child(ok_button)
	_trap_focus()


## Every arrow and Tab from the box's controls leads to another of its controls (or nowhere), so the
## keyboard can't wander to the screen underneath.
func _trap_focus() -> void:
	var ring: Array[Control] = []
	if field != null:
		ring.append(field)
	if cancel_button != null:
		ring.append(cancel_button)
	ring.append(ok_button)
	var buttons: Array[Control] = []
	if cancel_button != null:
		buttons.append(cancel_button)
	buttons.append(ok_button)
	for i in ring.size():
		var c := ring[i]
		var self_path := NodePath(".")
		c.focus_next = c.get_path_to(ring[(i + 1) % ring.size()])
		c.focus_previous = c.get_path_to(ring[(i - 1 + ring.size()) % ring.size()])
		c.focus_neighbor_top = c.get_path_to(field) if field != null and c != field else self_path
		c.focus_neighbor_bottom = c.get_path_to(ok_button) if c == field else self_path
		if c != field:
			var j := buttons.find(c)
			c.focus_neighbor_left = c.get_path_to(buttons[(j - 1 + buttons.size()) % buttons.size()])
			c.focus_neighbor_right = c.get_path_to(buttons[(j + 1) % buttons.size()])
		else:
			c.focus_neighbor_left = self_path
			c.focus_neighbor_right = self_path


func _ready() -> void:
	Ui.play("ui_open")
	if field != null:
		field.grab_focus()
	else:
		ok_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close(cancel_button == null)
		accept_event()


func _input(event: InputEvent) -> void:
	# Keep the keyboard inside the box: Tab and arrows must not wander to the screen underneath.
	if event is InputEventKey and event.is_pressed() and get_viewport().gui_get_focus_owner() != null \
			and not is_ancestor_of(get_viewport().gui_get_focus_owner()):
		(field if field != null else ok_button).grab_focus()


func _close(accepted: bool) -> void:
	if _done:
		return
	_done = true
	closed.emit(accepted, field.text if field != null else "")
	queue_free()
