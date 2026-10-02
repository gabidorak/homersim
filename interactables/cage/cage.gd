class_name Cage
extends Interactable
## A rat cage (GDD §5.3). Supervisors carrying a rat press E (instant) to cage it; rats hold E
## for 4 s to free one occupant (the one caged first). CaptureService does the moving and the
## bookkeeping; the cage keeps the occupant list, replicated so every peer can show it.
##
## Layout (local space, origin at the door, 0.5 m above the floor, +Z out of the door): the
## interior is the box behind the origin; Slot1..4 markers are where caged rats stand.

const CAGE_GROUP := "cages"

# --- Replicated by the Sync child --------------------------------------------------------
var occupants := PackedInt32Array()  ## caged peers, oldest first

@onready var bars: StaticBody3D = $Bars
@onready var _label: Label3D = get_node_or_null("Label")
@onready var _door: Node3D = Art.part(get_node_or_null("Model"), "Door")

const DOOR_OPEN := -1.7  ## radians about Y: swung out
var _shown_count := 0
var _door_tween: Tween


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR, Role.Kind.RAT]
	prompt = "Cage"
	reach = 2.2


func _enter_tree() -> void:
	super()
	add_to_group(CAGE_GROUP)


func _ready() -> void:
	super()
	duration_s = PvpTuning.load_default().free_hold_s
	set_physics_process(Net.is_server)


func _synced_properties() -> Array[String]:
	var list := super()
	list.append("occupants")
	return list


func slots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in get_children():
		if child is Marker3D:
			out.append(child)
	return out


func is_full() -> bool:
	return occupants.size() >= slots().size()


func has_occupant(peer_id: int) -> bool:
	return peer_id in occupants


## Where a freed rat is put: on the floor just outside the door.
func door_position() -> Vector3:
	var out := global_basis.z
	out.y = 0.0
	var spot := global_position + out.normalized() * 0.7
	spot.y -= 0.5
	return spot


func kind_for(player: Player) -> String:
	return "instant" if player.role == Role.Kind.SUPERVISOR else "hold"


func is_available(player: Player) -> bool:
	if player.role == Role.Kind.SUPERVISOR:
		return player.status.carrying != 0 and not is_full()
	return not occupants.is_empty()


func prompt_for(player: Player) -> String:
	if player.role == Role.Kind.SUPERVISOR:
		if player.status.carrying == 0:
			return "Cage (bring a stunned rat)"
		if is_full():
			return "The cage is full"
		return "Cage %s" % _name_of(player.status.carrying)
	if occupants.is_empty():
		return "Empty cage"
	return "Free %s" % _name_of(occupants[0])


func _complete(player: Player) -> void:
	if player.role == Role.Kind.SUPERVISOR:
		Session.current.captures.cage(player, self)
	else:
		Session.current.captures.free_rat(player, self)
	super(player)


# --- Server ------------------------------------------------------------------------------

## Puts `peer_id` in the first free slot and returns that slot's floor position.
func add_occupant(peer_id: int) -> Vector3:
	var index := occupants.size()
	var copy := occupants.duplicate()
	copy.append(peer_id)
	occupants = copy  # a new array, so the synchronizer notices
	return slots()[index].global_position


func remove_occupant(peer_id: int) -> void:
	var copy := PackedInt32Array()
	for p in occupants:
		if p != peer_id:
			copy.append(p)
	occupants = copy


func clear_occupants() -> void:
	occupants = PackedInt32Array()


func _physics_process(_delta: float) -> void:
	# A caged rat that left the game (or got despawned) frees its slot.
	for p in occupants:
		if Session.current.get_body(p) == null:
			remove_occupant(p)


func _process(_delta: float) -> void:
	if _label != null:
		_label.text = "CAGE" if occupants.is_empty() else "CAGE (%d)" % occupants.size()
	# Cosmetic: the door swings open and slams when a rat goes in or gets out.
	if occupants.size() != _shown_count:
		var caged := occupants.size() > _shown_count
		_shown_count = occupants.size()
		_swing_door(caged)


func _swing_door(caged: bool) -> void:
	if _door == null or Art.headless():
		return
	if _door_tween != null:
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_property(_door, "rotation:y", DOOR_OPEN, 0.18).set_ease(Tween.EASE_OUT)
	_door_tween.tween_interval(0.35 if caged else 0.8)
	_door_tween.tween_property(_door, "rotation:y", 0.0, 0.12).set_ease(Tween.EASE_IN)
	var front := global_position + global_basis.z * 0.1
	Sfx.play_at(self, "cage_open", front, -4.0)
	_door_tween.tween_callback(func() -> void: Sfx.play_at(self, "cage_slam", front))


func _name_of(peer_id: int) -> String:
	var info: PlayerInfo = Session.current.players.get(peer_id)
	return info.name if info != null else "the rat"
