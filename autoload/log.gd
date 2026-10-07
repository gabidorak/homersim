extends Node
## Logging: `Log.info/warn/error(tag, msg)` prints `[HH:MM:SS][S|C<id>][tag] msg`.


func info(tag: String, msg: String) -> void:
	print(_format(tag, msg))


func warn(tag: String, msg: String) -> void:
	push_warning(_format(tag, msg))


func error(tag: String, msg: String) -> void:
	push_error(_format(tag, msg))


func _format(tag: String, msg: String) -> String:
	var time: String = Time.get_time_string_from_system()
	return "[%s][%s][%s] %s" % [time, _side(), tag, msg]


func _side() -> String:
	if Cli.has_arg("launcher"):
		return "L"  # the launcher of online games (its games' servers log "S" in the same output)
	if OS.has_feature("dedicated_server") or Cli.has_arg("server"):
		return "S"
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer \
			or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "C"
	return "C%d" % multiplayer.get_unique_id()
