class_name Hazard
extends Area3D
## Base for the plant's hazards (GDD §6). They hit **both teams**.
##
## Each hazard sits in the level (placed by tools/map/gen_plant.py) in the group
## `hazard_<subsystem_id>`; the server's HazardDirector switches the group on when that subsystem's
## health drops below 50 and off again at 60 (set_active). Two values are synced: `active` and
## `start_time`, the server-clock time (Net.server_time) it switched on. Everything cyclic
## (a steam jet's 3 s on / 3 s off) is derived from that start time, so clients animate the cycle
## themselves with no per-frame traffic: is_live(Net.server_time()) gives the same answer everywhere.
##
## Only the server checks overlaps (monitoring is off on clients) and applies effects, through
## StatusComponent and Player.server_apply_impulse (which opens the movement validator's grace
## window). A body is hit at most once per live window. Clients only draw: subclasses build their
## look in _build_look() and update it in _update_look(live, delta), skipped on the headless server.

const ALL_GROUP := "hazards"
const GROUP_PREFIX := "hazard_"
## Switching on starts the cycle a moment later, so clients hear about it before the first blast.
const START_DELAY_S := 0.5

@export var subsystem_id: StringName = &"pumps"
@export var size := Vector3(2, 2, 2)  ## m: the box the effect covers (subclasses may shape it)
@export var phase := 0.0  ## s into the cycle at the start, so neighbouring jets take turns

# --- Replicated by the Sync child (server → clients) ------------------------------------
var active := false
var start_time := 0.0  ## server clock

var tuning: HazardTuning = HazardTuning.load_default()
var on_s := 1.0  ## live this long…
var off_s := 0.0  ## …then off this long (0 = always live while active)

var _hit_cycle: Dictionary[int, int] = {}  # server: peer → index of the live window it was hit in
var _headless := false


static func group_for(id: StringName) -> String:
	return GROUP_PREFIX + String(id)


func _enter_tree() -> void:
	add_to_group(ALL_GROUP)
	add_to_group(group_for(subsystem_id))


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS
	monitorable = false
	monitoring = Net.is_server and _checks_overlaps()
	_configure()
	var shape := _make_shape()
	if shape != null:
		add_child(shape)
	_add_sync()
	set_physics_process(Net.is_server)
	set_process(not _headless)
	if not _headless:
		_build_look()


func _add_sync() -> void:
	var config := SceneReplicationConfig.new()
	for property: String in ["active", "start_time"]:
		var path := NodePath(".:%s" % property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	add_child(sync)


## Live (dangerous) at server-clock time `t`.
func is_live(t: float) -> bool:
	return active and HazardRules.cycle_live(t - start_time, on_s, off_s, phase)


## Seconds since the cycle started at server-clock time `t` (negative before the start).
func elapsed(t: float) -> float:
	return t - start_time


## Server (HazardDirector): switch on or off.
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	start_time = Net.server_time() + START_DELAY_S
	_hit_cycle.clear()
	_on_switched(value)


## Server: can a hazard hit this body right now? Not while carried, caged, frozen or out.
static func can_hit(player: Player) -> bool:
	if player == null or player.is_queued_for_deletion():
		return false
	if not player.role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		return false
	for status in [StatusComponent.Status.CARRIED, StatusComponent.Status.CAGED,
			StatusComponent.Status.ELIMINATED, StatusComponent.Status.LOCKED]:
		if player.status.has(status):
			return false
	return true


func _physics_process(delta: float) -> void:
	if active:
		_server_tick(delta)


## Default server behaviour: while live, hit every body inside once per live window.
func _server_tick(_delta: float) -> void:
	var now := Net.server_time()
	if not is_live(now):
		return
	var cycle := HazardRules.cycle_index(elapsed(now), on_s, off_s, phase)
	for node in get_overlapping_bodies():
		var player := node as Player
		if not can_hit(player) or _hit_cycle.get(player.peer_id, -1) == cycle:
			continue
		_hit_cycle[player.peer_id] = cycle
		_hit(player)


## Server: apply the effect to `player`, credit the stat, tell the clients.
func _hit(player: Player) -> void:
	_affect(player)
	Log.info("hazard", "%s hit %s" % [InteractionService.short_path(get_path()), player.display_name])
	Session.current.match_manager.add_stat(player.peer_id, "hazard_hits")
	on_hit.rpc(player.peer_id)


## Client: a body was hit (cosmetic: the victim gets a banner).
@rpc("authority", "call_remote", "reliable")
func on_hit(peer_id: int) -> void:
	if Session.current != null and peer_id == Session.current.local_peer_id:
		Events.local_hazard_hit.emit(hit_text())
	_on_hit_cosmetic(peer_id)


func _process(delta: float) -> void:
	_update_look(is_live(Net.server_time()), delta)


# --- Virtual ---------------------------------------------------------------------------------

## Set on_s / off_s from the tuning (both sides).
func _configure() -> void:
	pass


## False for hazards that never look at overlaps on the server (smoke, debris).
func _checks_overlaps() -> bool:
	return true


## The collision shape of the effect; default: a box of `size` sitting on the node's origin.
func _make_shape() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	return shape


func _affect(_player: Player) -> void:
	pass


func _on_switched(_value: bool) -> void:
	pass


func hit_text() -> String:
	return "Ouch!"


func _build_look() -> void:
	pass


func _update_look(_live: bool, _delta: float) -> void:
	pass


func _on_hit_cosmetic(_peer_id: int) -> void:
	pass
