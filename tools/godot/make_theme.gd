extends SceneTree
## Builds the UI theme, client/ui/theme.tres (M8), from code: the fonts, the palette colours
## (tools/art/palette.py) and chunky cartoon widgets (thick dark outlines, a deeper bottom edge that
## flattens when pressed, a light-blue ring around whatever has the keyboard focus).
## project.godot makes it the project theme, so every Control uses it unless it overrides something.
##   godot --headless -s tools/godot/make_theme.gd    (after `godot --headless --import` for the fonts)
## Type variations (set a Control's theme_type_variation): AccentButton (yellow, the main action),
## DangerButton (red), FlatButton (list rows), ChoiceButton (a toggle that turns yellow when chosen), TitleLabel, HeaderLabel, SubheaderLabel, MutedLabel,
## HudLabel (outlined, over the 3D view), CardPanel, HudPanel (see-through), DimPanel (modal backdrop).

const OUT := "res://client/ui/theme.tres"
const DISPLAY_FONT := "res://assets/fonts/LuckiestGuy-Regular.ttf"
const BODY_FONT := "res://assets/fonts/Fredoka.ttf"

# Palette swatches (tools/art/palette.py) plus a few darker UI shades.
const INK := Color("1b1b1f")
const NAVY := Color("1f2a44")
const NAVY_LIGHT := Color("2a3858")
const NAVY_DEEP := Color("141b2d")
const STEEL := Color("5b6b78")
const STEEL_LIGHT := Color("6f8090")
const STEEL_DARK := Color("3d4a55")
const YELLOW := Color("ffc93c")
const YELLOW_LIGHT := Color("ffd76a")
const YELLOW_DARK := Color("d9a21b")
const RED := Color("e84a5f")
const RED_LIGHT := Color("ef6c7e")
const RED_DARK := Color("a8303f")
const BLUE := Color("3f7cc0")
const SKY := Color("7fb7e6")
const OFF_WHITE := Color("e8e6df")
const GREY := Color("a3a6ad")
const GREY_DARK := Color("74777f")


