class_name StealHandle
extends Interactable
## On every supervisor's back (Player.setup): a rat holds E for 1 s behind a supervisor who faces
## away to steal the keycard (GDD §5.2). The server re-checks the facing every tick, so turning
## around cancels the steal. Rats find it by distance (no trigger area needed), so it never blocks
## anyone's look ray.

const BACK_OFFSET := 0.3  ## m behind the body's centre

var supervisor: Player


func _init() -> void:
	allowed_roles = [Role.Kind.RAT]
	kind = "hold"
	prompt = "Steal"
	reach = 1.2
	needs_sync = false  # the rat's ring is a local estimate (InteractorComponent.hold_progress)


func _ready() -> void:
	super()
	collision_layer = 0
	supervisor = get_parent() as Player
	position = Vector3(0, supervisor.role_data.height * 0.5, BACK_OFFSET)
	duration_s = PvpTuning.load_default().steal_hold_s


## The supervisor faces away from `player` (dot product of its facing and the direction to us < 0).
func facing_away_from(player: Player) -> bool:
	var forward := -supervisor.global_basis.z
	var to := player.global_position - supervisor.global_position
	return Vector2(forward.x, forward.z).dot(Vector2(to.x, to.z)) < 0.0


func is_available(player: Player) -> bool:
	return supervisor.inventory.keycard and player.inventory.stolen_item == &"" and facing_away_from(player)


func prompt_for(player: Player) -> String:
	if not supervisor.inventory.keycard:
		return "%s has no keycard" % supervisor.display_name
	if player.inventory.stolen_item != &"":
		return "Your paws are full"
	if not facing_away_from(player):
		return "Sneak behind %s to steal" % supervisor.display_name
	return "Steal %s's keycard" % supervisor.display_name


func _complete(player: Player) -> void:
	Session.current.items.steal(player, supervisor)
	super(player)
