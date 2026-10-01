class_name Session
extends Node
## The shared networked scene. It lives at /root/Session on the server AND on every client,
## because RPCs and replication only work between nodes that have the same path everywhere.
##
## It owns the join handshake, the player list, and spawning/despawning bodies (MatchManager
## decides who spawns where and as what). Children: MatchManager, PlantSim, InteractionService,
## ChatService, AbilityService, CaptureService, ItemService, World (level, Players, Dynamic), and
## the side-specific ServerOnly / ClientOnly nodes, filled at runtime. The services are reachable
## as `plant`, `interactions`, `abilities`, `captures` and `items`.
##
## Join flow:
##   client connects ─▶ request_join(name, version) ─▶ server validates
##     ok:  on_join_accepted(peer_id, roster) to the client, on_player_joined to the others,
##          player_added (MatchManager spawns a lobby body)
##     bad: on_join_rejected(reason), then the server drops the peer

signal joined  ## client: the server accepted us
signal roster_changed
signal player_added(peer_id: int)  ## server: a player finished the join handshake
signal player_removed(peer_id: int)  ## server: a joined player left

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const MENU_SCENE_PATH := "res://client/MainMenu.tscn"
const LOBBY_SCENE: PackedScene = preload("res://client/Lobby.tscn")
const HUD_SCENE: PackedScene = preload("res://client/HUD.tscn")
const CHAT_SCENE: PackedScene = preload("res://client/Chat.tscn")
const POST_MATCH_SCENE: PackedScene = preload("res://client/PostMatch.tscn")
const SPECTATOR_CAM_SCENE: PackedScene = preload("res://client/SpectatorCam.tscn")
## Server: drop peers that connect but never send request_join.
const PENDING_TIMEOUT_S := 5.0
## Server: delay before dropping a rejected peer, so on_join_rejected reaches it first
## (ENet discards queued packets when a peer is disconnected).
const REJECT_DISCONNECT_DELAY_S := 0.5
## Server, retire_bodies(): how long to wait for owners to confirm they stopped sending positions,
## then a little more for packets they sent just before (unreliable, so they can trail the reply).
const RETIRE_TIMEOUT_S := 1.0
const RETIRE_GRACE_S := 0.1

static var current: Session

## Server settings, set by ServerMain before the node enters the tree.
var max_players := 6
var match_rules: MatchRules
## Client setting, set by MainMenu before the node enters the tree.
var desired_name := JoinRules.DEFAULT_NAME

## Joined players by peer id (on the server and, via RPCs, on clients).
var players: Dictionary[int, PlayerInfo] = {}
## Client: our own peer id once accepted.
var local_peer_id := 0

## Set in _enter_tree (not @onready) because children use them in their own _ready, which runs
## before ours.
var plant: PlantSim
var interactions: InteractionService
var abilities: AbilityService
var captures: CaptureService
var items: ItemService

var _pending: Dictionary[int, bool] = {}  # server: connected peers that haven't joined yet
var _retire_acks: Dictionary[int, bool] = {}  # server: peers asked to stop syncing -> confirmed
var _leaving := false

@onready var match_manager: MatchManager = $MatchManager
@onready var chat: ChatService = $ChatService
@onready var players_root: Node3D = $World/Players
@onready var spawner: MultiplayerSpawner = $World/PlayerSpawner
@onready var server_only: Node = $ServerOnly
@onready var client_only: Node = $ClientOnly


## The protocol version clients must match. CI builds add their branch and build number, so clients
## only join a server running the very same build (the auto-updater keeps both on the newest one).
## Debug builds accept `--game-version X` to test mismatches.
static func game_version() -> String:
	if OS.is_debug_build() and Cli.has_arg("game-version"):
		return Cli.get_str("game-version")
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if BuildInfo.NUMBER > 0:
		version += "+%s.%d" % [BuildInfo.BRANCH, BuildInfo.NUMBER]
	return version


func _enter_tree() -> void:
	current = self
	plant = $PlantSim
	interactions = $InteractionService
	abilities = $AbilityService
	captures = $CaptureService
	items = $ItemService


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	# The spawn function must be set on every peer: the server calls spawner.spawn(data) and
	# Godot runs _spawn_player(data) on each client too, so all of them build the same node.
	spawner.spawn_function = _spawn_player
	# Net.is_server, not multiplayer.is_server(): on a client this node is created before the
	# connection exists, and the offline placeholder peer claims to be the server.
	if Net.is_server:
		Net.peer_joined.connect(_on_peer_joined)
		Net.peer_left.connect(_on_peer_left)
		var validator := MovementValidator.new()
		validator.name = "MovementValidator"
		server_only.add_child(validator)
	else:
		Net.connected.connect(_on_connected)
		Net.connection_failed.connect(_leave_to_menu)
		Net.disconnected.connect(_leave_to_menu.bind("Disconnected from server"))
		_build_client_ui()


func roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: PlayerInfo in players.values():
		result.append(info.to_dict())
	return result


