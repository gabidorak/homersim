class_name OverviewCamera
extends Camera3D
## A fixed camera over the arena, used whenever this client has no body of its own
## (spectating, or the moment between despawn and respawn), so the screen is never empty.

const VIEW_POSITION := Vector3(0, 24, 26)
const LOOK_AT := Vector3(0, 0, 2)


func _ready() -> void:
	position = VIEW_POSITION
	look_at_from_position(VIEW_POSITION, LOOK_AT)


func _process(_delta: float) -> void:
	if get_viewport().get_camera_3d() == null:
		make_current()
