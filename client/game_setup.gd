extends Control
## The card before "Play solo" and "Host a game" (main menu): the choices for the server this game
## starts itself (client/local_server.gd). Every change is saved at once (Config.solo_* / host_*), so
## the card opens with the last choices. Start emits start_requested; the main menu does the rest.
##   Solo: the role you'd like, the teams (you + bots), the bots' difficulty.
##   Host: where (this computer, or the online server: the launcher on the VPS, OnlineClient), the
##   game's name, a password, the most players, the teams' seats, the bots (none, or a difficulty: they
##   take the seats nobody fills); on this computer the UDP port and whether the game shows on the
##   local network, online the friends key.

signal closed
signal start_requested(mode: LocalServer.Mode, options: Dictionary)

const CONTROL_WIDTH := 390
const PORT_ERROR_COLOR := Color(1, 0.55, 0.5)

## Set by the main menu before the card enters the tree.
var hosting := false

var _teams_label: Label
var _port_edit: LineEdit
var _note: Label
var _local_rows: Array[Control] = []  # host: the rows only hosting on this computer has
var _key_row: Control  # host: the friends key, online only
var _key_edit: LineEdit
var _first: Control  # focused when the card opens

@onready var rows: VBoxContainer = %Rows
@onready var start_button: Button = %StartButton


func _ready() -> void:
	(%BackButton as Button).pressed.connect(func() -> void: closed.emit())
	start_button.pressed.connect(_start)
	if hosting:
		_build_host()
	else:
		_build_solo()
	_first.grab_focus()
	Ui.play("ui_open")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		closed.emit()
		accept_event()


# --- Solo ----------------------------------------------------------------------

func _build_solo() -> void:
	(%Title as Label).text = tr("Play solo")
	(%Intro as Label).text = tr("A match against bots on this computer. Nobody else can join.")
	start_button.text = tr("Start")
	_choices(tr("I'd like to play"), "solo_role", [[Role.Kind.NONE, tr("Any")],
		[Role.Kind.SUPERVISOR, tr("Supervisor")], [Role.Kind.RAT, tr("Rat")]])
	_team_rows("solo_supervisors", "solo_rats")
	_choices(tr("Bots"), "solo_difficulty", _difficulties())
	_teams_label = _muted(rows)
	_note = _muted(%Col)
	_note.text = tr("The match doesn't pause: Esc only opens the menu.")
	%Col.move_child(_note, start_button.get_index())
	_refresh()


# --- Host ----------------------------------------------------------------------

func _build_host() -> void:
	(%Title as Label).text = tr("Host a game")
	start_button.text = tr("Host")
	_choices(tr("Where"), "host_online", [[false, tr("This computer")], [true, tr("Online server")]])
	var default_name := LocalServer.default_host_name(MainMenu.player_name())
	var name_edit := _line_edit(Config.host_name if Config.host_name != "" else default_name, LanDiscovery.MAX_NAME)
	name_edit.text_changed.connect(func(text: String) -> void:
		Config.set_value("host_name", "" if text.strip_edges() == default_name else text))  # (the default follows the player's name)
	_row(tr("Name"), name_edit)
	var password := _line_edit(Config.host_password, 40)
	password.placeholder_text = tr("None: anyone can join")
	password.text_changed.connect(func(text: String) -> void: Config.set_value("host_password", text))
	_row(tr("Password"), password)
	var players := []
	for count in range(2, Config.HOST_MAX_PLAYERS + 1):
		players.append([count, str(count)])
	_row(tr("Most players"), _option("host_max_players", players))
	_team_rows("host_supervisors", "host_rats")
	# One row for both: no bots, or bots of a difficulty (host_bots + host_difficulty).
	_choice_row(tr("Bots"), [[-1, tr("None")]] + _difficulties(), Config.host_difficulty if Config.host_bots else -1,
		func(value: int) -> void:
			Config.set_value("host_bots", value >= 0)
			if value >= 0:
				Config.set_value("host_difficulty", value))
	_teams_label = _muted(rows)
	_port_edit = _line_edit(str(Config.host_port), 5)
	_port_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	_local_rows.append(_row(tr("UDP port"), _port_edit))
	var lan := CheckButton.new()
	lan.button_pressed = Config.host_lan
	lan.toggled.connect(func(on: bool) -> void: Config.set_value("host_lan", on))
	var lan_row := _row(tr("Show it on the local network"), lan)
	_local_rows.append(lan_row)
	lan.custom_minimum_size = Vector2.ZERO
	lan.size_flags_horizontal = Control.SIZE_SHRINK_END
	lan_row.get_child(0).mouse_filter = Control.MOUSE_FILTER_STOP
	(lan_row.get_child(0) as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			lan.button_pressed = not lan.button_pressed)  # clicking the label flips it too
	_key_edit = _line_edit(OnlineClient.key(), 200)
	_key_edit.secret = true
	_key_edit.placeholder_text = tr("Ask whoever runs the server")
	_key_edit.text_changed.connect(func(text: String) -> void:
		Config.set_value("online_key", text)
		_refresh())
	_key_row = _row(tr("Friends key"), _key_edit)
	_note = _muted(%Col)
	%Col.move_child(_note, start_button.get_index())
	_refresh()


