class_name Player
extends CharacterBody3D
## A networked player body. M1: a single temporary role, drawn as a capsule.
##
## The owning client (multiplayer authority = its peer id) simulates movement and writes the
## sync_* properties; BodySync replicates them at 20 Hz. Everyone else smoothly moves the body
## toward the latest synced values in _process, which hides the gaps between updates.

const INTERP_RATE := 15.0  ## higher = snappier, lower = smoother but more behind
const SNAP_DISTANCE := 5.0  ## farther than this (teleport, respawn): jump instead of gliding

var peer_id := 0
var display_name := ""

## Written by the owner every physics tick, replicated by BodySync.
var sync_position := Vector3.ZERO
var sync_yaw := 0.0
var sync_pitch := 0.0

@onready var rig: FirstPersonRig = $CameraRig
@onready var name_tag: Label3D = $NameTag
@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var visor: MeshInstance3D = $CameraRig/Visor


static func color_for_peer(id: int) -> Color:
	return Color.from_hsv(fmod(id * 0.618034, 1.0), 0.65, 0.95)


func _ready() -> void:
	# Run after the MovementComponent child, so we publish this tick's result.
	process_physics_priority = 10
	sync_position = position
	sync_yaw = rotation.y
	name_tag.text = display_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for_peer(peer_id)
	body_mesh.material_override = mat
	if is_local():
		# Our own body would only get in the way of the camera.
		visual.visible = false
		visor.visible = false
		name_tag.visible = false
		Events.local_player_spawned.emit(self)
	Log.info("player", "spawned %s (peer %d)%s" % [display_name, peer_id, " [local]" if is_local() else ""])


func _exit_tree() -> void:
	Log.info("player", "despawned %s (peer %d)" % [display_name, peer_id])


func is_local() -> bool:
	return is_multiplayer_authority()


func _physics_process(_delta: float) -> void:
	if is_local():
		sync_position = position
		sync_yaw = rotation.y
		sync_pitch = rig.rotation.x


func _process(delta: float) -> void:
	if is_local():
		return
	# The server doesn't render, so it keeps the exact latest position (it will check it later).
	if multiplayer.is_server() or position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
		rotation.y = sync_yaw
		rig.rotation.x = sync_pitch
		return
	var weight := 1.0 - exp(-INTERP_RATE * delta)  # frame-rate independent smoothing
	position = position.lerp(sync_position, weight)
	rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
	rig.rotation.x = lerp_angle(rig.rotation.x, sync_pitch, weight)
