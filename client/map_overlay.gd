class_name MapOverlay
extends CanvasLayer
## The in-game map (ClientOnly): a minimap in the top right corner with the name of the room the player
## is in and the map key under it, and the full map of the level on that key (M; press it again to
## close). Both are MapViews of the level's plan (MapInfo → LevelMap); a level without a plan has neither.
## The minimap follows the player and turns with the camera (Settings → Gameplay: hide it, or keep north
## up). It steps aside while the full map is open, at the CCTV chair, in the lobby (whose panel takes that
## corner) and after the match. The full map doesn't pause anything or free the mouse: players keep
## moving while they read it. Frames, keycaps and cards use the UI theme's look.

const MINIMAP_SIZE := 190.0
const MINIMAP_PPM := 3.2  ## pixels per metre: about 60 m across
const MARGIN := 12.0
const ROOM_LABEL_H := 26.0
const KEY_HINT_H := 26.0
const LEGEND_W := 250.0
const ROOM_CHECK_MS := 200
const STEEL := Color("5b6b78")  ## the theme's plain button colour (keycaps)

var _plan: LevelMap
var _minimap_frame: PanelContainer
var _minimap: MapView
var _room_label: Label
var _key_hint: HBoxContainer
var _key_cap: Label
var _key_text: Label
var _full: Control
var _full_map: MapView
var _title: Label
var _close_cap: Label
var _close_text: Label
var _legend: VBoxContainer
var _next_room_check_ms := 0


## Where the event feed starts (top right), so it sits under the minimap.
static func feed_top() -> float:
	return MARGIN + MINIMAP_SIZE + ROOM_LABEL_H + KEY_HINT_H + 8.0 if Config.show_minimap else 30.0


func _ready() -> void:
	layer = 4
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_unhandled_input(false)
		return
	_plan = MapInfo.plan_in(get_tree())
	_build_minimap()
	_build_full_map()
	Config.changed.connect(func(key: String) -> void:
		if key == "minimap_rotate":
			_minimap.turn_with_view = Config.minimap_rotate)
	Events.match_state_changed.connect(func(state: int) -> void:
		if state == MatchManager.State.POST_MATCH:
			set_open(false)
		elif is_open():
			_build_legend())  # (the roles changed)
	get_viewport().size_changed.connect(_layout_full)


func is_open() -> bool:
	return _full != null and _full.visible


## Opens or closes the full map.
func set_open(open: bool) -> void:
	if _full == null or open == _full.visible or (open and _plan == null):
		return
	_full.visible = open
	if open:
		_title.text = tr(_plan.title)
		_close_cap.text = Keys.label(&"map")
		_close_text.text = tr("Close")
		_layout_full()
		_build_legend()
		_next_room_check_ms = 0
		Config.mark_hint_seen("map")  # (they found it: no need for the tip any more)
	Ui.play("ui_open" if open else "ui_close")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"map") or PlayerInput.blocked:
		return
	var pause := Session.current.client_only.get_node_or_null("PauseMenu") as PauseMenu
	if pause != null and pause.is_open:
		return
	set_open(not is_open())
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var wanted := _minimap_wanted()
	_minimap_frame.visible = wanted
	_room_label.visible = wanted
	_key_hint.visible = wanted
	if (wanted or is_open()) and Time.get_ticks_msec() >= _next_room_check_ms:
		_next_room_check_ms = Time.get_ticks_msec() + ROOM_CHECK_MS
		_update_room()


func _minimap_wanted() -> bool:
	if not Config.show_minimap or _plan == null or is_open():
		return false
	var session := Session.current
	var mm := session.match_manager
	if mm.state in [MatchManager.State.LOBBY, MatchManager.State.POST_MATCH]:
		return false
	var body := session.get_body(session.local_peer_id)
	if body != null:
		return body.seated_console() == null
	return mm.in_match()  # a ghost or a spectator, flying around


