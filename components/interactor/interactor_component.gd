class_name InteractorComponent
extends Node
## The local player's side of interactions. Every physics tick it picks the best target:
##   first person (supervisor): what the camera looks at, via a ray from the screen centre
##   third person (rat): the nearest interactable within reach, in front of the body or camera (or
##   right under its nose: pressed against a machine, the rat is already past the point's origin)
## Holding E on an available target sends request_interact_start, then a heartbeat every 0.25 s;
## releasing E (or losing the target) sends request_interact_stop. A target that glides its holder
## into place (a sabotage point) also starts MovementComponent.glide_to(); the end of the hold stops
## it. An instant target (grab, cage, pickups, keycard readers) only gets the start request, and E
## must be released before the next.
## A repair point (when the player wants minigames) gets request_minigame_start instead: the server
## opens the minigame overlay (MinigameHost), which takes the mouse until it closes. The server decides everything
## else and reports the end of every hold through server_ended_hold(). After a hold ends on the
## server's side, E must be released before a new hold starts.
## A fresh press of E with nothing to interact with uses the Hotbar's selected item (eats the donut);
## the prompt says so. (Only a fresh press: looking away from a hold with E still down eats nothing.)
## Runs only on the owning client (not for an AI bot's body on the server: the AI calls
## InteractionService.ai_start directly). HUD reads `target`, `holding` and prompt_text().

signal hold_ended(reason: String)

const LOOK_RAY_LENGTH := 3.0  ## m from the camera
const FRONT_CONE_COS := 0.34  ## rats: within about 70° of facing
const CLOSE_RANGE := 0.4  ## m, flat: rats can use what is this close whichever way they face

var target: Interactable  ## what E would use now (may be unavailable, see prompt_text())
var holding: Interactable  ## the hold we asked the server for
## Test-only (bots): hold this target as if E were down (set it back to null to "release").
## null = use the keyboard.
var bot_hold: Interactable

var _since_heartbeat := 0.0
var _held_s := 0.0  # local estimate, for holds whose interactable has no synced progress
var _needs_release := false
var _key_was_down := false

@onready var body: Player = get_parent()


func _ready() -> void:
	set_physics_process(is_multiplayer_authority() and body.role != Role.Kind.NONE and not Net.is_server)


func _physics_process(delta: float) -> void:
	if body.seated_console() != null:
		target = null  # E switches cameras while we watch the CCTV
		if holding != null:
			_stop()
		return
	target = bot_hold if bot_hold != null else _find_target()
	var key_down := bot_hold != null or (PlayerInput.has_control() and Input.is_action_pressed("interact"))
	if not key_down:
		_needs_release = false
	var wants := key_down and not _needs_release
	var pressed := key_down and not _key_was_down
	_key_was_down = key_down

	if holding != null and (not wants or target != holding or not is_instance_valid(holding)):
		_stop()
	if holding == null and wants and target != null and target.is_available(body) and body.status.can_act():
		_start(target)
	elif holding == null and wants and pressed and target == null and body.hotbar.use_selected():
		_needs_release = true  # one press, one donut
	if holding != null:
		_held_s += delta
		_since_heartbeat += delta
		if _since_heartbeat >= InteractionService.HEARTBEAT_S:
			_since_heartbeat = 0.0
			_service().request_interact_heartbeat.rpc_id(1)


## The line for the HUD: "[E] Sabotage Coolant pumps", or why E won't work; with nothing to
## interact with, what E does with the selected hotbar item ("[E] Eat your donut").
func prompt_text() -> String:
	if target == null:
		var use := body.hotbar.use_prompt()
		return "[E] %s" % use if use != "" else ""
	var text := target.prompt_for(body)
	if holding != null or not target.is_available(body):
		return text
	return "[E] %s" % text


## 0..1 for the progress ring: the server's synced progress of what we hold, or a local estimate
## for interactables without a synced ring (the steal handle on a supervisor's back).
func hold_progress() -> float:
	if holding == null or not is_instance_valid(holding):
		return 0.0
	if holding.needs_sync:
		return holding.progress
	return clampf(_held_s / maxf(holding.hold_duration(), 0.01), 0.0, 1.0)


## Called (through InteractionService.on_hold_ended) when the server ends or refuses our hold.
func server_ended_hold(target_path: NodePath, reason: String) -> void:
	if holding == null or not is_instance_valid(holding) or holding.get_path() != target_path:
		return  # we had already let go, or this is about an older hold
	holding = null
	body.movement.stop_glide()
	_needs_release = true
	Log.info("interact", "hold ended: %s" % reason)
	hold_ended.emit(reason)


func _start(t: Interactable) -> void:
	var repair := t as RepairPoint
	if repair != null and repair.prefers_minigame(body):
		Session.current.minigames.request_minigame_start.rpc_id(1, t.get_path())
		_needs_release = true
		return
	_service().request_interact_start.rpc_id(1, t.get_path())
	if t.kind_for(body) == "instant":
		_needs_release = true  # one press, one use
		return
	holding = t
	_since_heartbeat = 0.0
	_held_s = 0.0
	if t.glides_holder:
		var spot := t.stand_position(body.role)
		var to := t.global_position - spot
		body.movement.glide_to(spot, atan2(-to.x, -to.z))


func _stop() -> void:
	holding = null
	body.movement.stop_glide()
	_service().request_interact_stop.rpc_id(1)


func _service() -> InteractionService:
	return Session.current.interactions


func _find_target() -> Interactable:
	if body.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON:
		return _look_target()
	return _nearby_target()


func _look_target() -> Interactable:
	var camera := body.rig.camera
	if camera == null:
		return null
	var from := camera.global_position
	var exclude: Array[RID] = [body.get_rid()]
	for child in body.get_children():  # the handles on our own body
		if child is Interactable:
			exclude.append((child as Interactable).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * LOOK_RAY_LENGTH,
		PhysicsLayers.WORLD | PhysicsLayers.TRIGGERS, exclude)
	query.collide_with_areas = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	var found := hit.get("collider") as Interactable
	if found == null or not found.role_allowed(body) or found.distance_to_player(body) > found.reach_for(body.role):
		return null
	return found


func _nearby_target() -> Interactable:
	var origin := Interactable.origin_of(body)
	var body_forward := _flat(-body.global_basis.z)
	var camera_forward := _flat(Vector3.FORWARD.rotated(Vector3.UP, body.rig.move_yaw()))
	var best: Interactable = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var candidate := node as Interactable
		if not candidate.role_allowed(body) or body.is_ancestor_of(candidate):
			continue
		var distance := candidate.distance_to_player(body)
		if distance > candidate.reach_for(body.role) or distance >= best_distance:
			continue
		var offset := candidate.global_position - origin
		offset.y = 0.0
		if offset.length() > CLOSE_RANGE:
			var to := offset.normalized()
			if maxf(to.dot(body_forward), to.dot(camera_forward)) < FRONT_CONE_COS:
				continue
		best = candidate
		best_distance = distance
	return best


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
