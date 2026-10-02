class_name PlantProp
extends Node3D
## Moving parts of a plant model (M7), driven by its subsystem's synced health (PlantSim), on
## clients only. The level generator puts this script on the model instance and picks `motion`:
##   fan       children "Fan" spin, at a speed that follows the health (stopped when broken)
##   shaft     "Shaft" spins about its X axis (the turbine)
##   wheels    "Wheel*" strain back and forth when damaged, frantically when below 25
##   switches  "Switch*" breakers: up when healthy, flicking when damaged, all down when broken
##   rods      "Rod*" rise as the rods subsystem degrades, drop during a SCRAM

@export var subsystem_id: StringName = &"ventilation"
@export_enum("fan", "shaft", "wheels", "switches", "rods") var motion := "fan"
@export var spin_speed := 9.0  ## radians per second at full health
## The parts' turning axis in their own space (Blender Z = Godot Y, Blender X = Godot X,
## Blender Y = Godot -Z).
@export var axis := Vector3.UP

var _parts: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _index := -1
var _spin := 0.0
var _angle := 0.0


func _ready() -> void:
	if Art.headless() or Session.current == null:
		set_process(false)
		return
	var prefix: String = {"fan": "Fan", "shaft": "Shaft", "wheels": "Wheel", "switches": "Switch", "rods": "Rod"}[motion]
	for node in find_children(prefix + "*", "Node3D", true, false):
		_parts.append(node as Node3D)
	# Keep only the outermost matches (a part's own mesh child can share its name prefix).
	_parts = _parts.filter(func(n: Node3D) -> bool: return not _parts.any(func(o: Node3D) -> bool: return o != n and o.is_ancestor_of(n)))
	for part in _parts:
		_rest.append(part.transform)
	_index = Session.current.plant.index_of(subsystem_id)


func _process(delta: float) -> void:
	if _index == -1 or _parts.is_empty():
		return
	var plant := Session.current.plant
	var health := plant.health(_index) / plant.tuning.max_health
	var t := Time.get_ticks_msec() / 1000.0
	match motion:
		"fan", "shaft":
			_spin = move_toward(_spin, spin_speed * health, spin_speed * delta * 0.5)
			_angle = fmod(_angle + _spin * delta, TAU)
			for i in _parts.size():
				_parts[i].transform = _rest[i] * Transform3D(Basis(axis, _angle), Vector3.ZERO)
		"wheels":
			var strain := 0.0 if health >= 0.5 else (0.25 if health >= 0.25 else 0.7)
			for i in _parts.size():
				var a := sin(t * (3.0 + i) + i) * strain
				_parts[i].transform = _rest[i] * Transform3D(Basis(axis, a), Vector3.ZERO)
		"switches":
			for i in _parts.size():
				var down := health <= 0.0 or (health < 0.5 and fmod(t * 0.7 + i * 0.37, 1.0) < 0.2)
				_parts[i].transform = _rest[i] * Transform3D(Basis(Vector3.RIGHT, 1.0 if down else -0.15), Vector3.ZERO)
		"rods":
			var lift := (1.0 - health) * 0.45
			if plant.scram_left > 0.0:
				lift = -0.3
			for i in _parts.size():
				var jitter := sin(t * 2.0 + i) * 0.02 if health < 0.5 else 0.0
				var target := _rest[i].origin + Vector3.UP * (lift + jitter)
				_parts[i].position = _parts[i].position.lerp(target, 1.0 - exp(-3.0 * delta))

