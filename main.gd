extends Node
## Entry point: self-update (exported CI builds), then dedicated server, test bot (debug builds),
## or client.

const BOT_SCENE := "res://tests/helpers/BotClient.tscn"  # not exported (tests/ is filtered out)

var _update_label: Label


func _ready() -> void:
	if not Updater.is_enabled():
		_start()
	elif Updater.is_server():
		_start_server_with_updates()
	else:
		_start_client_with_updates()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Updater.is_busy():
		Updater.cancel()  # play this build anyway


func _start() -> void:
	if Updater.is_server():
		get_tree().change_scene_to_file.call_deferred("res://server/ServerMain.tscn")
	elif OS.is_debug_build() and Cli.has_arg("bot"):
		get_tree().change_scene_to_file.call_deferred(BOT_SCENE)
	else:
		get_tree().change_scene_to_file.call_deferred("res://client/MainMenu.tscn")


## The first server process only supervises (see autoload/updater.gd). Its child updates, then serves.
func _start_server_with_updates() -> void:
	if not Updater.is_supervised():
		Updater.supervise()
		return
	if await Updater.update():
		get_tree().quit(Updater.EXIT_RESTART)
		return
	_start()


func _start_client_with_updates() -> void:
	if DisplayServer.get_name() != "headless":
		_update_label = Label.new()
		_update_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_update_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_update_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_update_label)
		Updater.status_changed.connect(_on_update_status)
	if await Updater.update():
		Updater.relaunch()
		get_tree().quit()
		return
	_start()


func _on_update_status(text: String) -> void:
	_update_label.text = text + "\n\n" + tr("Esc: skip and play this version")
