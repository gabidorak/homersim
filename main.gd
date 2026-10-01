extends Node
## Entry point: dedicated server or client.


func _ready() -> void:
	if OS.has_feature("dedicated_server") or Cli.has_arg("server"):
		get_tree().change_scene_to_file.call_deferred("res://server/ServerMain.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://client/MainMenu.tscn")
