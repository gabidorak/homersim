class_name ItemService
extends Node
## Items and traps, server side (GDD §5):
##   request_place_trap(id, pos)  a supervisor places a snap trap or a cheese lure on the floor
##   steal / drop_stolen          a rat takes a supervisor's keycard (StealHandle); a stunned
##                                (or caught) rat drops it as a pickup any supervisor can take
##   trap_sprung                  a trap went off (Trap): SNAP for every supervisor, stats, log
## Traps and dropped keycards live in World/Dynamic, created through the DynamicSpawner so they
## appear (and disappear) on every client. The spawn function runs on every peer.
## It lives in Session (on the server AND the clients) like the other services.
## AI bots (M10) place traps with ai_place_trap(), hear a SNAP through snap_heard, and see a theft
## through keycard_stolen.

const PLACE_TOLERANCE := 0.5  ## m added to the trap range (lag)
const FLOOR_PROBE := 0.35  ## m above / below the requested spot to look for the floor
const MIN_FLOOR_NORMAL_Y := 0.7  ## about 45°: steeper isn't a floor

signal trap_snapped(position: Vector3)  ## clients (supervisors only receive it)
signal snap_heard(position: Vector3)  ## server: a snap trap went off (AI supervisors hear it)
signal keycard_stolen(rat: int, supervisor: int)  ## server: AI supervisors who see the thief remember it

var tuning: PvpTuning = PvpTuning.load_default()

var _rate := RateLimiter.new()
var _next_id := 1

@onready var session: Session = get_parent()
@onready var dynamic_root: Node3D = $"../World/Dynamic"
@onready var spawner: MultiplayerSpawner = $"../World/DynamicSpawner"


func _ready() -> void:
	spawner.spawn_function = _spawn_item
	if Net.is_server:
		session.player_removed.connect(_rate.forget)


## Server: remove every trap and dropped item (a new match, back to the lobby).
func clear() -> void:
	for child in dynamic_root.get_children():
		dynamic_root.remove_child(child)
		child.queue_free()


# --- Client → server -----------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_place_trap(id: StringName, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _rate.allow(peer):
		return
	var reason := _place_trap(peer, id, pos)
	if reason != "":
		Log.info("item", "%s refused to place %s at %s: %s" % [session.name_of(peer), id, pos, reason])


## AI bots (M10): request_place_trap without the RPC. "" = placed, otherwise why not.
func ai_place_trap(peer: int, id: StringName, pos: Vector3) -> String:
	var reason := _place_trap(peer, id, pos)
	if reason != "":
		Log.info("item", "%s refused to place %s at %s: %s" % [session.name_of(peer), id, pos, reason])
	return reason


func _place_trap(peer: int, id: StringName, pos: Vector3) -> String:
	if session.match_manager.state != MatchManager.State.PLAYING:
		return "the match isn't running"
	var body := session.get_body(peer)
	if body == null:
		return "no body"
	var data := body.role_data.ability(id)
	if data == null or data.kind != AbilityData.Kind.TRAP:
		return "not a trap of this role"
	if not pos.is_finite():
		return "bad position"
	if not body.status.can_act():
		return "can't act"
	if body.inventory.trap_charges <= 0:
		return "no charges"
	if not body.abilities.server_ready(id):
		return "cooling down"
	var flat := Vector2(pos.x - body.global_position.x, pos.z - body.global_position.z).length()
	if flat > data.range + PLACE_TOLERANCE:
		return "too far (%.2f m)" % flat
	var found: Variant = _floor_at(pos)
	if found == null:
		return "not on a floor"
	var floor_pos: Vector3 = found
	if not HitCheck.has_line_of_sight(body, Interactable.origin_of(body), floor_pos + Vector3.UP * 0.2):
		return "no line of sight"
	for child in dynamic_root.get_children():
		if child is Trap and (child as Node3D).global_position.distance_to(floor_pos) < tuning.trap_min_spacing:
			return "too close to another trap"
	body.inventory.trap_charges -= 1
	body.abilities.server_start_cooldown(data)
	if not Session.is_ai_id(peer):
		session.abilities.on_ability_cooldown.rpc_id(peer, id, data.cooldown_s)
	_spawn({"type": "trap", "kind": data.extra.get("trap_kind", "snap"), "pos": floor_pos, "owner": peer})
	Log.info("item", "%s placed a %s at %s (%d left)" % [body.display_name, data.display_name,
		floor_pos.snapped(Vector3.ONE * 0.01), body.inventory.trap_charges])
	return ""


## The floor point under `pos` (within FLOOR_PROBE), or null.
func _floor_at(pos: Vector3) -> Variant:
	var space := session.get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * FLOOR_PROBE, pos - Vector3.UP * FLOOR_PROBE,
		PhysicsLayers.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < MIN_FLOOR_NORMAL_Y:
		return null
	return hit["position"]


# --- Server API ----------------------------------------------------------------------------

## StealHandle: `rat` took `supervisor`'s keycard.
func steal(rat: Player, supervisor: Player) -> void:
	supervisor.inventory.lose_keycard()
	rat.inventory.stolen_item = &"keycard"
	session.match_manager.add_stat(rat.peer_id, "steals")
	Log.info("item", "%s stole %s's keycard" % [rat.display_name, supervisor.display_name])
	session.match_manager.feed("stolen", supervisor.display_name)
	session.chat.tell(supervisor.peer_id, "A rat stole your keycard! Stun it to get it back, or take the spare in Storage in %d s.",
		[roundi(tuning.spare_keycard_delay_s)])
	keycard_stolen.emit(rat.peer_id, supervisor.peer_id)


## A stunned or caught rat drops what it stole, as a pickup at its feet.
func drop_stolen(rat: Player) -> void:
	if rat.inventory.stolen_item == &"":
		return
	rat.inventory.stolen_item = &""
	_spawn({"type": "keycard", "pos": rat.global_position + Vector3.UP * 0.05})
	Log.info("item", "%s dropped the keycard" % rat.display_name)


## Trap: `trap` went off under `rat` (the status is already applied).
func trap_sprung(trap: Trap, rat: Player) -> void:
	Log.info("item", "%s stepped on a %s trap" % [rat.display_name, trap.trap_kind])
	session.match_manager.feed("trap_snap" if trap.trap_kind == "snap" else "trap_lure", rat.display_name)
	if trap.trap_kind == "snap":
		for node in session.players_root.get_children():
			var p := node as Player
			if p != null and p.role == Role.Kind.SUPERVISOR and not p.is_bot:
				on_trap_snap.rpc_id(p.peer_id, trap.global_position)
		snap_heard.emit(trap.global_position)


func _spawn(data: Dictionary) -> void:
	data["name"] = "%s%d" % [String(data["type"]).capitalize(), _next_id]
	_next_id += 1
	spawner.spawn(data)


## Runs on the server and every client with the same data.
func _spawn_item(data: Variant) -> Node:
	var d: Dictionary = data
	var node: Node3D
	match d["type"]:
		"trap":
			var trap := Trap.new()
			trap.trap_kind = d["kind"]
			trap.owner_peer = d["owner"]
			node = trap
		_:
			var pickup := Pickup.new()
			pickup.item = "keycard"
			node = pickup
	node.name = d["name"]
	node.position = d["pos"]
	return node


# --- Server → supervisors ------------------------------------------------------------------

@rpc("authority", "reliable")
func on_trap_snap(pos: Vector3) -> void:
	Log.info("item", "SNAP! A trap went off at %s" % pos.snapped(Vector3.ONE * 0.1))
	trap_snapped.emit(pos)
