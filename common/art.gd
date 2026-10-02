class_name Art
extends RefCounted
## Helpers for the generated models (assets/generated/*.glb, tools/blender/): load one, find its
## named animatable parts, and change a part's colour or glow. Emissive parts (lamps, screens) use the
## tintable toon shader, whose `tint` and `glow` instance uniforms change per instance with no
## material copy; other parts get a tinted copy of their material (cached per colour).

const GENERATED := "res://assets/generated/%s.glb"
const TINTABLE: Shader = preload("res://shaders/toon_tintable.gdshader")

static var _tinted: Dictionary = {}  # [material, colour] -> tinted copy; Session clears it when it leaves


static func exists(model_name: String) -> bool:
	return ResourceLoader.exists(GENERATED % model_name)


## A new instance of assets/generated/<model_name>.glb, or null if it hasn't been generated.
static func instance(model_name: String) -> Node3D:
	# No cache of our own: ResourceLoader keeps loaded scenes, and a static one would still hold
	# them when the process exits ("resources still in use").
	var scene := load(GENERATED % model_name) as PackedScene if exists(model_name) else null
	return scene.instantiate() as Node3D if scene != null else null


## Adds the model under `parent` (with an optional transform); returns it or null.
static func add(parent: Node, model_name: String, xform := Transform3D.IDENTITY, shadows := true) -> Node3D:
	var model := instance(model_name)
	if model == null:
		return null
	model.transform = xform
	parent.add_child(model)
	if not shadows:
		for mesh in meshes(model):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


## The first descendant named `part_name` (a model's animatable part), or null.
static func part(root: Node, part_name: String) -> Node3D:
	if root == null:
		return null
	if root.name == part_name:
		return root as Node3D
	return root.find_child(part_name, true, false) as Node3D


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result


static func set_tint(root: Node, color: Color) -> void:
	if headless() or root == null:
		return
	for mesh in meshes(root):
		if _tintable(mesh):
			mesh.set_instance_shader_parameter(&"tint", color)
		elif mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			var source := mesh.mesh.surface_get_material(0) as ShaderMaterial
			if source == null:
				continue
			var key := [source, color]
			if not _tinted.has(key):
				var copy := source.duplicate() as ShaderMaterial  # shallow: shares the outline pass
				copy.set_shader_parameter(&"albedo", color)
				_tinted[key] = copy
			mesh.material_override = _tinted[key]


## Emissive (tintable) parts only: 0 = off, 1 = normal.
static func set_glow(root: Node, value: float) -> void:
	if headless() or root == null:
		return
	for mesh in meshes(root):
		if _tintable(mesh):
			mesh.set_instance_shader_parameter(&"glow", value)


static func clear_cache() -> void:
	_tinted.clear()


static func _tintable(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	for i in mesh.mesh.get_surface_count():
		var mat := mesh.mesh.surface_get_material(i) as ShaderMaterial
		if mat == null or mat.shader != TINTABLE:
			return false
	return mesh.mesh.get_surface_count() > 0


static func headless() -> bool:
	return DisplayServer.get_name() == "headless"