## The room the player is in: its name under the minimap, and drawn brighter on both maps.
func _update_room() -> void:
	var session := Session.current
	var body := session.get_body(session.local_peer_id)
	var index := _plan.room_at(_minimap.viewer()[0])
	if body != null and VentVolume.contains(body):
		_room_label.text = tr("In the vents")
		index = -1
	else:
		_room_label.text = tr(_plan.room_names[index]) if index != -1 else ""
	_minimap.highlight = index
	_full_map.highlight = index
	# (set here, so they follow a rebinding and the language)
	_key_cap.text = Keys.label(&"map")
	_key_text.text = tr("Map")


# --- Building ------------------------------------------------------------------------------------

## A box in the theme's style: ink outline, rounded, a deeper bottom edge.
static func _theme_box(bg: Color, border: int, bottom: int, radius: int, margin: Vector4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = MapView.INK
	box.set_border_width_all(border)
	box.border_width_bottom = bottom
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	box.anti_aliasing = true
	return box


func _build_minimap() -> void:
	_minimap_frame = PanelContainer.new()
	var style := _theme_box(MapView.BACKGROUND, 3, 6, 12, Vector4(7, 7, 7, 9))
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	_minimap_frame.add_theme_stylebox_override("panel", style)
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_align(_minimap_frame, MARGIN, MINIMAP_SIZE)
	add_child(_minimap_frame)
	_minimap = MapView.new()
	_minimap.plan = _plan
	_minimap.follow = true
	_minimap.compact = true
	_minimap.pixels_per_m = MINIMAP_PPM
	_minimap.turn_with_view = Config.minimap_rotate
	_minimap.clip_contents = true
	_minimap_frame.add_child(_minimap)
	# The room's name in the title font, and the map key as a keycap.
	_room_label = Label.new()
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_override("font", _room_label.get_theme_font("font", &"HeaderLabel"))
	_room_label.add_theme_font_size_override("font_size", 18)
	_room_label.add_theme_color_override("font_color", MapView.OFF_WHITE)
	_room_label.add_theme_constant_override("outline_size", 7)
	_room_label.add_theme_color_override("font_outline_color", MapView.INK)
	_room_label.add_theme_constant_override("shadow_offset_y", 3)
	_room_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_room_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_align(_room_label, MARGIN + MINIMAP_SIZE + 4.0, ROOM_LABEL_H)
	add_child(_room_label)
	var hint := _key_hint_row()
	_key_hint = hint[0] as HBoxContainer
	_key_cap = hint[1]
	_key_text = hint[2]
	_key_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_right_align(_key_hint, MARGIN + MINIMAP_SIZE + 4.0 + ROOM_LABEL_H, KEY_HINT_H)
	add_child(_key_hint)


## [row, keycap label, text label]: a key drawn like a little theme button, then what it does.
func _key_hint_row() -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", _theme_box(STEEL, 2, 4, 6, Vector4(8, 0, 8, 2)))
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cap)
	var key := Label.new()
	key.add_theme_font_override("font", key.get_theme_font("font", &"Button"))
	key.add_theme_font_size_override("font_size", 14)
	key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cap.add_child(key)
	var text := Label.new()
	text.add_theme_font_override("font", text.get_theme_font("font", &"Button"))
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", MapView.OFF_WHITE)
	text.add_theme_constant_override("outline_size", 5)
	text.add_theme_color_override("font_outline_color", MapView.INK)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(text)
	return [row, key, text]


## Anchors `control` to the top right corner: MINIMAP_SIZE wide, `height` tall, `top` from the top.
func _right_align(control: Control, top: float, height: float) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.offset_left = -MARGIN - MINIMAP_SIZE
	control.offset_right = -MARGIN
	control.offset_top = top
	control.offset_bottom = top + height


