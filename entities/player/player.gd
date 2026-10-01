class_name Player
extends CharacterBody3D
## A networked player body. One scene for every role: the spawn function calls setup(role), which
## sizes the collision capsule and instances the role's visual and camera rig (RoleData).
##
## The owning client (multiplayer authority = its peer id) simulates movement and writes the
## sync_* properties; BodySync replicates them at 20 Hz. Everyone else smoothly moves the body
## toward the latest synced values in _process, which hides the gaps between updates.
## StatusComponent and StatusSync stay owned by the server.

const FIRST_PERSON_RIG: PackedScene = preload("res://components/camera/FirstPersonRig.tscn")
const THIRD_PERSON_RIG: PackedScene = preload("res://components/camera/ThirdPersonRig.tscn")
const INTERP_RATE := 15.0  ## higher = snappier, lower = smoother but more behind
const SNAP_DISTANCE := 5.0  ## farther than this (teleport, respawn): jump instead of gliding
const NAME_TAG_GAP := 0.35  ## m above the head
const VALIDATOR_GRACE_S := 1.0  ## after a server-imposed move

var peer_id := 0
var display_name := ""
var role := Role.Kind.NONE
var role_data: RoleData
var rig: CameraRig

## Written by the owner every physics tick, replicated by BodySync.
var sync_position := Vector3.ZERO
var sync_yaw := 0.0
var sync_pitch := 0.0

## Server: the movement validator skips this body until then (Time.get_ticks_msec()).
var validator_grace_until_ms := 0

@onready var name_tag: Label3D = $NameTag
@onready var visual: Node3D = $Visual
@onready var movement: MovementComponent = $MovementComponent
@onready var status: StatusComponent = $StatusComponent


static func color_for_peer(id: int) -> Color:
	return Color.from_hsv(fmod(id * 0.618034, 1.0), 0.65, 0.95)


## Called by the spawn function before the node enters the tree (on the server and every client).
func setup(p_role: Role.Kind) -> void:
	role = p_role
	role_data = Role.data(role)
	var shape := CapsuleShape3D.new()
	shape.radius = role_data.radius
	shape.height = role_data.height
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position.y = role_data.height * 0.5
	add_child(collision)
	$Visual.add_child(role_data.visual_scene.instantiate())
	var third_person := role_data.camera_kind == RoleData.CameraKind.THIRD_PERSON
	rig = (THIRD_PERSON_RIG if third_person else FIRST_PERSON_RIG).instantiate()
	add_child(rig)
	($NameTag as Node3D).position.y = role_data.height + NAME_TAG_GAP


func _ready() -> void:
	if name != str(peer_id):
		Log.error("player", "body for peer %d is named '%s': replication paths will break" % [peer_id, name])
	# Run after the MovementComponent child, so we publish this tick's result.
	process_physics_priority = 10
	# A respawn reuses the node path, so the owner's last position packets for its previous body
	# can still land on this one: don't let the validator judge those.
	_grant_validator_grace()
	sync_position = position
	sync_yaw = rotation.y
	name_tag.text = display_name
	if role == Role.Kind.NONE:
		# Lobby bodies are tinted per player so you can tell them apart.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color_for_peer(peer_id)
		(visual.get_child(0).get_node("Body") as MeshInstance3D).material_override = mat
	if is_local():
		name_tag.visible = false
		# In first person our own body would only get in the way of the camera.
		visual.visible = role_data.camera_kind == RoleData.CameraKind.THIRD_PERSON
		Events.local_player_spawned.emit(self)
	Log.info("player", "spawned %s (peer %d) as %s%s" % [display_name, peer_id, Role.display_name(role),
		" [local]" if is_local() else ""])


func _exit_tree() -> void:
	Log.info("player", "despawned %s (peer %d)" % [display_name, peer_id])


func is_local() -> bool:
	return is_multiplayer_authority()


func _physics_process(_delta: float) -> void:
	if is_local():
		sync_position = position
		sync_yaw = rotation.y
		sync_pitch = rig.look_pitch()


func _process(delta: float) -> void:
	if is_local():
		return
	# The server doesn't render, so it keeps the exact latest position (the validator checks it).
	if multiplayer.is_server() or position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
		rotation.y = sync_yaw
		rig.apply_look_pitch(sync_pitch)
		return
	var weight := 1.0 - exp(-INTERP_RATE * delta)  # frame-rate independent smoothing
	position = position.lerp(sync_position, weight)
	rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
	rig.apply_look_pitch(lerp_angle(rig.look_pitch(), sync_pitch, weight))


# --- Server helpers for server-imposed movement ------------------------------------

func server_force_position(pos: Vector3) -> void:
	_grant_validator_grace()
	movement.force_position.rpc_id(peer_id, pos)


func server_apply_impulse(impulse: Vector3) -> void:
	_grant_validator_grace()
	movement.apply_impulse.rpc_id(peer_id, impulse)


func server_set_locked(value: bool) -> void:
	movement.set_locked.rpc_id(peer_id, value)


func _grant_validator_grace() -> void:
	validator_grace_until_ms = Time.get_ticks_msec() + int(VALIDATOR_GRACE_S * 1000.0)
