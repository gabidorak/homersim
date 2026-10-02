class_name ChatService
extends Node
## Text chat. A client calls send(); the server checks the request (sender joined, length,
## 1 message/s, channel allowed) and strips BBCode brackets, then relays on_message to the
## recipients. An empty from_name marks a system message (joins, leaves, warnings): its text is an
## English format string and `args` its values, so each client shows it in its own language
## (tr(text) % args, M8). Gameplay events (cages, sabotages…) go to the event feed instead
## (MatchManager.feed).
##
## Channels (routing is server-side, see route()):
##   ALL    everyone
##   TEAM   (T key) the sender's team, during a match only
##   GHOST  eliminated players and spectators, during a match. Living players never receive it,
##          and ghosts can't talk to the living: whatever channel a ghost picks becomes GHOST.

enum Channel { ALL, TEAM, GHOST, SYSTEM }

const MAX_LENGTH := 200
const MIN_INTERVAL_MS := 1000

signal message_received(from_name: String, text: String, channel: Channel)  ## text already translated

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


## Where a message goes. `members`: peer -> {"role": Role.Kind, "ghost": bool} for every joined
## player (ghost = eliminated or spectating during a match). Returns
## {"channel": Channel actually used, "to": Array[int], "error": String}; a non-empty error
## means the message is refused.
static func route(channel: int, sender: int, members: Dictionary, in_match: bool) -> Dictionary:
	var me: Dictionary = members.get(sender, {})
	if me.is_empty() or channel not in [Channel.ALL, Channel.TEAM, Channel.GHOST]:
		return {"channel": channel, "to": [] as Array[int], "error": "not allowed"}
	var ghost: bool = in_match and me.get("ghost", false)
	if ghost:
		channel = Channel.GHOST
	elif channel == Channel.GHOST:
		return {"channel": channel, "to": [] as Array[int], "error": "Only eliminated players can use the ghost chat."}
	var role: Role.Kind = me.get("role", Role.Kind.NONE)
	if channel == Channel.TEAM and (not in_match or role not in [Role.Kind.SUPERVISOR, Role.Kind.RAT]):
		return {"channel": channel, "to": [] as Array[int], "error": "Team chat only works during a match."}
	var to: Array[int] = []
	for peer: int in members:
		var m: Dictionary = members[peer]
		match channel:
			Channel.ALL:
				to.append(peer)
			Channel.TEAM:
				if m.get("role", Role.Kind.NONE) == role:
					to.append(peer)
			Channel.GHOST:
				if m.get("ghost", false):
					to.append(peer)
	return {"channel": channel, "to": to, "error": ""}


## Client: send a message.
func send(text: String, channel: Channel = Channel.ALL) -> void:
	request_send.rpc_id(1, text, channel)


## Server: a message from "the server" to everyone. `text` is an English format string for `args`.
func broadcast_system(text: String, args: Array = []) -> void:
	Log.info("chat", "* %s" % format(text, args, false))
	for peer: int in Session.current.players:
		on_message.rpc_id(peer, "", text, Channel.SYSTEM, args)


## Server: a system message to one peer.
func tell(peer_id: int, text: String, args: Array = []) -> void:
	on_message.rpc_id(peer_id, "", text, Channel.SYSTEM, args)


## A system message's text: `text` (translated when `translate`) with `args` filled in. A format
## that doesn't match its args shows as is rather than failing.
static func format(text: String, args: Array, translate: bool = true) -> String:
	var pattern: String = TranslationServer.translate(text) if translate else text
	if args.is_empty():
		return pattern
	var count := pattern.count("%s") + pattern.count("%d")
	return pattern % args if count == args.size() else text


## Server: forget a peer that left.
func forget(peer_id: int) -> void:
	_last_sent_ms.erase(peer_id)


@rpc("any_peer", "reliable")
func request_send(text: String, channel: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var info: PlayerInfo = Session.current.players.get(peer)
	if info == null or text.length() > MAX_LENGTH:
		return  # unknown sender, or a client that ignores the limit
	var cleaned := clean(text)
	if cleaned.is_empty():
		return
	var mm := Session.current.match_manager
	var routed := route(channel, peer, mm.chat_members(), mm.in_match())
	if routed["error"] != "":
		Log.info("chat", "refused %s's message on channel %s: %s" % [info.name, channel, routed["error"]])
		tell(peer, routed["error"])
		return
	var now := Time.get_ticks_msec()
	if _last_sent_ms.has(peer) and not rate_ok(_last_sent_ms[peer], now):
		tell(peer, "Slow down: one message per second.")
		return
	_last_sent_ms[peer] = now
	var used: int = routed["channel"]
	Log.info("chat", "%s%s: %s" % [_tag(used), info.name, cleaned])
	for other: int in routed["to"]:
		on_message.rpc_id(other, info.name, cleaned, used, [])


@rpc("authority", "reliable")
func on_message(from_name: String, text: String, channel: int, args: Array) -> void:
	if from_name.is_empty():
		Log.info("chat", "* %s" % format(text, args, false))
		text = format(text, args)
	else:
		Log.info("chat", "%s%s: %s" % [_tag(channel), from_name, text])
	message_received.emit(from_name, text, channel)
	Events.chat_message.emit(from_name, text, channel)


static func _tag(channel: int) -> String:
	match channel:
		Channel.TEAM:
			return "(team) "
		Channel.GHOST:
			return "(ghost) "
	return ""
