class_name MapView
extends Control
## Draws a level's plan (LevelMap) and what is on it right now. MapOverlay uses two: the minimap in the
## corner (`follow`: centred on the player, and by default turned so the camera looks up) and the full
## map (the whole plan, north up, with names). Everything is drawn in screen pixels: world points go
## through `_xf`, so line widths and text stay the same size whatever the zoom or the turn.
## The look follows the UI theme (tools/godot/make_theme.gd): bright palette colours, thick ink
## outlines, a darker bottom edge under the building and the machine badges, the theme's fonts.
##
## It only shows what the player could know anyway, like the 3D view: their own team; enemies while
## they are REVEALED (the cheese lure, radiation); everyone for ghosts, spectators and in the lobby. The
## machines are coloured by health, cages say how many rats are inside, supervisors see their pickups,
## and the vents are drawn for everyone but supervisors (they can't fit in them).

# The theme's colours (make_theme.gd) and palette swatches (tools/art/palette.py).
const INK := Color("1b1b1f")
const NAVY_DEEP := Color("141b2d")
const OFF_WHITE := Color("e8e6df")
const YELLOW := Color("ffc93c")
const RED := Color("e84a5f")
const GREEN := Color("7bd389")
const SUPERVISOR_COLOR := YELLOW
const RAT_COLOR := GREEN
const BACKGROUND := NAVY_DEEP
const SHADOW := Color("0b0f1a")  ## under the building, like the theme's deeper bottom edges
const GRID := Color(1, 1, 1, 0.05)
const FENCE_COLOR := Color("c9ccd1")
const DOOR_COLOR := Color("f28c28")
const KEYCARD_COLOR := Color("57c7ff")
const WINDOW_COLOR := Color("bfe3f2")
const VENT_COLOR := Color("b08cff")
const LADDER_COLOR := YELLOW
const CAGE_COLOR := Color("c9ccd1")
const DONUT_COLOR := Color("ff8fb8")
const TRAP_COLOR := Color("f28c28")
const TOWER_COLOR := Color("c9ccd1")
const NODE_REFRESH_MS := 1000  ## how often the lists of stations, cages and pickups are gathered again

var plan: LevelMap
var follow := false  ## centred on the viewer (the minimap); otherwise the whole plan fits in the rect
var turn_with_view := false  ## when following: turned so that the camera's forward points up
var pixels_per_m := 3.0  ## when following
var compact := false  ## the minimap: smaller marks, no names on players, machines and pickups
var highlight := -1  ## a room of the plan drawn brighter (the one the player is in)

var _xf := Transform2D()  # world (x, z) -> local pixels
var _ppm := 1.0  # pixels per metre
var _display: Font  # Luckiest Guy (room names)
var _bold: Font  # Fredoka bold (everything else)
var _stations: Array[StationLabel] = []
var _cages: Array[Cage] = []
var _pickups: Array[Pickup] = []
var _nodes_at_ms := -NODE_REFRESH_MS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


# --- Who sees what -------------------------------------------------------------------------------

## True for ghosts (eliminated rats, late joiners): they watch, so they see every player.
func _watching() -> bool:
	var session := Session.current
	return session.match_manager.in_match() and session.match_manager.is_ghost(session.local_peer_id)


## The vents are rat business: everyone else sees them, supervisors don't (they can't get in anyway).
func shows_vents() -> bool:
	return Session.current.match_manager.local_role() != Role.Kind.SUPERVISOR or _watching()


func shows_pickups() -> bool:
	return Session.current.match_manager.local_role() == Role.Kind.SUPERVISOR or _watching()


## Whether `player` (not the local one) is on the map: team mates, revealed enemies, or everyone.
func shows_player(player: Player) -> bool:
	if _watching():
		return true
	var mine := Session.current.match_manager.local_role()
	if player.role == mine:
		return true
	return mine in [Role.Kind.SUPERVISOR, Role.Kind.RAT] and player.status.has(StatusComponent.Status.REVEALED)


static func team_color(role: Role.Kind, peer_id: int) -> Color:
	match role:
		Role.Kind.SUPERVISOR:
			return SUPERVISOR_COLOR
		Role.Kind.RAT:
			return RAT_COLOR
	return Player.color_for_peer(peer_id)  # the lobby: the colour of their hat


