class_name OverviewCamera
extends Camera3D
## A fixed camera over the level, used whenever this client has no body of its own
## (spectating, or the moment between despawn and respawn), so the screen is never empty.
## It looks from the level's "overview_point" marker if there is one.

const VIEW_POSITION := Vector3(0, 24, 26)
const LOOK_AT := Vector3(0, 0, 2)


const POINT_GROUP := "overview_point"


func _ready() -> void:
	var point := get_tree().get_first_node_in_group(POINT_GROUP) as Node3D
	if point != null:
		global_transform = point.global_transform
	else:
		look_at_from_position(VIEW_POSITION, LOOK_AT)


func _process(_delta: float) -> void:
	if get_viewport().get_camera_3d() == null:
		make_current()
