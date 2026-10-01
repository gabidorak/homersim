class_name SabotagePoint
extends Interactable
## A normal sabotage point (GDD §4.3): a rat holds E for 4 s, the subsystem loses 50 health.
## While the subsystem is on its sabotage cooldown the point is disabled: red light and sparks.

@export var subsystem_id: StringName = &"pumps"

var index := -1

@onready var _light: OmniLight3D = get_node_or_null("Light")
@onready var _sparks: CPUParticles3D = get_node_or_null("Sparks")


func _init() -> void:
	allowed_roles = [Role.Kind.RAT]
	prompt = "Sabotage"


func _ready() -> void:
	super()
	index = _plant().index_of(subsystem_id)
	if index == -1:
		Log.error("interact", "%s: unknown subsystem '%s'" % [get_path(), subsystem_id])
	duration_s = _plant().tuning.sabotage_hold_s


func is_available(_player: Player) -> bool:
	return index != -1 and _plant().can_sabotage(index)


func prompt_for(player: Player) -> String:
	var plant := _plant()
	var subsystem := plant.data(index).display_name
	if plant.health(index) <= 0.0:
		return "%s is already broken" % subsystem
	if not is_available(player):
		return "%s: cooling down, %d s" % [subsystem, ceili(plant.cooldown_left(index))]
	return "Sabotage %s" % subsystem


func _complete(player: Player) -> void:
	_plant().apply_damage(index, _plant().tuning.sabotage_damage, [player.peer_id])
	super(player)


# Cosmetic, every peer: red + sparks on cooldown, flashing yellow while a rat is at it.
func _process(_delta: float) -> void:
	if index == -1 or _light == null:
		return
	var cooling := _plant().cooldown_left(index) > 0.0
	if _sparks != null:
		_sparks.emitting = cooling
	if cooling:
		_light.light_color = Color(1, 0.15, 0.1)
		_light.light_energy = 1.5
	elif holder_count > 0:
		_light.light_color = Color(1, 0.85, 0.2)
		_light.light_energy = 1.0 + sin(Time.get_ticks_msec() / 60.0)
	else:
		_light.light_color = Color(0.3, 1, 0.4)
		_light.light_energy = 0.4
