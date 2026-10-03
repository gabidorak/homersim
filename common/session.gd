class_name Session
extends Node
## The shared networked scene. It lives at /root/Session on the server AND on every client,
## because RPCs and replication only work between nodes that have the same path everywhere.
##
## It owns the join handshake, the player list, and spawning/despawning bodies (MatchManager
## decides who spawns where and as what). Children: MatchManager, PlantSim, InteractionService,
## ChatService, AbilityService, CaptureService, ItemService, MinigameService, World (level, Players,
## Dynamic), and the side-specific ServerOnly / ClientOnly nodes, filled at runtime. The services are
## reachable as `plant`, `interactions`, `abilities`, `captures`, `items` and `minigames`.
##
## The level (World's first child) is added in _enter_tree: the plant, or the TestArena sandbox in
## debug builds started with `--level test` (the PvP integration tests use it). Server and clients
## must load the same one, so the join handshake compares them.
##
## Join flow:
##   client connects ─▶ request_join(name, version, level, password) ─▶ server validates
##     ok:  on_join_accepted(peer_id, roster) to the client, on_player_joined to the others,
##          player_added (MatchManager spawns a lobby body)
##     bad: on_join_rejected(LeaveReason.Code, detail), then the server drops the peer
## Whatever ends a client's session (refused, kicked, connection lost, the player leaving) goes
## through _leave_to_menu(code, detail): the menu reopens and explains it (MainMenu.leave_code).
##
## AI bots (M10, ARCHITECTURE §6): their bodies spawn like players' (spawn_body) but have negative
## ids (is_ai_id) and are owned and moved by the server (AiDirector, under ServerOnly). They are in
## MatchManager.roster, never in `players`, so nothing that talks to connected peers sees them.

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
const LEVELS := {"plant": "res://levels/plant/Plant.tscn", "test": "res://levels/test/TestArena.tscn"}
const DEFAULT_LEVEL := "plant"
## Server: drop peers that connect but never send request_join.
const PENDING_TIMEOUT_S := 5.0
## Server: delay before dropping a rejected or kicked peer, so on_join_rejected / on_kicked reaches
## it first (ENet discards queued packets when a peer is disconnected).
const REJECT_DISCONNECT_DELAY_S := 0.5
## Server, retire_bodies(): how long to wait for owners to confirm they stopped sending positions,
## then a little more for packets they sent just before (unreliable, so they can trail the reply).
const RETIRE_TIMEOUT_S := 1.0
const RETIRE_GRACE_S := 0.1

static var current: Session

## Server settings, set by ServerMain before the node enters the tree.
var max_players := 6
var match_rules: MatchRules
var server_name := "HomerSim server"
var password := ""  ## "" = anyone may join
## Client settings, set by the menu before the node enters the tree.
var desired_name := JoinRules.DEFAULT_NAME
var desired_password := ""

## Joined players by peer id (on the server and, via RPCs, on clients).
var players: Dictionary[int, PlayerInfo] = {}
## Client: our own peer id once accepted.
var local_peer_id := 0
## Server: the AI's navigation meshes are baked, so bots can play (AiDirector sets it).
var ai_ready := false

## Set in _enter_tree (not @onready) because children use them in their own _ready, which runs
## before ours.
var plant: PlantSim
var interactions: InteractionService
var abilities: AbilityService
var captures: CaptureService
var items: ItemService
var minigames: MinigameService
var level: Node3D  ## the loaded level scene (Plant or TestArena)

var _pending: Dictionary[int, bool] = {}  # server: connected peers that haven't joined yet
var _kicked: Dictionary[int, bool] = {}  # server: peers told to go, about to be dropped
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
## The level this process plays (a LEVELS key): the plant, or `--level test` in debug builds.
static func level_id() -> String:
	if OS.is_debug_build() and LEVELS.has(Cli.get_str("level")):
		return Cli.get_str("level")
	return DEFAULT_LEVEL


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
	minigames = $MinigameService
	if level == null:
		# Before the children enter the tree, so the level's interactables exist (with their
		# synchronizers) before a client connects.
		level = (load(LEVELS[level_id()]) as PackedScene).instantiate()
		$World.add_child(level)
		$World.move_child(level, 0)