func _init() -> void:
	var theme := Theme.new()
	var display := load(DISPLAY_FONT) as FontFile
	var body_file := load(BODY_FONT) as FontFile
	if display == null or body_file == null:
		push_error("make_theme: fonts missing, run `godot --headless --import` first")
		quit(1)
		return
	var body := _weight(body_file, 500)
	var bold := _weight(body_file, 640)
	theme.default_font = body
	theme.default_font_size = 18

	_buttons(theme, bold)
	_labels(theme, display, bold)
	_panels(theme)
	_fields(theme, bold)
	_lists(theme, bold)
	_tabs(theme, bold)
	_misc(theme, body, bold)

	var err := ResourceSaver.save(theme, OUT)
	print("make_theme: %s -> %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


## Fredoka is a variable font (weights 300 to 700, default 300). The axis must be given by its
## numeric OpenType tag: the text name "wght" is silently ignored.
func _weight(file: FontFile, weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = file
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return font


## A rounded box with a dark outline; `bottom` is the thicker bottom edge (the button's depth).
func _box(bg: Color, border := INK, width := 3, radius := 14, bottom := -1, margin := Vector4(18, 9, 18, 9)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.border_width_bottom = width if bottom < 0 else bottom
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	box.anti_aliasing = true
	return box


func _focus_ring(radius := 16) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = SKY
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(radius)
	ring.set_expand_margin_all(4)
	return ring


## normal / hover / pressed / disabled / focus for one button colour scheme.
func _button_type(theme: Theme, type: String, bg: Color, hover: Color, pressed: Color, text: Color) -> void:
	theme.set_stylebox("normal", type, _box(bg, INK, 3, 14, 7))
	theme.set_stylebox("hover", type, _box(hover, INK, 3, 14, 7))
	theme.set_stylebox("hover_pressed", type, _box(pressed, INK, 3, 14, 4, Vector4(18, 12, 18, 9)))
	theme.set_stylebox("pressed", type, _box(pressed, INK, 3, 14, 4, Vector4(18, 12, 18, 9)))
	theme.set_stylebox("disabled", type, _box(Color("3a4048"), Color("2a2d33"), 3, 14, 7))
	theme.set_stylebox("focus", type, _focus_ring())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, text)
	theme.set_color("font_disabled_color", type, GREY_DARK)
	theme.set_color("icon_normal_color", type, text)
	theme.set_color("icon_hover_color", type, text)
	theme.set_color("icon_pressed_color", type, text)
	theme.set_color("icon_focus_color", type, text)


func _buttons(theme: Theme, bold: Font) -> void:
	_button_type(theme, "Button", STEEL, STEEL_LIGHT, STEEL_DARK, Color.WHITE)
	theme.set_font("font", "Button", bold)
	theme.set_font_size("font_size", "Button", 20)
	theme.set_constant("h_separation", "Button", 10)
	theme.set_constant("icon_max_width", "Button", 28)
	for variation: Array in [["AccentButton", YELLOW, YELLOW_LIGHT, YELLOW_DARK, INK],
			["DangerButton", RED, RED_LIGHT, RED_DARK, Color.WHITE]]:
		theme.set_type_variation(variation[0], "Button")
		_button_type(theme, variation[0], variation[1], variation[2], variation[3], variation[4])
	# Choices (a ButtonGroup of toggles): the chosen one is yellow.
	theme.set_type_variation("ChoiceButton", "Button")
	_button_type(theme, "ChoiceButton", STEEL, STEEL_LIGHT, YELLOW, Color.WHITE)
	theme.set_stylebox("hover_pressed", "ChoiceButton", _box(YELLOW_LIGHT, INK, 3, 14, 4, Vector4(18, 12, 18, 9)))
	theme.set_color("font_pressed_color", "ChoiceButton", INK)
	theme.set_color("font_hover_pressed_color", "ChoiceButton", INK)
	# List rows: flat until hovered.
	theme.set_type_variation("FlatButton", "Button")
	var flat := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0, Vector4(10, 6, 10, 6))
	theme.set_stylebox("normal", "FlatButton", flat)
	theme.set_stylebox("hover", "FlatButton", _box(NAVY_LIGHT, NAVY_LIGHT, 0, 10, 0, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("pressed", "FlatButton", _box(BLUE, BLUE, 0, 10, 0, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("hover_pressed", "FlatButton", _box(BLUE, BLUE, 0, 10, 0, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("disabled", "FlatButton", flat)
	theme.set_stylebox("focus", "FlatButton", _focus_ring(12))
	theme.set_font_size("font_size", "FlatButton", 18)
	# Option buttons and toggles share the button look.
	_button_type(theme, "OptionButton", STEEL, STEEL_LIGHT, STEEL_DARK, Color.WHITE)
	theme.set_font("font", "OptionButton", bold)
	theme.set_font_size("font_size", "OptionButton", 18)
	for type in ["CheckBox", "CheckButton"]:
		var row := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0, Vector4(6, 4, 6, 4))
		theme.set_stylebox("normal", type, row)
		theme.set_stylebox("pressed", type, row)
		theme.set_stylebox("hover", type, _box(NAVY_LIGHT, NAVY_LIGHT, 0, 10, 0, Vector4(6, 4, 6, 4)))
		theme.set_stylebox("hover_pressed", type, _box(NAVY_LIGHT, NAVY_LIGHT, 0, 10, 0, Vector4(6, 4, 6, 4)))
		theme.set_stylebox("focus", type, _focus_ring(12))
		theme.set_color("font_color", type, OFF_WHITE)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_hover_pressed_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, Color.WHITE)
	# Toggle switches you can read at a glance: a yellow track with the knob on the right when on.
	theme.set_icon("checked", "CheckButton", _toggle_icon(true, false))
	theme.set_icon("unchecked", "CheckButton", _toggle_icon(false, false))
	theme.set_icon("checked_disabled", "CheckButton", _toggle_icon(true, true))
	theme.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(false, true))
	theme.set_icon("checked_mirrored", "CheckButton", _toggle_icon(true, false))
	theme.set_icon("unchecked_mirrored", "CheckButton", _toggle_icon(false, false))


## A 52 × 28 switch, drawn at 4× and scaled down for smooth edges.
func _toggle_icon(on: bool, disabled: bool) -> ImageTexture:
	const S := 4
	var w := 52 * S
	var h := 28 * S
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var track := (YELLOW if on else NAVY_DEEP)
	var knob := Color.WHITE if on else GREY
	if disabled:
		track = track.darkened(0.45)
		knob = knob.darkened(0.45)
	_capsule(img, Rect2(0, 0, w, h), INK)
	_capsule(img, Rect2(3 * S, 3 * S, w - 6 * S, h - 6 * S), track)
	var r := (h - 10 * S) / 2.0
	var cx := w - 5 * S - r if on else 5 * S + r
	_disc(img, Vector2(cx, h / 2.0), r + 1.5 * S, INK)
	_disc(img, Vector2(cx, h / 2.0), r, knob)
	img.resize(52, 28, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _capsule(img: Image, rect: Rect2, color: Color) -> void:
	var r := rect.size.y / 2.0
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			var cx := clampf(x + 0.5, rect.position.x + r, rect.end.x - r)
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, rect.position.y + r)) <= r:
				img.set_pixel(x, y, color)


func _disc(img: Image, center: Vector2, r: float, color: Color) -> void:
	for y in range(int(center.y - r), int(center.y + r) + 1):
		for x in range(int(center.x - r), int(center.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() \
					and Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				img.set_pixel(x, y, color)


func _labels(theme: Theme, display: Font, bold: Font) -> void:
	theme.set_color("font_color", "Label", OFF_WHITE)
	theme.set_color("font_outline_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	for variation: Array in [
			# name, font, size, colour, outline
			["TitleLabel", display, 72, YELLOW, 14],
			["HeaderLabel", display, 34, OFF_WHITE, 9],
			["SubheaderLabel", bold, 22, YELLOW, 0],
			["MutedLabel", null, 15, GREY, 0],
			["HudLabel", null, 18, Color.WHITE, 6]]:
		theme.set_type_variation(variation[0], "Label")
		if variation[1] != null:
			theme.set_font("font", variation[0], variation[1])
		theme.set_font_size("font_size", variation[0], variation[2])
		theme.set_color("font_color", variation[0], variation[3])
		theme.set_constant("outline_size", variation[0], variation[4])
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 6)
	theme.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.45))


func _panels(theme: Theme) -> void:
	var panel := _box(Color(NAVY, 0.96), INK, 3, 18, 3, Vector4(22, 18, 22, 18))
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 10
	panel.shadow_offset = Vector2(0, 5)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _box(NAVY_LIGHT, NAVY_DEEP, 2, 14, 4, Vector4(14, 12, 14, 12)))
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", _box(Color(0.03, 0.04, 0.08, 0.62), Color(0, 0, 0, 0), 0, 12, 0,
		Vector4(14, 10, 14, 10)))
	theme.set_type_variation("DimPanel", "Panel")
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0.02, 0.03, 0.06, 0.6)
	theme.set_stylebox("panel", "DimPanel", dim)


