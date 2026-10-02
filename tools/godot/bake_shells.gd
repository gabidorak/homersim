extends SceneTree
## Bakes the plant's CSG shells (levels/plant/shells/*Shell.tscn, written by tools/map/gen_plant.py)
## into static resources the POI scenes use: levels/plant/baked/<Poi>_shell.res (an ArrayMesh, one
## surface per material) and <Poi>_shell_col.res (a ConcavePolygonShape3D). CSG is handy for cutting
## doors and duct insides, but slow to rebuild at load time and not meant for shipping.
##   godot --headless -s tools/godot/bake_shells.gd

const SHELL_DIR := "res://levels/plant/shells/"
const BAKED_DIR := "res://levels/plant/baked/"
const SETTLE_FRAMES := 3  ## CSG rebuilds its mesh deferred, after entering the tree

var _shells: Dictionary[String, CSGShape3D] = {}
var _frames := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(BAKED_DIR)
	for file in DirAccess.get_files_at(SHELL_DIR):
		if not file.ends_with("Shell.tscn"):
			continue
		var shell := (load(SHELL_DIR + file) as PackedScene).instantiate() as CSGShape3D
		root.add_child(shell)
		_shells[file.trim_suffix("Shell.tscn")] = shell


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var failed := 0
	for poi: String in _shells:
		var shell := _shells[poi]
		var mesh := shell.bake_static_mesh()
		var shape := shell.bake_collision_shape()
		if mesh == null or shape == null or mesh.get_surface_count() == 0:
			printerr("bake_shells: %s produced no geometry" % poi)
			failed += 1
			continue
		var tris := 0
		for i in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(i) / 3 if mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_INDEX == 0 \
				else mesh.surface_get_array_index_len(i) / 3
		mesh.resource_name = poi + "Shell"
		var err := ResourceSaver.save(mesh, BAKED_DIR + poi + "_shell.res", ResourceSaver.FLAG_COMPRESS)
		err = maxi(err, ResourceSaver.save(shape, BAKED_DIR + poi + "_shell_col.res", ResourceSaver.FLAG_COMPRESS))
		if err != OK:
			printerr("bake_shells: cannot save %s: %s" % [poi, error_string(err)])
			failed += 1
			continue
		print("bake_shells: %-14s %2d surfaces, %6d triangles, %6d collision faces" % [
			poi, mesh.get_surface_count(), tris, shape.get_faces().size() / 3])
	print("bake_shells: %d shells baked%s" % [_shells.size() - failed, (", %d FAILED" % failed) if failed else ""])
	quit(1 if failed else 0)
	return true
