extends Node
## Networking: host/join/leave and connection signals. LAN discovery comes later (M8).
##
## Everything here wraps Godot's high-level multiplayer API: once `multiplayer.multiplayer_peer`
## is an ENet peer, `@rpc` calls and MultiplayerSpawner/Synchronizer nodes start talking to the
## other side. The server always has peer id 1; clients get random ids.

signal connected  ## client: the ENet connection to the server is up (the join handshake comes next)
signal connection_failed(reason: String)  ## client: could not reach the server
signal disconnected  ## client: lost the connection to the server
signal peer_joined(id: int)  ## server: a client connected
signal peer_left(id: int)  ## server: a client disconnected (or timed out)

const DEFAULT_PORT := 7777
const CONNECT_TIMEOUT_S := 5.0
## ENet drops a peer that hasn't acknowledged a packet within this time, so a killed process
## disappears in about 5 s instead of ENet's default of up to 30 s.
const PEER_TIMEOUT_MIN_MS := 2000
const PEER_TIMEOUT_MAX_MS := 5000

## True in the dedicated server process once `host()` succeeded.
var is_server := false

var _connect_timer: Timer


func _ready() -> void:
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _notification(what: int) -> void:
	# Closing the window: tell the other side right away instead of letting it time out.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()


func host(port: int, max_clients: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	return OK


func join(address: String, port: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_timer.start(CONNECT_TIMEOUT_S)
	return OK


func leave() -> void:
	_connect_timer.stop()
	is_server = false
	var peer := multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Client: the round-trip time to the server in ms (ENet's estimate), -1 when not connected.
func ping_ms() -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if is_server or enet == null or not is_online():
		return -1
	var server := enet.get_peer(1)
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if server != null else -1


## Server: drop a client (no-op if it already left).
func kick(peer_id: int) -> void:
	if is_server and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## Parses "host:port" or "host" into {"host": String, "port": int}. Returns {} if invalid.
static func parse_address(text: String, default_port: int = DEFAULT_PORT) -> Dictionary:
	var s := text.strip_edges()
	var host := s
	var port := default_port
	var colon := s.rfind(":")
	if colon != -1:
		host = s.substr(0, colon)
		var port_text := s.substr(colon + 1)
		if not port_text.is_valid_int():
			return {}
		port = port_text.to_int()
	if host.is_empty() or host.contains(":") or host.contains(" ") or port < 1 or port > 65535:
		return {}
	return {"host": host, "port": port}


func _apply_timeout(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var packet_peer := enet.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_connected(id: int) -> void:
	if is_server:
		_apply_timeout(id)
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if is_server:
		peer_left.emit(id)


func _on_connected_to_server() -> void:
	_connect_timer.stop()
	_apply_timeout(1)
	connected.emit()


# The three handlers below run inside the multiplayer poll, so the peer is reset deferred
# (replacing `multiplayer_peer` while it is being polled is asking for trouble).
func _on_connection_failed() -> void:
	_connect_timer.stop()
	leave.call_deferred()
	connection_failed.emit("Could not reach the server")


func _on_server_disconnected() -> void:
	leave.call_deferred()
	disconnected.emit()


func _on_connect_timeout() -> void:
	leave()
	connection_failed.emit("Connection timed out")
