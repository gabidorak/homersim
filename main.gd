extends Node
## Entry point: dedicated server, test bot (debug builds), or client.

const BOT_SCENE := "res://tests/helpers/BotClient.tscn"  # not exported (tests/ is filtered out)


func _ready() -> void:
	if OS.has_feature("dedicated_server") or Cli.has_arg("server"):
		get_tree().change_scene_to_file.call_deferred("res://server/ServerMain.tscn")
	elif OS.is_debug_build() and Cli.has_arg("bot"):
		get_tree().change_scene_to_file.call_deferred(BOT_SCENE)
	else:
		get_tree().change_scene_to_file.call_deferred("res://client/MainMenu.tscn")
