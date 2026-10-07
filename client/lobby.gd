extends Control
## The lobby panel (M8): the server's name and match settings (the teams first), one card per player
## (name, preferred role, ready, ping), a line when bots fill the matches (M10), the role preference
## and the Ready button, plus the centre banner for the
## countdown ("You are a RAT!", the goal, the seconds left) and "GO!". Keys work without the mouse:
## 1 / 2 / 3 pick a preference, R toggles ready (rebindable). It only shows the replicated
## MatchManager state and sends requests; the server decides.

const GO_BANNER_MS := 1500
const SUPERVISOR_COLOR := Color("ffc93c")
const RAT_COLOR := Color("7bd389")

var _go_until_ms := 0
var _cards_key := ""  # what the cards show, to rebuild them only when it changes
var _bots_row: HBoxContainer  # "BOT  Bots fill the match up to 6 players"
var _bots_label: Label
var _host_label: Label  # a game we host: where friends join
var _addresses := PackedStringArray()  # this computer's LAN addresses (read once)

@onready var panel: Control = %Panel
@onready var status_label: Label = %StatusLabel
@onready var cards: VBoxContainer = %Cards
@onready var any_button: Button = %AnyButton
@onready var supervisor_button: Button = %SupervisorButton
@onready var rat_button: Button = %RatButton
@onready var ready_button: Button = %ReadyButton
@onready var banner: Control = %Banner
@onready var role_line: Label = %RoleLine
@onready var goal_line: Label = %GoalLine
@onready var count_line: Label = %CountLine


func _ready() -> void:
	var group := ButtonGroup.new()
	for button: Button in [any_button, supervisor_button, rat_button]:
		button.button_group = group
	any_button.pressed.connect(_request_pref.bind(Role.Kind.NONE))
	supervisor_button.pressed.connect(_request_pref.bind(Role.Kind.SUPERVISOR))
	rat_button.pressed.connect(_request_pref.bind(Role.Kind.RAT))
	ready_button.toggled.connect(_request_ready)
	_build_bots_row()
	_build_host_label()
	_match().state_changed.connect(_on_state_changed)
	_match().roster_changed.connect(_refresh)
	Config.changed.connect(func(key: String) -> void:
		if key == "bindings" or key == "language":
			_refresh())
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_cards_key = ""
		_refresh.call_deferred()  # (children can't change while the notification goes down the tree)


func _match() -> MatchManager:
	return Session.current.match_manager


func _request_pref(pref: Role.Kind) -> void:
	_match().request_set_pref.rpc_id(1, pref)


func _request_ready(on: bool) -> void:
	_match().request_set_ready.rpc_id(1, on)


func _unhandled_input(event: InputEvent) -> void:
	if _match().state != MatchManager.State.LOBBY or PlayerInput.blocked:
		return
	var pref := -1
	if event.is_action_pressed(&"lobby_pref_any"):
		pref = Role.Kind.NONE
	elif event.is_action_pressed(&"lobby_pref_supervisor"):
		pref = Role.Kind.SUPERVISOR
	elif event.is_action_pressed(&"lobby_pref_rat"):
		pref = Role.Kind.RAT
	elif event.is_action_pressed(&"lobby_ready"):
		var me := _match().entry(Session.current.local_peer_id)
		if not me.is_empty():
			Ui.play("ui_confirm" if not me["ready"] else "ui_click")
			_request_ready(not me["ready"])
		get_viewport().set_input_as_handled()
		return
	if pref >= 0:
		Ui.play("ui_click")
		_request_pref(pref)
		get_viewport().set_input_as_handled()


func _on_state_changed(state: MatchManager.State) -> void:
	if state == MatchManager.State.PLAYING:
		_go_until_ms = Time.get_ticks_msec() + GO_BANNER_MS
	_refresh()


func _process(_delta: float) -> void:
	_update_banner()  # countdown_left changes every second without a signal
	if panel.visible:
		_update_cards()  # pings change without a roster change


func _refresh() -> void:
	var mm := _match()
	panel.visible = mm.state == MatchManager.State.LOBBY
	var info := mm.server_info
	var local := LocalServer.for_session()
	var solo := local != null and local.mode == LocalServer.Mode.SOLO
	%ServerName.text = str(info.get("name", tr("Lobby")))
	var minutes := func(s: int) -> String: return "%d:%02d" % [s / 60, s % 60]
	var duration := minutes.call(int(info.get("duration_s", 540))) as String
	var duration_single := minutes.call(int(info.get("duration_single_s", 480))) as String
	var seats := [int(info.get("supervisors", 2)), int(info.get("rats", 4))]
	var teams := Ui.teams_text(seats[0], seats[1])
	# Bots in every empty seat: the teams are always these. Otherwise they depend on who plays.
	var teams_line := tr("%s vs %s") % teams if int(info.get("bot_fill_to", 0)) >= seats[0] + seats[1] \
		else tr("Up to %s and %s") % teams
	if solo:
		%Summary.text = "%s · %s" % [teams_line, tr("Matches of %s (%s with one supervisor)") % [duration, duration_single]]
	else:
		%Summary.text = "%s · %s" % [teams_line, tr("Matches of %s (%s with one supervisor) · %d+ players to start · %d / %d here") % [
			duration, duration_single, mm.min_players, mm.roster.size(), int(info.get("max_players", 6))]]
	var count := mm.roster.size()
	if solo:
		status_label.text = tr("Press Ready to start a match against the bots.")
	elif count < mm.min_players:
		status_label.text = tr("Waiting for players: %d / %d") % [count, mm.min_players]
	else:
		status_label.text = tr("%d / %d ready. The match starts when more than half are ready.") % [mm.ready_count(), count]
	_host_label.visible = local != null and local.mode == LocalServer.Mode.HOST
	if _host_label.visible:
		if _addresses.is_empty():
			_addresses = LocalServer.lan_addresses(IP.get_local_interfaces())
		_host_label.text = tr("You are the host. Friends on your network can also type %s") \
			% ("%s:%d" % [_addresses[0], local.port]) if not _addresses.is_empty() \
			else tr("You are the host (UDP port %d).") % local.port
	any_button.text = "%s  [%s]" % [tr("Any"), Keys.label(&"lobby_pref_any")]
	supervisor_button.text = "%s  [%s]" % [tr("Supervisor"), Keys.label(&"lobby_pref_supervisor")]
	rat_button.text = "%s  [%s]" % [tr("Rat"), Keys.label(&"lobby_pref_rat")]
	%Hint.text = tr("Esc opens the menu and frees the mouse to click here.")
	var fill := int(info.get("bot_fill_to", 0))
	_bots_row.visible = fill >= 2
	_bots_label.text = tr("Bots fill the match up to %d players") % fill
	var me := mm.entry(Session.current.local_peer_id)
	if not me.is_empty():
		# All three: set_pressed_no_signal() doesn't release the other buttons of the group.
		var pref := int(me["pref"])
		any_button.set_pressed_no_signal(pref not in [Role.Kind.SUPERVISOR, Role.Kind.RAT])
		supervisor_button.set_pressed_no_signal(pref == Role.Kind.SUPERVISOR)
		rat_button.set_pressed_no_signal(pref == Role.Kind.RAT)
		ready_button.set_pressed_no_signal(me["ready"])
		ready_button.text = "%s  [%s]" % [tr("Ready!") if me["ready"] else tr("Ready?"), Keys.label(&"lobby_ready")]
	_update_cards()
	_update_banner()


