class_name MinigameService
extends Node
## Repair minigames, server side (GDD §4.4, ARCHITECTURE §4 Minigames). It lives in Session (on the
## server AND the clients), which RPCs require.
##   client: request_minigame_start(repair point) ─▶ server validates, remembers when it started,
##           on_open_minigame(path, kind, seed, difficulty) ─▶ the client's MinigameHost plays it
##   client: request_minigame_result(success) ─▶ server checks: a game is open, at least
##           minigame_min_s passed (faster = a hacked client: refused), the player is still there
##           and can act ─▶ won: +50 health; lost: +10 and a 3 s lockout of the repair point
##   client: request_minigame_cancel() (Esc) ─▶ closed, no penalty
## The server closes a game itself (on_minigame_closed) when the player is bitten, stunned, knocked down,
## moves away, the repair point stops needing a repair, it runs past minigame_max_s, or the match stops.
## The hold repair (+35) stays available through InteractionService; the client picks (M8 setting).

const MAX_MOVE := 0.5  ## m away from where the game started
const MAX_REQUESTS_PER_S := 10

## An open game (server).
class Game:
	var target: RepairPoint
	var started_ms: int
	var start_position: Vector3

	func _init(p_target: RepairPoint, p_start: Vector3, now_ms: int) -> void:
		target = p_target
		start_position = p_start
		started_ms = now_ms


var _games: Dictionary[int, Game] = {}  # server: peer → its open game
var _rate := RateLimiter.new(MAX_REQUESTS_PER_S)
var _rng := RandomNumberGenerator.new()

@onready var session: Session = get_parent()


func _ready() -> void:
	set_physics_process(Net.is_server)
	_rng.randomize()
	if Net.is_server:
		session.player_removed.connect(func(peer_id: int) -> void:
			_close(peer_id, "disconnected", false)
			_rate.forget(peer_id))


## Server: close `peer_id`'s minigame, if any, and tell its client (a bite).
func interrupt(peer_id: int, reason: String) -> void:
	_close(peer_id, reason)


## Server: is `peer_id` playing a minigame?
func is_playing(peer_id: int) -> bool:
	return _games.has(peer_id)


# --- Client → server -----------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_minigame_start(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _rate.allow(peer):
		return
	var reason := _start(peer, target_path)
	if reason != "":
		Log.info("minigame", "%s refused a minigame at %s: %s" % [session.name_of(peer),
			InteractionService.short_path(target_path), reason])
		on_minigame_closed.rpc_id(peer, "refused: %s" % reason)


@rpc("any_peer", "reliable")
func request_minigame_result(success: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _rate.allow(peer):
		return
	var game: Game = _games.get(peer)
	if game == null:
		Log.warn("minigame", "%s sent a minigame result with no minigame open" % session.name_of(peer))
		return
	var seconds := (Time.get_ticks_msec() - game.started_ms) / 1000.0
	var player := session.get_body(peer)
	var tuning := session.plant.tuning
	var reason := _still_valid(peer, game)
	if reason != "":
		_close(peer, reason)
	elif success and seconds < tuning.minigame_min_s:
		Log.warn("minigame", "rejected %s's minigame win: too fast (%.2f s < %.1f s)" % [session.name_of(peer),
			seconds, tuning.minigame_min_s])
		game.target.minigame_rejected(player)
		_close(peer, "rejected: too fast")
	else:
		Log.info("minigame", "%s %s the %s minigame in %.1f s" % [player.display_name, "won" if success else "lost",
			game.target.minigame_kind(), seconds])
		if success:
			game.target.minigame_won(player)
		else:
			game.target.minigame_lost(player)
		_close(peer, "won" if success else "lost")


@rpc("any_peer", "reliable")
func request_minigame_cancel() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _rate.allow(peer):
		_close(peer, "given up", false)


# --- Server --------------------------------------------------------------------------------

func _start(peer: int, target_path: NodePath) -> String:
	if session.match_manager.state != MatchManager.State.PLAYING:
		return "the match isn't running"
	var player := session.get_body(peer)
	if player == null:
		return "no body"
	var target := get_node_or_null(target_path) as RepairPoint
	if target == null or not session.is_ancestor_of(target):
		return "not a repair point"
	var reason := target.can_interact(player)
	if reason != "":
		return reason
	if not target.minigame_available(player):
		return "no minigame here right now"
	_close(peer, "started another", false)
	session.interactions.stop_hold(peer)
	_games[peer] = Game.new(target, player.global_position, Time.get_ticks_msec())
	target.minigame_user = peer
	var seed_value := _rng.randi()
	var difficulty := 1.0 - session.plant.health(target.index) / session.plant.tuning.max_health
	Log.info("minigame", "%s started the %s minigame at %s" % [player.display_name, target.minigame_kind(),
		InteractionService.short_path(target_path)])
	on_open_minigame.rpc_id(peer, target_path, target.minigame_kind(), seed_value, difficulty)
	return ""


## "" while `peer`'s game may go on, otherwise why not.
func _still_valid(peer: int, game: Game) -> String:
	var player := session.get_body(peer)
	if session.match_manager.state != MatchManager.State.PLAYING:
		return "match stopped"
	if player == null or not is_instance_valid(game.target):
		return "gone"
	if not player.status.can_act():
		return "interrupted"
	if player.global_position.distance_to(game.start_position) > MAX_MOVE:
		return "moved"
	if game.target.distance_to_player(player) > game.target.reach_for(player.role) + Interactable.LAG_TOLERANCE:
		return "too far"
	if not game.target.needs_repair():
		return "nothing left to repair"
	if Time.get_ticks_msec() - game.started_ms > session.plant.tuning.minigame_max_s * 1000.0:
		return "took too long"
	return ""


func _physics_process(_delta: float) -> void:
	for peer: int in _games.keys():
		var reason := _still_valid(peer, _games[peer])
		if reason != "":
			_close(peer, reason)


## Ends `peer`'s game, if any. `notify` = tell the client (not when the client itself asked).
func _close(peer: int, reason: String, notify: bool = true) -> void:
	var game: Game = _games.get(peer)
	if game == null:
		return
	_games.erase(peer)
	if is_instance_valid(game.target) and game.target.minigame_user == peer:
		game.target.minigame_user = 0
	Log.info("minigame", "%s's minigame ended: %s" % [session.name_of(peer), reason])
	if notify and multiplayer.get_peers().has(peer):
		on_minigame_closed.rpc_id(peer, reason)


# --- Server → client -----------------------------------------------------------------------

@rpc("authority", "reliable")
func on_open_minigame(target_path: NodePath, kind: String, seed_value: int, difficulty: float) -> void:
	var host := _host()
	if host != null:
		host.open(target_path, kind, seed_value, difficulty)


@rpc("authority", "reliable")
func on_minigame_closed(reason: String) -> void:
	var host := _host()
	if host != null:
		host.close(reason)
	Log.info("minigame", "server closed the minigame: %s" % reason)


func _host() -> MinigameHost:
	return session.client_only.get_node_or_null("MinigameHost") as MinigameHost
