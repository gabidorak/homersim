extends Control
## The settings screen (M8), from the main menu and from the in-game pause menu. Four tabs whose
## rows are generated below from the Config settings: Video, Controls (mouse, camera, repairs, key
## rebinding), Audio and Gameplay. Every change goes through Config.set_value(), which applies it
## at once and saves it. Changing the language rebuilds the screen in the new language.

signal closed

const TABS: Array[String] = ["video", "controls", "audio", "gameplay"]
const TAB_TITLES := {"video": "Video", "controls": "Controls", "audio": "Audio", "gameplay": "Gameplay"}
const FPS_CAPS: Array[int] = [0, 30, 60, 75, 120, 144, 165, 240]
const RENDER_SCALES := [[1.0, "100% (native)"], [0.85, "85%"], [0.77, "77% (FSR ultra quality)"],
	[0.67, "67% (FSR quality)"], [0.59, "59% (FSR balanced)"], [0.5, "50% (FSR performance)"]]
const VOLUMES := [["volume_master", "Master volume"], ["volume_music", "Music"], ["volume_sfx", "Sound effects"],
	["volume_ui", "Interface"], ["volume_ambience", "Ambience"]]
const CONTROL_WIDTH := 340
const CONFLICT_COLOR := Color(1, 0.55, 0.5)

## Opened from the pause menu: dims the game behind it, and says a new name waits for the next join.
var in_game := false

var _lists: Dictionary = {}  # tab -> VBoxContainer
var _key_rows: Dictionary = {}  # action -> {"button": Button, "note": Label}
var _capturing := StringName()
var _resolution_option: OptionButton
var _render_scale_option: OptionButton
var _restart_note: Label
var _rebuild_pending := false

@onready var tabs: TabContainer = %Tabs


func _ready() -> void:
	(%Dim as Control).visible = in_game
	(%BackButton as Button).pressed.connect(_close)
	(%ResetButton as Button).pressed.connect(_reset_tab)
	Config.changed.connect(_on_config_changed)
	_build()
	tabs.get_tab_bar().grab_focus()
	Ui.play("ui_open")


func _close() -> void:
	_stop_capture()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close()
		accept_event()


func _reset_tab() -> void:
	Config.reset_section(TABS[tabs.current_tab])
	_rebuild_soon()


func _on_config_changed(key: String) -> void:
	match key:
		"language":
			_rebuild_soon()
		"window_mode":
			if is_instance_valid(_resolution_option):
				_resolution_option.disabled = Config.window_mode != Config.WindowMode.WINDOWED
		"renderer":
			_update_restart_note()
		"bindings":
			_refresh_keys()


func _rebuild_soon() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		_build.call_deferred()


func _build() -> void:
	_rebuild_pending = false
	var keep := maxi(tabs.current_tab, 0)
	for child in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	_key_rows.clear()
	(%ResetButton as Button).text = tr("Reset this tab")
	(%BackButton as Button).text = tr("Done")
	for tab in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab.capitalize()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_right", 16)
		scroll.add_child(margin)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		margin.add_child(list)
		tabs.add_child(scroll)
		tabs.set_tab_title(tabs.get_tab_count() - 1, tr(TAB_TITLES[tab]))
		_lists[tab] = list
	_build_video()
	_build_controls()
	_build_audio()
	_build_gameplay()
	tabs.current_tab = keep


# --- The tabs ------------------------------------------------------------------