## Red when broken, yellow halfway, green when fine.
static func health_color(fraction: float) -> Color:
	var f := clampf(fraction, 0.0, 1.0)
	return RED.lerp(YELLOW, f * 2.0) if f < 0.5 else YELLOW.lerp(GREEN, f * 2.0 - 1.0)


## Where the local player is (their body, or the camera without one) and where the camera looks:
## [Vector2 position on the plan, float heading (radians about Y, 0 = north, like rotation.y)].
func viewer() -> Array:
	var session := Session.current
	var body := session.get_body(session.local_peer_id)
	var camera := get_viewport().get_camera_3d()
	var pos := Vector3.ZERO
	if body != null:
		pos = body.global_position
	elif camera != null:
		pos = camera.global_position
	var heading := 0.0
	if camera != null:
		var forward := -camera.global_basis.z
		heading = atan2(-forward.x, -forward.z)
	elif body != null:
		heading = body.rotation.y
	return [Vector2(pos.x, pos.z), heading]


# --- Drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	if plan == null or Session.current == null:
		return
	_display = get_theme_font("font", &"HeaderLabel")
	_bold = get_theme_font("font", &"Button")
	var session := Session.current
	var view := viewer()
	var me: Vector2 = view[0]
	var heading: float = view[1]
	if follow:
		_ppm = pixels_per_m
		_xf = Transform2D(heading if turn_with_view else 0.0, Vector2(_ppm, _ppm), 0.0, size / 2.0) * Transform2D(0.0, -me)
	else:
		_ppm = minf(size.x / plan.area.size.x, size.y / plan.area.size.y)
		_xf = Transform2D(0.0, Vector2(_ppm, _ppm), 0.0, size / 2.0) * Transform2D(0.0, -plan.area.get_center())
	_draw_plan()
	_refresh_nodes()
	_draw_cages()
	if shows_pickups():
		_draw_pickups()
	_draw_stations()
	_draw_room_names()
	_draw_players(session)
	var body := session.get_body(session.local_peer_id)
	var forward := _xf.basis_xform(Vector2(-sin(heading), -cos(heading))).normalized()
	if body != null:
		if not compact:  # (a pulse, to find yourself at a glance)
			var pulse := fmod(Time.get_ticks_msec() / 900.0, 1.0)
			draw_arc(_xf * me, 9.0 + 16.0 * pulse, 0.0, TAU, 32, Color(YELLOW, 1.0 - pulse), 3.0, true)
		draw_arrow(self, _xf * me, forward, Color.WHITE, 10.0 if compact else 12.0)
	elif _watching():
		draw_arrow(self, _xf * me, forward, Color(1, 1, 1, 0.5), 9.0)
	if follow and turn_with_view:
		_draw_north()


func _corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_xf * r.position, _xf * Vector2(r.end.x, r.position.y), _xf * r.end,
		_xf * Vector2(r.position.x, r.end.y)])


