class_name HotbarView
extends Control
## The local player's inventory on the HUD, bottom centre, like most games' hotbars: one square per
## item with its icon (assets/ui/items, rendered from the models by tests/helpers/ItemIcons.tscn)
## and how many are left.
##   supervisor  [keycard]  [1 snap trap] [2 cheese lure] [3 donut]
##   rat         [stolen item]
## The numbered slots are the Hotbar's: the selected one is raised with a yellow ring, its key is a
## little keycap in the corner; each trap slot shows how many of that trap are left (red 0 when
## empty: the trap box or the cheese box in Storage refills them) and darkens during the cooldown; the donut slot is a faint outline until the player carries one. The
## slot on the left isn't selectable, its item works by itself: the keycard (dim and crossed out
## while a rat has it), a rat's stolen loot. Above, for a few seconds after the selection changes
## (or a donut lands in the hotbar), the item's name, how to use it and what it does.
## Reads only the local player's synced Inventory and its owner-side Hotbar and AbilityComponent.

const SLOT := 60.0
const GAP := 6.0
const SIDE_GAP := 18.0  ## between the side slot and the numbered ones
const RAISE := 5.0  ## the selected slot sits this much higher
const BOTTOM := 12.0  ## from the bottom of the screen
const ICON_PAD := 7.0
const CAPTION_S := 4.0
const CAPTION_LINE := 20.0  ## px between the caption's two lines
const CAPTION_FADE_S := 0.5
const ICONS := "res://assets/ui/items/%s.png"

# The UI theme's colours (tools/godot/make_theme.gd).
const INK := Color("1b1b1f")
const NAVY := Color("1f2a44")
const NAVY_LIGHT := Color("2a3858")
const STEEL := Color("5b6b78")
const YELLOW := Color("ffc93c")
const RED := Color("e84a5f")
const RED_LIGHT := Color("ef6c7e")
const OFF_WHITE := Color("e8e6df")

var player: Player
## How far above the view's top the caption's baseline sits (the HUD keeps the stamina bar and the
## statuses in between).
var caption_lift := 60.0

var _icons: Dictionary[StringName, Texture2D] = {}
var _slot_box: StyleBoxFlat
var _side_box: StyleBoxFlat
var _ring_box: StyleBoxFlat
var _cap_box: StyleBoxFlat
var _caption_name := ""
var _caption_hint := ""
var _caption_effect := ""
var _caption_until := 0.0
var _last_selected := -1
var _last_donuts := 0
var _last_player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item: StringName in [&"snap_trap", &"cheese_lure", &"donut", &"keycard"]:
		if ResourceLoader.exists(ICONS % item):
			_icons[item] = load(ICONS % item)
	_slot_box = _box(Color(NAVY, 0.88), INK, 3, 6, 12)
	_side_box = _box(Color(NAVY, 0.6), INK, 3, 6, 12)
	_ring_box = _box(Color.TRANSPARENT, YELLOW, 3, 3, 9)
	_ring_box.draw_center = false
	_cap_box = _box(STEEL, INK, 2, 3, 5)


## Something to show: a supervisor or a rat in a match (the HUD hides the view otherwise).
func wanted() -> bool:
	return is_instance_valid(player) and player.role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]


## The view's height on screen, from the bottom edge to the top of a raised slot.
static func height() -> float:
	return BOTTOM + SLOT + RAISE


func _process(_delta: float) -> void:
	if not wanted():
		_last_player = null
		return
	_watch()
	var width := _width()
	if not is_equal_approx(size.x, width):
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -width * 0.5
		offset_right = width * 0.5
		offset_top = -height()
		offset_bottom = -BOTTOM
	queue_redraw()


## Shows the caption when the selection changes or a donut lands in the hotbar.
func _watch() -> void:
	var selected := player.hotbar.selected
	var donuts := player.inventory.donuts
	if player != _last_player:
		_last_player = player
		_last_selected = selected
		_last_donuts = donuts
		_caption_until = 0.0
		return
	var slots := player.hotbar.slots()
	if selected != _last_selected and selected < slots.size():
		_show_caption(slots[selected])
	elif donuts > _last_donuts:
		_show_caption(Hotbar.DONUT)
	_last_selected = selected
	_last_donuts = donuts


func _show_caption(item: StringName) -> void:
	var interact := Keys.label(&"interact")
	if item == Hotbar.DONUT:
		_caption_name = tr("Donut")
		var slot := player.hotbar.slots().find(Hotbar.DONUT)
		if player.inventory.donuts <= 0:
			_caption_hint = tr("take one at the Break Room counter")
		elif player.hotbar.selected_item() == Hotbar.DONUT:
			_caption_hint = tr("%s to eat it") % interact
		else:
			_caption_hint = tr("%s, then %s to eat it") % [Keys.label(Hotbar.SLOT_ACTIONS[slot]), interact] \
				if slot < Hotbar.SLOT_ACTIONS.size() else ""
	else:
		var data := player.role_data.ability(item)
		_caption_name = tr(data.display_name) if data != null else String(item)
		_caption_hint = tr("none left: refill in Storage") if player.inventory.charges(item) <= 0 \
			else tr("hold %s, release to place") % Keys.label(&"secondary")
	_caption_effect = _effect_of(item)
	_caption_until = _now() + CAPTION_S


## What the item does, with the numbers from the data ("" if it has nothing to say).
func _effect_of(item: StringName) -> String:
	if item == Hotbar.DONUT:
		var tuning := player.inventory.tuning
		return tr("Eating it makes you %d%% faster for %d s") % [roundi((tuning.donut_speed - 1.0) * 100.0),
			roundi(tuning.donut_duration_s)]
	var data := player.role_data.ability(item)
	if data == null:
		return ""
	match data.status:
		StatusComponent.Status.STUNNED:
			return tr("Stuns a rat for %d s, and every supervisor hears the SNAP") % roundi(data.status_duration)
		StatusComponent.Status.REVEALED:
			return tr("A rat that touches it glows through walls for %d s") % roundi(data.status_duration)
	return ""