func _build_video() -> void:
	_header("video", tr("Display"))
	_option("video", tr("Window mode"), "window_mode", [[Config.WindowMode.WINDOWED, tr("Windowed")],
		[Config.WindowMode.FULLSCREEN, tr("Fullscreen (borderless)")],
		[Config.WindowMode.EXCLUSIVE, tr("Fullscreen (exclusive)")]])
	var sizes := []
	for size in Config.resolutions():
		sizes.append([size, "%d × %d" % [size.x, size.y]])
	_resolution_option = _option("video", tr("Window size"), "resolution", sizes)
	_resolution_option.disabled = Config.window_mode != Config.WindowMode.WINDOWED
	_toggle("video", tr("VSync (no tearing)"), "vsync")
	var caps := []
	for cap in FPS_CAPS:
		caps.append([cap, tr("Unlimited") if cap == 0 else tr("%d FPS") % cap])
	_option("video", tr("Frame rate limit"), "max_fps", caps)
	_header("video", tr("Quality"))
	var scales := []
	for entry: Array in RENDER_SCALES:
		scales.append([entry[0], tr(entry[1])])
	_render_scale_option = _option("video", tr("3D resolution"), "render_scale", scales)
	_option("video", tr("Shadows"), "shadows", [[Config.Shadows.LOW, tr("Low")], [Config.Shadows.MEDIUM, tr("Medium")],
		[Config.Shadows.HIGH, tr("High")]])
	_toggle("video", tr("Ambient occlusion (SSAO)"), "ssao")
	_toggle("video", tr("Glow"), "glow")
	_option("video", tr("Renderer"), "renderer", [["forward_plus", tr("Forward+ (best looking)")],
		["gl_compatibility", tr("Compatibility (older graphics cards)")]])
	_restart_note = _note("video", "")
	_update_restart_note()


func _update_restart_note() -> void:
	if not is_instance_valid(_restart_note):
		return
	var pending := Config.renderer != Config.running_renderer()
	_restart_note.text = tr("Restart the game to switch renderers.") if pending else \
		(tr("Compatibility runs on older graphics cards; 3D resolution then scales without FSR.")
		if Config.running_renderer() == "gl_compatibility" else "")
	_restart_note.modulate = Color(1, 0.85, 0.5) if pending else Color.WHITE


func _build_controls() -> void:
	_header("controls", tr("Mouse"))
	var times := func(v: float) -> String: return "%.2f×" % v
	_slider("controls", tr("Mouse sensitivity (first person)"), "sensitivity_fp", 0.1, 3.0, 0.05, times)
	_slider("controls", tr("Mouse sensitivity (third person, rats)"), "sensitivity_tp", 0.1, 3.0, 0.05, times)
	_toggle("controls", tr("Invert mouse Y"), "invert_y")
	_header("controls", tr("Camera"))
	_slider("controls", tr("Field of view"), "fov", 60.0, 110.0, 1.0, func(v: float) -> String: return "%d°" % roundi(v))
	_toggle("controls", tr("Head bob"), "head_bob")
	_toggle("controls", tr("Camera shake"), "camera_shake")
	_header("controls", tr("Repairs"))
	_toggle("controls", tr("Hold to repair instead of playing the minigames"), "minigame_repairs", true)
	_note("controls", tr("Minigames repair more (+50) than holding the interact key (+35), but holding needs no mouse skills."))
	_header("controls", tr("Keys"))
	_note("controls", tr("Click a key, then press the new key or mouse button. Esc cancels. Esc itself always opens the menu."))
	for action in Keys.REBINDABLE:
		_key_row(action)
	_refresh_keys()


func _build_audio() -> void:
	_header("audio", tr("Volume"))
	for entry: Array in VOLUMES:
		_slider("audio", tr(entry[1]), entry[0], 0.0, 1.0, 0.01, func(v: float) -> String: return "%d%%" % roundi(v * 100.0))


func _build_gameplay() -> void:
	_header("gameplay", tr("You"))
	var name_edit := LineEdit.new()
	name_edit.text = Config.player_name
	name_edit.max_length = JoinRules.MAX_NAME_LENGTH
	name_edit.placeholder_text = tr("Your name")
	var commit := func(_t: String = "") -> void:
		if name_edit.text.strip_edges() != "" and name_edit.text != Config.player_name:
			Config.set_value("player_name", name_edit.text)
			name_edit.text = Config.player_name
	name_edit.text_submitted.connect(commit)
	name_edit.focus_exited.connect(commit)
	_row("gameplay", tr("Name"), name_edit)
	if in_game:
		_note("gameplay", tr("A new name is used from the next server you join."))
	var languages := []
	for code: String in Config.LANGUAGES:
		languages.append([code, tr(Config.LANGUAGES[code]) if code == "" else Config.LANGUAGES[code]])
	_option("gameplay", tr("Language"), "language", languages)
	_header("gameplay", tr("Interface"))
	_toggle("gameplay", tr("Hide rude words in the chat"), "chat_filter")
	_toggle("gameplay", tr("Show FPS and ping"), "show_fps")
	_toggle("gameplay", tr("Show the minimap"), "show_minimap")
	_toggle("gameplay", tr("Minimap turns with you"), "minimap_rotate")
	var hints := Button.new()
	hints.text = tr("Show them again")
	hints.pressed.connect(func() -> void:
		Config.reset_hints()
		hints.text = tr("Done! They come back as you play")
		hints.disabled = true)
	_row("gameplay", tr("First-time hints"), hints)


