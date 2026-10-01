class_name Ladder
extends Area3D
## A climbable volume (the vent roof ladder, the rats' shaft). Not an interactable: walking into it
## is enough. The node's -Z axis points "up the ladder": into the wall it is fixed to, toward where
## a climber ends up at the top. MovementComponent does the climbing (owner client):
##   push toward -Z         climb up (and at the top, step off onto the roof)
##   push away (+Z) in air  climb down
##   no input in the air    hang on
##   jump                   let go, pushed off the ladder
## Rats and supervisors both climb; the shaft's 0.7 m opening keeps supervisors out anyway.

const GROUP := "ladders"

@export var climb_speed := 3.0  ## m/s up and down


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false


## The direction a climber pushes to go up (horizontal, unit length).
func up_direction() -> Vector3:
	var dir := -global_basis.z
	dir.y = 0.0
	return dir.normalized()


## The ladder `body` is in, or null.
static func find(body: PhysicsBody3D) -> Ladder:
	for node in body.get_tree().get_nodes_in_group(GROUP):
		if (node as Ladder).overlaps_body(body):
			return node
	return null
