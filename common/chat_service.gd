class_name ChatService
extends Node
## Text chat. A client calls send(); the server checks the request (sender joined, length,
## 1 message/s) and strips BBCode brackets, then relays on_message to the recipients.
## An empty from_name marks a system message (joins, leaves, warnings).
## M2: only the ALL channel. TEAM and GHOST arrive in M4.

enum Channel { ALL, TEAM, GHOST, SYSTEM }

const MAX_LENGTH := 200
const MIN_INTERVAL_MS := 1000

signal message_received(from_name: String, text: String, channel: Channel)

var _last_sent_ms: Dictionary[int, int] = {}  # server: peer -> time of its last accepted message


## Drops control characters and the BBCode brackets `[` `]`, trims the ends.
static func clean(raw: String) -> String:
	var kept := ""
	for c in raw:
		if c.unicode_at(0) >= 32 and c != "[" and c != "]":
			kept += c
	return kept.strip_edges()


## True if a peer whose last message was at `last_ms` may send another at `now_ms`.
static func rate_ok(last_ms: int, now_ms: int) -> bool:
	return now_ms - last_ms >= MIN_INTERVAL_MS


## Client: send a message.
func send(text: String, channel: Channel = Channel.ALL) -> void:
	request_send.rpc_id(1, text, channel)


## Server: a message from "the server" to everyone.
func broadcast_system(text: String) -> void:
	Log.info("chat", "* %s" % text)
	for peer: int in Session.current.players:
		on_message.rpc_id(peer, "", text, Channel.SYSTEM)


## Server: forget a peer that left.
func forget(peer_id: int) -> void:
	_last_sent_ms.erase(peer_id)


@rpc("any_peer", "reliable")
func request_send(text: String, channel: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var info: PlayerInfo = Session.current.players.get(peer)
	if info == null or channel != Channel.ALL or text.length() > MAX_LENGTH:
		return  # unknown sender, channel not available yet, or a client that ignores the limit
	var cleaned := clean(text)
	if cleaned.is_empty():
		return
	var now := Time.get_ticks_msec()
	if _last_sent_ms.has(peer) and not rate_ok(_last_sent_ms[peer], now):
		on_message.rpc_id(peer, "", "Slow down: one message per second.", Channel.SYSTEM)
		return
	_last_sent_ms[peer] = now
	Log.info("chat", "%s: %s" % [info.name, cleaned])
	for other: int in Session.current.players:
		on_message.rpc_id(other, info.name, cleaned, channel)


@rpc("authority", "reliable")
func on_message(from_name: String, text: String, channel: int) -> void:
	Log.info("chat", ("* %s" % text) if from_name.is_empty() else ("%s: %s" % [from_name, text]))
	message_received.emit(from_name, text, channel)
	Events.chat_message.emit(from_name, text, channel)
