class_name CaptureService
extends Node
## The capture chain, server side (GDD §5.1, §5.3):
##   grab   a supervisor picks up a stunned rat (GrabHandle): the rat gets CARRIED and hangs from
##          the supervisor's HandSocket (attach_to on the rat's client); the supervisor walks at
##          carry speed
##   drop   the rat escapes after carry_max_s, or when another rat bites the carrier, or when the
##          carrier is stunned / knocked down / gone: it lands at the carrier's feet, INVULNERABLE
##   cage   the carrier presses E at a cage: the rat gets CAGED and is moved inside. Its Nth
##          capture (captures_to_eliminate) eliminates it instead: MatchManager makes it a ghost
##   free   a rat holds E at an occupied cage: the oldest occupant walks out, INVULNERABLE
## The win check (every rat that isn't eliminated is caged) is MatchManager's.
## It lives in Session (on the server AND the clients) like the other services.

var tuning: PvpTuning = PvpTuning.load_default()
## Server: rat peer → times captured this match.
var captures: Dictionary[int, int] = {}

var _carry_started: Dictionary[int, float] = {}  # server: carried rat peer → when it was grabbed

@onready var session: Session = get_parent()


func _ready() -> void:
	set_physics_process(Net.is_server)


## Server: a new match.
func reset() -> void:
	captures.clear()
	_carry_started.clear()
	for node in get_tree().get_nodes_in_group(Cage.CAGE_GROUP):
		if session.is_ancestor_of(node):
			(node as Cage).clear_occupants()


func is_carried(peer_id: int) -> bool:
	return _carry_started.has(peer_id)


## Server (GrabHandle): `supervisor` picks up `rat`. The handle already checked that it may.
func grab(supervisor: Player, rat: Player) -> void:
	rat.status.carrier = supervisor.peer_id
	rat.status.apply(StatusComponent.Status.CARRIED)
	supervisor.status.carrying = rat.peer_id
	_carry_started[rat.peer_id] = _now()
	rat.server_attach_to(supervisor.hand_socket.get_path())
	Log.info("capture", "%s grabbed %s" % [supervisor.display_name, rat.display_name])


## Server: drop the carried `rat_peer` at its carrier's feet with `invulnerable_s` of safety.
func release(rat_peer: int, reason: String, invulnerable_s: float = -1.0) -> void:
	if not _carry_started.has(rat_peer):
		return
	_carry_started.erase(rat_peer)
	var rat := session.get_body(rat_peer)
	var carrier: Player = null
	if rat != null:
		carrier = session.get_body(rat.status.carrier)
	_unlink(rat, carrier, rat_peer)
	if rat == null:
		return
	var spot := rat.global_position
	if carrier != null:
		spot = _drop_spot(carrier)
	rat.server_attach_to(NodePath())
	rat.server_force_position(spot)
	rat.status.apply(StatusComponent.Status.INVULNERABLE,
		tuning.drop_invulnerable_s if invulnerable_s < 0.0 else invulnerable_s)
	Log.info("capture", "%s got away (%s)" % [rat.display_name, reason])


## Server (AbilityService): a rat bit `supervisor`; if it carries a rat, it drops it.
func on_carrier_bitten(supervisor: Player, biter: Player) -> void:
	if supervisor.status.carrying != 0:
		release(supervisor.status.carrying, "%s bit the carrier" % biter.display_name)


## Server (Cage, supervisor side): the carried rat goes into `cage`, or is eliminated.
func cage(supervisor: Player, target: Cage) -> void:
	var rat := session.get_body(supervisor.status.carrying)
	if rat == null:
		return
	_carry_started.erase(rat.peer_id)
	_unlink(rat, supervisor, rat.peer_id)
	rat.server_attach_to(NodePath())
	captures[rat.peer_id] = captures.get(rat.peer_id, 0) + 1
	session.match_manager.add_stat(supervisor.peer_id, "catches")
	session.items.drop_stolen(rat)
	if captures[rat.peer_id] >= tuning.captures_to_eliminate:
		Log.info("capture", "%s caught %s again: eliminated" % [supervisor.display_name, rat.display_name])
		session.chat.broadcast_system("%s eliminated %s!" % [supervisor.display_name, rat.display_name])
		session.match_manager.eliminate(rat.peer_id)
		return
	var spot := target.add_occupant(rat.peer_id)
	rat.status.apply(StatusComponent.Status.CAGED)
	rat.server_force_position(spot)
	Log.info("capture", "%s caged %s (capture %d)" % [supervisor.display_name, rat.display_name, captures[rat.peer_id]])
	session.chat.broadcast_system("%s caged %s!" % [supervisor.display_name, rat.display_name])


## Server (Cage, rat side): `helper` freed the oldest occupant of `target`.
func free_rat(helper: Player, target: Cage) -> void:
	if target.occupants.is_empty():
		return
	var peer := target.occupants[0]
	target.remove_occupant(peer)
	var rat := session.get_body(peer)
	if rat == null:
		return
	rat.status.clear(StatusComponent.Status.CAGED)
	rat.status.apply(StatusComponent.Status.INVULNERABLE, tuning.freed_invulnerable_s)
	rat.server_force_position(target.door_position())
	session.match_manager.add_stat(helper.peer_id, "frees")
	Log.info("capture", "%s freed %s" % [helper.display_name, rat.display_name])
	session.chat.broadcast_system("%s freed %s!" % [helper.display_name, rat.display_name])


func _physics_process(_delta: float) -> void:
	var now := _now()
	for rat_peer: int in _carry_started.keys():
		var rat := session.get_body(rat_peer)
		var carrier: Player = session.get_body(rat.status.carrier) if rat != null else null
		if rat == null:  # the rat left the game: free its carrier's hands
			_carry_started.erase(rat_peer)
			_free_hands_of(rat_peer)
		elif carrier == null:
			release(rat_peer, "the carrier is gone")
		elif not carrier.status.can_act():
			release(rat_peer, "the carrier went down")
		elif now - _carry_started[rat_peer] >= tuning.carry_max_s:
			release(rat_peer, "wriggled free")


## Clears the carry link on both bodies (either may be null).
func _unlink(rat: Player, carrier: Player, rat_peer: int) -> void:
	if rat != null:
		rat.status.carrier = 0
		rat.status.clear(StatusComponent.Status.CARRIED)
	if carrier != null and carrier.status.carrying == rat_peer:
		carrier.status.carrying = 0


## A carrier whose rat vanished (we no longer know who carried it): find it by its link.
func _free_hands_of(rat_peer: int) -> void:
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p.status.carrying == rat_peer:
			p.status.carrying = 0


## In front of the carrier if there's room, else at its feet.
func _drop_spot(carrier: Player) -> Vector3:
	var forward := -carrier.global_basis.z
	forward.y = 0.0
	var ahead := carrier.global_position + forward.normalized() * 0.6
	var from := Interactable.origin_of(carrier)
	var to := ahead + Vector3.UP * 0.25
	return ahead if HitCheck.has_line_of_sight(carrier, from, to) else carrier.global_position


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
