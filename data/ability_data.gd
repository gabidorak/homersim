class_name AbilityData
extends Resource
## One ability (GDD §5): broom, bite, traps, spit. Saved as data/abilities/*.tres and listed in the
## role's RoleData.abilities. Keep them in sync with the GDD.

enum Kind {
	MELEE_STUN,  ## broom: stun the nearest target in a cone
	BITE,  ## bite: slow the nearest target, knock down on repeated bites
	TRAP,  ## place a trap on the floor (snap trap, cheese lure)
	SPIT,  ## caged rats only: spit at the nearest target in a cone, with a chance to stun it
}

@export var id: StringName = &""
@export var display_name := ""
@export var kind := Kind.MELEE_STUN
@export var input_action: StringName = &"primary"  ## the action that triggers it
@export var range := 2.0  ## m, body centre to body centre (horizontal); traps: placement distance
@export var cone_deg := 70.0  ## full cone width around the aim; 360 = any direction
@export var cooldown_s := 1.0
@export var status := StatusComponent.Status.STUNNED  ## what a hit applies
@export var status_duration := 2.0  ## s
## Kind-specific numbers: bite {slow_factor, knockdown_bites, knockdown_window_s, knockdown_s},
## trap {trap_kind}, spit {stun_chance, stun_cooldown_s}.
@export var extra: Dictionary = {}


## True if a body with `status` may use this ability now: spitting needs a cage, everything else
## needs to be free to act.
func usable(status: StatusComponent) -> bool:
	if kind == Kind.SPIT:
		return status.has(StatusComponent.Status.CAGED)
	return status.can_act()
