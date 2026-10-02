class_name Trap
extends Area3D
## A supervisor's trap on the floor (GDD §5.1), spawned by ItemService through the Dynamic
## spawner. The server watches for rats stepping on it:
##   snap  STUNNED 3 s and a loud SNAP every supervisor hears (on_trap_snap), then consumed
##   lure  REVEALED 10 s (outlined through walls for supervisors), then consumed
## A rat that can't be stunned right now (invulnerable, stun immunity) doesn't set off a snap trap.
## The numbers come from the matching AbilityData (snap_trap / cheese_lure).

const ABILITY_FOR := {"snap": &"snap_trap", "lure": &"cheese_lure"}

var trap_kind := "snap"
var owner_peer := 0
var _sprung := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false
	monitoring = Net.is_server
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.3, 0.5)
	shape.shape = box
	shape.position.y = 0.15
	add_child(shape)
	_build_look()
	if Net.is_server:
		body_entered.connect(_on_body_entered)


func _on_body_entered(node: Node3D) -> void:
	var rat := node as Player
	if _sprung or rat == null or rat.role != Role.Kind.RAT \
			or rat.status.has(StatusComponent.Status.CARRIED) or rat.status.has(StatusComponent.Status.CAGED):
		return
	var data := Role.data(Role.Kind.SUPERVISOR).ability(ABILITY_FOR[trap_kind])
	if not rat.status.apply(data.status, data.status_duration):
		return  # immune or invulnerable: the trap stays armed
	_sprung = true
	Session.current.items.trap_sprung(self, rat)
	queue_free()  # the Dynamic spawner removes it on clients too


func _build_look() -> void:
	Art.add(self, "snap_trap" if trap_kind == "snap" else "cheese_lure", Transform3D.IDENTITY)