func _fields(theme: Theme, bold: Font) -> void:
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, _box(NAVY_DEEP, STEEL_DARK, 2, 10, 2, Vector4(12, 8, 12, 8)))
		theme.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), SKY, 3, 10, 3, Vector4(12, 8, 12, 8)))
		theme.set_stylebox("read_only", type, _box(Color(NAVY_DEEP, 0.6), STEEL_DARK, 2, 10, 2, Vector4(12, 8, 12, 8)))
		theme.set_color("font_color", type, Color.WHITE)
		theme.set_color("font_placeholder_color", type, GREY_DARK)
		theme.set_color("caret_color", type, YELLOW)
		theme.set_color("selection_color", type, Color(BLUE, 0.7))
		theme.set_font_size("font_size", type, 18)
	# Sliders: a dark track filled in yellow.
	var track := _box(NAVY_DEEP, INK, 2, 6, 2, Vector4(0, 5, 0, 5))
	var fill := _box(YELLOW, INK, 2, 6, 2, Vector4(0, 5, 0, 5))
	var fill_hot := _box(YELLOW_LIGHT, INK, 2, 6, 2, Vector4(0, 5, 0, 5))
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_hot)
	theme.set_stylebox("focus", "HSlider", _focus_ring(10))
	# Progress bars (the HUD overrides the fill colour where it means something).
	theme.set_stylebox("background", "ProgressBar", _box(NAVY_DEEP, INK, 2, 7, 2, Vector4(0, 0, 0, 0)))
	theme.set_stylebox("fill", "ProgressBar", _box(YELLOW, INK, 2, 7, 2, Vector4(0, 0, 0, 0)))
	theme.set_color("font_color", "ProgressBar", Color.WHITE)
	theme.set_font("font", "ProgressBar", bold)


