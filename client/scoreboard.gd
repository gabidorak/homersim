class_name Scoreboard
extends CanvasLayer
## The scoreboard and map (M8, ClientOnly): shown while the scoreboard key (Tab) is held. Laid out like
## the full map (MapOverlay): the same map of the level, as big and as detailed (with the player's room
## drawn brighter), and the players in a column where that one has its legend. During a match: each team,
## with for each player how they are doing (caged, out, knocked down…), their ping (MatchManager.pings)
## or a BOT badge for an AI bot (M10), and under it their key stats so far (MatchManager.live_stats);
## bots and spectators at the bottom. From COMPACT_FROM players (big bot matches) each team is two
## columns of names without stats, and the column never grows past the map. In the lobby: everyone with their preferred role and ready state.
## Without a plan, and after the match, the column alone. The minimap steps aside meanwhile. Only reads
## replicated state.

const SUPERVISOR_COLOR := Color("ffc93c")
const RAT_COLOR := Color("7bd389")
const MUTED := Color(0.64, 0.65, 0.68)
const SIDE_W := 320.0  ## the player column, next to the map
const COMPACT_FROM := 11  ## match players from which they are listed in two columns of single lines
const SUPERVISOR_STATS: Array[String] = ["repairs", "catches", "bonks"]
const RAT_STATS: Array[String] = ["sabotages", "bites", "frees"]
const STAT_TITLES := {
	"repairs": "Repairs", "catches": "Catches", "bonks": "Bonks", "sabotages": "Sabotages", "bites": "Bites",
	"frees": "Frees",
}

var _forced := false  # (the UI tour shows it without the key)
var _root: Control
var _title: Label
var _map_card: PanelContainer
var _map: MapView
var _plan: LevelMap
var _scroll: ScrollContainer
var _list: VBoxContainer
var _compact := false
var _footer: Label
var _next_refresh_ms := 0


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	_build_map(row)
	var side_card := PanelContainer.new()
	side_card.theme_type_variation = &"CardPanel"
	side_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(side_card)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	side.add_theme_constant_override("separation", 6)
	side_card.add_child(side)
	# Clips the players to the map's height instead of growing the board past the screen.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_footer = Label.new()
	_footer.theme_type_variation = &"MutedLabel"
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	side.add_child(_footer)
	_root.visible = false


## The map, sized like the full map (MapOverlay.full_map_size) whenever the window changes.
func _build_map(row: HBoxContainer) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_plan = MapInfo.plan_in(get_tree())
	if _plan == null:
		return
	_map_card = PanelContainer.new()
	_map_card.theme_type_variation = &"CardPanel"
	_map_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_map_card)
	_map = MapView.new()
	_map.plan = _plan
	_map_card.add_child(_map)
	get_viewport().size_changed.connect(_layout_map)
	_layout_map()


func _layout_map() -> void:
	_map.custom_minimum_size = MapOverlay.full_map_size(get_viewport().get_visible_rect().size, _plan, SIDE_W)


func is_shown() -> bool:
	return _root.visible


## Test hook: show it without holding the key.
func set_forced(on: bool) -> void:
	_forced = on
	_next_refresh_ms = 0


func _process(_delta: float) -> void:
	var wanted := _forced or (Input.is_action_pressed(&"scoreboard") and not PlayerInput.blocked)
	if wanted != _root.visible:
		_root.visible = wanted
		_next_refresh_ms = 0
	if not wanted or Time.get_ticks_msec() < _next_refresh_ms:
		return
	_next_refresh_ms = Time.get_ticks_msec() + 300
	_refresh()


func _refresh() -> void:
	var session := Session.current
	var mm := session.match_manager
	var info := mm.server_info
	_refresh_map()
	var title := str(info.get("name", ""))
	if mm.state == MatchManager.State.PLAYING:
		title += "  ·  %d:%02d" % [floori(mm.time_left / 60.0), mm.time_left % 60]
	_title.text = title
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if mm.in_match() or mm.state == MatchManager.State.POST_MATCH:
		var playing := 0
		for peer: int in mm.roster:
			playing += 1 if mm.roster[peer]["role"] in [Role.Kind.SUPERVISOR, Role.Kind.RAT] else 0
		_compact = playing >= COMPACT_FROM
		_list.add_theme_constant_override("separation", 2 if _compact else 6)
		_team(tr("Supervisors"), Role.Kind.SUPERVISOR, SUPERVISOR_COLOR, SUPERVISOR_STATS)
		_team(tr("Rats"), Role.Kind.RAT, RAT_COLOR, RAT_STATS)
		var watching: Array[String] = []
		for peer: int in mm.roster:
			if mm.roster[peer]["role"] == Role.Kind.SPECTATOR:
				watching.append(mm.roster[peer]["name"])
		_footer.text = (tr("Watching: %s") % ", ".join(watching)) if not watching.is_empty() else \
			tr("Hold %s to see this board") % Keys.label(&"scoreboard")
		var bots := mm.roster.size() - mm.human_count()
		if bots > 0:
			_footer.text = tr("%d humans, %d bots") % [mm.human_count(), bots] + "  ·  " + _footer.text
	else:
		_compact = false
		_list.add_theme_constant_override("separation", 6)
		_lobby_list()
		_footer.text = tr("%d / %d players") % [mm.human_count(), int(info.get("max_players", 6))]
	# Beside the map the column takes its height; alone (no plan, after the match) it needs its own.
	var alone := _map_card == null or not _map_card.visible
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y,
		get_viewport().get_visible_rect().size.y - 220.0) if alone else 0.0


