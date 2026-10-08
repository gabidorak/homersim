class_name SabotagePoint
extends Interactable
## A normal sabotage point (GDD §4.3): a rat holds E for 4 s, the subsystem loses 50 health. The rat
## glides into place in front of the box first (stand_distance, glides_holder).
## While the subsystem is on its sabotage cooldown the point is disabled: red light and sparks.

@export var subsystem_id: StringName = &"pumps"

var index := -1

const SPARK_EVERY_S := 0.5  ## while cooling down: a burst of sparks this often (with some jitter)

@onready var _light: OmniLight3D = get_node_or_null("Light")
@onready var _model: Node3D = get_node_or_null("Model")
@onready var _broken: Node3D = get_node_or_null("Broken")
@onready var _lamp: Node3D = Art.part(_model, "Lamp")

var _spark_in := 0.0


func _init() -> void:
	allowed_roles = [Role.Kind.RAT]
	prompt = "Sabotage"
	# The box's face is 0.16 m behind the origin and a gnawing rat's nose 0.45 m ahead of its feet:
	# from here it chews the box without poking into it.
	stand_distance = 0.3
	glides_holder = true


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
	var subsystem := tr(plant.data(index).display_name)
	if plant.health(index) <= 0.0:
		return tr("%s is already broken") % subsystem
	if not is_available(player):
		return tr("%s: cooling down, %d s") % [subsystem, ceili(plant.cooldown_left(index))]
	return tr("Sabotage %s") % subsystem


func _complete(player: Player) -> void:
	_plant().apply_damage(index, _plant().tuning.sabotage_damage, [player.peer_id])
	super(player)


# Cosmetic, every peer: red lamp and sparks on cooldown, flashing yellow while a rat is at it, the
# chewed-open box while the subsystem is broken.
func _process(delta: float) -> void:
	if index == -1 or _light == null:
		return
	var plant := _plant()
	var cooling := plant.cooldown_left(index) > 0.0
	var broken := plant.health(index) <= 0.0
	if _broken != null:
		_broken.visible = broken
		_model.visible = not broken
	var color := Color(0.3, 1, 0.4)
	var energy := 0.4
	if cooling:
		color = Color(1, 0.15, 0.1)
		energy = 1.5
		_spark_in -= delta
		if _spark_in <= 0.0:
			_spark_in = SPARK_EVERY_S * randf_range(0.5, 1.5)
			var at := global_position - global_basis.z * 0.2 + Vector3.UP * 0.1
			Vfx.sparks(self, at, 8)
			if randf() < 0.4:
				Sfx.play_at(self, "spark", at)
	elif holder_count > 0:
		color = Color(1, 0.85, 0.2)
		energy = 1.0 + sin(Time.get_ticks_msec() / 60.0)
		_spark_in -= delta  # little sparks fly while the wires get chewed
		if _spark_in <= 0.0:
			_spark_in = randf_range(0.25, 0.6)
			Vfx.sparks(self, global_position - global_basis.z * 0.2 + Vector3.DOWN * 0.15, 4)
	_light.light_color = color
	_light.light_energy = energy
	if _lamp != null:
		Art.set_tint(_lamp, color)
		Art.set_glow(_lamp, 0.6 + energy)