## The port typed, or 0 if it isn't one we can use (1024 to 65535).
func _typed_port() -> int:
	var text := _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() and text.to_int() >= 1024 and text.to_int() <= 65535 else 0


# --- Both ----------------------------------------------------------------------

func _refresh() -> void:
	if hosting:
		var teams := Ui.teams_text(Config.host_supervisors, Config.host_rats)
		_teams_label.text = (tr("Bots take the empty seats: %s and %s in all.") if Config.host_bots
			else tr("Without bots, matches have up to %s and %s, depending on who joins.")) % teams \
			+ _lone_rat_note(Config.host_rats)
		var online := Config.host_online
		for row in _local_rows:
			row.visible = not online
		_key_row.visible = online
		if online:
			(%Intro as Label).text = tr("The online server (%s) runs the game and you play in it. It keeps going when you leave, and stops a few minutes after the last player left.") \
				% OnlineClient.host_label()
			start_button.disabled = _key_edit.text.strip_edges() == ""
			_note.text = tr("Friends find it in Join a game > Online. They need the same friends key.")
			return
		(%Intro as Label).text = tr("Your computer runs the game and you play in it. When you leave, the game ends for everyone.")
		var port := _typed_port()
		if port > 0:
			_port_edit.remove_theme_color_override("font_color")
		else:
			_port_edit.add_theme_color_override("font_color", PORT_ERROR_COLOR)
		start_button.disabled = port == 0
		_note.text = tr("Friends on your network find it in their server browser. Over the internet, they need your public address, and UDP port %s must be forwarded to this computer on your router.") \
			% (str(port) if port > 0 else "?")
	else:
		var bots := Config.solo_supervisors + Config.solo_rats - 1
		var teams := Ui.teams_text(Config.solo_supervisors, Config.solo_rats)
		_teams_label.text = (tr("You and 1 bot: %s and %s.") % teams if bots == 1
			else tr("You and %d bots: %s and %s.") % ([bots] + teams)) + _lone_rat_note(Config.solo_rats)


## A lone rat can't sabotage the critical machines: their two levers need two rats (GDD §4.3).
func _lone_rat_note(rats: int) -> String:
	return " " + tr("A lone rat can't sabotage the critical machines: their two levers need two rats.") if rats == 1 else ""


