class_name Player
extends CharacterBody3D
## A networked player body. One scene for every role: the spawn function calls setup(role), which
## sizes the collision capsule and instances the role's visual and camera rig (RoleData).
##
## The owning client (multiplayer authority = its peer id) simulates movement and writes the
## sync_* properties; BodySync replicates them at 20 Hz. Everyone else smoothly moves the body
## toward the latest synced values in _process, which hides the gaps between updates.
## StatusComponent, Inventory and StatusSync stay owned by the server.
##
## PvP handles (built by setup): rats get a GrabHandle (supervisors grab them when stunned),
## supervisors get a StealHandle on their back and a HandSocket that a carried rat hangs from.
## A carried rat is drawn at its carrier's HandSocket on every peer.

const FIRST_PERSON_RIG: PackedScene = preload("res://components/camera/FirstPersonRig.tscn")
const THIRD_PERSON_RIG: PackedScene = preload("res://components/camera/ThirdPersonRig.tscn")
const INTERP_RATE := 15.0  ## higher = snappier, lower = smoother but more behind
## Farther than this (teleport, respawn, caged, freed): jump instead of gliding, so the body doesn't
## sweep through bars and shove other players on the way. A sprinting rat covers about 0.4 m per
## BodySync packet, so 2 m still leaves room for a few lost packets.
const SNAP_DISTANCE := 2.0
const NAME_TAG_GAP := 0.35  ## m above the head
const VALIDATOR_GRACE_S := 1.0  ## after a server-imposed move
const HAND_SOCKET_POSITION := Vector3(0.3, 0.75, -0.55)  ## supervisor: where a carried rat hangs
const STATUS_TAG_GAP := 0.25  ## m above the name tag
const REVEAL_MATERIAL: ShaderMaterial = preload("res://shaders/reveal_outline.tres")

var peer_id := 0
var display_name := ""
var role := Role.Kind.NONE
var role_data: RoleData
var rig: CameraRig
var hand_socket: Node3D  ## supervisors only

## Written by the owner every physics tick, replicated by BodySync.
var sync_position := Vector3.ZERO
var sync_yaw := 0.0
var sync_pitch := 0.0
## What the body is doing, for everyone's animations: AnimationController.FLAG_* bits (M7).
var sync_anim := 0

## Clients: the character model's animation and its sounds/particles (null on the server).
var anim: AnimationController
var fx: BodyFx

## Server: the movement validator skips this body until then (Time.get_ticks_msec()).
var validator_grace_until_ms := 0

@onready var name_tag: Label3D = $NameTag
@onready var visual: Node3D = $Visual
@onready var movement: MovementComponent = $MovementComponent
@onready var status: StatusComponent = $StatusComponent
@onready var interactor: InteractorComponent = $InteractorComponent
@onready var abilities: AbilityComponent = $AbilityComponent
@onready var inventory: Inventory = $Inventory
@onready var status_tag: Label3D = $StatusTag

var _revealed_shown := false


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
	($StatusTag as Node3D).position.y = role_data.height + NAME_TAG_GAP + STATUS_TAG_GAP
	($StatusComponent as StatusComponent).setup(role_data)
	($Inventory as Inventory).setup(role)
	match role:
		Role.Kind.RAT:
			var grab := GrabHandle.new()
			grab.name = "GrabHandle"
			add_child(grab)
		Role.Kind.SUPERVISOR:
			hand_socket = Node3D.new()
			hand_socket.name = "HandSocket"
			hand_socket.position = HAND_SOCKET_POSITION
			add_child(hand_socket)
			var steal := StealHandle.new()
			steal.name = "StealHandle"
			add_child(steal)


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
	var character := visual.get_child(0) as CharacterVisual
	if role == Role.Kind.NONE and character != null:
		character.tint_hat(color_for_peer(peer_id))  # lobby bodies: tell players apart
	if not Net.is_server:
		# Every client animates every body (bots too: they fill in sync_anim for the others).
		anim = AnimationController.new()
		anim.name = "AnimationController"
		anim.setup(self, character.model if character != null else null)
		add_child(anim)
		if not Art.headless():
			fx = BodyFx.new()
			fx.name = "BodyFx"
			fx.setup(self)
			add_child(fx)
	if Net.is_server:
		# A status change can change how fast the owner may move before it hears about it.
		status.changed.connect(_grant_validator_grace)
		status.applied.connect(_on_status_applied)
	status_tag.visible = false
	status.changed.connect(_update_collision)
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
		if anim != null:
			sync_anim = anim.local_flags()


