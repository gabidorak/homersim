class_name Door
extends Node3D
## A sliding door (GDD §5, ARCHITECTURE §4). The server owns `open` (replicated by a Sync child
## built in _ready); every peer slides its own Panel (an AnimatableBody3D, so the collision moves
## too) toward the open or closed spot.
##   auto_open = true:  a normal door. It opens while anyone is near it (rats push doors open).
##   auto_open = false: a keycard door. A KeycardReader child opens it for a few seconds.

@export var auto_open := true
@export var open_offset := Vector3(0, 2.6, 0)  ## how far the panel slides when open
@export var slide_speed := 6.0  ## m/s

# --- Replicated by the Sync child --------------------------------------------------------
var open := false

var _open_until := 0.0  # server clock
var _closed_position := Vector3.ZERO
var _shown_open := false
var _lamps: Array[Node3D] = []  # keycard readers' lamps: red when locked, green when open

@onready var panel: AnimatableBody3D = $Panel
@onready var sensor: Area3D = get_node_or_null("Sensor")


func _ready() -> void:
	_closed_position = panel.position
	var config := SceneReplicationConfig.new()
	var path := NodePath(".:open")
	config.add_property(path)
	config.property_set_spawn(path, true)
	config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	add_child(sync)
	for reader in find_children("Reader*", "Area3D", false, false):
		var lamp := Art.part(reader, "Lamp")
		if lamp != null:
			_lamps.append(lamp)
	_set_lamps(false)
	if sensor != null:
		sensor.collision_layer = 0
		sensor.collision_mask = PhysicsLayers.PLAYERS
		sensor.monitorable = false
		sensor.monitoring = Net.is_server and auto_open


## The panel is all the way up (AI bots wait for it: a door still sliding blocks the way).
func is_fully_open() -> bool:
	return open and panel.position.distance_to(_closed_position + open_offset) < 0.05


## Server: open for `seconds` (keycard readers).
func open_for(seconds: float) -> void:
	_open_until = maxf(_open_until, _now() + seconds)
	open = true
	Log.info("door", "%s opened for %.0f s" % [name, seconds])


func _physics_process(delta: float) -> void:
	if Net.is_server:
		var wanted := _now() < _open_until
		if auto_open and sensor != null and sensor.has_overlapping_bodies():
			wanted = true
		open = wanted
	var target := _closed_position + (open_offset if open else Vector3.ZERO)
	panel.position = panel.position.move_toward(target, slide_speed * delta)
	if open != _shown_open:  # cosmetic: the slide sound and the readers' lamps
		_shown_open = open
		Sfx.play_at(self, "door_open" if open else "door_close", global_position + Vector3.UP * 1.3)
		_set_lamps(open)


func _set_lamps(is_open: bool) -> void:
	for lamp in _lamps:
		Art.set_tint(lamp, Color(0.3, 1, 0.4) if is_open else Color(1, 0.2, 0.15))
		Art.set_glow(lamp, 1.5)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
