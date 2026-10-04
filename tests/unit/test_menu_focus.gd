extends GutTest
## Keyboard navigation (M8): every menu screen opens with something focused, and the arrow keys walk
## through its controls without the focus getting lost or leaving the screen. (Headless: layout and
## focus work without rendering.)

const SCREENS := {
	"settings": "res://client/Settings.tscn",
	"browser": "res://client/ServerBrowser.tscn",
	"how_to": "res://client/HowToPlay.tscn",
	"credits": "res://client/Credits.tscn",
}

var _name_before := ""


func before_all() -> void:
	_name_before = Config.player_name
	Config.player_name = "Tester"  # (no welcome box on the main menu)


func after_all() -> void:
	Config.player_name = _name_before


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


func _walk(screen: Control, action: StringName, steps: int) -> Array[Control]:
	var seen: Array[Control] = []
	for i in steps:
		_press(action)
		await get_tree().process_frame
		var owner := get_viewport().gui_get_focus_owner()
		assert_not_null(owner, "%s: focus kept after %s #%d" % [screen.name, action, i + 1])
		if owner == null:
			break
		assert_true(screen.is_ancestor_of(owner), "%s: focus stays on the screen (%s)" % [screen.name, owner.name])
		if not seen.has(owner):
			seen.append(owner)
	return seen


func _open(path: String) -> Control:
	var screen := (load(path) as PackedScene).instantiate() as Control
	add_child_autofree(screen)
	for i in 4:
		await get_tree().process_frame
	return screen


func test_main_menu_buttons() -> void:
	var menu := await _open("res://client/MainMenu.tscn")
	assert_eq(get_viewport().gui_get_focus_owner(), menu.get_node("%PlayButton"), "Join a game is focused first")
	var seen := await _walk(menu, &"ui_down", 6)
	assert_eq(seen.size(), 6, "down goes through Play solo, Host a game, How to play, Settings, Credits, Quit")
	assert_eq(seen[0], menu.get_node("%SoloButton"))
	assert_eq(seen[-1], menu.get_node("%QuitButton"))


## The Play solo and Host a game cards (GameSetup): built in code, so check they're walkable too.
func test_game_setup_cards_walk() -> void:
	for hosting in [false, true]:
		var card := (load("res://client/GameSetup.tscn") as PackedScene).instantiate() as Control
		card.set("hosting", hosting)
		add_child_autofree(card)
		for i in 4:
			await get_tree().process_frame
		var label := "host card" if hosting else "solo card"
		assert_not_null(get_viewport().gui_get_focus_owner(), "%s: something is focused when it opens" % label)
		var seen := await _walk(card, &"ui_down", 10)
		assert_gt(seen.size(), 4 if hosting else 2, "%s: down reaches every row" % label)
		assert_true(seen.has(card.get_node("%StartButton")), "%s: and the start button" % label)
		card.queue_free()
		await get_tree().process_frame


func test_each_screen_walks() -> void:
	for key: String in SCREENS:
		var screen := await _open(SCREENS[key])
		assert_not_null(get_viewport().gui_get_focus_owner(), "%s: something is focused when it opens" % key)
		var seen := await _walk(screen, &"ui_down", 6)
		seen.append_array(await _walk(screen, &"ui_right", 3))
		# (How to play and Credits are a tab bar or a text and one button.)
		assert_gt(seen.size(), 1 if key in ["credits", "how_to"] else 2, "%s: the arrows reach several controls" % key)
		screen.queue_free()
		await get_tree().process_frame


func test_message_dialog_keeps_the_focus() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(host)
	var outside := Button.new()
	host.add_child(outside)
	var box := MessageDialog.confirm(host, "Leave?", "Sure?", "Leave", "Stay")
	await get_tree().process_frame
	await get_tree().process_frame
	var seen := await _walk(box, &"ui_left", 2)
	assert_true(seen.has(box.cancel_button), "left reaches Cancel")
	assert_ne(get_viewport().gui_get_focus_owner(), outside, "never the button behind the box")
	var closed := []
	box.closed.connect(func(ok: bool, _t: String) -> void: closed.append(ok))
	_press(&"ui_cancel")
	await get_tree().process_frame
	assert_eq(closed, [false], "Esc / cancel answers no")
