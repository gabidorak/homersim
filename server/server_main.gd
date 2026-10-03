extends Node
## Dedicated server boot: reads server.cfg + CLI overrides, hosts, then adds the shared
## Session at /root/Session. The server has no camera and no player body.
## Started without --headless (the editor's Run Instances, a terminal) it still gets a window, which
## it doesn't render (_windowed).

const SESSION_SCENE: PackedScene = preload("res://common/Session.tscn")
## Extra ENet slots beyond max_players. Without them ENet itself refuses surplus clients, who then
## only see "could not reach the server"; with them they connect and get a clear "Server full".
const EXTRA_SLOTS := 2
const SERVER_NAME_DEFAULT := "HomerSim server"
const WINDOWED_MAX_FPS := 120  ## a windowed server draws nothing, so nothing else paces its main loop


func _ready() -> void:
	Log.info("server", "server boot")
	if DisplayServer.get_name() != "headless":
		_windowed()
	_boot.call_deferred()  # deferred: the root node is still busy adding this scene


## A server with a window has nothing to show in it, and on Wayland a window hidden behind another one
## is throttled by the compositor to about one frame per second. With V-Sync on, Godot waits for those
## frames, so the whole server (physics, the AI bots) ran once a second. So: V-Sync off, a frame cap
## instead, a note in the window, then no rendering at all.
func _windowed() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = WINDOWED_MAX_FPS
	var note := Label.new()
	note.text = "HomerSim dedicated server\n\nThis window shows nothing: the log is in the terminal.\nStart the server with --headless to run it without a window."
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(note)
	await RenderingServer.frame_post_draw
	RenderingServer.render_loop_enabled = false
	Log.info("server", "running in a window: rendering is off (start with --headless to have no window)")


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
	var server_name := ChatService.clean(str(cfg["name"])).substr(0, LanDiscovery.MAX_NAME)
	session.server_name = server_name if server_name != "" else SERVER_NAME_DEFAULT
	session.password = Cli.get_str("password", str(cfg["password"]))
	get_tree().root.add_child(session)
	Log.info("server", "'%s' listening on UDP %d, max %d players, version %s%s"
		% [session.server_name, port, max_players, Session.game_version(), ", password protected" if session.password != "" else ""])


## From source: the project folder. Exported: next to the server binary.
func _default_config_path() -> String:
	if OS.has_feature("editor"):
		return "res://server.cfg"
	return OS.get_executable_path().get_base_dir().path_join("server.cfg")
