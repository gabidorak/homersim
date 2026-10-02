class_name Scoreboard
extends CanvasLayer
## The scoreboard (M8, ClientOnly): shown while the scoreboard key (Tab) is held. During a match, one
## column per team: name, how they are doing (caged, out, knocked down…), their key stats so far
## (MatchManager.live_stats) and ping (MatchManager.pings); spectators below. In the lobby: everyone
## with their preferred role and ready state. Only reads replicated state.

const SUPERVISOR_COLOR := Color("ffc93c")
const RAT_COLOR := Color("7bd389")
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
var _next_refresh_ms := 0


func _ready() -> void:
	layer = 15
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
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
	_root.visible = false


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
	else:
		_columns.add_child(_lobby_list())
		_footer.text = tr("%d / %d players") % [mm.roster.size(), int(info.get("max_players", 6))]


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