## A joined player's name, or "peer N" (for logs).
func name_of(peer_id: int) -> String:
	return players[peer_id].name if players.has(peer_id) else "peer %d" % peer_id


func get_body(peer_id: int) -> Player:
	return players_root.get_node_or_null(str(peer_id)) as Player


func spawn_points_for(role: Role.Kind) -> Array[SpawnPoint]:
	var points: Array[SpawnPoint] = []
	for node in get_tree().get_nodes_in_group(SpawnPoint.GROUP):
		var point := node as SpawnPoint
		if point.role == role and is_ancestor_of(point):
			points.append(point)
	return points


# --- Server side ------------------------------------------------------------

func _on_peer_joined(peer_id: int) -> void:
	_pending[peer_id] = true
	Log.info("session", "peer %d connected, waiting for its join request" % peer_id)
	get_tree().create_timer(PENDING_TIMEOUT_S).timeout.connect(func() -> void:
		if _pending.erase(peer_id):
			Log.warn("session", "peer %d never sent a join request, dropping it" % peer_id)
			Net.kick(peer_id))


func _on_peer_left(peer_id: int) -> void:
	_pending.erase(peer_id)
	if not players.has(peer_id):
		return
	var info: PlayerInfo = players[peer_id]
	players.erase(peer_id)
	despawn_body(peer_id)
	chat.forget(peer_id)
	Log.info("session", "%s (peer %d) left, %d player(s) remain" % [info.name, peer_id, players.size()])
	for other: int in players:
		on_player_left.rpc_id(other, peer_id)
	chat.broadcast_system("%s left" % info.name)
	player_removed.emit(peer_id)


