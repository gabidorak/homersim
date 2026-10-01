class_name RepairPoint
extends Interactable
## Supervisor hold repair (GDD §4.4, the M3 fallback before minigames): hold E for 6 s, +35 health.
## A subsystem at 0 health needs a 3 s "Reboot" hold first.

@export var subsystem_id: StringName = &"pumps"

var index := -1
var _lamp_material := StandardMaterial3D.new()

@onready var _lamp: MeshInstance3D = get_node_or_null("Lamp")


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	prompt = "Repair"


func _ready() -> void:
	super()
	index = _plant().index_of(subsystem_id)
	if index == -1:
		Log.error("interact", "%s: unknown subsystem '%s'" % [get_path(), subsystem_id])
	duration_s = _plant().tuning.repair_hold_s
	_lamp_material.emission_enabled = true
	if _lamp != null:
		_lamp.material_override = _lamp_material


func _rebooting() -> bool:
	return _plant().needs_reboot(index)


func hold_duration() -> float:
	return _plant().tuning.reboot_hold_s if _rebooting() else _plant().tuning.repair_hold_s


func is_available(_player: Player) -> bool:
	if index == -1:
		return false
	return _rebooting() or _plant().health(index) < _plant().tuning.max_health


func prompt_for(_player: Player) -> String:
	var plant := _plant()
	var subsystem := plant.data(index).display_name
	if _rebooting():
		return "Reboot %s" % subsystem
	if plant.health(index) >= plant.tuning.max_health:
		return "%s is fine" % subsystem
	return "Repair %s (%d%%)" % [subsystem, roundi(plant.health(index))]


func _complete(player: Player) -> void:
	if _rebooting():
		_plant().reboot(index, [player.peer_id])
	else:
		_plant().apply_repair(index, _plant().tuning.repair_amount, [player.peer_id])
	super(player)


# Cosmetic: lamp green when healthy, orange when damaged, blinking red when it needs a reboot.
func _process(_delta: float) -> void:
	if index == -1:
		return
	var color := Color(0.2, 0.9, 0.3)
	if _rebooting():
		color = Color(1, 0.1, 0.1) if Time.get_ticks_msec() % 600 < 300 else Color(0.3, 0, 0)
	elif _plant().health(index) < _plant().tuning.max_health:
		color = Color(1, 0.55, 0.1)
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
