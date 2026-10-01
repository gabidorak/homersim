class_name Inventory
extends Node
## What a player carries (GDD §5), owned by the server and replicated by the body's StatusSync:
##   keycard          supervisor: opens keycard doors (everyone spawns with one)
##   stolen_item      rat: what it stole (&"keycard"), &"" = nothing; slows the rat a little
##   trap_charges     supervisor: traps left (refilled at Storage)
##   spare_wait_left  supervisor: whole seconds before Storage hands out a spare keycard
##   donut_wait_left  supervisor: whole seconds before the next donut
## Clients only read these (prompts, HUD, movement speed).

# --- Replicated by StatusSync ------------------------------------------------------------
var keycard := false
var stolen_item: StringName = &""
var trap_charges := 0
var spare_wait_left := 0
var donut_wait_left := 0

var tuning: PvpTuning = PvpTuning.load_default()

# Server only (seconds, server clock).
var _keycard_lost_at := -INF
var _donut_ready_at := 0.0


## Called by the spawn function (on every peer, so the first frame already shows the start kit).
func setup(role: Role.Kind) -> void:
	keycard = role == Role.Kind.SUPERVISOR
	trap_charges = tuning.trap_charges if role == Role.Kind.SUPERVISOR else 0


func _ready() -> void:
	set_process(Net.is_server)


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


func donut_ready() -> bool:
	return _now() >= _donut_ready_at


func eat_donut() -> void:
	_donut_ready_at = _now() + tuning.donut_cooldown_s
	_update_waits()


func _process(_delta: float) -> void:
	_update_waits()


func _update_waits() -> void:
	var now := _now()
	spare_wait_left = 0 if keycard else maxi(ceili(_keycard_lost_at + tuning.spare_keycard_delay_s - now), 0)
	donut_wait_left = maxi(ceili(_donut_ready_at - now), 0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
