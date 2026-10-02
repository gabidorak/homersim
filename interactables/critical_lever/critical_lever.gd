class_name CriticalLever
extends Interactable
## One lever of a critical sabotage (GDD §4.3): two levers about 6 m apart must be held at the
## same time for 6 s, then the subsystem loses 100 health. Progress pauses while only one lever is
## held and resets once both are let go.
##
## Pairing: set `partner_path` on ONE lever of the pair. That lever is the "leader": it links the
## other one and runs the shared progress on the server.

@export var subsystem_id: StringName = &"rods"
@export var partner_path: NodePath

var index := -1
var partner: CriticalLever
var _leader := false
var _pair_s := 0.0  # leader, server: seconds both levers were held together

@onready var _handle: Node3D = Art.part(get_node_or_null("Model"), "Handle")
@onready var _light: OmniLight3D = get_node_or_null("Light")

var _clunked := false


func _init() -> void:
	allowed_roles = [Role.Kind.RAT]
	prompt = "Pull the lever"


func _ready() -> void:
	super()
	index = _plant().index_of(subsystem_id)
	if index == -1:
		Log.error("interact", "%s: unknown subsystem '%s'" % [get_path(), subsystem_id])
	duration_s = _plant().tuning.critical_hold_s
	if not partner_path.is_empty():
		partner = get_node_or_null(partner_path) as CriticalLever
		if partner == null:
			Log.error("interact", "%s: partner %s is not a CriticalLever" % [get_path(), partner_path])
		else:
			partner.partner = self
			_leader = true
	set_physics_process(_leader and Net.is_server)


func is_available(_player: Player) -> bool:
	return index != -1 and partner != null and _plant().can_sabotage(index)


func prompt_for(player: Player) -> String:
	var plant := _plant()
	var subsystem := plant.data(index).display_name
	if plant.health(index) <= 0.0:
		return "%s is already broken" % subsystem
	if not is_available(player):
		return "%s: cooling down, %d s" % [subsystem, ceili(plant.cooldown_left(index))]
	if partner != null and partner.holder_count == 0:
		return "%s lever: needs a 2nd rat on the other lever" % subsystem
	return "Pull the %s lever" % subsystem


## Per-holder time doesn't matter here: the leader advances the shared progress itself.
func advance(_player: Player, _delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	var mine := not holders.is_empty()
	var theirs := not partner.holders.is_empty()
	if mine and theirs:
		_pair_s += delta
	elif not mine and not theirs:
		_pair_s = 0.0
	if _pair_s >= hold_duration():
		_finish()
	_set_pair_progress(_pair_s / hold_duration())


func _finish() -> void:
	var credited: Array[int] = []
	credited.append_array(holders.keys())
	credited.append_array(partner.holders.keys())
	var plant := _plant()
	plant.apply_damage(index, plant.tuning.critical_sabotage_damage, credited)
	for lever: CriticalLever in [self, partner]:
		for peer: int in lever.holders.keys():
			var body := Session.current.get_body(peer)
			if body != null:
				lever.completed.emit(body)
		lever.holders.clear()
	_pair_s = 0.0
	Log.info("interact", "critical sabotage of %s done" % plant.data(index).display_name)


func _set_pair_progress(value: float) -> void:
	for lever: CriticalLever in [self, partner]:
		lever.progress = clampf(value, 0.0, 1.0)
		lever.holder_count = lever.holders.size()


func _publish() -> void:
	holder_count = holders.size()  # progress is set by the leader


# Cosmetic: the handle tilts with progress (with a clunk when it gets there); red light while
# cooling down.
func _process(_delta: float) -> void:
	if _handle != null:
		_handle.rotation.x = lerpf(-0.6, 0.7, progress)
		if progress >= 0.99 and not _clunked:
			Sfx.play_at(self, "lever", _handle.global_position)
		_clunked = progress >= 0.99 if progress >= 0.99 or progress < 0.5 else _clunked
	if _light != null and index != -1:
		var cooling := _plant().cooldown_left(index) > 0.0
		_light.light_color = Color(1, 0.15, 0.1) if cooling else (Color(1, 0.85, 0.2) if holder_count > 0 else Color(0.3, 1, 0.4))
