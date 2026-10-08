class_name Interactable
extends Area3D
## Base for everything a player can use with E (ARCHITECTURE §4). The area is what the
## supervisor's look ray hits (layer TRIGGERS); its origin is the point reach is measured to.
##
## The server owns all of it: InteractionService validates requests with can_interact(), then
## calls begin() / advance() every physics tick / cancel(). Each holder's progress lives in
## `holders`; the synced `progress` (0..1) and `holder_count` let every client draw the ring and
## the prop's "someone is at it" feedback. Subclasses override the virtual methods marked below.
##
## Orientation convention: the node's +Z axis points away from the machine, toward where the
## player stands (see stand_position()).

const GROUP := "interactables"
const SUPERVISOR_REACH := 1.8  ## m, from the body's centre to this node's origin
const RAT_REACH := 1.0
const LAG_TOLERANCE := 0.75  ## m added to reach on the server
const LOS_SLACK := 0.3  ## m: a line-of-sight ray may stop this close to the target

signal completed(player: Player)  ## server

@export var allowed_roles: Array[Role.Kind] = []
@export_enum("instant", "hold", "minigame") var kind := "hold"
@export var duration_s := 4.0  ## hold time; subclasses may vary it (hold_duration())
@export var prompt := "Use"
@export var reach := 0.0  ## m; 0 = the role's default
## False for interactables that don't need a synced progress ring (instant ones, the handles on
## player bodies). Set it in _init.
var needs_sync := true
## m in front of the origin where players stand to use it (stand_position()); 0 = half the role's
## reach. Set it in _init.
var stand_distance := 0.0
## True: a player who starts holding this glides to stand_position() and turns to face it (a rat
## settling in at a sabotage point). Third-person roles only: it would yank a first-person view. Set
## it in _init.
var glides_holder := false

# --- Replicated by the Sync child (server → clients) ------------------------------------
var progress := 0.0  ## 0..1
var holder_count := 0

## Server: peer id → seconds held so far.
var holders: Dictionary[int, float] = {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collision_layer = PhysicsLayers.TRIGGERS
	collision_mask = 0
	monitoring = false
	_add_sync()


## The synchronizer is built here rather than in each scene, so no subclass can forget it.
## Like every static node's synchronizer it must exist before the client connects: it does,
## because the whole Session (level included) is added before Net.join().
func _add_sync() -> void:
	var properties := _synced_properties()
	if properties.is_empty():
		return
	var config := SceneReplicationConfig.new()
	for property in properties:
		var path := NodePath(".:%s" % property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	add_child(sync)


## The properties the Sync child replicates (on change). Subclasses may add their own.
func _synced_properties() -> Array[String]:
	if not needs_sync:
		return []
	return ["progress", "holder_count"]


# --- Shared helpers ----------------------------------------------------------------------

func reach_for(role: Role.Kind) -> float:
	if reach > 0.0:
		return reach
	return RAT_REACH if role == Role.Kind.RAT else SUPERVISOR_REACH


## Where reach and line of sight are measured from: the middle of the body.
static func origin_of(player: Player) -> Vector3:
	return player.global_position + Vector3.UP * player.role_data.height * 0.5


func distance_to_player(player: Player) -> float:
	return origin_of(player).distance_to(global_position)


func role_allowed(player: Player) -> bool:
	return player.role in allowed_roles


## A floor spot in front of this interactable where `role` can stand and reach it.
func stand_position(role: Role.Kind) -> Vector3:
	var out := global_basis.z
	out.y = 0.0
	var distance := stand_distance if stand_distance > 0.0 else reach_for(role) * 0.5
	var spot := global_position + out.normalized() * distance
	spot.y = _floor_below(spot)
	return spot


## The height of the floor under `spot` (catwalks and roofs too), 0 if nothing is found.
func _floor_below(spot: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 3.0,
		PhysicsLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


# --- Virtual -----------------------------------------------------------------------------

## Game-state availability (cooldown, health…), checked on clients for the prompt and on the server
## before and during a hold. Uses only synced state, so both sides agree.
func is_available(_player: Player) -> bool:
	return true


func hold_duration() -> float:
	return duration_s


## "instant", "hold" or "minigame" for this player (a cage is instant for supervisors, a hold for rats).
func kind_for(_player: Player) -> String:
	return kind


## The prompt line for the local player ("Sabotage Coolant pumps", "Cooling down: 12 s").
func prompt_for(_player: Player) -> String:
	return tr(prompt)


## Server: the effect. Subclasses do their thing, then call super() to emit and reset.
func _complete(player: Player) -> void:
	Log.info("interact", "%s completed %s" % [player.display_name, InteractionService.short_path(get_path())])
	completed.emit(player)
	holders.clear()
	_publish()


# --- Server ------------------------------------------------------------------------------

## Returns "" if `player` may use this now, otherwise why not (logged by InteractionService).
func can_interact(player: Player) -> String:
	if not role_allowed(player):
		return "wrong role"
	if not player.status.can_act():
		return "can't act"
	if distance_to_player(player) > reach_for(player.role) + LAG_TOLERANCE:
		return "too far (%.2f m)" % distance_to_player(player)
	if not _has_line_of_sight(player):
		return "no line of sight"
	if not is_available(player):
		return "not available"
	return ""


func begin(player: Player) -> void:
	if kind_for(player) == "instant":
		_complete(player)
		return
	holders[player.peer_id] = 0.0
	_publish()


func cancel(peer_id: int) -> void:
	if holders.erase(peer_id):
		_publish()


## Called by InteractionService once per physics tick for each valid hold.
func advance(player: Player, delta: float) -> void:
	if not holders.has(player.peer_id):
		return
	holders[player.peer_id] += delta
	if holders[player.peer_id] >= hold_duration():
		_complete(player)
	else:
		_publish()


func _current_progress() -> float:
	var best := 0.0
	for seconds: float in holders.values():
		best = maxf(best, seconds)
	return clampf(best / maxf(hold_duration(), 0.01), 0.0, 1.0)


func _publish() -> void:
	progress = _current_progress()
	holder_count = holders.size()


func _has_line_of_sight(player: Player) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin_of(player), global_position, PhysicsLayers.WORLD,
		[player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(global_position) <= LOS_SLACK


## Shortcut for subclasses.
func _plant() -> PlantSim:
	return Session.current.plant
