class_name CharacterVisual
extends Node3D
## A role's character model (M7, tools/blender/supervisor.py and rat.py), turned to face the body's
## forward (-Z: models face +Z), plus its props: the supervisor's broom in the right hand. The
## AnimationController animates `model`. Lobby bodies use the supervisor without a broom, with the
## hard hat tinted in the player's colour.

const BROOM_BONE := "arm-right"
## The broom's grip in the right hand, in the arm bone's space (measured on the model's rest pose):
## position (m) and rotation (degrees, XYZ Euler).
const BROOM_POSITION := Vector3(-0.5, -0.02, 0.06)
const BROOM_ROTATION := Vector3(0.0, 0.0, -45.0)

@export var model_name := "supervisor"
@export var with_broom := false

var model: Node3D
var skeleton: Skeleton3D
var broom: Node3D


func _ready() -> void:
	model = Art.add(self, model_name, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	if model == null:
		push_warning("CharacterVisual: model '%s' is missing (run tools/build_assets.sh)" % model_name)
		return
	var found := model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if with_broom and skeleton != null and skeleton.find_bone(BROOM_BONE) >= 0:
		var hand := BoneAttachment3D.new()
		hand.name = "RightHand"
		hand.bone_name = BROOM_BONE
		skeleton.add_child(hand)
		var basis := Basis.from_euler(BROOM_ROTATION * PI / 180.0)
		broom = Art.add(hand, "broom", Transform3D(basis, BROOM_POSITION))


## Lobby bodies: the hard hat in the player's colour.
func tint_hat(color: Color) -> void:
	var hat := Art.part(model, "HardHat")
	if hat != null:
		Art.set_tint(hat, color)
