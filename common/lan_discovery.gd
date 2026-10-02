class_name LanDiscovery
extends RefCounted
## LAN discovery (M8): the protocol, and the list of servers a client has heard about.
##
## Every ANNOUNCE_S a server (server/lan_announcer.gd) broadcasts a small JSON packet:
##   {"game": "homersim", "id": <random per server process>, "name", "players", "max", "port",
##    "version", "state": "lobby"|"starting"|"playing"|"results", "locked": bool}
## to every port of PORTS on 255.255.255.255 (the LAN) and on 127.0.0.1 (this machine, which also
## works with no network at all). A client (client/lan_browser.gd) listens on the first free port of
## PORTS: Godot can't share a UDP port between processes, and several clients on one PC (testing
## alone) each need their own. A client measures the ping by sending {"game", "ping": <token>} back to
## the address an announcement came from; the server answers {"game", "pong": <token>}.
## Servers not heard from for EXPIRE_S disappear from the list.
##
## Windows' firewall asks, the first time the game or the server listens, whether to allow it on
## private networks: say yes, or LAN servers stay invisible.

const GAME_TAG := "homersim"
const PORTS: Array[int] = [7778, 7779, 7780, 7781]
const ANNOUNCE_S := 2.0
const EXPIRE_S := 6.0
const MAX_PACKET := 1024
const MAX_NAME := 40
const STATES: Array[String] = ["lobby", "starting", "playing", "results"]

## id -> {"id", "name", "players", "max", "port", "version", "state", "locked", "address" (ip the
## announcement came from), "reply_port" (where pings go), "seen" (s), "ping_ms" (-1 = not yet)}
var servers: Dictionary = {}


## The announcement packet for `info` (the keys listed above, without "game").
static func encode_announce(info: Dictionary) -> PackedByteArray:
	var data := info.duplicate()
	data["game"] = GAME_TAG
	return JSON.stringify(data).to_utf8_buffer()


static func encode_ping(token: int) -> PackedByteArray:
	return JSON.stringify({"game": GAME_TAG, "ping": token}).to_utf8_buffer()


static func encode_pong(token: int) -> PackedByteArray:
	return JSON.stringify({"game": GAME_TAG, "pong": token}).to_utf8_buffer()


## A received packet as a Dictionary with a "kind" of "announce", "ping" or "pong", or {} if it is
## not ours or malformed (anyone on the LAN can send anything to these ports).
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET:
		return {}
	var json := JSON.new()  # (the instance parser stays quiet about garbage; JSON.parse_string logs it)
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var d: Dictionary = json.data
	if d.get("game") != GAME_TAG:
		return {}
	if d.has("ping") and _is_number(d["ping"]):
		return {"kind": "ping", "token": int(d["ping"])}
	if d.has("pong") and _is_number(d["pong"]):
		return {"kind": "pong", "token": int(d["pong"])}
	for key in ["id", "players", "max", "port"]:
		if not _is_number(d.get(key)):
			return {}
	var server_port := int(d["port"])
	if server_port < 1 or server_port > 65535:
		return {}
	var state := str(d.get("state", "lobby"))
	return {
		"kind": "announce",
		"id": int(d["id"]),
		"name": ChatService.clean(str(d.get("name", "?"))).substr(0, MAX_NAME),
		"players": clampi(int(d["players"]), 0, 99),
		"max": clampi(int(d["max"]), 1, 99),
		"port": server_port,
		"version": str(d.get("version", "")).substr(0, 64),
		"state": state if state in STATES else "lobby",
		"locked": d.get("locked", false) == true,
	}


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


## An announcement `packet` (decoded) arrived from `ip`:`reply_port` at `now` (seconds). Returns true
## for a server we hadn't heard of yet. The first address heard is kept (a local server arrives both
## through the LAN and through 127.0.0.1).
func heard(packet: Dictionary, ip: String, reply_port: int, now: float) -> bool:
	var id: int = packet["id"]
	var known: Dictionary = servers.get(id, {})
	var entry := packet.duplicate()
	entry.erase("kind")
	entry["address"] = known.get("address", ip)
	entry["reply_port"] = known.get("reply_port", reply_port)
	entry["seen"] = now
	entry["ping_ms"] = known.get("ping_ms", -1)
	servers[id] = entry
	return known.is_empty()


## A pong for the server `id`: its round trip took `rtt_s` seconds.
func got_pong(id: int, rtt_s: float) -> void:
	if servers.has(id):
		servers[id]["ping_ms"] = roundi(rtt_s * 1000.0)


## Forgets servers not heard from for EXPIRE_S. Returns true if any went.
func expire(now: float) -> bool:
	var gone: Array = []
	for id: int in servers:
		if now - float(servers[id]["seen"]) > EXPIRE_S:
			gone.append(id)
	for id: int in gone:
		servers.erase(id)
	return not gone.is_empty()


## The servers sorted for display: joinable lobbies first, then by name.
func sorted() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entry: Dictionary in servers.values():
		list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_open: bool = a["state"] == "lobby" and a["players"] < a["max"]
		var b_open: bool = b["state"] == "lobby" and b["players"] < b["max"]
		if a_open != b_open:
			return a_open
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return list


## "host:port" to join `entry`.
static func address_of(entry: Dictionary) -> String:
	return "%s:%d" % [entry["address"], entry["port"]]