func _draw_plan() -> void:
	# A faint 10 m grid, like a blueprint.
	var a := plan.area
	for x in range(ceili(a.position.x / 10.0) * 10, int(a.end.x) + 1, 10):
		draw_line(_xf * Vector2(x, a.position.y), _xf * Vector2(x, a.end.y), GRID, 1.0)
	for z in range(ceili(a.position.y / 10.0) * 10, int(a.end.y) + 1, 10):
		draw_line(_xf * Vector2(a.position.x, z), _xf * Vector2(a.end.x, z), GRID, 1.0)
	# The building's shadow (its bottom edge), then the rooms in their colours.
	var drop := _xf.affine_inverse().basis_xform(Vector2(0, clampf(0.9 * _ppm, 3.0, 7.0)))  # (down on screen)
	for r in plan.room_rects:
		draw_colored_polygon(_corners(Rect2(r.position + drop, r.size)), SHADOW)
	for c in plan.circles:
		draw_circle(_xf * (Vector2(c.x, c.y) + drop), c.z * _ppm, SHADOW)
	for i in plan.room_rects.size():
		var color := plan.room_colors[i]
		draw_colored_polygon(_corners(plan.room_rects[i]), color.lightened(0.15) if i == highlight else color)
	if highlight != -1:  # the room we're in: a white line inside its walls (on ink, so it shows on any colour)
		var inner := _corners(plan.room_rects[highlight].grow(-0.75))
		inner.append(inner[0])
		draw_polyline(inner, INK, 5.0 if compact else 6.0, true)
		draw_polyline(inner, Color.WHITE, 2.0 if compact else 3.0, true)
	for c in plan.circles:  # the cooling tower, seen from above
		var at := _xf * Vector2(c.x, c.y)
		draw_circle(at, c.z * _ppm, TOWER_COLOR)
		draw_circle(at, c.z * _ppm * 0.62, TOWER_COLOR.darkened(0.25))
		draw_arc(at, c.z * _ppm * 0.62, 0.0, TAU, 32, INK, 1.5, true)
		draw_arc(at, c.z * _ppm, 0.0, TAU, 40, INK, maxf(2.0, 0.5 * _ppm), true)
	var wall := maxf(2.5, 0.8 * _ppm)
	if shows_vents():  # thick tubes with an ink outline
		var duct := maxf(2.0, 0.55 * _ppm)
		_segments(plan.vent_ducts, INK, duct + 3.0)
		_segments(plan.vent_ducts, VENT_COLOR, duct)
		for i in range(0, plan.raised_ducts.size() - 1, 2):
			var p0 := _xf * plan.raised_ducts[i]
			var p1 := _xf * plan.raised_ducts[i + 1]
			draw_dashed_line(p0, p1, INK, duct + 3.0, 7.0, true, true)
			draw_dashed_line(p0, p1, VENT_COLOR, duct, 7.0, true, true)
	_segments(plan.fences, INK, maxf(2.0, 0.35 * _ppm) + 2.0)
	_segments(plan.fences, FENCE_COLOR, maxf(1.0, 0.35 * _ppm))
	_segments(plan.walls, INK, wall)
	_segments(plan.windows, WINDOW_COLOR, maxf(1.5, 0.35 * _ppm))
	_doors(plan.doors, DOOR_COLOR, wall)
	_doors(plan.keycard_doors, KEYCARD_COLOR, wall)
	if shows_vents():  # the grates where a duct opens into a room
		var r := maxf(3.0, 0.75 * _ppm)
		for p in plan.vent_openings:
			draw_circle(_xf * p, r + 1.5, INK)
			draw_circle(_xf * p, r, VENT_COLOR)
	for p in plan.ladders:
		draw_ladder(self, _xf * p, 1.0 if compact else 1.3)
		if not compact:
			_label(tr("Ladder"), _xf * p + Vector2(0, 18), 11, LADDER_COLOR)


