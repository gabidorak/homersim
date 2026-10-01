class_name AlarmBeacon
extends Node3D
## A ceiling alarm beacon (ASSETS §1 lighting). It follows the plant's alarm state
## (Events.plant_alarm_changed, and PlantSim.alarm when it appears): dark when NORMAL, a slow amber
## pulse for WARNING, a spinning red light for CRITICAL. Client only, cosmetic.

const SPIN_SPEED := TAU * 0.8  ## radians per second

var _alarm := PlantModel.Alarm.NORMAL
var _material := StandardMaterial3D.new()
var _glow: OmniLight3D
var _spin: Node3D
var _spot: SpotLight3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.12
	cylinder.bottom_radius = 0.16
	cylinder.height = 0.25
	mesh.mesh = cylinder
	mesh.material_override = _material
	add_child(mesh)
	_glow = OmniLight3D.new()
	_glow.omni_range = 7.0
	_glow.position.y = -0.3
	add_child(_glow)
	_spin = Node3D.new()
	add_child(_spin)
	_spot = SpotLight3D.new()
	_spot.spot_range = 12.0
	_spot.spot_angle = 30.0
	_spot.light_color = Color(1, 0.1, 0.05)
	_spot.light_energy = 6.0
	_spot.rotation.x = -0.5  # tilted down a little, then spun around Y
	_spin.add_child(_spot)
	Events.plant_alarm_changed.connect(func(alarm: int) -> void: _alarm = alarm as PlantModel.Alarm)
	if Session.current != null:
		_alarm = Session.current.plant.alarm


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	match _alarm:
		PlantModel.Alarm.WARNING:
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			_set_look(Color(1, 0.65, 0.1), 0.4 + pulse * 1.6, false)
		PlantModel.Alarm.CRITICAL:
			_spin.rotation.y += SPIN_SPEED * delta
			_set_look(Color(1, 0.1, 0.05), 1.5, true)
		_:
			_set_look(Color(0.35, 0.08, 0.06), 0.0, false)


func _set_look(color: Color, energy: float, spinning: bool) -> void:
	_material.albedo_color = color
	_material.emission_enabled = energy > 0.0
	_material.emission = color
	_material.emission_energy_multiplier = energy * 2.0
	_glow.visible = energy > 0.0
	_glow.light_color = color
	_glow.light_energy = energy
	_spot.visible = spinning