## Where we look: yaw from the body, pitch from the head (synced for remote bodies).
func look_direction() -> Vector3:
	var pitch := rig.look_pitch() if is_local() else sync_pitch
	return Vector3.FORWARD.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, rotation.y)


## The fastest we may legally move right now (movement validator).
func max_speed() -> float:
	var base := role_data.carry_speed if status.carrying != 0 else role_data.sprint_speed
	return base * status.speed_multiplier() * inventory.speed_multiplier()


## The CCTV chair we sit at, or null (while seated: no moving, interacting or abilities).
func seated_console() -> CctvConsole:
	return CctvConsole.of_peer(get_tree(), peer_id)


## The carrier's HandSocket while we are carried, else null.
func carried_anchor() -> Node3D:
	if status.carrier == 0 or not status.has(StatusComponent.Status.CARRIED):
		return null
	var carrier := Session.current.get_body(status.carrier) if Session.current else null
	return carrier.hand_socket if carrier != null else null


func _process(delta: float) -> void:
	if not Net.is_server:
		_update_feedback(delta)
	if is_local():
		return
	var anchor := carried_anchor()
	if anchor != null:
		global_position = anchor.global_position
		rotation.y = anchor.global_rotation.y
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


## Hang the body from `path` (a HandSocket) until called again with an empty path.
func server_attach_to(path: NodePath) -> void:
	_grant_validator_grace()
	movement.attach_to.rpc_id(peer_id, path)


## A carried rat hangs right in front of its carrier: without its collision layer, the carrier
## doesn't bump into it, and it can't open doors or block anyone.
func _update_collision() -> void:
	collision_layer = 0 if status.has(StatusComponent.Status.CARRIED) else PhysicsLayers.PLAYERS


func _on_status_applied(what: StatusComponent.Status) -> void:
	# A stunned rat drops what it stole (GDD §5.2).
	if what == StatusComponent.Status.STUNNED and inventory.stolen_item != &"":
		Session.current.items.drop_stolen(self)


# --- Client feedback ------------------------------------------------------------------------

func _update_feedback(delta: float) -> void:
	var labels := StatusComponent.describe(status.flags)
	status_tag.visible = not is_local() and not labels.is_empty()
	if status_tag.visible:
		status_tag.text = labels[0][0]
		status_tag.modulate = labels[0][1]
	if is_local() and anim != null and PlayerInput.has_control() and Input.is_action_just_pressed("emote"):
		anim.start_emote()
	# Without a clip for it (placeholder visuals, a supervisor's stun): fall flat / wobble.
	var weight := 1.0 - exp(-12.0 * delta)
	var knocked := status.has(StatusComponent.Status.KNOCKED_DOWN) and not _has_clip_for("knocked")
	visual.rotation.x = lerpf(visual.rotation.x, -PI * 0.5 if knocked else 0.0, weight)
	var stunned := status.has(StatusComponent.Status.STUNNED) and not _has_clip_for("stunned")
	var wobble := sin(Time.get_ticks_msec() / 70.0) * 0.25 if stunned else 0.0
	visual.rotation.z = lerpf(visual.rotation.z, wobble, weight)
	_update_reveal()


func _has_clip_for(state: String) -> bool:
	return anim != null and anim.has_clip(anim.clips.get(state, ""))


## Revealed bodies get the see-through outline, but only for the enemy team.
func _update_reveal() -> void:
	var show := false
	if status.has(StatusComponent.Status.REVEALED) and not is_local():
		var mine := Session.current.match_manager.local_role()
		show = (mine == Role.Kind.SUPERVISOR and role == Role.Kind.RAT) \
			or (mine == Role.Kind.RAT and role == Role.Kind.SUPERVISOR)
	if show == _revealed_shown:
		return
	_revealed_shown = show
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = REVEAL_MATERIAL if show else null


func _grant_validator_grace() -> void:
	validator_grace_until_ms = Time.get_ticks_msec() + int(VALIDATOR_GRACE_S * 1000.0)
