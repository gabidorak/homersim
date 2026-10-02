class_name KeycardReader
extends Interactable
## The badge reader on each side of a keycard door: a supervisor with a keycard presses E and the
## parent Door opens for a few seconds (GDD §5.1). A supervisor whose keycard was stolen is locked
## out until it gets one back (a dropped keycard, or the spare in Storage).

var door: Door


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	kind = "instant"
	prompt = "Open"
	needs_sync = false


func _ready() -> void:
	super()
	door = get_parent() as Door


func is_available(player: Player) -> bool:
	return player.inventory.keycard and not door.open


func prompt_for(player: Player) -> String:
	if door.open:
		return tr("Open")
	if not player.inventory.keycard:
		return tr("Keycard needed")
	return tr("Open (keycard)")


func _complete(player: Player) -> void:
	door.open_for(Session.current.items.tuning.keycard_door_open_s)
	super(player)
