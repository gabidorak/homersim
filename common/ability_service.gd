class_name AbilityService
extends Node
## Melee abilities, server side (GDD §5): the broom, the bite and a caged rat's spit. Clients only
## send intents:
##   request_use_ability(id, aim)  → the server checks the match, the role's ability list,
##                                   AbilityData.usable() and the cooldown, then runs the ability
## Traps go through ItemService.request_place_trap instead (they need a position).
##
## Hit checks use the server's latest known positions with a generous tolerance (HitCheck), plus a
## line-of-sight ray. The aim comes from the client but is only trusted within AIM_TOLERANCE_DEG
## of the synced look direction (a caged rat's spit is the exception: it can't turn its body, so it
## aims with its camera). Cosmetic results go to everyone (on_broom_swing, on_bite, on_spit);
## the attacker's cooldown goes back to it (on_ability_cooldown).
## It lives in Session (on the server AND the clients), which RPCs require.
## AI bots (M10) use ai_use(), the same checks without an RPC. On the server, broom_swung and bitten
## are emitted too: AI bots hear them (AiSenses).
## Spit (GDD §5.3) is mostly for fun: a hit has a stun_chance to stun the supervisor, who then can't be
## stunned by spit again for stun_cooldown_s (so a cage full of rats can't keep a guard down).

const HIT_TOLERANCE := 0.5  ## m added to an ability's range (lag)
const AIM_TOLERANCE_DEG := 45.0

signal broom_swung(attacker: int, victim: int, stunned: bool)  ## clients: cosmetics; server: the AI hears it
signal bitten(attacker: int, victim: int, result: int)  ## clients: cosmetics (StatusRules.Bite); server: the AI
## Clients: cosmetics. `aim` is the flat direction it flew in (a miss flies that way); victim 0 = missed.
signal spat(attacker: int, victim: int, aim: Vector3, stunned: bool)

var rng := RandomNumberGenerator.new()  ## server: the spit's stun roll

var _rate := RateLimiter.new()
var _spit_stun_until: Dictionary[int, float] = {}  # server: supervisor peer -> no spit stun before then

@onready var session: Session = get_parent()


func _ready() -> void:
	if Net.is_server:
		session.player_removed.connect(_rate.forget)
		session.player_removed.connect(func(peer: int) -> void: _spit_stun_until.erase(peer))


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

## AI bots (M10): request_use_ability without the RPC. "" = used, otherwise why not.
func ai_use(peer: int, id: StringName, aim: Vector3) -> String:
	var reason := _use(peer, id, aim)
	if reason != "":
		Log.info("ability", "%s refused %s: %s" % [session.name_of(peer), id, reason])
	return reason


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
	if not data.usable(body.status):
		return "only from a cage" if data.kind == AbilityData.Kind.SPIT else "can't act"
	if not body.abilities.server_ready(id):
		return "cooling down"
	body.abilities.server_start_cooldown(data)
	if not Session.is_ai_id(peer):
		on_ability_cooldown.rpc_id(peer, id, data.cooldown_s)
	match data.kind:
		AbilityData.Kind.MELEE_STUN:
			_broom(body, data, aim)
		AbilityData.Kind.BITE:
			_bite(body, data, aim)
		AbilityData.Kind.SPIT:
			_spit(body, data, aim)
	return ""


## The nearest enemy of `attacker` (of role `victim_role`) that the ability reaches along `look`, or
## null. The line of sight ignores the bodies in `see_through` (a caged rat's bars).
func _target(attacker: Player, data: AbilityData, look: Vector3, victim_role: Role.Kind,
		see_through: Array[RID] = []) -> Player:
	var origin := Interactable.origin_of(attacker)
	var candidates := {}
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p.role == victim_role and not p.is_queued_for_deletion() \
				and not p.status.has(StatusComponent.Status.CARRIED) and not p.status.has(StatusComponent.Status.CAGED):
			candidates[p.peer_id] = Interactable.origin_of(p)
	for peer: int in HitCheck.targets_in_reach(origin, look, candidates, data.range + HIT_TOLERANCE, data.cone_deg):
		var victim := session.get_body(peer)
		var ignore: Array[RID] = [victim.get_rid()]
		ignore.append_array(see_through)
		if HitCheck.has_line_of_sight(attacker, origin, candidates[peer], ignore):
			return victim
	return null