func _exit_tree() -> void:
	if current == self:
		current = null
	Sfx.clear_cache()
	Vfx.clear_cache()
	Art.clear_cache()


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
		var heatmap := HeatmapRecorder.new()
		heatmap.name = "HeatmapRecorder"
		server_only.add_child(heatmap)
		var hazards := HazardDirector.new()
		hazards.name = "HazardDirector"
		server_only.add_child(hazards)
		if not Cli.has_arg("no-lan"):
			var lan := LanAnnouncer.new()
			lan.name = "LanAnnouncer"
			server_only.add_child(lan)
		var ai := AiDirector.new()
		ai.name = "AiDirector"
		server_only.add_child(ai)
	else:
		Net.connected.connect(_on_connected)
		Net.connection_failed.connect(_on_connection_failed)
		Net.disconnected.connect(_leave_to_menu.bind(LeaveReason.Code.LOST, ""))
		Config.apply_environment(_level_environment())
		_build_client_ui()


func roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: PlayerInfo in players.values():
		result.append(info.to_dict())
	return result


## A joined player's name, a bot's name (from the roster), or "peer N" (for logs).
func name_of(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id].name
	var e: Dictionary = match_manager.entry(peer_id) if match_manager != null else {}
	return str(e.get("name", "peer %d" % peer_id))


## True for an AI bot's id (M10): bots get negative ids, ENet peers are always positive.
static func is_ai_id(id: int) -> bool:
	return id < 0


## Server: the AI (M10), or null on clients.
func ai_director() -> AiDirector:
	return server_only.get_node_or_null("AiDirector") as AiDirector


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
	_kicked.erase(peer_id)
	if not players.has(peer_id):
		return
	var info: PlayerInfo = players[peer_id]
	players.erase(peer_id)
	despawn_body(peer_id)
	chat.forget(peer_id)
	Log.info("session", "%s (peer %d) left, %d player(s) remain" % [info.name, peer_id, players.size()])
	for other: int in players:
		on_player_left.rpc_id(other, peer_id)
	chat.broadcast_system("%s left", [info.name])
	player_removed.emit(peer_id)


