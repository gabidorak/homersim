class_name StationLabel
extends Label3D
## Floating name + health over a plant station, so everyone can read the plant at a glance.
## The in-game map (MapView) finds the stations through these labels.

const GROUP := "station_labels"

@export var subsystem_id: StringName = &"pumps"

var _index := -1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_index = Session.current.plant.index_of(subsystem_id) if Session.current != null else -1


func _process(_delta: float) -> void:
	if _index == -1:
		return
	var plant := Session.current.plant
	var data := plant.data(_index)
	var state := tr("OFFLINE") if plant.needs_reboot(_index) else "%d%%" % roundi(plant.health(_index))
	text = "%s%s\n%s" % [tr(data.display_name), tr("  (2 rats)") if data.critical else "", state]
	var health := plant.health(_index) / plant.tuning.max_health
	modulate = Color(1, 0.3, 0.25).lerp(Color(0.6, 1, 0.6), health)