func _lists(theme: Theme, bold: Font) -> void:
	theme.set_stylebox("panel", "ItemList", _box(NAVY_DEEP, STEEL_DARK, 2, 10, 2, Vector4(6, 6, 6, 6)))
	theme.set_stylebox("selected", "ItemList", _box(BLUE, BLUE, 0, 8, 0))
	theme.set_stylebox("selected_focus", "ItemList", _box(BLUE, SKY, 2, 8, 2))
	theme.set_stylebox("hovered", "ItemList", _box(NAVY_LIGHT, NAVY_LIGHT, 0, 8, 0))
	theme.set_stylebox("focus", "ItemList", _focus_ring(12))
	theme.set_color("font_color", "ItemList", OFF_WHITE)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	# Drop-down menus.
	theme.set_stylebox("panel", "PopupMenu", _box(NAVY, INK, 3, 12, 3, Vector4(6, 6, 6, 6)))
	theme.set_stylebox("hover", "PopupMenu", _box(BLUE, BLUE, 0, 8, 0, Vector4(8, 4, 8, 4)))
	theme.set_color("font_color", "PopupMenu", OFF_WHITE)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_font("font", "PopupMenu", bold)
	theme.set_font_size("font_size", "PopupMenu", 18)
	theme.set_constant("v_separation", "PopupMenu", 8)
	# Scroll bars.
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _box(Color(NAVY_DEEP, 0.8), Color(0, 0, 0, 0), 0, 6, 0, Vector4(4, 4, 4, 4)))
		theme.set_stylebox("grabber", type, _box(STEEL, STEEL, 0, 6, 0, Vector4(4, 4, 4, 4)))
		theme.set_stylebox("grabber_highlight", type, _box(STEEL_LIGHT, STEEL_LIGHT, 0, 6, 0, Vector4(4, 4, 4, 4)))
		theme.set_stylebox("grabber_pressed", type, _box(YELLOW, YELLOW, 0, 6, 0, Vector4(4, 4, 4, 4)))


func _tabs(theme: Theme, bold: Font) -> void:
	var margin := Vector4(18, 8, 18, 8)
	var selected := _box(NAVY_LIGHT, INK, 3, 12, 0, margin)
	selected.corner_radius_bottom_left = 0
	selected.corner_radius_bottom_right = 0
	var unselected := _box(NAVY_DEEP, INK, 3, 12, 0, margin)
	unselected.corner_radius_bottom_left = 0
	unselected.corner_radius_bottom_right = 0
	var hovered := unselected.duplicate() as StyleBoxFlat
	hovered.bg_color = Color("33456b")
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_unselected", type, unselected)
		theme.set_stylebox("tab_hovered", type, hovered)
		theme.set_stylebox("tab_focus", type, _focus_ring(12))
		theme.set_font("font", type, bold)
		theme.set_font_size("font_size", type, 20)
		theme.set_color("font_selected_color", type, YELLOW)
		theme.set_color("font_unselected_color", type, GREY)
		theme.set_color("font_hovered_color", type, Color.WHITE)
	var tab_panel := _box(NAVY_LIGHT, INK, 3, 14, 3, Vector4(18, 16, 18, 16))
	tab_panel.corner_radius_top_left = 0
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_constant("side_margin", "TabContainer", 0)


func _misc(theme: Theme, body: Font, bold: Font) -> void:
	theme.set_stylebox("panel", "TooltipPanel", _box(NAVY_DEEP, YELLOW, 2, 8, 2, Vector4(10, 6, 10, 6)))
	theme.set_color("font_color", "TooltipLabel", OFF_WHITE)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_color("default_color", "RichTextLabel", OFF_WHITE)
	theme.set_font("normal_font", "RichTextLabel", body)
	theme.set_font("bold_font", "RichTextLabel", bold)
	theme.set_color("font_outline_color", "RichTextLabel", INK)
	var line := StyleBoxLine.new()
	line.color = STEEL_DARK
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 12)
	var vline := StyleBoxLine.new()
	vline.color = STEEL_DARK
	vline.thickness = 2
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