@rpc("any_peer", "reliable")
func request_join(player_name: String, version: String, level_name: String, join_password: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _pending.erase(peer_id):
		return  # already joined, or unknown
	var code := JoinRules.check(version, game_version(), players.size(), max_players, join_password, password)
	var detail := ""
	if code == LeaveReason.Code.VERSION:
		detail = "%s|%s" % [game_version(), version]
	elif code == LeaveReason.Code.NONE and level_name != level_id():
		code = LeaveReason.Code.LEVEL
		detail = "%s|%s" % [level_id(), level_name]
	if code != LeaveReason.Code.NONE:
		Log.info("session", "rejected peer %d (%s): %s" % [peer_id, player_name, LeaveReason.log_text(code, detail)])
		on_join_rejected.rpc_id(peer_id, code, detail)
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
	chat.broadcast_system("%s joined", [info.name])
	player_added.emit(peer_id)


## Server: remove a joined player, telling it why first (`reason`, English; the client translates
## it when it knows the line). Nothing kicks players automatically yet: the movement validator and the
## server console get kick commands in M9.
func kick(peer_id: int, reason: String) -> void:
	if not players.has(peer_id) or _kicked.has(peer_id):
		return
	_kicked[peer_id] = true
	Log.info("session", "kicking %s: %s" % [name_of(peer_id), reason])
	on_kicked.rpc_id(peer_id, reason)
	get_tree().create_timer(REJECT_DISCONNECT_DELAY_S).timeout.connect(Net.kick.bind(peer_id))


## Server: spawn `peer_id`'s body as `role` at `point`. `locked` = frozen (LOCKED status) from
## its first frame, until the server clears it. A bot (is_ai_id) must already be in the roster.
func spawn_body(peer_id: int, role: Role.Kind, point: Node3D, locked: bool) -> Player:
	return spawner.spawn({
		"peer": peer_id,
		"name": name_of(peer_id),
		"bot": is_ai_id(peer_id),
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
## A bot's body is the server's own: its BodySync stops at once, and it waits out the grace too (for
## the server → client packets already on their way).
func retire_bodies(peers: Array) -> void:
	var waiting: Array[int] = []
	var bots := false
	for peer: int in peers:
		var body := get_body(peer)
		if body == null:
			continue
		body.status.apply(StatusComponent.Status.LOCKED)
		if body.is_bot:
			(body.get_node("BodySync") as MultiplayerSynchronizer).public_visibility = false
			bots = true
		elif multiplayer.get_peers().has(peer):
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
	if not waiting.is_empty() or bots:
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
## Authority is set here, before the node enters the tree, so BodySync starts with the right owner:
## the player's client, or the server (1) for a bot.
func _spawn_player(data: Variant) -> Node:
	var d: Dictionary = data
	var player: Player = PLAYER_SCENE.instantiate()
	player.peer_id = d["peer"]
	player.is_bot = d.get("bot", false)
	player.name = str(player.peer_id)
	player.display_name = d["name"]
	player.setup(d["role"])
	player.position = d["pos"]
	player.rotation.y = d["yaw"]
	player.set_multiplayer_authority(1 if player.is_bot else player.peer_id)  # recursive: the body, its components, BodySync…
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


## Test-only (M8): kick the sender, to test the client's "kicked" message. Refused unless debug_allowed().
@rpc("any_peer", "reliable")
func request_debug_kick_me() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not debug_allowed():
		Log.warn("session", "refused a debug kick from peer %d" % peer)
		return
	kick(peer, "Kicked for testing")


## Test-only (M6 bots): put the plant in a state that would take minutes of play. `what`:
## "health" sets subsystem `id`'s health to `value` (0 also takes it offline), "core_temp" sets the
## core temperature. Refused unless debug_allowed() on the server.
@rpc("any_peer", "reliable")
func request_debug_plant(what: String, id: StringName, value: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not debug_allowed() or not plant.debug_set(what, id, value):
		Log.warn("session", "refused a debug plant change from peer %d (%s %s %s)" % [peer, what, id, value])
		return
	Log.info("session", "debug plant change by %s: %s %s = %s" % [name_of(peer), what, id, value])


# --- Client side ------------------------------------------------------------

func _on_connected() -> void:
	Log.info("session", "connected, requesting to join as '%s'" % desired_name)
	request_join.rpc_id(1, desired_name, game_version(), level_id(), desired_password)


func _on_connection_failed(reason: String) -> void:
	_leave_to_menu(LeaveReason.Code.TIMEOUT if reason == Net.FAIL_TIMEOUT else LeaveReason.Code.CANNOT_CONNECT, "")


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
func on_join_rejected(code: int, detail: String) -> void:
	Log.info("session", "join rejected: %s" % LeaveReason.log_text(code, detail))
	_leave_to_menu(code, detail)


@rpc("authority", "reliable")
func on_kicked(reason: String) -> void:
	_leave_to_menu(LeaveReason.Code.KICKED, reason)


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


## Client: leave the server on purpose (the pause menu's Leave, Cancel while connecting).
func leave() -> void:
	_leave_to_menu(LeaveReason.Code.NONE, "")


## Client: tear the session down and reopen the menu, which explains `code`. Safe to call more than once.
func _leave_to_menu(code: LeaveReason.Code, detail: String) -> void:
	if _leaving:
		return
	_leaving = true
	Log.info("session", "back to menu: %s" % LeaveReason.log_text(code, detail))
	MainMenu.leave_code = code
	MainMenu.leave_detail = detail
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_teardown.call_deferred()


func _level_environment() -> Environment:
	var world_env := level.find_child("WorldEnvironment", false, false) as WorldEnvironment if level != null else null
	return world_env.environment if world_env != null else null


func _teardown() -> void:
	var tree := get_tree()
	# Out of the tree first (also so the name "Session" is free if we reconnect right away), then
	# drop the connection: the multiplayer node cache forgets nodes as they leave the tree, so it is
	# (nearly) empty when the peer resets. Godot 4.7 release builds log "Attempt to disconnect a
	# nonexistent connection" for every node still cached at that moment.
	get_parent().remove_child(self)
	Net.leave()
	queue_free()
	# A join that failed or was cancelled: the menu is still open, it only has to explain.
	var scene := tree.current_scene
	var menu := scene as MainMenu if is_instance_valid(scene) else null
	if menu != null and not menu.is_queued_for_deletion():
		menu.show_leave_reason()
	else:
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
	var cctv := CctvView.new()
	cctv.name = "CctvView"
	client_only.add_child(cctv)
	var minigame_host := MinigameHost.new()
	minigame_host.name = "MinigameHost"
	client_only.add_child(minigame_host)
	var alarm := AlarmEffects.new()
	alarm.name = "AlarmEffects"
	client_only.add_child(alarm)
	var music := MusicDirector.new()
	music.name = "MusicDirector"
	client_only.add_child(music)
	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	client_only.add_child(overlay)
	# M8: the event feed, first-time hints, the scoreboard (Tab) and the pause menu (Esc). Then the
	# minimap and the full map (M).
	for node: Node in [EventFeed.new(), Hints.new(), Scoreboard.new(), PauseMenu.new(), MapOverlay.new()]:
		node.name = (node.get_script() as Script).get_global_name()
		client_only.add_child(node)
	if OS.is_debug_build() and DebugHooks.wanted():
		var hooks := DebugHooks.new()
		hooks.name = "DebugHooks"
		client_only.add_child(hooks)
