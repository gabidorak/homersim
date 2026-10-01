class_name Session
extends Node
## The shared networked scene. It lives at /root/Session on the server AND on every client,
## because RPCs and replication only work between nodes that have the same path everywhere.
##
## M1 scope: the join handshake, the player roster, and spawning/despawning player bodies.
##
## Join flow:
##   client connects ─▶ request_join(name, version) ─▶ server validates
##     ok:  on_join_accepted(peer_id, roster) to the client, on_player_joined to the others, spawn body
##     bad: on_join_rejected(reason), then the server drops the peer

signal joined  ## client: the server accepted us
signal roster_changed

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const MENU_SCENE_PATH := "res://client/MainMenu.tscn"
## Server: drop peers that connect but never send request_join.
const PENDING_TIMEOUT_S := 5.0
## Server: delay before dropping a rejected peer, so on_join_rejected reaches it first
## (ENet discards queued packets when a peer is disconnected).
const REJECT_DISCONNECT_DELAY_S := 0.5

static var current: Session

## Server setting, set by ServerMain before the node enters the tree.
var max_players := 6
## Client setting, set by MainMenu before the node enters the tree.
var desired_name := JoinRules.DEFAULT_NAME

## Joined players by peer id (on the server and, via RPCs, on clients).
var players: Dictionary[int, PlayerInfo] = {}
## Client: our own peer id once accepted.
var local_peer_id := 0

var _pending: Dictionary[int, bool] = {}  # server: connected peers that haven't joined yet
var _next_spawn := 0
var _leaving := false
var _hud: Label

@onready var players_root: Node3D = $World/Players
@onready var spawner: MultiplayerSpawner = $World/PlayerSpawner
@onready var spawn_points: Node3D = $World/TestArena/SpawnPoints
@onready var client_only: Node = $ClientOnly


## The protocol version clients must match. Debug builds accept `--game-version X` to test mismatches.
static func game_version() -> String:
	if OS.is_debug_build() and Cli.has_arg("game-version"):
		return Cli.get_str("game-version")
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _enter_tree() -> void:
	current = self


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
	else:
		Net.connected.connect(_on_connected)
		Net.connection_failed.connect(_leave_to_menu)
		Net.disconnected.connect(_leave_to_menu.bind("Disconnected from server"))
		_build_hud()


func roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: PlayerInfo in players.values():
		result.append(info.to_dict())
	return result


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
	var body := players_root.get_node_or_null(str(peer_id))
	if body != null:
		body.queue_free()  # the spawner replicates the removal to clients
	Log.info("session", "%s (peer %d) left, %d player(s) remain" % [info.name, peer_id, players.size()])
	for other: int in players:
		on_player_left.rpc_id(other, peer_id)


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
	_spawn_body(info)


func _spawn_body(info: PlayerInfo) -> void:
	var marker := spawn_points.get_child(_next_spawn % spawn_points.get_child_count()) as Marker3D
	_next_spawn += 1
	spawner.spawn({
		"peer": info.peer_id,
		"name": info.name,
		"pos": marker.global_position,
		"yaw": marker.global_rotation.y,
	})


## Runs on the server and on every client with the same data. Authority is set here, before the
## node enters the tree, so BodySync starts with the right owner.
func _spawn_player(data: Variant) -> Node:
	var d: Dictionary = data
	var player: Player = PLAYER_SCENE.instantiate()
	player.peer_id = d["peer"]
	player.name = str(player.peer_id)
	player.display_name = d["name"]
	player.position = d["pos"]
	player.rotation.y = d["yaw"]
	player.set_multiplayer_authority(player.peer_id)  # recursive: the body, its components and BodySync
	return player


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


func _build_hud() -> void:
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	client_only.add_child(_hud)
	roster_changed.connect(_update_hud)
	_update_hud()


func _update_hud() -> void:
	var names: Array[String] = []
	for info: PlayerInfo in players.values():
		names.append(info.name + (" (you)" if info.peer_id == local_peer_id else ""))
	_hud.text = "Players: %s\nEsc: free the mouse · click: capture it" % ", ".join(names)
