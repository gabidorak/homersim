extends Node
## Dedicated server boot: reads server.cfg + CLI overrides, hosts, then adds the shared
## Session at /root/Session. The server has no camera and no player body.

const SESSION_SCENE: PackedScene = preload("res://common/Session.tscn")
## Extra ENet slots beyond max_players. Without them ENet itself refuses surplus clients, who then
## only see "could not reach the server"; with them they connect and get a clear "Server full".
const EXTRA_SLOTS := 2


func _ready() -> void:
	Log.info("server", "server boot")
	_boot.call_deferred()  # deferred: the root node is still busy adding this scene


func _boot() -> void:
	var path := Cli.get_str("config", _default_config_path())
	var cfg := Config.load_server_config(path)
	var port := Cli.get_int("port", int(cfg["port"]))
	var max_players := clampi(Cli.get_int("max-players", int(cfg["max_players"])), 1, 16)

	var err := Net.host(port, max_players + EXTRA_SLOTS)
	if err != OK:
		Log.error("server", "cannot listen on UDP port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return

	var session: Session = SESSION_SCENE.instantiate()
	session.max_players = max_players
	session.match_rules = Config.load_match_rules(path)
	get_tree().root.add_child(session)
	Log.info("server", "'%s' listening on UDP %d, max %d players, version %s"
		% [cfg["name"], port, max_players, Session.game_version()])


## From source: the project folder. Exported: next to the server binary.
func _default_config_path() -> String:
	if OS.has_feature("editor"):
		return "res://server.cfg"
	return OS.get_executable_path().get_base_dir().path_join("server.cfg")
