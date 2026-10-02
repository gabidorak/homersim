class_name ConsoleAction
extends Interactable
## A Control Room remote action (GDD §4.5): supervisor-only, instant, with a cooldown.
##   coolant  Emergency coolant: core_temp −150. Needs the power grid at 25% or more. 90 s cooldown.
##   scram    Partial SCRAM: heat ×0.5 for 30 s, but the shift gets 30 s longer. 120 s cooldown.
##            A big red button under a flip cover: the first press lifts the cover (it drops again
##            after COVER_OPEN_S), the second press fires.
## Synced: `ready_at` and `cover_open_until`, both on the server clock (Net.server_time), so every
## client counts the cooldown down by itself. The console's own screen (a Label3D) and the status
## board show it.

const GROUP_NAME := "console_actions"
const COVER_OPEN_S := 5.0

@export_enum("coolant", "scram") var action := "coolant"

# --- Replicated by the Sync child --------------------------------------------------------
var ready_at := 0.0  ## server clock: usable again from then
var cover_open_until := 0.0  ## server clock (scram only)

var _screen: Label3D
var _cover: Node3D
var _button: Node3D
var _button_rest := Vector3.ZERO


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	kind = "instant"
	reach = 2.2
	needs_sync = false


func _enter_tree() -> void:
	super()
	add_to_group(GROUP_NAME)
	add_to_group(MatchManager.RESET_GROUP)


func _ready() -> void:
	super()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.4, 0.6)
	shape.shape = box
	add_child(shape)
	if DisplayServer.get_name() != "headless":
		_build_look()
	else:
		set_process(false)


func _synced_properties() -> Array[String]:
	return ["ready_at", "cover_open_until"]


func title() -> String:
	return "EMERGENCY COOLANT" if action == "coolant" else "PARTIAL SCRAM"


func cooldown_left() -> float:
	return maxf(ready_at - Net.server_time(), 0.0)


func cover_open() -> bool:
	return action == "scram" and Net.server_time() < cover_open_until


## Coolant: the pumps need power.
func has_power() -> bool:
	if action != "coolant":
		return true
	var plant := _plant()
	return plant.health(plant.index_of(&"grid")) >= plant.tuning.coolant_min_grid_health


func is_available(_player: Player) -> bool:
	return cooldown_left() <= 0.0 and has_power()


func prompt_for(_player: Player) -> String:
	var tuning := _plant().tuning
	if cooldown_left() > 0.0:
		return "%s ready in %d s" % [title().capitalize(), ceili(cooldown_left())]
	if action == "coolant":
		if not has_power():
			return "No power for the coolant pumps (grid below %d%%)" % roundi(tuning.coolant_min_grid_health)
		return "Emergency coolant (core −%d°)" % roundi(tuning.coolant_amount)
	if not cover_open():
		return "Lift the SCRAM cover"
	return "SCRAM! (heat ×%.1f for %d s, the shift gets %d s longer)" % [tuning.scram_heat_factor,
		roundi(tuning.scram_duration_s), tuning.scram_time_penalty_s]


## Server (MatchManager, at every match start).
func reset_for_match() -> void:
	ready_at = 0.0
	cover_open_until = 0.0


func _complete(player: Player) -> void:
	var tuning := _plant().tuning
	var now := Net.server_time()
	match action:
		"coolant":
			_plant().emergency_coolant()
			ready_at = now + tuning.coolant_cooldown_s
			Log.info("console", "%s used the emergency coolant" % player.display_name)
			on_used.rpc("Emergency coolant! Core −%d°" % roundi(tuning.coolant_amount))
		"scram":
			if not cover_open():
				cover_open_until = now + COVER_OPEN_S
				Log.info("console", "%s lifted the SCRAM cover" % player.display_name)
			else:
				_plant().scram()
				Session.current.match_manager.extend_time(tuning.scram_time_penalty_s)
				ready_at = now + tuning.scram_cooldown_s
				cover_open_until = 0.0
				Log.info("console", "%s pressed SCRAM" % player.display_name)
				on_used.rpc("SCRAM! Heat halved for %d s · the shift is %d s longer" % [roundi(tuning.scram_duration_s),
					tuning.scram_time_penalty_s])
	super(player)


## Server → clients: a plant-wide announcement (HUD banner, sound).
@rpc("authority", "call_remote", "reliable")
func on_used(text: String) -> void:
	Events.plant_announcement.emit(text)
	if DisplayServer.get_name() == "headless":
		return
	if action == "scram":
		Sfx.play(self, "klaxon", -4.0)
	else:
		Sfx.play_at(self, "whoosh_cold", global_position)
	Sfx.play_at(self, "button", global_position)
	_press_button()


# --- Client look -----------------------------------------------------------------------------------

func _build_look() -> void:
	# The panel model (assets/generated/console_*.glb) sits on the desk top, 0.2 m below this node.
	var model := Art.add(self, "console_" + action, Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)))
	_button = Art.part(model, "Button")
	if _button != null:
		_button_rest = _button.position
	_cover = Art.part(model, "Cover")
	_screen = Label3D.new()
	_screen.position = Vector3(0, 0.7, -0.25)
	_screen.font_size = 48
	_screen.outline_size = 12
	_screen.pixel_size = 0.004
	add_child(_screen)


## A short press of the button (cosmetic).
func _press_button() -> void:
	if _button == null:
		return
	var tween := create_tween()
	tween.tween_property(_button, "position", _button_rest - _button.basis.y * 0.025, 0.06)
	tween.tween_property(_button, "position", _button_rest, 0.15)


func _process(delta: float) -> void:
	var left := cooldown_left()
	var color := Color(0.3, 1, 0.4)
	var state := "READY"
	if left > 0.0:
		state = "%d s" % ceili(left)
		color = Color(1, 0.6, 0.2)
	elif not has_power():
		state = "NO POWER"
		color = Color(1, 0.25, 0.2)
	if action == "scram" and _plant().scram_left > 0.0:
		state = "ACTIVE %d s  ·  %s" % [ceili(_plant().scram_left), state]
	_screen.text = "%s\n%s" % [title(), state]
	_screen.modulate = color
	if _button != null:  # lit while ready
		Art.set_tint(_button, Color.WHITE if left <= 0.0 else Color(0.45, 0.45, 0.45))
	if _cover != null:
		var target := -1.9 if cover_open() else 0.0
		_cover.rotation.x = lerpf(_cover.rotation.x, target, 1.0 - exp(-10.0 * delta))