## Under the summary: a BOT badge and "Bots fill the match up to N players" (server_info.bot_fill_to).
func _build_bots_row() -> void:
	_bots_row = HBoxContainer.new()
	_bots_row.add_theme_constant_override("separation", 8)
	_bots_row.add_child(Ui.bot_badge(14))
	_bots_label = Label.new()
	_bots_label.add_theme_font_override("font", _bots_label.get_theme_font("font", &"Button"))
	_bots_label.add_theme_font_size_override("font_size", 16)
	_bots_label.add_theme_color_override("font_color", Color("ffc93c"))
	_bots_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_bots_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bots_row.add_child(_bots_label)
	_bots_row.visible = false
	%Summary.add_sibling(_bots_row)


## Under the bots line, in a game this game hosts: the address friends on the LAN can type.
func _build_host_label() -> void:
	_host_label = Label.new()
	_host_label.add_theme_font_override("font", _host_label.get_theme_font("font", &"Button"))
	_host_label.add_theme_font_size_override("font_size", 16)
	_host_label.add_theme_color_override("font_color", Color("7fb7e6"))
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_host_label.visible = false
	_bots_row.add_sibling(_host_label)


func _update_cards() -> void:
	var mm := _match()
	var key := "%s|%s" % [mm.roster, mm.pings]
	if key == _cards_key:
		return
	_cards_key = key
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	for peer: int in mm.roster:
		cards.add_child(_card(peer, mm.roster[peer]))


func _card(peer: int, e: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var me := peer == Session.current.local_peer_id
	var name_label := _label(str(e["name"]), Color("ffc93c") if me else Color.WHITE)  # (yellow: you)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	var pref: Role.Kind = e["pref"]
	row.add_child(_label(tr(Role.pref_name(pref)), SUPERVISOR_COLOR if pref == Role.Kind.SUPERVISOR
		else RAT_COLOR if pref == Role.Kind.RAT else Color(0.75, 0.76, 0.8)))
	var ready_label := _label(tr("READY") if e["ready"] else tr("not ready"),
		Color(0.5, 1, 0.55) if e["ready"] else Color(0.55, 0.57, 0.62))
	ready_label.custom_minimum_size = Vector2(84, 0)
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ready_label)
	var ping: int = _match().pings.get(peer, -1)
	var ping_label := _label(tr("%d ms") % ping if ping >= 0 else "-", Scoreboard.ping_color(ping))
	ping_label.custom_minimum_size = Vector2(58, 0)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ping_label)
	return card


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 17)
	return label


func _update_banner() -> void:
	var mm := _match()
	var role := mm.local_role()
	var role_text := ""
	var goal := ""
	var count := ""
	var color := Color.WHITE
	match mm.state:
		MatchManager.State.ROLE_ASSIGN, MatchManager.State.COUNTDOWN:
			if role == Role.Kind.SPECTATOR:
				goal = tr("Spectating until the next match")
			else:
				role_text = tr("You are a SUPERVISOR!") if role == Role.Kind.SUPERVISOR else tr("You are a RAT!")
				color = SUPERVISOR_COLOR if role == Role.Kind.SUPERVISOR else RAT_COLOR
				goal = tr("Keep the plant running until the shift ends!") if role == Role.Kind.SUPERVISOR \
					else tr("Sabotage the plant until it melts down!")
				count = tr("Starting in %d") % mm.countdown_left if mm.state == MatchManager.State.COUNTDOWN else ""
		MatchManager.State.PLAYING:
			if role == Role.Kind.SPECTATOR:
				goal = tr("Spectating until the next match")
			elif Time.get_ticks_msec() < _go_until_ms:
				role_text = tr("GO!")
				color = SUPERVISOR_COLOR if role == Role.Kind.SUPERVISOR else RAT_COLOR
	role_line.text = role_text
	role_line.add_theme_color_override("font_color", color)
	goal_line.text = goal
	count_line.text = count
	banner.visible = role_text != "" or goal != ""
