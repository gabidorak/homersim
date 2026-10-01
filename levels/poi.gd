class_name Poi
extends Node3D
## A point of interest of the plant (one sub-scene per POI in levels/plant/pois/). `bounds` are the
## boxes it covers (world space: the POI scenes sit at the origin), so anyone can ask which POI a
## position is in: the debug overlay (F3) and the server's heatmap log do.
## A scene covering several named areas (the corridors) lists one name per box in `area_names`.

const GROUP := "pois"

@export var display_name := ""
@export var bounds: Array[AABB] = []
@export var area_names := PackedStringArray()


func _enter_tree() -> void:
	add_to_group(GROUP)


## The name of the area at `pos` in this POI, or "" if it isn't inside.
func area_at(pos: Vector3) -> String:
	for i in bounds.size():
		if bounds[i].has_point(pos):
			return area_names[i] if i < area_names.size() else display_name
	return ""


## The name of the smallest POI area containing `pos`, or "" (outside every POI).
static func name_at(tree: SceneTree, pos: Vector3) -> String:
	var best := ""
	var best_volume := INF
	for node in tree.get_nodes_in_group(GROUP):
		var poi := node as Poi
		for i in poi.bounds.size():
			var box := poi.bounds[i]
			if box.has_point(pos) and box.get_volume() < best_volume:
				best_volume = box.get_volume()
				best = poi.area_names[i] if i < poi.area_names.size() else poi.display_name
	return best
