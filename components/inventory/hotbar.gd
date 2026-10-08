class_name Hotbar
extends Node
## The local player's hotbar: which of the items they can pick between is selected (1 2 3, the
## mouse wheel). HotbarView draws it at the bottom of the HUD, with icons and counts.
##   supervisor  the role's traps (RoleData order: snap trap, cheese lure), then the donut
##   rat         nothing to select (a stolen keycard is only carried)
## Selecting a trap makes it the one RMB places (AbilityComponent.selected_trap); Q still switches
## between the traps and selects the one it switches to. With the donut selected RMB keeps placing
## the last trap picked, so a supervisor never fumbles a trap in a chase. E eats the selected donut
## when it has nothing to interact with (InteractorComponent asks use_selected()).
## Owner only and never synced: the server only sees the requests that follow (request_eat_donut).

const DONUT := &"donut"
const SLOT_ACTIONS: Array[StringName] = [&"slot_1", &"slot_2", &"slot_3"]

var selected := 0  ## index into slots()

@onready var body: Player = get_parent()


func _ready() -> void:
	set_process_unhandled_input(is_multiplayer_authority() and not Net.is_server and not slots().is_empty())


## The selectable items of our role, in slot order.
func slots() -> Array[StringName]:
	return slots_for(body.role)


## The selectable items of `role`, in slot order: its trap ability ids (RoleData order), then &"donut"
## for supervisors (only they may take donuts: Pickup.allowed_roles).
static func slots_for(role: Role.Kind) -> Array[StringName]:
	var out: Array[StringName] = []
	var data := Role.data(role)
	for ability: AbilityData in (data.abilities if data != null else []):
		if ability.kind == AbilityData.Kind.TRAP:
			out.append(ability.id)
	if role == Role.Kind.SUPERVISOR:
		out.append(DONUT)
	return out


func selected_item() -> StringName:
	var items := slots()
	return items[selected] if selected < items.size() else &""


func select(index: int) -> void:
	var items := slots()
	if index < 0 or index >= items.size():
		return
	selected = index
	var traps := body.abilities.trap_abilities()
	for i in traps.size():
		if traps[i].id == items[index]:
			body.abilities.selected_trap = i


## What E does with the selected item when it has nothing to interact with ("" = nothing).
func use_prompt() -> String:
	return tr("Eat your donut") if _can_eat() else ""


## Owner: E with nothing to interact with. True if it used the selected item.
func use_selected() -> bool:
	if not _can_eat():
		return false
	Session.current.items.request_eat_donut.rpc_id(1)
	return true


func _can_eat() -> bool:
	return selected_item() == DONUT and body.inventory.donuts > 0 and body.status.can_act() \
		and not body.watching_cctv() and Session.current.match_manager.state == MatchManager.State.PLAYING


func _unhandled_input(event: InputEvent) -> void:
	if not PlayerInput.has_control() or body.watching_cctv() or Session.current.match_manager.state \
			not in [MatchManager.State.COUNTDOWN, MatchManager.State.PLAYING]:
		return  # (1 2 3 pick a role in the lobby; Q and E switch cameras at the CCTV)
	var count := slots().size()
	var index := -1
	for i in mini(SLOT_ACTIONS.size(), count):
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			index = i
	if event.is_action_pressed(&"slot_next"):
		index = wrapi(selected + 1, 0, count)
	elif event.is_action_pressed(&"slot_prev"):
		index = wrapi(selected - 1, 0, count)
	elif event.is_action_pressed(&"next_trap"):
		index = _next_trap_slot()
	if index >= 0:
		select(index)
		get_viewport().set_input_as_handled()


## Q: the slot of the trap after the current one (AbilityComponent.selected_trap).
func _next_trap_slot() -> int:
	var traps := body.abilities.trap_abilities()
	if traps.is_empty():
		return -1
	var next := traps[(body.abilities.selected_trap + 1) % traps.size()]
	return slots().find(next.id)