func _segments(points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(0, points.size() - 1, 2):
		draw_line(_xf * points[i], _xf * points[i + 1], color, width, true)


## Doors as coloured bars across their gap in the wall, outlined in ink.
func _doors(points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(0, points.size() - 1, 2):
		var a := _xf * points[i]
		var b := _xf * points[i + 1]
		var along := (b - a).normalized()
		draw_line(a - along, b + along, INK, width + 1.0, true)
		draw_line(a + along, b - along, color, maxf(1.5, width - 2.5), true)


func _draw_room_names() -> void:
	for i in plan.room_names.size():
		var text := tr(plan.room_names[i])
		var at := _xf * plan.room_label_at[i]
		if compact:
			# Only names that fit whole, not over the player's arrow, and not the room we're in (its name is
			# under the minimap).
			var half := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11) / 2.0
			var box := Rect2(at - half, half * 2.0)
			if i != highlight and Rect2(Vector2.ZERO, size).grow(-2.0).encloses(box) \
					and not box.intersects(Rect2(size / 2.0 - Vector2(14, 14), Vector2(28, 28))):
				_label(text, at, 11, OFF_WHITE)
			continue
		var lines := _wrap(text, plan.room_rects[i].size.x * _ppm - 8.0, 15)
		for l in lines.size():
			var line_at := at + Vector2(0, (l - (lines.size() - 1) * 0.5) * 16.0)
			_label(lines[l], line_at, 15, OFF_WHITE, _display, 5, true)


## `text` split into two lines at the space nearest the middle when it is wider than `width`.
func _wrap(text: String, width: float, font_size: int) -> PackedStringArray:
	if _display.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width or not text.contains(" "):
		return PackedStringArray([text])
	var middle := text.length() / 2.0
	var best := -1
	for i in text.length():
		if text[i] == " " and (best == -1 or absf(i - middle) < absf(best - middle)):
			best = i
	return PackedStringArray([text.substr(0, best), text.substr(best + 1)])


func _refresh_nodes() -> void:
	if Time.get_ticks_msec() - _nodes_at_ms < NODE_REFRESH_MS:
		return
	_nodes_at_ms = Time.get_ticks_msec()
	var tree := get_tree()
	_stations.assign(tree.get_nodes_in_group(StationLabel.GROUP))
	_cages.assign(tree.get_nodes_in_group(Cage.CAGE_GROUP))
	_pickups.clear()
	for node in tree.get_nodes_in_group(Interactable.GROUP):
		if node is Pickup:
			_pickups.append(node)


func _flat(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


func _draw_stations() -> void:
	var plant := Session.current.plant
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 140.0)
	for label in _stations:
		if not is_instance_valid(label) or not label.is_inside_tree():
			continue
		var index := plant.index_of(label.subsystem_id)
		if index == -1:
			continue
		var at := _xf * _flat(label)
		var health := plant.health(index) / plant.tuning.max_health
		var offline := plant.needs_reboot(index)
		var data := plant.data(index)
		if offline:  # a red alarm pulse around a machine that needs a reboot
			draw_circle(at, (9.0 if compact else 20.0) + 4.0 * blink, Color(RED, 0.25 + 0.35 * blink))
		if compact:
			draw_box(self, Rect2(at - Vector2(6, 6), Vector2(12, 12)), health_color(health), 2.0, 3.0)
			continue
		draw_badge(self, _bold, at, tr(data.short_name), health_color(health))
		_label(tr(data.display_name), at + Vector2(0, 21), 11, OFF_WHITE)
		_label(tr("OFFLINE") if offline else "%d%%" % roundi(plant.health(index)), at + Vector2(0, 33), 11,
			RED.lightened(0.25) if offline else health_color(health))


func _draw_cages() -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
	for cage in _cages:
		if not is_instance_valid(cage) or not cage.is_inside_tree():
			continue
		var at := _xf * _flat(cage)
		var full := not cage.occupants.is_empty()
		if full:  # a friend to free: a green pulse
			draw_circle(at, (10.0 if compact else 14.0) + 3.0 * blink, Color(RAT_COLOR, 0.25 + 0.35 * blink))
		draw_cage(self, at, 0.8 if compact else 1.0)
		if not compact:
			var text := tr("CAGE (%d)") % cage.occupants.size() if full else tr("CAGE")
			_label(text, at + Vector2(0, 17), 11, RAT_COLOR if full else CAGE_COLOR)


func _draw_pickups() -> void:
	for pickup in _pickups:
		if not is_instance_valid(pickup) or not pickup.is_inside_tree():
			continue
		var at := _xf * _flat(pickup)
		draw_pickup(self, at, pickup.item, 0.8 if compact else 1.0)
		var look: Array = Pickup.LOOKS.get(pickup.item, [])
		if not compact and look.size() > 3 and look[3] != "":
			_label(tr(look[3]), at + Vector2(0, 14), 10, OFF_WHITE)


func _draw_players(session: Session) -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	var mine := session.match_manager.local_role()
	var watching := _watching()
	for node in session.players_root.get_children():
		var player := node as Player
		if player == null or player.peer_id == session.local_peer_id or not player.is_inside_tree() \
				or not shows_player(player):
			continue
		var at := _xf * _flat(player)
		var color := team_color(player.role, player.peer_id)
		if not watching and mine in [Role.Kind.SUPERVISOR, Role.Kind.RAT] and player.role != mine:
			draw_arc(at, 9.0 + 5.0 * blink, 0.0, TAU, 24, Color(color, 1.0 - blink * 0.6), 3.0, true)  # revealed
		var down := player.status.has(StatusComponent.Status.CAGED) \
			or player.status.has(StatusComponent.Status.KNOCKED_DOWN)
		draw_dot(self, at, color.darkened(0.35) if down else color, 5.0 if compact else 6.5)
		if not compact:
			_label(player.display_name, at + Vector2(0, -15), 11, color)


## A yellow "N" badge on the rim of the turning minimap, where north is.
func _draw_north() -> void:
	var north := _xf.basis_xform(Vector2(0, -1)).normalized()
	var at := size / 2.0 + north * (minf(size.x, size.y) / 2.0 - 12.0)
	draw_circle(at, 10.0, INK)
	draw_circle(at, 8.0, YELLOW)
	var width := _display.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_display, at + Vector2(-width / 2.0, 5.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)


## Text centred on `at` with an ink outline (and the theme's drop shadow for the big names).
func _label(text: String, at: Vector2, font_size: int, color: Color, font: Font = null, outline := 4,
		shadow := false) -> void:
	var f := font if font != null else _bold
	var text_size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := at + Vector2(-text_size.x / 2.0, (f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0)
	if shadow:
		draw_string_outline(f, pos + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.5))
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, INK)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- Marks (also used by the full map's legend) --------------------------------------------------

## A rounded box with an ink outline and a deeper bottom edge, like the theme's buttons.
static func draw_box(item: CanvasItem, rect: Rect2, fill: Color, border := 2.0, radius := 5.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(int(border))
	box.border_width_bottom = int(border) + 2
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	item.draw_style_box(box, rect)


## The player's arrow at `at`, pointing along `direction` (a unit vector in pixels): chunky, outlined.
static func draw_arrow(item: CanvasItem, at: Vector2, direction: Vector2, color: Color, length: float) -> void:
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([at + direction * length, at - direction * length * 0.65 + side * length * 0.75,
		at - direction * length * 0.25, at - direction * length * 0.65 - side * length * 0.75])
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(0, 2.5))
	item.draw_colored_polygon(shadow, Color(INK, 0.6 * color.a))
	item.draw_colored_polygon(points, color)
	points.append(points[0])
	item.draw_polyline(points, Color(INK, color.a), 2.5, true)


## A player: a round token in their team colour, outlined, with a little shine.
static func draw_dot(item: CanvasItem, at: Vector2, color: Color, radius: float) -> void:
	item.draw_circle(at + Vector2(0, 1.5), radius + 2.0, INK)
	item.draw_circle(at, radius, color)
	item.draw_circle(at + Vector2(-radius, -radius) * 0.35, radius * 0.3, Color(1, 1, 1, 0.6))


## A machine: its short name on a badge in its health colour (a tiny theme button).
static func draw_badge(item: CanvasItem, font: Font, at: Vector2, text: String, fill: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_box(item, Rect2(at - Vector2(width / 2.0 + 7.0, 10.0), Vector2(width + 14.0, 21.0)), fill, 2.0, 6.0)
	item.draw_string(font, Vector2(at.x - width / 2.0, at.y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)


## A cage: a silver box with bars.
static func draw_cage(item: CanvasItem, at: Vector2, scale_by: float) -> void:
	var half := 7.0 * scale_by
	draw_box(item, Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), CAGE_COLOR, 2.0, 3.0)
	for k: float in [-0.4, 0.0, 0.4]:
		item.draw_line(at + Vector2(k * half, -half + 2.0), at + Vector2(k * half, half - 2.0), INK, 1.5)


static func draw_ladder(item: CanvasItem, at: Vector2, scale_by: float) -> void:
	var w := 4.0 * scale_by
	var h := 7.0 * scale_by
	for pass_color: Color in [INK, LADDER_COLOR]:
		var width := 4.0 if pass_color == INK else 2.0
		for x: float in [-w, w]:
			item.draw_line(at + Vector2(x, -h), at + Vector2(x, h), pass_color, width)
		for k in 3:
			var y := -h + (k + 1) * h * 0.5
			item.draw_line(at + Vector2(-w, y), at + Vector2(w, y), pass_color, width - 0.5)


## What a supervisor can pick up: a pink donut, an orange trap box, a blue keycard.
static func draw_pickup(item: CanvasItem, at: Vector2, kind: String, scale_by: float) -> void:
	match kind:
		"donut":
			item.draw_circle(at, 6.5 * scale_by, INK)
			item.draw_circle(at, 5.0 * scale_by, DONUT_COLOR)
			item.draw_circle(at, 1.8 * scale_by, INK)
		"trap_refill":
			draw_box(item, Rect2(at - Vector2(5, 5) * scale_by, Vector2(10, 10) * scale_by), TRAP_COLOR, 2.0, 3.0)
		_:
			draw_box(item, Rect2(at - Vector2(6, 4.5) * scale_by, Vector2(12, 9) * scale_by), KEYCARD_COLOR, 2.0, 2.0)
