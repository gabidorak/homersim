class_name AbilityComponent
extends Node
## The player's abilities (RoleData.abilities: broom / bite / traps).
##   Owning client: LMB uses the primary ability (request_use_ability with the aim direction).
##     Supervisors hold RMB to see where the selected trap would go (a preview only this client
##     ever draws, so rats never see it), release to place it (request_place_trap); Q switches
##     between snap trap and cheese lure. Cooldowns start locally on use and are corrected by the
##     server (AbilityService.on_ability_cooldown); the HUD reads cooldown_left().
##   Server: the authoritative cooldowns (server_ready / server_start_cooldown).

const PREVIEW_RAY := 3.5  ## m from the camera
const COOLDOWN_SLACK := 0.1  ## s: the server forgives jitter between two requests

var selected_trap := 0  ## index into trap_abilities()

var _cooldown_left: Dictionary[StringName, float] = {}  # owner: seconds left, for the HUD
var _ready_at: Dictionary[StringName, float] = {}  # server: server clock
var _placing := false
var _preview: MeshInstance3D
var _preview_pos: Variant = null  # Vector3 where the trap would go, or null

@onready var body: Player = get_parent()


func _ready() -> void:
	# (not for an AI bot's body on the server: the AI calls AbilityService.ai_use directly)
	set_process(is_multiplayer_authority() and not body.role_data.abilities.is_empty() and not Net.is_server)


func primary() -> AbilityData:
	for a in body.role_data.abilities:
		if a.input_action == &"primary":
			return a
	return null


func trap_abilities() -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for a in body.role_data.abilities:
		if a.kind == AbilityData.Kind.TRAP:
			out.append(a)
	return out


func selected_trap_ability() -> AbilityData:
	var traps := trap_abilities()
	return traps[selected_trap % traps.size()] if not traps.is_empty() else null


func cooldown_left(id: StringName) -> float:
	return _cooldown_left.get(id, 0.0)


## Owner: use an ability now (also the bots' entry point). `aim` defaults to where we look.
func use(id: StringName, aim: Vector3 = Vector3.ZERO) -> bool:
	var data := body.role_data.ability(id)
	if data == null or cooldown_left(id) > 0.0 or not body.status.can_act() or not _playing():
		return false
	if aim == Vector3.ZERO:
		aim = _aim()
	_cooldown_left[id] = data.cooldown_s
	Session.current.abilities.request_use_ability.rpc_id(1, id, aim)
	if data.kind == AbilityData.Kind.MELEE_STUN and body.rig is FirstPersonRig:
		(body.rig as FirstPersonRig).swing()
	if body.anim != null:  # the others see it when the server's cosmetic RPC comes back
		body.anim.play_one_shot("swing" if data.kind == AbilityData.Kind.MELEE_STUN else "bite")
	return true


## Owner: place the selected trap at `pos` (also the bots' entry point).
func place_trap(pos: Vector3) -> bool:
	var data := selected_trap_ability()
	if data == null or cooldown_left(data.id) > 0.0 or body.inventory.trap_charges <= 0 or not _playing():
		return false
	_cooldown_left[data.id] = data.cooldown_s
	Session.current.items.request_place_trap.rpc_id(1, data.id, pos)
	if body.anim != null:
		body.anim.play_one_shot("place")
	return true


## Owner: the server's word on a cooldown.
func server_cooldown(id: StringName, seconds: float) -> void:
	_cooldown_left[id] = seconds


func _process(delta: float) -> void:
	for id: StringName in _cooldown_left.keys():
		_cooldown_left[id] = maxf(_cooldown_left[id] - delta, 0.0)
	var control := PlayerInput.has_control() and _playing() and body.seated_console() == null
	if control and Input.is_action_just_pressed("primary") and primary() != null:
		use(primary().id)
	if control and Input.is_action_just_pressed("next_trap") and not trap_abilities().is_empty():
		selected_trap = (selected_trap + 1) % trap_abilities().size()
	var wants_preview := control and Input.is_action_pressed("secondary") and selected_trap_ability() != null
	if _placing and not wants_preview:
		if control and _preview_pos != null:
			place_trap(_preview_pos)
		_placing = false
	elif wants_preview:
		_placing = true
	_update_preview()


func _playing() -> bool:
	return Session.current.match_manager.state == MatchManager.State.PLAYING


## Where we aim: the camera's forward (first person) or the third-person camera's yaw.
func _aim() -> Vector3:
	if body.rig.camera != null and body.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON:
		return -body.rig.camera.global_basis.z
	return Vector3.FORWARD.rotated(Vector3.UP, body.rig.move_yaw())


## The floor spot under the crosshair within the trap's range, or null.
func _trap_spot() -> Variant:
	var data := selected_trap_ability()
	var camera := body.rig.camera
	if data == null or camera == null:
		return null
	var space := body.get_world_3d().direct_space_state
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * PREVIEW_RAY,
		PhysicsLayers.WORLD, [body.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < ItemService.MIN_FLOOR_NORMAL_Y:
		return null
	var spot: Vector3 = hit["position"]
	if Vector2(spot.x - body.global_position.x, spot.z - body.global_position.z).length() > data.range:
		return null
	return spot


func _update_preview() -> void:
	_preview_pos = _trap_spot() if _placing else null
	if _preview == null and _placing:
		_preview = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.3
		disc.bottom_radius = 0.3
		disc.height = 0.02
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1, 0.4, 0.5)
		disc.material = mat
		_preview.mesh = disc
		_preview.top_level = true
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(_preview)
	if _preview != null:
		_preview.visible = _preview_pos != null
		if _preview_pos != null:
			_preview.global_position = (_preview_pos as Vector3) + Vector3.UP * 0.02


# --- Server --------------------------------------------------------------------------------

func server_ready(id: StringName) -> bool:
	return _now() + COOLDOWN_SLACK >= _ready_at.get(id, 0.0)


func server_start_cooldown(data: AbilityData) -> void:
	_ready_at[data.id] = _now() + data.cooldown_s


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
