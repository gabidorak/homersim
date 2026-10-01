class_name AbilityData
extends Resource
## One ability (GDD §5): broom, bite, traps. Saved as data/abilities/*.tres and listed in the
## role's RoleData.abilities. Keep them in sync with the GDD.

enum Kind {
	MELEE_STUN,  ## broom: stun the nearest target in a cone
	BITE,  ## bite: slow the nearest target, knock down on repeated bites
	TRAP,  ## place a trap on the floor (snap trap, cheese lure)
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
## trap {trap_kind}.
@export var extra: Dictionary = {}
