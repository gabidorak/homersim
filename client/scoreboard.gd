class_name Scoreboard
extends CanvasLayer
## The scoreboard (M8, ClientOnly): shown while the scoreboard key (Tab) is held. During a match, one
## column per team: name, how they are doing (caged, out, knocked down…), their key stats so far
## (MatchManager.live_stats) and ping (MatchManager.pings), or a BOT badge for an AI bot (M10);
## spectators below. In the lobby: everyone with their preferred role and ready state. Under the board,
## the map of the level (a MapView of its plan, as on the full map key) fills the rest of the screen,
## with the player's room drawn brighter; the minimap steps aside meanwhile. Only reads replicated state.

const SUPERVISOR_COLOR := Color("ffc93c")
const RAT_COLOR := Color("7bd389")
const MARGIN := 24.0
const SUPERVISOR_STATS: Array[String] = ["repairs", "catches", "bonks"]
const RAT_STATS: Array[String] = ["sabotages", "bites", "frees"]
const STAT_TITLES := {
	"repairs": "Repairs", "catches": "Catches", "bonks": "Bonks", "sabotages": "Sabotages", "bites": "Bites",
	"frees": "Frees",
}

var _forced := false  # (the UI tour shows it without the key)
var _root: Control
var _title: Label
var _columns: HBoxContainer
var _footer: Label
var _plan: LevelMap
var _map_box: AspectRatioContainer
var _map: MapView
var _next_refresh_ms := 0


func _ready() -> void:
	layer = 15
	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_root.alignment = BoxContainer.ALIGNMENT_CENTER  # (the board alone, without a map: in the middle)
	_root.add_theme_constant_override("separation", 12)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_title)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 18)
	col.add_child(_columns)
	_footer = Label.new()
	_footer.theme_type_variation = &"MutedLabel"
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_footer)
	_build_map()
	_root.visible = false


## The map under the board: as big as the space left allows, in the plan's proportions.
func _build_map() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_plan = MapInfo.plan_in(get_tree())
	if _plan == null:
		return
	_map_box = AspectRatioContainer.new()
	_map_box.ratio = _plan.area.size.x / _plan.area.size.y
	_map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_box)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_box.add_child(card)
	_map = MapView.new()
	_map.plan = _plan
	card.add_child(_map)


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
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	if mm.in_match() or mm.state == MatchManager.State.POST_MATCH:
		_columns.add_child(_team(tr("Supervisors"), Role.Kind.SUPERVISOR, SUPERVISOR_COLOR, SUPERVISOR_STATS))
		_columns.add_child(_team(tr("Rats"), Role.Kind.RAT, RAT_COLOR, RAT_STATS))
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
		_columns.add_child(_lobby_list())
		_footer.text = tr("%d / %d players") % [mm.human_count(), int(info.get("max_players", 6))]


func _refresh_map() -> void:
	if _map_box == null:
		return
	_map_box.visible = Session.current.match_manager.state != MatchManager.State.POST_MATCH
	if not _map_box.visible:
		return
	var session := Session.current
	var body := session.get_body(session.local_peer_id)
	_map.highlight = -1 if body != null and VentVolume.contains(body) else _plan.room_at(_map.viewer()[0])
	Config.mark_hint_seen("map")  # (they found it: no need for the tip any more)


func _team(title: String, role: Role.Kind, color: Color, stat_keys: Array[String]) -> Control:
	var mm := Session.current.match_manager
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3 + stat_keys.size()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	var heading := _cell(title, color, true)
	heading.add_theme_font_size_override("font_size", 22)
	grid.add_child(heading)
	grid.add_child(_cell("", Color.WHITE))
	for key in stat_keys:
		grid.add_child(_cell(tr(STAT_TITLES[key]), Color(0.64, 0.65, 0.68), false, true))
	grid.add_child(_cell(tr("Ping"), Color(0.64, 0.65, 0.68), false, true))
	var peers: Array = mm.roster.keys()
	peers.sort_custom(func(a: int, b: int) -> bool: return str(mm.roster[a]["name"]).naturalnocasecmp_to(mm.roster[b]["name"]) < 0)
	for peer: int in peers:
		var e: Dictionary = mm.roster[peer]
		if e["role"] != role:
			continue
		var me := peer == Session.current.local_peer_id
		grid.add_child(_cell(str(e["name"]) + (" " + tr("(you)") if me else ""), Color.WHITE if not me else color, me))
		var state := _state_of(peer, e)
		grid.add_child(_cell(state[0], state[1]))
		var counts: Dictionary = mm.live_stats.get(peer, {})
		for key in stat_keys:
			grid.add_child(_cell(str(counts.get(key, 0)), Color.WHITE, false, true))
		if e.get("bot", false):
			var badge := Ui.bot_badge()
			badge.size_flags_horizontal = Control.SIZE_SHRINK_END
			grid.add_child(badge)
		else:
			grid.add_child(_ping_cell(peer))
	return card


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


func _lobby_list() -> Control:
	var mm := Session.current.match_manager
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Lobby"), tr("Wants to play"), tr("Ready?"), tr("Ping")]:
		grid.add_child(_cell(title, Color(0.64, 0.65, 0.68), false))
	for peer: int in mm.roster:
		var e: Dictionary = mm.roster[peer]
		var me := peer == Session.current.local_peer_id
		grid.add_child(_cell(str(e["name"]) + (" " + tr("(you)") if me else ""), Color.WHITE, me))
		var pref: Role.Kind = e["pref"]
		grid.add_child(_cell(tr(Role.pref_name(pref)), SUPERVISOR_COLOR if pref == Role.Kind.SUPERVISOR
			else RAT_COLOR if pref == Role.Kind.RAT else Color(0.8, 0.8, 0.8)))
		grid.add_child(_cell(tr("Ready!") if e["ready"] else "-", Color(0.5, 1, 0.55) if e["ready"] else Color(0.6, 0.6, 0.6)))
		grid.add_child(_ping_cell(peer))
	return card


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