func _refresh_map() -> void:
	if _map_card == null:
		return
	_map_card.visible = Session.current.match_manager.state != MatchManager.State.POST_MATCH
	if not _map_card.visible:
		return
	var session := Session.current
	var body := session.get_body(session.local_peer_id)
	_map.highlight = -1 if body != null and VentVolume.contains(body) else _plan.room_at(_map.viewer()[0])
	Config.mark_hint_seen("map")  # (they found it: no need for the tip any more)


## One team in the column: its name, then each player (name, state, ping) with their stats under it.
func _team(title: String, role: Role.Kind, color: Color, stat_keys: Array[String]) -> void:
	var mm := Session.current.match_manager
	_heading(title, color)
	var grid: GridContainer = null
	if _compact:
		grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 2)
		_list.add_child(grid)
	var peers: Array = mm.roster.keys()
	peers.sort_custom(func(a: int, b: int) -> bool: return str(mm.roster[a]["name"]).naturalnocasecmp_to(mm.roster[b]["name"]) < 0)
	for peer: int in peers:
		var e: Dictionary = mm.roster[peer]
		if e["role"] != role:
			continue
		var me := peer == Session.current.local_peer_id
		var state := _state_of(peer, e)
		var right: Control = Ui.bot_badge() if e.get("bot", false) else _ping_cell(peer)
		var counts: Dictionary = mm.live_stats.get(peer, {})
		var stats: Array[String] = []
		for key in stat_keys:
			stats.append("%s %d" % [tr(STAT_TITLES[key]), int(counts.get(key, 0))])
		var sub := _cell("  ·  ".join(stats), MUTED)
		sub.add_theme_font_size_override("font_size", 14)
		var player_name := str(e["name"]) + (" " + tr("(you)") if me and not _compact else "")
		_entry(player_name, color if me else Color.WHITE, me, _cell(state[0], state[1]), right, sub, grid)


## [text, colour] for how a player is doing right now.
func _state_of(peer: int, e: Dictionary) -> Array:
	if e.get("eliminated", false):
		return [tr("OUT"), Color(1, 0.45, 0.45)]
	var body := Session.current.get_body(peer)
	if body == null:
		return ["", Color.WHITE]
	if body.status.has(StatusComponent.Status.CAGED):
		return [tr("Caged"), Color(0.75, 0.75, 0.8)]
	if body.status.has(StatusComponent.Status.CARRIED):
		return [tr("Caught!"), Color(1, 0.6, 0.3)]
	if body.status.has(StatusComponent.Status.KNOCKED_DOWN):
		return [tr("Knocked down"), Color(1, 0.45, 0.4)]
	if body.status.has(StatusComponent.Status.STUNNED):
		return [tr("Stunned"), Color(1, 0.9, 0.3)]
	return ["", Color.WHITE]


## The lobby: each player with their ping, and under it the role they want and whether they are ready.
func _lobby_list() -> void:
	var mm := Session.current.match_manager
	_heading(tr("Lobby"), Color.WHITE)
	for peer: int in mm.roster:
		var e: Dictionary = mm.roster[peer]
		var me := peer == Session.current.local_peer_id
		var pref: Role.Kind = e["pref"]
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override("separation", 10)
		for cell: Label in [_cell(tr(Role.pref_name(pref)), SUPERVISOR_COLOR if pref == Role.Kind.SUPERVISOR
				else RAT_COLOR if pref == Role.Kind.RAT else Color(0.8, 0.8, 0.8)),
				_cell(tr("Ready!") if e["ready"] else tr("Ready?"), Color(0.5, 1, 0.55) if e["ready"] else MUTED)]:
			cell.add_theme_font_size_override("font_size", 14)
			sub.add_child(cell)
		_entry(str(e["name"]) + (" " + tr("(you)") if me else ""), Color.WHITE, me, null, _ping_cell(peer), sub)


func _heading(text: String, color: Color) -> void:
	var heading := _cell(text, color, true)
	heading.add_theme_font_size_override("font_size", 22)
	if _list.get_child_count() > 0:
		heading.custom_minimum_size = Vector2(0, 36)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(heading)


## A player in the column: a line with their name, `state` and `right` (ping or BOT), then `sub`.
## `parent`: where it goes (the column when null).
func _entry(player_name: String, color: Color, bold: bool, state: Control, right: Control, sub: Control,
		parent: Container = null) -> void:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	entry.add_child(line)
	var name_label := _cell(player_name, color, bold)
	if _compact:
		name_label.add_theme_font_size_override("font_size", 15)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if state is Label:
			state.add_theme_font_size_override("font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)
	if state != null:
		line.add_child(state)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(right)
	if _compact:
		sub.free()
	else:
		entry.add_child(sub)
	(parent if parent != null else _list).add_child(entry)


func _ping_cell(peer: int) -> Label:
	var ping: int = Session.current.match_manager.pings.get(peer, -1)
	return _cell(tr("%d ms") % ping if ping >= 0 else "-", ping_color(ping), false, true)


static func ping_color(ping: int) -> Color:
	if ping < 0:
		return Color(0.6, 0.6, 0.6)
	return Color(0.6, 1, 0.65) if ping < 80 else Color(1, 0.85, 0.5) if ping < 160 else Color(1, 0.5, 0.45)


func _cell(text: String, color: Color, bold: bool = false, right: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", get_theme_bold())
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


## The theme's bold font (the RichTextLabel's bold font in theme.tres).
func get_theme_bold() -> Font:
	return ThemeDB.get_project_theme().get_font("bold_font", "RichTextLabel")
