class_name AlarmEffects
extends Node
## Client: the plant's alarm state (GDD §4.2) in the world, on top of the beacons and the HUD tint:
## room lights stay normal, turn amber for WARNING and pulse red for CRITICAL. Only the level's room
## lights (children of a POI's "Lights" node) are tinted. The music follows the alarm too
## (MusicDirector), and the beacons sound it (AlarmBeacon).

const TINTS := {
	PlantModel.Alarm.NORMAL: Color(1, 1, 1),
	PlantModel.Alarm.WARNING: Color(1, 0.78, 0.55),
	PlantModel.Alarm.CRITICAL: Color(1, 0.45, 0.4),
}

var _lights: Array[OmniLight3D] = []
var _base_colors: Array[Color] = []
var _tint := Color.WHITE


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var level := Session.current.level
	for node in level.find_children("*", "OmniLight3D", true, false):
		if node.get_parent().name == "Lights":
			_lights.append(node as OmniLight3D)
			_base_colors.append((node as OmniLight3D).light_color)


func _process(delta: float) -> void:
	var session := Session.current
	var playing := session.match_manager.state == MatchManager.State.PLAYING
	var alarm: PlantModel.Alarm = session.plant.alarm if playing else PlantModel.Alarm.NORMAL
	# Lights.
	var target: Color = TINTS[alarm]
	if alarm == PlantModel.Alarm.CRITICAL:
		target = target.lerp(Color.WHITE, 0.25 + 0.25 * sin(Time.get_ticks_msec() / 400.0))
	var weight := 1.0 - exp(-3.0 * delta)
	var tint := _tint.lerp(target, weight)
	if not tint.is_equal_approx(_tint):
		_tint = tint
		for i in _lights.size():
			_lights[i].light_color = _base_colors[i] * _tint