func _width() -> float:
	var count := player.hotbar.slots().size()
	return SLOT + (SIDE_GAP + count * SLOT + (count - 1) * GAP if count > 0 else 0.0)


func _draw() -> void:
	if not wanted():
		return
	var top := RAISE
	_draw_side_slot(Rect2(0, top, SLOT, SLOT))
	var slots := player.hotbar.slots()
	var x := SLOT + SIDE_GAP
	for i in slots.size():
		var chosen := i == player.hotbar.selected
		var rect := Rect2(x, top - (RAISE if chosen else 0.0), SLOT, SLOT)
		_draw_slot(rect, slots[i], i, chosen)
		x += SLOT + GAP
	_draw_caption()


## The keycard (supervisor) or the stolen item (rat): not selectable, a little see-through.
func _draw_side_slot(rect: Rect2) -> void:
	draw_style_box(_side_box, rect)
	var inv := player.inventory
	if player.role == Role.Kind.SUPERVISOR:
		_draw_icon(rect, &"keycard", 1.0 if inv.keycard else 0.45)
		if not inv.keycard:  # stolen: a red cross over it (the HUD's text says where the spare is)
			var a := rect.grow(-16.0)
			for line: Array in [[a.position, a.end], [Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y)]]:
				draw_line(line[0], line[1], INK, 7.0, true)
				draw_line(line[0], line[1], RED, 3.5, true)
	elif inv.stolen_item != &"":
		_draw_icon(rect, inv.stolen_item, 1.0)


func _draw_slot(rect: Rect2, item: StringName, index: int, chosen: bool) -> void:
	draw_style_box(_slot_box, rect)
	var inv := player.inventory
	if item == Hotbar.DONUT:
		_draw_icon(rect, item, 1.0 if inv.donuts > 0 else 0.18)
		if inv.donuts > 1:
			_draw_count(rect, str(inv.donuts), OFF_WHITE)
	else:
		var empty := inv.charges(item) <= 0
		_draw_icon(rect, item, 0.35 if empty else 1.0)
		var data := player.role_data.ability(item)
		var cooldown := player.abilities.cooldown_left(item)
		if data != null and cooldown > 0.0 and data.cooldown_s > 0.0:
			var inner := rect.grow(-3.0)
			var cover := inner.size.y * clampf(cooldown / data.cooldown_s, 0.0, 1.0)
			draw_rect(Rect2(inner.position, Vector2(inner.size.x, cover)), Color(0, 0, 0, 0.5))
		_draw_count(rect, str(inv.charges(item)), RED_LIGHT if empty else OFF_WHITE)
	if chosen:
		draw_style_box(_ring_box, rect.grow(-3.0))
	if index < Hotbar.SLOT_ACTIONS.size():
		_draw_keycap(rect.position + Vector2(5, 5), Keys.label(Hotbar.SLOT_ACTIONS[index]))


func _draw_icon(rect: Rect2, item: StringName, alpha: float) -> void:
	var texture: Texture2D = _icons.get(item)
	if texture != null:
		draw_texture_rect(texture, rect.grow(-ICON_PAD), false, Color(1, 1, 1, alpha))


## The count in the bottom right corner, in the title font with an ink outline.
func _draw_count(rect: Rect2, text: String, color: Color) -> void:
	var font := get_theme_font(&"font", &"HeaderLabel")
	var font_size := 24
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(rect.end.x - 8.0 - width, rect.end.y - 10.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, INK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A key drawn like a tiny theme button ("1"), its top left corner at `at`.
func _draw_keycap(at: Vector2, text: String) -> void:
	var font := get_theme_font(&"font", &"Button")
	var font_size := 12
	var width := maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0, 17.0)
	var cap := Rect2(at, Vector2(width, 18.0))
	draw_style_box(_cap_box, cap)
	draw_string(font, Vector2(cap.position.x, cap.position.y + 13.0), text, HORIZONTAL_ALIGNMENT_CENTER, width,
		font_size, Color.WHITE)


## "Snap trap · hold RMB, release to place" and, below it, what the item does: centred above the
## slots, fading out.
func _draw_caption() -> void:
	var left := _caption_until - _now()
	if left <= 0.0:
		return
	var alpha := clampf(left / CAPTION_FADE_S, 0.0, 1.0)
	var font := get_theme_font(&"font", &"Button")
	var font_size := 17
	var name_text := _caption_name
	var rest := "  ·  " + _caption_hint if _caption_hint != "" else ""
	var name_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var rest_w := font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2((size.x - name_w - rest_w) * 0.5, -caption_lift - (CAPTION_LINE if _caption_effect != "" else 0.0))
	var parts: Array = [[name_text, at, YELLOW, font_size], [rest, at + Vector2(name_w, 0), OFF_WHITE, font_size]]
	if _caption_effect != "":
		var effect_size := 15
		var effect_w := font.get_string_size(_caption_effect, HORIZONTAL_ALIGNMENT_LEFT, -1, effect_size).x
		parts.append([_caption_effect, Vector2((size.x - effect_w) * 0.5, -caption_lift), OFF_WHITE, effect_size])
	for part: Array in parts:
		draw_string_outline(font, part[1], part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, part[3], 6, Color(INK, alpha))
		draw_string(font, part[1], part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, part[3], Color(part[2], alpha))


## A box in the theme's style: ink outline, rounded, a deeper bottom edge.
static func _box(bg: Color, border: Color, width: int, bottom: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.border_width_bottom = bottom
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	return box


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
