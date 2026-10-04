extends Node
## Networking: host/join/leave and connection signals. LAN discovery (M8) lives in
## common/lan_discovery.gd (the protocol), server/lan_announcer.gd and client/lan_browser.gd.
##
## Everything here wraps Godot's high-level multiplayer API: once `multiplayer.multiplayer_peer`
## is an ENet peer, `@rpc` calls and MultiplayerSpawner/Synchronizer nodes start talking to the
## other side. The server always has peer id 1; clients get random ids.
##
## Server clock (M6): server_time() is the server's clock on every machine, so things that run on a
## schedule (hazard cycles, cooldowns) can be synced once as a start time and animated locally.
## After connecting, a client asks for the server's time a few times (then every RESYNC_S) and keeps
## the answer that came back fastest: offset = server time + half the round trip - our time.
## An autoload has the same path (/root/Net) everywhere, so it can carry these RPCs.

signal connected  ## client: the ENet connection to the server is up (the join handshake comes next)
signal connection_failed(reason: String)  ## client: could not reach the server
signal disconnected  ## client: lost the connection to the server
signal peer_joined(id: int)  ## server: a client connected
signal peer_left(id: int)  ## server: a client disconnected (or timed out)

const DEFAULT_PORT := 7777
const CONNECT_TIMEOUT_S := 5.0
## connection_failed reasons.
const FAIL_UNREACHABLE := "Could not reach the server"
const FAIL_TIMEOUT := "Connection timed out"
## ENet drops a peer that hasn't acknowledged a packet within this time, so a killed process
## disappears in about 5 s instead of ENet's default of up to 30 s.
const PEER_TIMEOUT_MIN_MS := 2000
const PEER_TIMEOUT_MAX_MS := 5000
const SYNC_SAMPLES := 5  ## clock requests right after connecting…
const SYNC_SAMPLE_GAP_S := 0.2
const RESYNC_S := 10.0  ## …then one every RESYNC_S

## True in the dedicated server process once `host()` succeeded.
var is_server := false
## Server: the UDP port it listens on (the LAN announcements carry it).
var port := 0

var _connect_timer: Timer
var _sync_timer: Timer
var _sync_sent := 0
var _clock_offset := 0.0  # client: server clock - our clock
var _best_rtt := INF  # client: round trip of the sample the offset comes from


func _ready() -> void:
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)
	_sync_timer = Timer.new()
	_sync_timer.timeout.connect(_send_clock_sync)
	add_child(_sync_timer)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _notification(what: int) -> void:
	# Closing the window: tell the other side right away instead of letting it time out.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()


## Listens on UDP `listen_port` (0 = any free port: `port` then tells which). `bind_ip` limits it to
## one address of this machine, e.g. 127.0.0.1 for a solo game nobody else can reach.
func host(listen_port: int, max_clients: int, bind_ip: String = "*") -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if bind_ip != "*":
		if not bind_ip.is_valid_ip_address():
			return ERR_INVALID_PARAMETER
		peer.set_bind_ip(bind_ip)
	var err := peer.create_server(listen_port, max_clients)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	port = peer.host.get_local_port()
	return OK


func join(address: String, server_port: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, server_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_timer.start(CONNECT_TIMEOUT_S)
	return OK


func leave() -> void:
	_connect_timer.stop()
	_sync_timer.stop()
	_clock_offset = 0.0
	_best_rtt = INF
	is_server = false
	port = 0
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


## Server: a client's round-trip time in ms (ENet's estimate), -1 if unknown.
func peer_ping_ms(peer_id: int) -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not is_server or enet == null:
		return -1
	var packet_peer := enet.get_peer(peer_id)
	return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if packet_peer != null else -1


## Seconds on the server's clock (on the server: its own clock). Comparable across machines.
func server_time() -> float:
	return local_time() + _clock_offset


## Client: true once at least one clock sample came back.
func clock_synced() -> bool:
	return is_server or _best_rtt < INF


## This machine's monotonic clock in seconds (the same one PlantSim and StatusComponent use).
static func local_time() -> float:
	return Time.get_ticks_usec() / 1000000.0


## The offset to add to our clock to get the server's, from one sample: we sent at `sent`, the
## server answered with its time `server_now`, and the answer arrived at `received`. Assumes the
## trip took as long both ways.
static func clock_offset(sent: float, server_now: float, received: float) -> float:
	return server_now + (received - sent) * 0.5 - received


## Server: drop a client (no-op if it already left).
func kick(peer_id: int) -> void:
	if is_server and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## Parses "host:port" or "host" into {"host": String, "port": int}. Returns {} if invalid.
static func parse_address(text: String, default_port: int = DEFAULT_PORT) -> Dictionary:
	var s := text.strip_edges()
	var host := s
	var parsed_port := default_port
	var colon := s.rfind(":")
	if colon != -1:
		host = s.substr(0, colon)
		var port_text := s.substr(colon + 1)
		if not port_text.is_valid_int():
			return {}
		parsed_port = port_text.to_int()
	if host.is_empty() or host.contains(":") or host.contains(" ") or parsed_port < 1 or parsed_port > 65535:
		return {}
	return {"host": host, "port": parsed_port}


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
	_sync_sent = 0
	_send_clock_sync()
	connected.emit()


func _send_clock_sync() -> void:
	if is_server or not is_online():
		_sync_timer.stop()
		return
	_sync_sent += 1
	_sync_timer.start(SYNC_SAMPLE_GAP_S if _sync_sent < SYNC_SAMPLES else RESYNC_S)
	request_clock_sync.rpc_id(1, local_time())


# Unreliable both ways: a resent packet would only give a slow sample, which gets ignored anyway.
@rpc("any_peer", "unreliable")
func request_clock_sync(client_sent: float) -> void:
	if not is_server:
		return
	on_clock_sync.rpc_id(multiplayer.get_remote_sender_id(), client_sent, local_time())


@rpc("authority", "unreliable")
func on_clock_sync(client_sent: float, server_now: float) -> void:
	var now := local_time()
	var rtt := now - client_sent
	if rtt < 0.0 or rtt >= _best_rtt:
		return  # the fastest answer gives the best estimate
	_best_rtt = rtt
	_clock_offset = clock_offset(client_sent, server_now, now)


# The three handlers below run inside the multiplayer poll, so the peer is reset deferred
# (replacing `multiplayer_peer` while it is being polled is asking for trouble).
func _on_connection_failed() -> void:
	_connect_timer.stop()
	leave.call_deferred()
	connection_failed.emit(FAIL_UNREACHABLE)


func _on_server_disconnected() -> void:
	leave.call_deferred()
	disconnected.emit()


func _on_connect_timeout() -> void:
	leave()
	connection_failed.emit(FAIL_TIMEOUT)
