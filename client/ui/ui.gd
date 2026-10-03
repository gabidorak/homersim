extends CanvasLayer
## Client UI services that outlive scene changes (M8):
##   - every button plays the hover / click sounds (Sfx "ui_hover", "ui_click"; accent buttons
##     "ui_confirm"), sliders tick; a node with the meta `no_ui_sound` stays quiet
##   - the FPS and ping corner (Config.show_fps)
## Does nothing in a headless process.

const SLIDER_TICK_MS := 70

var _corner: Label
var _last_tick_ms := 0
var _corner_next_ms := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	layer = 100
	get_tree().node_added.connect(_on_node_added)
	_corner = Label.new()
	_corner.theme_type_variation = &"HudLabel"
	_corner.add_theme_font_size_override("font_size", 15)
	_corner.add_theme_constant_override("outline_size", 5)
	_corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_corner.offset_left = -220
	_corner.offset_right = -10
	_corner.offset_top = 4
	_corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corner.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_corner)


func _process(_delta: float) -> void:
	_corner.visible = Config.show_fps
	if not _corner.visible or Time.get_ticks_msec() < _corner_next_ms:
		return
	_corner_next_ms = Time.get_ticks_msec() + 250
	var text := tr("%d FPS") % Engine.get_frames_per_second()
	var ping := Net.ping_ms()
	if ping >= 0:
		text += "  ·  " + tr("%d ms") % ping
	_corner.text = text


func _exit_tree() -> void:
	Sfx.clear_cache()  # quitting from a menu: the cached UI sounds must not outlive the engine


## A little "BOT" tag in the theme's style (M10): yellow, ink outline with a deeper bottom edge, the
## bold body font. The lobby, the scoreboard and the post-match screen mark AI bots with it.
func bot_badge(font_size: int = 13) -> PanelContainer:
	var badge := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("ffc93c")
	box.border_color = Color("1b1b1f")
	box.set_border_width_all(2)
	box.border_width_bottom = 3
	box.set_corner_radius_all(6)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 0
	box.content_margin_bottom = 1
	box.anti_aliasing = true
	badge.add_theme_stylebox_override("panel", box)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = tr("BOT")
	label.add_theme_font_override("font", label.get_theme_font("font", &"Button"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("1b1b1f"))
	label.add_theme_constant_override("outline_size", 0)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	badge.add_child(label)
	return badge


## A UI sound (no position).
func play(sound: String) -> void:
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		Sfx.play(self, sound)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.mouse_entered.connect(_on_hover.bind(button))
		button.focus_entered.connect(_on_focus.bind(button))
		button.pressed.connect(_on_pressed.bind(button))
	elif node is Slider:
		(node as Slider).value_changed.connect(_on_slider.bind(node))


func _quiet(node: Node) -> bool:
	return node.has_meta(&"no_ui_sound") or not node.is_visible_in_tree()


func _on_hover(button: BaseButton) -> void:
	if not button.disabled and not _quiet(button):
		play("ui_hover")


func _on_focus(button: BaseButton) -> void:
	# Keyboard / gamepad focus moves only: a click focuses too, and already makes its own sound.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _quiet(button):
		play("ui_hover")


func _on_pressed(button: BaseButton) -> void:
	if _quiet(button):
		return
	play("ui_confirm" if button.theme_type_variation == &"AccentButton" else "ui_click")


func _on_slider(_value: float, slider: Slider) -> void:
	if _quiet(slider) or Time.get_ticks_msec() - _last_tick_ms < SLIDER_TICK_MS:
		return
	_last_tick_ms = Time.get_ticks_msec()
	play("tick")