@rpc("any_peer", "reliable")
func request_join(player_name: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _pending.erase(peer_id):
		return  # already joined, or unknown
	var reason := JoinRules.check(version, game_version(), players.size(), max_players)
	if reason != "":
		Log.info("session", "rejected peer %d (%s): %s" % [peer_id, player_name, reason])
		on_join_rejected.rpc_id(peer_id, reason)
		get_tree().create_timer(REJECT_DISCONNECT_DELAY_S).timeout.connect(Net.kick.bind(peer_id))
		return

	var taken: Array[String] = []
	for p: PlayerInfo in players.values():
		taken.append(p.name)
	var info := PlayerInfo.new(peer_id, JoinRules.unique_name(JoinRules.sanitize_name(player_name), taken))
	players[peer_id] = info
	Log.info("session", "%s (peer %d) joined, %d/%d players" % [info.name, peer_id, players.size(), max_players])
	on_join_accepted.rpc_id(peer_id, peer_id, roster())
	for other: int in players:
		if other != peer_id:
			on_player_joined.rpc_id(other, info.to_dict())
	chat.broadcast_system("%s joined" % info.name)
	player_added.emit(peer_id)


## Server: spawn `peer_id`'s body as `role` at `point`. `locked` = frozen (LOCKED status) from
## its first frame, until the server clears it.
func spawn_body(peer_id: int, role: Role.Kind, point: Node3D, locked: bool) -> Player:
	return spawner.spawn({
		"peer": peer_id,
		"name": players[peer_id].name,
		"role": role,
		"pos": point.global_position,
		"yaw": point.global_rotation.y,
		"locked": locked,
	}) as Player


## Server: remove the bodies of `peers` cleanly (awaitable). Despawning a body whose owner is still
## sending positions makes those in-flight BodySync packets arrive for a node that no longer exists
## (Godot logs "Ignoring sync data … for missing node"), on the server and, relayed, on other
## clients. So first each owner is asked to stop syncing (on_retire_body), and the bodies go once
## every owner confirmed, or after RETIRE_TIMEOUT_S, plus RETIRE_GRACE_S. Meanwhile they are LOCKED.
func retire_bodies(peers: Array) -> void:
	var waiting: Array[int] = []
	for peer: int in peers:
		var body := get_body(peer)
		if body == null:
			continue
		body.status.apply(StatusComponent.Status.LOCKED)
		if multiplayer.get_peers().has(peer):
			_retire_acks[peer] = false
			waiting.append(peer)
			on_retire_body.rpc_id(peer)
	if not waiting.is_empty():
		var deadline := Time.get_ticks_msec() + int(RETIRE_TIMEOUT_S * 1000.0)
		while Time.get_ticks_msec() < deadline and waiting.any(func(p: int) -> bool: return not _retire_acks.get(p, true)):
			await get_tree().process_frame
		for peer in waiting:
			if not _retire_acks.get(peer, true):
				Log.warn("session", "%s didn't confirm it stopped syncing, removing its body anyway" % name_of(peer))
			_retire_acks.erase(peer)
		await get_tree().create_timer(RETIRE_GRACE_S).timeout
	for peer: int in peers:
		despawn_body(peer)


## Client → server: our body's BodySync is off (reply to on_retire_body).
@rpc("any_peer", "reliable")
func request_body_retired() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _retire_acks.has(peer):
		_retire_acks[peer] = true


## Server: remove `peer_id`'s body now if it has one. The spawner replicates the removal. Use
## retire_bodies() while the owner is connected; this is for owners that are already gone.
func despawn_body(peer_id: int) -> void:
	var body := get_body(peer_id)
	if body != null:
		# Out of the tree right away, not at the end of the frame: a respawn in the same frame
		# needs the name str(peer_id), and Godot would rename the newcomer if it were still taken.
		players_root.remove_child(body)
		body.queue_free()


## Runs on the server and on every client with the same data, so all of them build the same body.
## Authority is set here, before the node enters the tree, so BodySync starts with the right owner.
func _spawn_player(data: Variant) -> Node:
	var d: Dictionary = data
	var player: Player = PLAYER_SCENE.instantiate()
	player.peer_id = d["peer"]
	player.name = str(player.peer_id)
	player.display_name = d["name"]
	player.setup(d["role"])
	player.position = d["pos"]
	player.rotation.y = d["yaw"]
	player.set_multiplayer_authority(player.peer_id)  # recursive: the body, its components, BodySync…
	# …except the status and the inventory, which the server owns.
	var status := player.get_node("StatusComponent") as StatusComponent
	status.set_multiplayer_authority(1)
	player.get_node("Inventory").set_multiplayer_authority(1)
	player.get_node("StatusSync").set_multiplayer_authority(1)
	if d["locked"]:
		# Clients apply it too, so the body is frozen from its first frame instead of waiting
		# for StatusSync's first update.
		status.apply(StatusComponent.Status.LOCKED)
	return player


## Test-only: debug builds started with --allow-debug accept debug RPCs.
static func debug_allowed() -> bool:
	return OS.is_debug_build() and Cli.has_arg("allow-debug")


## Test-only (bots): teleport the sender's body. Refused unless debug_allowed() on the server.
@rpc("any_peer", "reliable")
func request_debug_teleport(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var body := get_body(peer)
	if not debug_allowed() or body == null:
		Log.warn("session", "refused a debug teleport from peer %d" % peer)
		return
	Log.info("session", "debug teleport of %s from %s to %s" % [body.display_name, body.global_position, pos])
	body.server_force_position(pos)


# --- Client side ------------------------------------------------------------

func _on_connected() -> void:
	Log.info("session", "connected, requesting to join as '%s'" % desired_name)
	request_join.rpc_id(1, desired_name, game_version())


@rpc("authority", "reliable")
func on_join_accepted(peer_id: int, roster_data: Array) -> void:
	local_peer_id = peer_id
	players.clear()
	for d: Dictionary in roster_data:
		var info := PlayerInfo.from_dict(d)
		players[info.peer_id] = info
	var me: PlayerInfo = players.get(peer_id)
	Log.info("session", "joined as %s, %d player(s) online" % [me.name if me else "?", players.size()])
	roster_changed.emit()
	joined.emit()


## Server → owner: stop sending our body's position, it is about to be removed (retire_bodies).
@rpc("authority", "reliable")
func on_retire_body() -> void:
	var body := get_body(local_peer_id)
	if body != null:
		(body.get_node("BodySync") as MultiplayerSynchronizer).public_visibility = false
	request_body_retired.rpc_id(1)


@rpc("authority", "reliable")
func on_join_rejected(reason: String) -> void:
	Log.info("session", "join rejected: %s" % reason)
	_leave_to_menu(reason)


@rpc("authority", "reliable")
func on_player_joined(info_data: Dictionary) -> void:
	var info := PlayerInfo.from_dict(info_data)
	players[info.peer_id] = info
	Log.info("session", "%s joined" % info.name)
	roster_changed.emit()


@rpc("authority", "reliable")
func on_player_left(peer_id: int) -> void:
	var info: PlayerInfo = players.get(peer_id)
	players.erase(peer_id)
	Log.info("session", "%s left" % (info.name if info else str(peer_id)))
	roster_changed.emit()


## Client: tear the session down and show the menu with `reason`. Safe to call more than once.
func _leave_to_menu(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	Log.info("session", "back to menu: %s" % reason)
	MainMenu.notice = reason
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_teardown.call_deferred()


func _teardown() -> void:
	var tree := get_tree()
	Net.leave()
	# Remove now (not just queue_free) so the name "Session" is free if we reconnect right away.
	get_parent().remove_child(self)
	queue_free()
	tree.change_scene_to_file(MENU_SCENE_PATH)


func _build_client_ui() -> void:
	var overview := OverviewCamera.new()
	overview.name = "OverviewCamera"
	client_only.add_child(overview)
	client_only.add_child(SPECTATOR_CAM_SCENE.instantiate())
	var feedback := CombatFeedback.new()
	feedback.name = "CombatFeedback"
	client_only.add_child(feedback)
	client_only.add_child(HUD_SCENE.instantiate())
	client_only.add_child(LOBBY_SCENE.instantiate())
	client_only.add_child(POST_MATCH_SCENE.instantiate())
	client_only.add_child(CHAT_SCENE.instantiate())
	if OS.is_debug_build() and DebugHooks.wanted():
		var hooks := DebugHooks.new()
		hooks.name = "DebugHooks"
		client_only.add_child(hooks)
