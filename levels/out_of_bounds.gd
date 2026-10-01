class_name OutOfBounds
extends Area3D
## A kill volume: a body that ends up inside one (fell off the map, jumped onto a roof) is put back
## where it last stood safely. The owning client does that itself (MovementComponent), like any of
## its own movement; the server's MovementValidator doesn't count that jump back as cheating.
## Shapes must be unrotated boxes (contains_point() checks them as AABBs).

const GROUP := "out_of_bounds"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false


## True if `body` overlaps any out-of-bounds volume.
static func contains(body: PhysicsBody3D) -> bool:
	for node in body.get_tree().get_nodes_in_group(GROUP):
		if (node as OutOfBounds).overlaps_body(body):
			return true
	return false


## True if `pos` is inside any out-of-bounds volume (no physics needed: the validator uses it on
## past positions).
static func contains_point(tree: SceneTree, pos: Vector3) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		for child in (node as Node).get_children():
			var shape := child as CollisionShape3D
			if shape != null and shape.shape is BoxShape3D:
				var size := (shape.shape as BoxShape3D).size
				if AABB(shape.global_position - size * 0.5, size).has_point(pos):
					return true
	return false
