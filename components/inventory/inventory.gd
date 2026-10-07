class_name Inventory
extends Node
## What a player carries (GDD §5), owned by the server and replicated by the body's StatusSync:
##   keycard          supervisor: opens keycard doors (everyone spawns with one)
##   stolen_item      rat: what it stole (&"keycard"), &"" = nothing; slows the rat a little
##   snap_charges     supervisor: snap traps left (the trap box in Storage refills them)
##   lure_charges     supervisor: cheese lures left (the cheese box in Storage refills them)
##   spare_wait_left  supervisor: whole seconds before Storage hands out a spare keycard
##   donuts           supervisor: donuts carried (taken at the Break Room counter, eaten from the hotbar)
##   donut_wait_left  supervisor: whole seconds before the counter hands out the next donut
## Clients only read these (prompts, HUD, hotbar, movement speed).

const SNAP_TRAP := &"snap_trap"  ## the trap abilities' ids (data/abilities)
const CHEESE_LURE := &"cheese_lure"

# --- Replicated by StatusSync ------------------------------------------------------------
var keycard := false
var stolen_item: StringName = &""
var snap_charges := 0
var lure_charges := 0
var spare_wait_left := 0
var donuts := 0
var donut_wait_left := 0

var tuning: PvpTuning = PvpTuning.load_default()

# Server only (seconds, server clock).
var _keycard_lost_at := -INF
var _donut_ready_at := 0.0


## Called by the spawn function (on every peer, so the first frame already shows the start kit).
func setup(role: Role.Kind) -> void:
	keycard = role == Role.Kind.SUPERVISOR
	for trap: StringName in [SNAP_TRAP, CHEESE_LURE]:
		set_charges(trap, max_charges(trap) if role == Role.Kind.SUPERVISOR else 0)


func _ready() -> void:
	set_process(Net.is_server)


## How many traps of kind `trap` (its ability id) we have left.
func charges(trap: StringName) -> int:
	match trap:
		SNAP_TRAP:
			return snap_charges
		CHEESE_LURE:
			return lure_charges
	return 0


## How many traps of kind `trap` a refill gives (and a supervisor starts with).
func max_charges(trap: StringName) -> int:
	match trap:
		SNAP_TRAP:
			return tuning.snap_trap_charges
		CHEESE_LURE:
			return tuning.cheese_lure_charges
	return 0


## Server (and the spawn function): what's left of `trap` after placing one or a refill.
func set_charges(trap: StringName, value: int) -> void:
	match trap:
		SNAP_TRAP:
			snap_charges = value
		CHEESE_LURE:
			lure_charges = value


## Movement multiplier from what we carry.
func speed_multiplier() -> float:
	return tuning.stolen_item_speed if stolen_item != &"" else 1.0


# --- Server ------------------------------------------------------------------------------

## A rat took our keycard: the spare-keycard countdown starts.
func lose_keycard() -> void:
	keycard = false
	_keycard_lost_at = _now()
	_update_waits()


func give_keycard() -> void:
	keycard = true
	_update_waits()


## True if Storage may hand us a spare keycard now.
func spare_ready() -> bool:
	return not keycard and _now() - _keycard_lost_at >= tuning.spare_keycard_delay_s


## True if the Break Room counter may hand us a donut now.
func can_take_donut() -> bool:
	return donuts < tuning.donut_carry_max and _now() >= _donut_ready_at


## The counter handed us a donut: the wait for the next one starts.
func take_donut() -> void:
	donuts += 1
	_donut_ready_at = _now() + tuning.donut_cooldown_s
	_update_waits()


## We ate one of the donuts we carry (ItemService applies the boost).
func eat_donut() -> void:
	donuts = maxi(donuts - 1, 0)


func _process(_delta: float) -> void:
	_update_waits()


func _update_waits() -> void:
	var now := _now()
	spare_wait_left = 0 if keycard else maxi(ceili(_keycard_lost_at + tuning.spare_keycard_delay_s - now), 0)
	donut_wait_left = maxi(ceili(_donut_ready_at - now), 0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