## The aim of a broom or a bite: the client's, within AIM_TOLERANCE_DEG of where the body looks.
func _melee_aim(attacker: Player, aim: Vector3) -> Vector3:
	return HitCheck.clamp_aim(aim, attacker.look_direction(), AIM_TOLERANCE_DEG)


func _broom(attacker: Player, data: AbilityData, aim: Vector3) -> void:
	var victim := _target(attacker, data, _melee_aim(attacker, aim), Role.Kind.RAT)
	var stunned := victim != null and victim.status.apply(data.status, data.status_duration)
	var victim_peer := victim.peer_id if victim != null else 0
	Log.info("ability", "%s swung the broom: %s" % [attacker.display_name,
		("BONK! %s is stunned" % victim.display_name) if stunned
		else ("%s shrugged it off" % victim.display_name) if victim != null else "missed"])
	if stunned:
		session.match_manager.add_stat(attacker.peer_id, "bonks")
		session.match_manager.feed("bonk", attacker.display_name, victim.display_name)
	on_broom_swing.rpc(attacker.peer_id, victim_peer, stunned)
	broom_swung.emit(attacker.peer_id, victim_peer, stunned)


func _bite(attacker: Player, data: AbilityData, aim: Vector3) -> void:
	var victim := _target(attacker, data, _melee_aim(attacker, aim), Role.Kind.SUPERVISOR)
	if victim == null:
		Log.info("ability", "%s bit the air" % attacker.display_name)
		on_bite.rpc(attacker.peer_id, 0, StatusRules.Bite.IGNORED)
		bitten.emit(attacker.peer_id, 0, StatusRules.Bite.IGNORED)
		return
	# A single bite makes the supervisor drop the rat it carries (GDD §5.1).
	session.captures.on_carrier_bitten(victim, attacker)
	var result := victim.status.bite(data)
	if result != StatusRules.Bite.IGNORED:
		session.match_manager.add_stat(attacker.peer_id, "bites")
		session.minigames.interrupt(victim.peer_id, "bitten")  # a bite makes you drop the wrench
	if result == StatusRules.Bite.KNOCKED_DOWN:
		session.match_manager.add_stat(attacker.peer_id, "knockdowns")
		session.match_manager.feed("knockdown", victim.display_name)
	Log.info("ability", "%s bit %s: %s" % [attacker.display_name, victim.display_name,
		["ignored", "slowed", "KNOCKED DOWN"][result]])
	on_bite.rpc(attacker.peer_id, victim.peer_id, result)
	bitten.emit(attacker.peer_id, victim.peer_id, result)


## A caged rat spits through its bars (any direction: it aims with its camera, see the header).
func _spit(attacker: Player, data: AbilityData, aim: Vector3) -> void:
	var look := Vector3(aim.x, 0.0, aim.z)
	if look.length_squared() < 0.0001 or not look.is_finite():
		look = attacker.look_direction()
		look.y = 0.0
	look = look.normalized()
	var cage := Cage.of_occupant(get_tree(), attacker.peer_id)
	var bars: Array[RID] = []
	if cage != null:
		bars.append(cage.bars.get_rid())
	var victim := _target(attacker, data, look, Role.Kind.SUPERVISOR, bars)
	var stunned := false
	if victim != null and _now() >= _spit_stun_until.get(victim.peer_id, -INF) \
			and rng.randf() < float(data.extra.get("stun_chance", 0.0)) \
			and victim.status.apply(data.status, data.status_duration):
		stunned = true
		_spit_stun_until[victim.peer_id] = _now() + float(data.extra.get("stun_cooldown_s", 0.0))
		session.minigames.interrupt(victim.peer_id, "spat on")
		session.match_manager.feed("spit", attacker.display_name, victim.display_name)
	Log.info("ability", "%s spat from the cage: %s" % [attacker.display_name,
		("PTOOEY! %s is stunned" % victim.display_name) if stunned
		else ("hit %s" % victim.display_name) if victim != null else "missed"])
	var victim_peer := victim.peer_id if victim != null else 0
	on_spit.rpc(attacker.peer_id, victim_peer, look, stunned)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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


@rpc("authority", "reliable")
func on_spit(attacker: int, victim: int, aim: Vector3, stunned: bool) -> void:
	spat.emit(attacker, victim, aim, stunned)
