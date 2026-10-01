class_name MovementValidator
extends Node
## Server sanity check of client-owned movement (ARCHITECTURE §3). Every CHECK_INTERVAL_S it
## compares each body's synced position with the previous sample: moving farther than the role's
## top speed allows (Player.max_speed(): carry speed, slows, donut, stolen item), or a non-rat body
## inside a VentVolume, earns a strike. Carried and caged rats are skipped: the server moves them.
## v1 only logs strikes (no correction, no kick); kicks come in M9.
##
## Checking over 0.25 s rather than every tick absorbs network jitter: BodySync packets arrive
## every 50 ms, sometimes two at once, so per-tick distances are meaningless.

const CHECK_INTERVAL_S := 0.25
const SPEED_TOLERANCE := 1.5
const DISTANCE_SLACK := 0.5  ## m

var strikes: Dictionary[int, int] = {}  ## peer -> strike count (kept across respawns)

var _samples: Dictionary[int, Dictionary] = {}  # peer -> {"body": id, "pos": Vector3, "ms": int}

@onready var session: Session = Session.current


## The farthest a body may legally move in `seconds` at `max_speed` (horizontal metres).
static func allowed_distance(max_speed: float, seconds: float) -> float:
	return max_speed * seconds * SPEED_TOLERANCE + DISTANCE_SLACK


func _ready() -> void:
	session.player_removed.connect(func(peer_id: int) -> void:
		strikes.erase(peer_id)
		_samples.erase(peer_id))


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for node in session.players_root.get_children():
		var player := node as Player
		if player == null or player.is_queued_for_deletion():
			continue
		var sample: Dictionary = _samples.get(player.peer_id, {})
		if player.status.has(StatusComponent.Status.CARRIED) or player.status.has(StatusComponent.Status.CAGED):
			_samples.erase(player.peer_id)  # moved by the server; start fresh once released
			continue
		if sample.get("body", 0) != player.get_instance_id():
			_samples[player.peer_id] = {"body": player.get_instance_id(), "pos": player.position, "ms": now}
			continue  # new body (spawn, respawn): start fresh
		var seconds := (now - int(sample["ms"])) / 1000.0
		if seconds < CHECK_INTERVAL_S:
			continue
		_check(player, sample["pos"], seconds, now)
		sample["pos"] = player.position
		sample["ms"] = now


func _check(player: Player, previous: Vector3, seconds: float, now: int) -> void:
	if now < player.validator_grace_until_ms or previous.y < MovementComponent.KILL_Y \
			or OutOfBounds.contains_point(get_tree(), previous):
		return  # server-imposed move, or the client put itself back after leaving the map
	var moved := Vector2(player.position.x - previous.x, player.position.z - previous.z).length()
	var max_speed := player.max_speed()
	if not player.status.can_act():
		max_speed = 0.0
	var allowed := allowed_distance(max_speed, seconds)
	if moved > allowed:
		_strike(player, "too fast: %.2f m in %.2f s (allowed %.2f)" % [moved, seconds, allowed])
	if not player.role_data.can_use_vents and VentVolume.contains(player):
		_strike(player, "inside a vent as %s" % Role.display_name(player.role))


func _strike(player: Player, reason: String) -> void:
	strikes[player.peer_id] = strikes.get(player.peer_id, 0) + 1
	Log.warn("validator", "strike %d for %s (peer %d): %s"
		% [strikes[player.peer_id], player.display_name, player.peer_id, reason])
