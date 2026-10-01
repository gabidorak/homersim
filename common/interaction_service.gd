class_name InteractionService
extends Node
## Hold interactions, server side (ARCHITECTURE §3 "Intent RPCs"). Clients only send intents:
##   request_interact_start(path) → the server validates everything and begins the hold
##   request_interact_heartbeat() every HEARTBEAT_S while E stays down
##   request_interact_stop()      when E is released or the target is lost
## Progress is advanced here, on the server, every physics tick. A hold is cancelled when the
## heartbeats stop, the player moves more than MAX_MOVE, loses the ability to act, leaves the
## reach / line of sight, disconnects, or the match stops. The client hears about every end of a
## hold (completed, cancelled, rejected) through on_hold_ended.
## It lives in Session (on the server AND the clients), which RPCs require.

const HEARTBEAT_S := 0.25  ## client send interval
const HEARTBEAT_TIMEOUT_S := 1.0  ## about four missed heartbeats
const MAX_MOVE := 0.5  ## m away from where the hold started
const MAX_REQUESTS_PER_S := 20

## A hold in progress (server).
class Hold:
	var target: Interactable
	var start_position: Vector3
	var last_beat_ms: int

	func _init(p_target: Interactable, p_start: Vector3, now_ms: int) -> void:
		target = p_target
		start_position = p_start
		last_beat_ms = now_ms


var _holds: Dictionary[int, Hold] = {}  # server: peer → its hold (one at a time)
var _rate: Dictionary[int, Vector2i] = {}  # server: peer → (second, requests in that second)

@onready var session: Session = get_parent()


func _ready() -> void:
	set_physics_process(Net.is_server)
	if Net.is_server:
		session.player_removed.connect(func(peer_id: int) -> void:
			_end(peer_id, "disconnected", false)
			_rate.erase(peer_id))


## Server: is `peer_id` holding something right now?
func is_holding(peer_id: int) -> bool:
	return _holds.has(peer_id)


# --- Client → server -----------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_interact_start(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _rate_ok(peer):
		return
	var reason := _start(peer, target_path)
	if reason != "":
		Log.info("interact", "%s refused %s: %s" % [_who(peer), short_path(target_path), reason])
		on_hold_ended.rpc_id(peer, target_path, "refused: %s" % reason)


# Reliable on purpose: unreliable heartbeats were sometimes dropped in the integration test
# (they share the ENet channel with reliable traffic), which cancelled valid holds.
@rpc("any_peer", "reliable")
func request_interact_heartbeat() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _rate_ok(peer) and _holds.has(peer):
		_holds[peer].last_beat_ms = Time.get_ticks_msec()


@rpc("any_peer", "reliable")
func request_interact_stop() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _rate_ok(peer):
		_end(peer, "released", true, false)


# --- Server --------------------------------------------------------------------------------

func _start(peer: int, target_path: NodePath) -> String:
	if session.match_manager.state != MatchManager.State.PLAYING:
		return "the match isn't running"
	var player := session.get_body(peer)
	if player == null:
		return "no body"
	var target := get_node_or_null(target_path) as Interactable
	if target == null or not session.is_ancestor_of(target):
		return "no such interactable"
	var reason := target.can_interact(player)
	if reason != "":
		return reason
	if _holds.has(peer):
		_end(peer, "switched target", true, false)
	if target.kind == "hold":
		_holds[peer] = Hold.new(target, player.global_position, Time.get_ticks_msec())
		Log.info("interact", "%s started %s" % [player.display_name, short_path(target.get_path())])
	target.begin(player)
	return ""


func _physics_process(delta: float) -> void:
	if _holds.is_empty():
		return
	var running := session.match_manager.state == MatchManager.State.PLAYING
	var now := Time.get_ticks_msec()
	for peer: int in _holds.keys():
		var hold: Hold = _holds[peer]
		var player := session.get_body(peer)
		if is_instance_valid(hold.target) and not hold.target.holders.has(peer):
			_end(peer, "completed", false)  # finished outside advance() (e.g. a lever pair's leader)
			continue
		var reason := ""
		if not running:
			reason = "match stopped"
		elif player == null or not is_instance_valid(hold.target):
			reason = "gone"
		elif now - hold.last_beat_ms > HEARTBEAT_TIMEOUT_S * 1000.0:
			reason = "heartbeat timeout"
		elif player.global_position.distance_to(hold.start_position) > MAX_MOVE:
			reason = "moved"
		else:
			reason = hold.target.can_interact(player)
		if reason != "":
			_end(peer, reason)
		else:
			hold.target.advance(player, delta)
	# Whatever finished this tick (possibly a partner's hold too) took its holders off the target.
	for peer: int in _holds.keys():
		if not _holds[peer].target.holders.has(peer):
			_end(peer, "completed", false)


## Ends `peer`'s hold, if any. `cancel` = take it off the target too. `notify` = tell the client
## (not when the client itself asked: by then it may already hold something new).
func _end(peer: int, reason: String, cancel: bool = true, notify: bool = true) -> void:
	var hold: Hold = _holds.get(peer)
	if hold == null:
		return
	_holds.erase(peer)
	var path := NodePath()
	if is_instance_valid(hold.target):
		path = hold.target.get_path()
		if cancel:
			hold.target.cancel(peer)
	Log.info("interact", "%s's hold on %s ended: %s" % [_who(peer), short_path(path), reason])
	if notify and multiplayer.get_peers().has(peer):
		on_hold_ended.rpc_id(peer, path, reason)


## "Pumps/SabotageA" from a full node path, for logs.
static func short_path(path: NodePath) -> String:
	var n := path.get_name_count()
	if n == 0:
		return "?"
	return "%s/%s" % [path.get_name(n - 2), path.get_name(n - 1)] if n >= 2 else str(path.get_name(0))


func _who(peer: int) -> String:
	return session.players[peer].name if session.players.has(peer) else "peer %d" % peer


func _rate_ok(peer: int) -> bool:
	var second := floori(Time.get_ticks_msec() / 1000.0)
	var entry: Vector2i = _rate.get(peer, Vector2i(second, 0))
	if entry.x != second:
		entry = Vector2i(second, 0)
	entry.y += 1
	_rate[peer] = entry
	return entry.y <= MAX_REQUESTS_PER_S


# --- Server → client -----------------------------------------------------------------------

@rpc("authority", "reliable")
func on_hold_ended(target_path: NodePath, reason: String) -> void:
	var body := session.get_body(session.local_peer_id)
	if body != null:
		body.interactor.server_ended_hold(target_path, reason)