# --- Key rebinding -------------------------------------------------------------

func _key_row(action: StringName) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(200, 0)
	button.pressed.connect(_start_capture.bind(action))
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.modulate = CONFLICT_COLOR
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var row := _row("controls", tr(Keys.ACTION_NAMES.get(action, String(action))), button)
	row.add_child(note)
	row.move_child(note, 1)
	_key_rows[action] = {"button": button, "note": note}


func _refresh_keys() -> void:
	var bindings := Config.all_bindings()
	for action: StringName in _key_rows:
		var row: Dictionary = _key_rows[action]
		var button: Button = row["button"]
		if action != _capturing:
			button.text = Keys.label(action) if bindings[action] != "" else tr("(none)")
		var names: Array[String] = []
		for other in Keys.conflicts(action, bindings[action], bindings):
			names.append(tr(Keys.ACTION_NAMES.get(other, String(other))))
		(row["note"] as Label).text = (tr("Also: %s") % ", ".join(names)) if not names.is_empty() else ""


func _start_capture(action: StringName) -> void:
	_stop_capture()
	_capturing = action
	(_key_rows[action]["button"] as Button).text = tr("Press a key...")


func _stop_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if key != null and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_stop_capture()
			return
		var action := _capturing
		_capturing = &""
		Config.set_binding(action, key)
	elif mouse != null and mouse.pressed:
		get_viewport().set_input_as_handled()
		var action := _capturing
		_capturing = &""
		Config.set_binding(action, mouse)


# --- Row builders --------------------------------------------------------------

func _row(tab: String, text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(label)
	if control is OptionButton or not control is Button:  # (key buttons and toggles keep their own size)
		control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, CONTROL_WIDTH)
	row.add_child(control)
	(_lists[tab] as VBoxContainer).add_child(row)
	return row


func _header(tab: String, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SubheaderLabel"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if (_lists[tab] as VBoxContainer).get_child_count() > 0:
		label.custom_minimum_size = Vector2(0, 40)
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	(_lists[tab] as VBoxContainer).add_child(label)


func _note(tab: String, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	(_lists[tab] as VBoxContainer).add_child(label)
	return label


## `items`: [[value, shown text], …].
func _option(tab: String, text: String, key: String, items: Array) -> OptionButton:
	var option := OptionButton.new()
	option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	option.fit_to_longest_item = false  # every drop-down as wide as the others
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var current: Variant = Config.get(key)
	for i in items.size():
		option.add_item(str(items[i][1]), i)
		option.set_item_metadata(i, items[i][0])
		var value: Variant = items[i][0]
		var same: bool = is_equal_approx(value, current) if value is float and current is float else value == current
		if same:
			option.select(i)
	option.item_selected.connect(func(i: int) -> void: Config.set_value(key, option.get_item_metadata(i)))
	_row(tab, text, option)
	return option


## A CheckButton bound to a bool setting (`inverted`: on means the setting is false).
func _toggle(tab: String, text: String, key: String, inverted: bool = false) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.button_pressed = (Config.get(key) as bool) != inverted
	toggle.toggled.connect(func(on: bool) -> void: Config.set_value(key, on != inverted))
	toggle.custom_minimum_size = Vector2(0, 0)
	var row := _row(tab, text, toggle)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.get_child(0).mouse_filter = Control.MOUSE_FILTER_STOP
	(row.get_child(0) as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			toggle.button_pressed = not toggle.button_pressed)  # clicking the label flips it too
	return toggle


func _slider(tab: String, text: String, key: String, low: float, high: float, step: float,
		shown: Callable) -> HSlider:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.set_value_no_signal(Config.get(key))
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_label.text = shown.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = shown.call(v)
		Config.set_value(key, v))
	box.add_child(slider)
	box.add_child(value_label)
	_row(tab, text, box)
	return slider
