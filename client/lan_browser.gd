class_name LanBrowser
extends Node
## Client (M8): listens for LAN server announcements and pings the servers it hears (protocol in
## common/lan_discovery.gd). The server browser owns one while it is open; `list` holds what was
## found and `changed` fires whenever it changes (new server, new numbers, ping, expiry).

signal changed

const PING_EVERY_S := 2.0

var list := LanDiscovery.new()
## The UDP port we listen on, or 0 if every port of LanDiscovery.PORTS was taken.
var port := 0

var _socket := PacketPeerUDP.new()
var _pings: Dictionary = {}  # token -> [server id, sent at (s)]
var _next_token := 1
var _last_ping: Dictionary = {}  # server id -> when we last pinged it (s)


func _ready() -> void:
	for candidate in LanDiscovery.PORTS:
		if _socket.bind(candidate) == OK:
			port = candidate
			break
	if port == 0:
		Log.warn("lan", "LAN discovery off: UDP ports %d-%d are all in use (other copies of the game?)"
			% [LanDiscovery.PORTS[0], LanDiscovery.PORTS[-1]])
		set_process(false)
	else:
		Log.info("lan", "listening for LAN servers on UDP %d" % port)


func _exit_tree() -> void:
	_socket.close()


func is_listening() -> bool:
	return port != 0


func _process(_delta: float) -> void:
	var now := Net.local_time()
	var dirty := false
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var reply_port := _socket.get_packet_port()
		var packet := LanDiscovery.decode(bytes)
		match packet.get("kind", ""):
			"announce":
				if list.heard(packet, ip, reply_port, now):
					Log.info("lan", "found '%s' at %s:%d" % [packet["name"], ip, packet["port"]])
				dirty = true
			"pong":
				var sent: Array = _pings.get(packet["token"], [])
				if not sent.is_empty():
					_pings.erase(packet["token"])
					list.got_pong(sent[0], now - float(sent[1]))
					dirty = true
	if list.expire(now):
		dirty = true
	for id: int in list.servers:
		if now - float(_last_ping.get(id, -INF)) >= PING_EVERY_S:
			_ping(id, now)
	if dirty:
		changed.emit()


func _ping(id: int, now: float) -> void:
	var entry: Dictionary = list.servers[id]
	_last_ping[id] = now
	var token := _next_token
	_next_token += 1
	_pings[token] = [id, now]
	_socket.set_dest_address(entry["address"], entry["reply_port"])
	_socket.put_packet(LanDiscovery.encode_ping(token))
	# Forget pings that never came back.
	for old: int in _pings.keys():
		if now - float(_pings[old][1]) > LanDiscovery.EXPIRE_S:
			_pings.erase(old)
