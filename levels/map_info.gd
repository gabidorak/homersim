class_name MapInfo
extends Node
## Points the in-game map at this level's plan (LevelMap). A level without one has no map.

const GROUP := "map_info"

@export var plan: LevelMap


func _enter_tree() -> void:
	add_to_group(GROUP)


## The plan of the level in `tree`, or null.
static func plan_in(tree: SceneTree) -> LevelMap:
	var info := tree.get_first_node_in_group(GROUP) as MapInfo
	return info.plan if info != null else null
