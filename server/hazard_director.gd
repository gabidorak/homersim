class_name HazardDirector
extends Node
## Server only: switches each subsystem's hazards (the level's `hazard_<id>` group, see Hazard) on
## when its health drops below 50 and off again once it is back to 60 or more (HazardRules
## hysteresis, numbers in data/hazard_tuning.tres). Outside PLAYING everything is off.
## It checks PlantSim's healths at PlantSim's own rate (10 Hz) rather than listening for each
## sabotage and repair, so a reset or anything else that moves health is covered too.

const CHECK_S := 0.1

var tuning: HazardTuning = HazardTuning.load_default()

var _active: Array[bool] = []
var _since_check := 0.0

@onready var session: Session = Session.current


func _ready() -> void:
	_active.resize(session.plant.count())
	_active.fill(false)
	get_tree().call_group(Hazard.ALL_GROUP, "set_active", false)


func is_active(index: int) -> bool:
	return _active[index]


func _physics_process(delta: float) -> void:
	_since_check += delta
	if _since_check < CHECK_S:
		return
	_since_check = 0.0
	var plant := session.plant
	var playing := session.match_manager.state == MatchManager.State.PLAYING
	for i in plant.count():
		var want := playing and HazardRules.next_active(_active[i], plant.health(i), tuning.on_below_health,
			tuning.off_at_health)
		if want == _active[i]:
			continue
		_active[i] = want
		var id := plant.data(i).id
		var group := Hazard.group_for(id)
		get_tree().call_group(group, "set_active", want)
		Log.info("hazard", "%s hazards %s (health %d, %d hazard node(s))" % [id, "ON" if want else "off",
			roundi(plant.health(i)), get_tree().get_node_count_in_group(group)])
