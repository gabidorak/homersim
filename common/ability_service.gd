class_name AbilityService
extends Node
## Melee abilities, server side (GDD §5): the broom and the bite. Clients only send intents:
##   request_use_ability(id, aim)  → the server checks the match, the role's ability list,
##                                   can_act() and the cooldown, then runs the ability
## Traps go through ItemService.request_place_trap instead (they need a position).
##
## Hit checks use the server's latest known positions with a generous tolerance (HitCheck), plus a
## line-of-sight ray. The aim comes from the client but is only trusted within AIM_TOLERANCE_DEG
## of the synced look direction. Cosmetic results go to everyone (on_broom_swing, on_bite);
## the attacker's cooldown goes back to it (on_ability_cooldown).
## It lives in Session (on the server AND the clients), which RPCs require.

const HIT_TOLERANCE := 0.5  ## m added to an ability's range (lag)
const AIM_TOLERANCE_DEG := 45.0

signal broom_swung(attacker: int, victim: int, stunned: bool)  ## clients: cosmetics
signal bitten(attacker: int, victim: int, result: int)  ## clients: cosmetics (StatusRules.Bite)

var _rate := RateLimiter.new()

@onready var session: Session = get_parent()


func _ready() -> void:
	if Net.is_server:
		session.player_removed.connect(_rate.forget)


# --- Client → server -----------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_use_ability(id: StringName, aim: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _rate.allow(peer):
		return
	var reason := _use(peer, id, aim)
	if reason != "":
		Log.info("ability", "%s refused %s: %s" % [session.name_of(peer), id, reason])


# --- Server --------------------------------------------------------------------------------

func _use(peer: int, id: StringName, aim: Vector3) -> String:
	if session.match_manager.state != MatchManager.State.PLAYING:
		return "the match isn't running"
	var body := session.get_body(peer)
	if body == null:
		return "no body"
	var data := body.role_data.ability(id)
	if data == null:
		return "not a %s ability" % Role.display_name(body.role)
	if data.kind == AbilityData.Kind.TRAP:
		return "traps are placed with request_place_trap"
	if not body.status.can_act():
		return "can't act"
	if not body.abilities.server_ready(id):
		return "cooling down"
	body.abilities.server_start_cooldown(data)
	on_ability_cooldown.rpc_id(peer, id, data.cooldown_s)
	match data.kind:
		AbilityData.Kind.MELEE_STUN:
			_broom(body, data, aim)
		AbilityData.Kind.BITE:
			_bite(body, data, aim)
	return ""


## The nearest enemy of `attacker` (of role `victim_role`) that the ability reaches, or null.
func _target(attacker: Player, data: AbilityData, aim: Vector3, victim_role: Role.Kind) -> Player:
	var origin := Interactable.origin_of(attacker)
	var look := HitCheck.clamp_aim(aim, attacker.look_direction(), AIM_TOLERANCE_DEG)
	var candidates := {}
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p.role == victim_role and not p.is_queued_for_deletion() \
				and not p.status.has(StatusComponent.Status.CARRIED) and not p.status.has(StatusComponent.Status.CAGED):
			candidates[p.peer_id] = Interactable.origin_of(p)
	for peer: int in HitCheck.targets_in_reach(origin, look, candidates, data.range + HIT_TOLERANCE, data.cone_deg):
		var victim := session.get_body(peer)
		if HitCheck.has_line_of_sight(attacker, origin, candidates[peer], [victim.get_rid()]):
			return victim
	return null


func _broom(attacker: Player, data: AbilityData, aim: Vector3) -> void:
	var victim := _target(attacker, data, aim, Role.Kind.RAT)
	var stunned := victim != null and victim.status.apply(data.status, data.status_duration)
	var victim_peer := victim.peer_id if victim != null else 0
	Log.info("ability", "%s swung the broom: %s" % [attacker.display_name,
		("BONK! %s is stunned" % victim.display_name) if stunned
		else ("%s shrugged it off" % victim.display_name) if victim != null else "missed"])
	on_broom_swing.rpc(attacker.peer_id, victim_peer, stunned)


func _bite(attacker: Player, data: AbilityData, aim: Vector3) -> void:
	var victim := _target(attacker, data, aim, Role.Kind.SUPERVISOR)
	if victim == null:
		Log.info("ability", "%s bit the air" % attacker.display_name)
		on_bite.rpc(attacker.peer_id, 0, StatusRules.Bite.IGNORED)
		return
	# A single bite makes the supervisor drop the rat it carries (GDD §5.1).
	session.captures.on_carrier_bitten(victim, attacker)
	var result := victim.status.bite(data)
	if result != StatusRules.Bite.IGNORED:
		session.match_manager.add_stat(attacker.peer_id, "bites")
		session.minigames.interrupt(victim.peer_id, "bitten")  # a bite makes you drop the wrench
	if result == StatusRules.Bite.KNOCKED_DOWN:
		session.match_manager.add_stat(attacker.peer_id, "knockdowns")
	Log.info("ability", "%s bit %s: %s" % [attacker.display_name, victim.display_name,
		["ignored", "slowed", "KNOCKED DOWN"][result]])
	on_bite.rpc(attacker.peer_id, victim.peer_id, result)


# --- Server → clients ----------------------------------------------------------------------

@rpc("authority", "reliable")
func on_ability_cooldown(id: StringName, seconds: float) -> void:
	var body := session.get_body(session.local_peer_id)
	if body != null:
		body.abilities.server_cooldown(id, seconds)


@rpc("authority", "reliable")
func on_broom_swing(attacker: int, victim: int, stunned: bool) -> void:
	broom_swung.emit(attacker, victim, stunned)


@rpc("authority", "reliable")
func on_bite(attacker: int, victim: int, result: int) -> void:
	bitten.emit(attacker, victim, result)
