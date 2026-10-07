class_name HttpServer
extends Node
## A minimal HTTP/1.1 server for the launcher's JSON API (common/online_api.gd): one request per
## connection, answered with Connection: close. On the VPS only Caddy talks to it (it terminates
## HTTPS and forwards plain HTTP), but it still caps everything: header and body sizes
## (OnlineApi.parse_request), REQUEST_TIMEOUT_S to send a request, MAX_CONNECTIONS at once.
## An answer may wait (a new game takes a few seconds to start): the Exchange stays open until
## respond() is called or the other side hangs up.

signal request_received(exchange: Exchange)

const REQUEST_TIMEOUT_S := 10.0  ## to send the whole request
const ANSWER_TIMEOUT_S := 300.0  ## the most an answer may take (the launcher answers within ~2 min)
const MAX_CONNECTIONS := 16


## One connection: the request it sent, and its answer.
class Exchange:
	extends RefCounted
	var peer: StreamPeerTCP
	var ip := ""
	var request: Dictionary = {}  # OnlineApi.parse_request() once done
	var answered := false
	var buffer := PackedByteArray()
	var deadline_ms := 0

	func _init(p_peer: StreamPeerTCP) -> void:
		peer = p_peer
		ip = peer.get_connected_host()
		deadline_ms = Time.get_ticks_msec() + int(REQUEST_TIMEOUT_S * 1000.0)

	## Sends the answer and closes the connection. Does nothing if it was already answered, or if the
	## other side is gone.
	func respond(status: int, data: Dictionary) -> void:
		if answered:
			return
		answered = true
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data(OnlineApi.response(status, data))
		peer.disconnect_from_host()

	func is_open() -> bool:
		return not answered and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


var port := 0  ## the TCP port it listens on, once listening

var _server := TCPServer.new()
var _exchanges: Array[Exchange] = []


## Starts listening on `bind` ("*" = every address). `listen_port` 0 = any free port.
func listen(listen_port: int, bind: String) -> Error:
	var err := _server.listen(listen_port, bind)
	if err == OK:
		port = _server.get_local_port()
	return err


func _exit_tree() -> void:
	for exchange in _exchanges:
		exchange.peer.disconnect_from_host()
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		var peer := _server.take_connection()
		if _exchanges.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()  # too many at once: the client retries
			continue
		_exchanges.append(Exchange.new(peer))
	var now := Time.get_ticks_msec()
	for exchange: Exchange in _exchanges.duplicate():
		exchange.peer.poll()
		if not exchange.is_open():
			_exchanges.erase(exchange)
			continue
		if not exchange.request.is_empty():
			if now > exchange.deadline_ms + int(ANSWER_TIMEOUT_S * 1000.0):
				exchange.respond(500, {"error": OnlineApi.ERR_START})
			continue  # (waiting for the answer)
		var available := exchange.peer.get_available_bytes()
		if available > 0:
			var got: Array = exchange.peer.get_partial_data(available)
			if got[0] == OK:
				exchange.buffer.append_array(got[1])
		var parsed := OnlineApi.parse_request(exchange.buffer)
		if parsed.has("error"):
			exchange.respond(int(parsed["error"]), {"error": OnlineApi.ERR_BAD_REQUEST})
		elif parsed.get("done", false):
			exchange.request = parsed
			request_received.emit(exchange)
		elif now > exchange.deadline_ms:
			exchange.respond(408, {"error": OnlineApi.ERR_BAD_REQUEST})