func _build_full_map() -> void:
	_full = Control.new()
	_full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full.visible = false
	add_child(_full)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := _key_hint_row()
	_close_cap = close[1]
	_close_text = close[2]
	(close[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close[0])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var map_card := PanelContainer.new()
	map_card.theme_type_variation = &"CardPanel"
	map_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(map_card)
	_full_map = MapView.new()
	_full_map.plan = _plan
	map_card.add_child(_full_map)
	var legend_card := PanelContainer.new()
	legend_card.theme_type_variation = &"CardPanel"
	legend_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(legend_card)
	_legend = VBoxContainer.new()
	_legend.custom_minimum_size = Vector2(LEGEND_W, 0)
	_legend.add_theme_constant_override("separation", 6)
	legend_card.add_child(_legend)


## Sizes the full map to the screen: as big as fits next to the legend, below the title.
func _layout_full() -> void:
	if _full_map == null or _plan == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var aspect := _plan.area.size.x / _plan.area.size.y
	var height := screen.y - 170.0
	var width := minf(height * aspect, screen.x - LEGEND_W - 150.0)
	_full_map.custom_minimum_size = Vector2(width, width / aspect)


## The key next to the full map, for what this player's map shows.
func _build_legend() -> void:
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = tr("Legend")
	heading.theme_type_variation = &"SubheaderLabel"
	heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_legend.add_child(heading)
	var session := Session.current
	var mm := session.match_manager
	var role := mm.local_role()
	if session.get_body(session.local_peer_id) != null:
		_legend_row(func(item: Control, at: Vector2) -> void:
			MapView.draw_arrow(item, at, Vector2.UP, Color.WHITE, 10.0), tr("You"))
	if mm.in_match() and mm.is_ghost(session.local_peer_id):
		_legend_row(_dot.bind(MapView.SUPERVISOR_COLOR, false), tr("Supervisors"))
		_legend_row(_dot.bind(MapView.RAT_COLOR, false), tr("Rats"))
	elif role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		var enemy := Role.Kind.RAT if role == Role.Kind.SUPERVISOR else Role.Kind.SUPERVISOR
		_legend_row(_dot.bind(MapView.team_color(role, 0), false), tr("Your team"))
		_legend_row(_dot.bind(MapView.team_color(enemy, 0), true), tr("Revealed enemies"))
	else:
		_legend_row(_dot.bind(Player.color_for_peer(3), false), tr("Players"))
	var bold := _legend.get_theme_font("font", &"Button")
	_legend_row(func(item: Control, at: Vector2) -> void:
		MapView.draw_badge(item, bold, at, "PMP", MapView.health_color(0.75)), tr("Machine (colour = health)"))
	_legend_row(func(item: Control, at: Vector2) -> void: MapView.draw_cage(item, at, 1.0), tr("Cage"))
	if _full_map.shows_pickups():
		_legend_row(func(item: Control, at: Vector2) -> void:
			MapView.draw_pickup(item, at + Vector2(-9, 0), "donut", 1.0)
			MapView.draw_pickup(item, at + Vector2(9, 0), "spare_keycard", 1.0), tr("Pickups"))
	_legend_row(func(item: Control, at: Vector2) -> void: MapView.draw_ladder(item, at, 1.3), tr("Ladder"))
	_legend_row(_line.bind(MapView.DOOR_COLOR), tr("Door"))
	_legend_row(_line.bind(MapView.KEYCARD_COLOR), tr("Keycard door"))
	if _full_map.shows_vents():
		_legend_row(_line.bind(MapView.VENT_COLOR), tr("Vents (rats only)"))


func _legend_row(painter: Callable, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(44, 26)
	icon.draw.connect(func() -> void: painter.call(icon, icon.size / 2.0))
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", 16)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_legend.add_child(row)


func _dot(item: Control, at: Vector2, color: Color, ring: bool) -> void:
	if ring:
		item.draw_arc(at, 11.0, 0.0, TAU, 24, color, 3.0, true)
	MapView.draw_dot(item, at, color, 6.5)


func _line(item: Control, at: Vector2, color: Color) -> void:
	item.draw_line(at - Vector2(15, 0), at + Vector2(15, 0), MapView.INK, 8.0, true)
	item.draw_line(at - Vector2(13, 0), at + Vector2(13, 0), color, 4.0, true)
