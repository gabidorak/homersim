class_name CctvConsole
extends Interactable
## The CCTV chair in the Control Room (GDD §4.5). A supervisor presses E to sit down: the server
## puts the body on the seat and freezes it there (still vulnerable to bites), and that client's
## CctvView shows the camera feeds (Q / E switch, Space stands up). A knockdown or a stun, being
## pushed off the seat, or the end of the match stands the supervisor up. One user at a time.

const CONSOLE_GROUP := "cctv_consoles"
const MAX_SEAT_DRIFT := 1.0  ## m from the seat before the server stands the body up
const SIT_GRACE_S := 1.0  ## after sitting, until the owner's new position has reached the server

# --- Replicated by the Sync child --------------------------------------------------------
var user := 0  ## the seated supervisor's peer id, 0 = free

var _sat_at_ms := 0  # server

@onready var seat: Node3D = $Seat


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	kind = "instant"
	prompt = "Watch the cameras"
	needs_sync = false


func _enter_tree() -> void:
	super()
	add_to_group(CONSOLE_GROUP)
	add_to_group(MatchManager.RESET_GROUP)


func _ready() -> void:
	super()
	set_physics_process(Net.is_server)


func _synced_properties() -> Array[String]:
	var list := super()
	list.append("user")
	return list


## The console `peer_id` sits at, or null.
static func of_peer(tree: SceneTree, peer_id: int) -> CctvConsole:
	if peer_id == 0:
		return null
	for node in tree.get_nodes_in_group(CONSOLE_GROUP):
		if (node as CctvConsole).user == peer_id:
			return node
	return null


func is_available(player: Player) -> bool:
	return user == 0 and player.status.carrying == 0


func prompt_for(player: Player) -> String:
	if user != 0:
		return "%s is watching the cameras" % Session.current.name_of(user)
	if player.status.carrying != 0:
		return "Cage the rat first"
	return "Watch the cameras (CCTV)"


func _complete(player: Player) -> void:
	user = player.peer_id
	_sat_at_ms = Time.get_ticks_msec()
	player.server_force_position(seat.global_position)
	player.server_set_locked(true)
	Log.info("cctv", "%s sat down at the CCTV" % player.display_name)
	super(player)


## Server (MatchManager, at every match start): nobody is seated.
func reset_for_match() -> void:
	user = 0


## Client → server: the seated supervisor stands up.
@rpc("any_peer", "reliable")
func request_stand_up() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer != 0 and peer == user:
		_release("stood up")


func _physics_process(_delta: float) -> void:
	if user == 0:
		return
	var body := Session.current.get_body(user)
	var reason := ""
	if body == null:
		reason = "gone"
	elif Session.current.match_manager.state != MatchManager.State.PLAYING:
		reason = "the match stopped"
	elif not body.status.can_act():
		reason = "can't act"
	elif Time.get_ticks_msec() - _sat_at_ms > SIT_GRACE_S * 1000.0 \
			and body.global_position.distance_to(seat.global_position) > MAX_SEAT_DRIFT:
		reason = "pushed off the seat"
	if reason != "":
		_release(reason)


func _release(reason: String) -> void:
	var body := Session.current.get_body(user)
	if body != null:
		body.server_set_locked(false)
	Log.info("cctv", "%s left the CCTV: %s" % [Session.current.name_of(user), reason])
	user = 0
