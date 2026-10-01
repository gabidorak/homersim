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
	var mat := StandardMaterial3D.new()
	var mesh := MeshInstance3D.new()
	if trap_kind == "snap":
		var plate := BoxMesh.new()
		plate.size = Vector3(0.4, 0.04, 0.25)
		mat.albedo_color = Color(0.65, 0.5, 0.3)
		plate.material = mat
		mesh.mesh = plate
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.36, 0.03, 0.03)
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.8, 0.8, 0.85)
		metal.metallic = 0.8
		bar_mesh.material = metal
		bar.mesh = bar_mesh
		bar.position = Vector3(0, 0.04, -0.08)
		add_child(bar)
	else:
		var wedge := PrismMesh.new()
		wedge.size = Vector3(0.3, 0.18, 0.2)
		mat.albedo_color = Color(1, 0.85, 0.2)
		wedge.material = mat
		mesh.mesh = wedge
	mesh.position.y = 0.05
	add_child(mesh)