func _start() -> void:
	if hosting and Config.host_online:
		if _key_edit.text.strip_edges() == "":
			Ui.play("ui_error")
			_key_edit.grab_focus()
			return
		var options := LocalServer.host_options(MainMenu.player_name())
		options["online"] = true
		start_requested.emit(LocalServer.Mode.HOST, options)
	elif hosting:
		var port := _typed_port()
		if port == 0:
			Ui.play("ui_error")
			_port_edit.grab_focus()
			return
		Config.set_value("host_port", port)
		start_requested.emit(LocalServer.Mode.HOST, LocalServer.host_options(MainMenu.player_name()))
	else:
		start_requested.emit(LocalServer.Mode.SOLO, LocalServer.solo_options())


func _difficulties() -> Array:
	return [[0, tr("Easy")], [1, tr("Normal")], [2, tr("Hard")]]


# --- Row builders --------------------------------------------------------------

func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(label)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, CONTROL_WIDTH)
	row.add_child(control)
	rows.add_child(row)
	if _first == null:
		_first = control.get_child(0) as Control if control is HBoxContainer else control
	return row


## The Supervisors and Rats rows: the teams' seats, 1 to the most the plant has spawn points for.
func _team_rows(supervisors_key: String, rats_key: String) -> void:
	_stepper(tr("Supervisors"), supervisors_key, MatchRules.SUPERVISORS_LIMIT)
	_stepper(tr("Rats"), rats_key, MatchRules.RATS_LIMIT)


## A row with − count + for an int setting from 1 to `most` (too many values for ChoiceButtons).
## Holding Shift steps by 5.
func _stepper(text: String, key: String, most: int) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var count := Label.new()
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count.add_theme_font_size_override("font_size", 22)
	var buttons: Array[Button] = []
	var show := func() -> void:
		var value: int = Config.get(key)
		count.text = str(value)
		buttons[0].disabled = value <= 1
		buttons[1].disabled = value >= most
	for step: int in [-1, 1]:
		var button := Button.new()
		button.text = "−" if step < 0 else "+"
		button.tooltip_text = tr("Shift: 5 at a time")
		button.theme_type_variation = &"ChoiceButton"
		button.add_theme_font_size_override("font_size", 22)
		button.custom_minimum_size.x = 64
		button.pressed.connect(func() -> void:
			var by := step * (5 if Input.is_key_pressed(KEY_SHIFT) else 1)
			Config.set_value(key, clampi(int(Config.get(key)) + by, 1, most))
			show.call()
			_refresh())
		buttons.append(button)
	box.add_child(buttons[0])
	box.add_child(count)
	box.add_child(buttons[1])
	show.call()
	_row(text, box)


## A row of ChoiceButtons (one chosen, yellow) for an int setting. `items`: [[value, text], …].
func _choices(text: String, key: String, items: Array) -> void:
	_choice_row(text, items, Config.get(key), func(value: Variant) -> void: Config.set_value(key, value))


## A row of ChoiceButtons with `selected` chosen; `on_pick(value)` saves a pick (then the card refreshes).
func _choice_row(text: String, items: Array, selected: Variant, on_pick: Callable) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for item: Array in items:
		var button := Button.new()
		button.text = item[1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.theme_type_variation = &"ChoiceButton"
		button.add_theme_font_size_override("font_size", 17)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = selected == item[0]
		button.pressed.connect(func() -> void:
			on_pick.call(item[0])
			_refresh())
		box.add_child(button)
	_row(text, box)


## `items`: [[value, shown text], …] for an int setting.
func _option(key: String, items: Array) -> OptionButton:
	var option := OptionButton.new()
	option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	option.fit_to_longest_item = false
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for i in items.size():
		option.add_item(str(items[i][1]), i)
		option.set_item_metadata(i, items[i][0])
		if items[i][0] == Config.get(key):
			option.select(i)
	option.item_selected.connect(func(i: int) -> void: Config.set_value(key, option.get_item_metadata(i)))
	return option


func _line_edit(text: String, max_length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.max_length = max_length
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	edit.text_submitted.connect(func(_t: String) -> void: _start())
	return edit


func _muted(parent: Node) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(label)
	return label
