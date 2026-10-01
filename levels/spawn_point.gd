class_name SpawnPoint
extends Marker3D
## Where a body of `role` can spawn (NONE = lobby bodies). Its rotation sets the facing.

const GROUP := "spawn_points"

@export var role := Role.Kind.NONE


func _enter_tree() -> void:
	add_to_group(GROUP)
