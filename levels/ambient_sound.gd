class_name AmbientSound
extends Marker3D
## A looping positional sound placed in the level (machinery hum, crickets, dripping), by name from
## Sfx. Clients only: the headless server plays nothing.

@export var sound := "hum_room"
@export var volume_db := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player := Sfx.loop_player(self, sound, volume_db)
	# Start each loop somewhere different, so neighbouring hums don't phase together.
	var length := player.stream.get_length() if player.stream != null else 0.0
	player.play(randf() * length * 0.9)
