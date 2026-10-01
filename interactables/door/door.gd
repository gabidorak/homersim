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
	if sensor != null:
		sensor.collision_layer = 0
		sensor.collision_mask = PhysicsLayers.PLAYERS
		sensor.monitorable = false
		sensor.monitoring = Net.is_server and auto_open


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


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
