extends Control
## The card before "Play solo" and "Host a game" (main menu): the choices for the server this game
## starts itself (client/local_server.gd). Every change is saved at once (Config.solo_* / host_*), so
## the card opens with the last choices. Start emits start_requested; the main menu does the rest.
##   Solo: the role you'd like, the bots' difficulty, the match size (you + bots).
##   Host: the game's name, a password, the most players, the bots (off or fill up to N players) and
##   their difficulty, the UDP port, and whether the game shows on the local network.

signal closed
signal start_requested(mode: LocalServer.Mode, options: Dictionary)

const CONTROL_WIDTH := 330
const PORT_ERROR_COLOR := Color(1, 0.55, 0.5)

## Set by the main menu before the card enters the tree.
var hosting := false

var _difficulty_buttons: Array[Button] = []
var _teams_label: Label
var _port_edit: LineEdit
var _note: Label
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
	_difficulty_buttons = _choices(tr("Bots"), "solo_difficulty", _difficulties())
	var sizes := []
	for players in range(Config.SOLO_PLAYERS_MIN, Config.BOT_FILL_MAX + 1):
		sizes.append([players, tr("%d players") % players])
	_choices(tr("Match size"), "solo_players", sizes)
	_teams_label = _muted(rows)
	_note = _muted(%Col)
	_note.text = tr("The match doesn't pause: Esc only opens the menu.")
	%Col.move_child(_note, start_button.get_index())
	_refresh()


# --- Host ----------------------------------------------------------------------

func _build_host() -> void:
	(%Title as Label).text = tr("Host a game")
	(%Intro as Label).text = tr("Your computer runs the game and you play in it. When you leave, the game ends for everyone.")
	start_button.text = tr("Host")
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
	var bots := [[0, tr("No bots")]]
	for fill in range(Config.SOLO_PLAYERS_MIN, Config.BOT_FILL_MAX + 1):
		bots.append([fill, tr("Fill up to %d players") % fill])
	var bots_option := _option("host_bots", bots)
	bots_option.item_selected.connect(func(_i: int) -> void: _refresh())
	_row(tr("Bots"), bots_option)
	_difficulty_buttons = _choices(tr("Bot difficulty"), "host_difficulty", _difficulties())
	_teams_label = _muted(rows)
	_port_edit = _line_edit(str(Config.host_port), 5)
	_port_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	_row(tr("UDP port"), _port_edit)
	var lan := CheckButton.new()
	lan.button_pressed = Config.host_lan
	lan.toggled.connect(func(on: bool) -> void: Config.set_value("host_lan", on))
	var lan_row := _row(tr("Show it on the local network"), lan)
	lan.custom_minimum_size = Vector2.ZERO
	lan.size_flags_horizontal = Control.SIZE_SHRINK_END
	lan_row.get_child(0).mouse_filter = Control.MOUSE_FILTER_STOP
	(lan_row.get_child(0) as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			lan.button_pressed = not lan.button_pressed)  # clicking the label flips it too
	_note = _muted(%Col)
	%Col.move_child(_note, start_button.get_index())
	_refresh()


## The port typed, or 0 if it isn't one we can use (1024 to 65535).
func _typed_port() -> int:
	var text := _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() and text.to_int() >= 1024 and text.to_int() <= 65535 else 0


# --- Both ----------------------------------------------------------------------

func _refresh() -> void:
	var rules: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	if hosting:
		var fill := Config.host_bots
		for button in _difficulty_buttons:
			button.disabled = fill == 0
		_teams_label.visible = fill > 0
		_teams_label.text = tr("Bots take the empty seats: %s and %s in all.") % _teams_text(fill, rules)
		var port := _typed_port()
		if port > 0:
			_port_edit.remove_theme_color_override("font_color")
		else:
			_port_edit.add_theme_color_override("font_color", PORT_ERROR_COLOR)
		start_button.disabled = port == 0
		_note.text = tr("Friends on your network find it in their server browser. Over the internet, they need your public address, and UDP port %s must be forwarded to this computer on your router.") \
			% (str(port) if port > 0 else "?")
	else:
		_teams_label.text = tr("You and %d bots: %s and %s.") % ([Config.solo_players - 1] + _teams_text(Config.solo_players, rules))


## ["2 supervisors", "4 rats"] for a match of `players`.
func _teams_text(players: int, rules: MatchRules) -> Array:
	var teams := LocalServer.teams_for(players, rules)
	return [tr("1 supervisor") if teams[0] == 1 else tr("%d supervisors") % teams[0],
		tr("1 rat") if teams[1] == 1 else tr("%d rats") % teams[1]]


func _start() -> void:
	if hosting:
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


## A row of ChoiceButtons (one chosen, yellow) for an int setting. `items`: [[value, text], …].
func _choices(text: String, key: String, items: Array) -> Array[Button]:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for item: Array in items:
		var button := Button.new()
		button.text = item[1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.theme_type_variation = &"ChoiceButton"
		button.add_theme_font_size_override("font_size", 17)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = Config.get(key) == item[0]
		button.pressed.connect(func() -> void:
			Config.set_value(key, item[0])
			_refresh())
		box.add_child(button)
		buttons.append(button)
	_row(text, box)
	return buttons


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
