class_name RoleData
extends Resource
## Tunable stats of a role (GDD §5). Saved as data/roles/*.tres; keep them in sync with the GDD.

enum CameraKind { FIRST_PERSON, THIRD_PERSON }

@export var kind: Role.Kind = Role.Kind.NONE
@export_group("Body")
@export var height := 1.8  ## m, capsule height
@export var radius := 0.35  ## m, capsule radius
@export_group("Movement")
@export var walk_speed := 4.0  ## m/s
@export var sprint_speed := 6.0  ## m/s
@export var stamina_s := 5.0  ## seconds of sprint on a full bar
@export var stamina_regen_s := 4.0  ## seconds to refill an empty bar
@export var stamina_regen_delay_s := 1.0  ## pause after sprinting before the bar refills
@export var jump_height := 1.0  ## m
@export var can_use_vents := false
@export var carry_speed := 0.0  ## m/s while carrying a rat (no sprint); 0 = can't carry
@export_group("Combat")
@export var abilities: Array[AbilityData] = []
@export var stun_immunity_s := 0.0  ## immune to stuns this long after one ends
@export var knockdown_immunity_s := 0.0  ## immune to knockdowns this long after one ends
@export_group("Presentation")
@export var visual_scene: PackedScene
@export var camera_kind := CameraKind.FIRST_PERSON


## The ability with this id, or null.
func ability(id: StringName) -> AbilityData:
	for a in abilities:
		if a.id == id:
			return a
	return null
