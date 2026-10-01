class_name VentVolume
extends Area3D
## Marks rat-only space inside a vent. Supervisors physically can't fit through the 0.7 m wide,
## 0.6 m high openings; the server's MovementValidator also flags any non-rat body overlapping a
## VentVolume (a cheater or a level bug). The local rat's camera pulls in while inside one.
##
## Keep the box inside the opening and about 0.1 m short of its ends, so a supervisor pressed
## against the opening doesn't touch it.

const GROUP := "vent_volumes"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false


## True if `body` overlaps any vent volume in its scene tree.
static func contains(body: PhysicsBody3D) -> bool:
	for node in body.get_tree().get_nodes_in_group(GROUP):
		if (node as VentVolume).overlaps_body(body):
			return true
	return false
