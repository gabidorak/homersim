class_name PropMultiMesh
extends Node3D
## Many copies of one generated model drawn in a single draw call per surface (M7 performance): the
## level generator uses it for long runs of repeated props (high pipes). At _ready it takes the
## model's mesh and builds a MultiMeshInstance3D with one instance per `transforms` entry (relative
## to this node). Clients only; the headless server keeps just the gameplay collision boxes.

@export var model := "pipe_2m"
@export var transforms: Array[Transform3D] = []


func _ready() -> void:
	if Art.headless() or transforms.is_empty():
		return
	var source := Art.instance(model)
	if source == null:
		return
	var meshes := Art.meshes(source)
	for mesh_instance in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_instance.mesh
		mm.instance_count = transforms.size()
		# The part's own offset inside the model, then each copy's transform.
		var local := _relative(source, mesh_instance)
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [model, mesh_instance.name]
		mmi.multimesh = mm
		add_child(mmi)
	source.free()


## A descendant's transform relative to `root` without the tree (the source model isn't added).
static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xform = (n as Node3D).transform * xform
		n = n.get_parent()
	return xform
