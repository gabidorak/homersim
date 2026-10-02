class_name GrabHandle
extends Interactable
## On every rat body (Player.setup): a supervisor presses E on a stunned rat to pick it up
## (GDD §5.1). Instant; the server hands it to CaptureService.grab(). Its trigger area only
## answers the supervisor's look ray while the rat can be grabbed, so a carried or caged rat
## never blocks the view of what's behind it (the cage, mostly).

const RADIUS := 0.45

var rat: Player


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	kind = "instant"
	prompt = "Grab"
	reach = 2.4  # supervisors look down at rats: measured from their chest to the rat's middle
	needs_sync = false


func _ready() -> void:
	super()
	rat = get_parent() as Player
	position = Vector3.UP * rat.role_data.height * 0.5
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)


func grabbable() -> bool:
	var s := rat.status
	return s.has(StatusComponent.Status.STUNNED) and not s.has(StatusComponent.Status.CARRIED) \
		and not s.has(StatusComponent.Status.CAGED)


func is_available(player: Player) -> bool:
	return grabbable() and player.status.carrying == 0


func prompt_for(player: Player) -> String:
	if player.status.carrying != 0:
		return tr("Your hands are full")
	if not grabbable():
		return tr("Stun %s first") % rat.display_name
	return tr("Grab %s") % rat.display_name


func _complete(player: Player) -> void:
	Session.current.captures.grab(player, rat)
	super(player)


func _process(_delta: float) -> void:
	collision_layer = PhysicsLayers.TRIGGERS if grabbable() else 0
