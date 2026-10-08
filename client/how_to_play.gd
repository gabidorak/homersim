extends Control
## How to play (M8): the goal, two illustrated cards per role, and the controls as currently bound
## (the texts name the player's own keys, so they stay right after rebinding). From the main menu
## and the pause menu. Illustrations: assets/ui/howto/*.png (staged in-game shots, see
## tests/helpers/HowToShots.tscn).

signal closed

const ART := "res://assets/ui/howto/%s.png"

## Opened from the pause menu: dims the game behind it.
var in_game := false

@onready var tabs: TabContainer = %Tabs


func _ready() -> void:
	(%Dim as Control).visible = in_game
	(%BackButton as Button).pressed.connect(func() -> void: closed.emit())
	_build()
	tabs.get_tab_bar().grab_focus()
	Ui.play("ui_open")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		closed.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build.call_deferred()  # (children can't change while the notification goes down the tree)


## Opens on a role's tab (the hints' "more" link).
func show_role(role: Role.Kind) -> void:
	tabs.current_tab = 1 if role == Role.Kind.RAT else 0


func _build() -> void:
	var keep := maxi(tabs.current_tab, 0)
	for child in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	(%Goal as Label).text = tr("One or two supervisors must keep the nuclear plant running until their shift ends. Three or four rats sneak through the vents and sabotage it until the meltdown meter hits 100%. Machines that break spray steam, sparks and radiation, and those hurt everyone.")
	var interact := Keys.label(&"interact")
	var primary := Keys.label(&"primary")
	var secondary := Keys.label(&"secondary")
	_role_tab(tr("Supervisor"), [
		["supervisor_repair", tr("Keep the plant alive"),
			tr("Damaged machines heat up the core. Press %s at a machine's repair panel and win the short minigame to fix it. Keep the meltdown meter (top of the screen) away from 100%% until the shift timer runs out. The Control Room has emergency coolant and a SCRAM button for bad moments.") % interact],
		["supervisor_catch", tr("Bonk, carry, cage"),
			tr("Swing your broom with %s to stun a rat, press %s to pick it up, and carry it to a cage in the Cage Room or the Reactor Hall (%s at the cage). A caged rat stays there until another rat frees it, however many times it was caught. Hold %s, then release, to place a trap: a snap trap stuns a rat, a cheese lure shows it through walls and on your map. Grab a donut in the Break Room and eat it when you need a burst of speed (select it, then %s).") % [primary, interact, interact, secondary, interact]],
	])
	_role_tab(tr("Rat"), [
		["rat_sabotage", tr("Sabotage!"),
			tr("Sneak through the vents to the machines and hold %s at their red junction boxes. The critical machines (control rods, turbine) need two rats pulling their levers at the same time. Each broken machine pushes the meltdown meter up: reach 100%% and the rats win.") % interact],
		["rat_bite", tr("Bite, steal, rescue"),
			tr("Bite supervisors with %s: one bite makes them drop the rat they carry, and 3 bites within 6 seconds knock them down. Hold %s behind a supervisor to steal their keycard: without it they lose their shortcut doors. A friend in a cage? Hold %s at the cage to set them free.") % [primary, interact, interact]],
	])
	_controls_tab()
	tabs.current_tab = keep


func _role_tab(title: String, cards: Array) -> void:
	var row := HBoxContainer.new()
	row.name = title.validate_node_name()
	row.add_theme_constant_override("separation", 18)
	for card: Array in cards:
		row.add_child(_card(card[0], card[1], card[2]))
	tabs.add_child(row)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)


func _card(art: String, title: String, text: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.custom_minimum_size = Vector2(0, 150)
	if ResourceLoader.exists(ART % art):
		picture.texture = load(ART % art)
	col.add_child(picture)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"SubheaderLabel"
	heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(heading)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(260, 0)
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.add_theme_font_size_override("font_size", 17)
	col.add_child(body)
	return panel


func _controls_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var entries: Array = [[tr("Move"), Keys.move_label()], [tr("Look"), tr("Mouse")]]
	for action in Keys.REBINDABLE:
		if action.begins_with("move_") or action.begins_with("debug_"):
			continue
		entries.append([tr(Keys.ACTION_NAMES[action]), Keys.label(action)])
	entries.append([tr("Menu (free the mouse)"), Keys.pause_label()])
	entries.append([tr("Repair minigames (Esc gives up)"), tr("Mouse")])
	for entry: Array in entries:
		var key := Label.new()
		key.text = entry[1]
		key.theme_type_variation = &"SubheaderLabel"
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(110, 0)
		key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		grid.add_child(key)
		var what := Label.new()
		what.text = entry[0]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		grid.add_child(what)
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, tr("Controls"))
