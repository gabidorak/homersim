class_name LanAnnouncer
extends Node
## Server (M8): tells the LAN this server exists, every LanDiscovery.ANNOUNCE_S, and answers the
## browsers' pings (see common/lan_discovery.gd for the protocol). Lives under Session/ServerOnly;
## `--no-lan` turns it off (the integration tests use it, so a test run doesn't show up in the
## server browser of everyone on the network).

const BROADCAST := "255.255.255.255"
const LOOPBACK := "127.0.0.1"

var _socket := PacketPeerUDP.new()
var _id := 0
var _timer: Timer
var _warned := false

@onready var session: Session = Session.current


func _ready() -> void:
	_id = randi() & 0x7fffffff
	_socket.set_broadcast_enabled(true)
	var err := _socket.bind(0)  # any free port: browsers answer to wherever announcements come from
	if err != OK:
		Log.warn("lan", "no LAN announcements: cannot open a UDP socket (%s)" % error_string(err))
		set_process(false)
		return
	_timer = Timer.new()
	_timer.wait_time = LanDiscovery.ANNOUNCE_S
	_timer.timeout.connect(announce)
	add_child(_timer)
	_timer.start()
	announce.call_deferred()
	Log.info("lan", "announcing '%s' on the LAN (UDP %d-%d)" % [session.server_name, LanDiscovery.PORTS[0],
		LanDiscovery.PORTS[-1]])


func _exit_tree() -> void:
	_socket.close()


## What the announcements say: Session.public_info(), plus this server's id on the LAN.
func info() -> Dictionary:
	var data := session.public_info()
	data["id"] = _id
	return data


func announce() -> void:
	var packet := LanDiscovery.encode_announce(info())
	var sent := 0
	for host in [BROADCAST, LOOPBACK]:
		for port in LanDiscovery.PORTS:
			_socket.set_dest_address(host, port)
			if _socket.put_packet(packet) == OK:
				sent += 1
	if sent == 0 and not _warned:
		_warned = true
		Log.warn("lan", "could not send any LAN announcement")


func _process(_delta: float) -> void:
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var port := _socket.get_packet_port()
		var packet := LanDiscovery.decode(bytes)
		if packet.get("kind") == "ping" and ip != "":
			_socket.set_dest_address(ip, port)
			_socket.put_packet(LanDiscovery.encode_pong(packet["token"]))
