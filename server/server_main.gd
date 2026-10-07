extends Node
## Dedicated server boot: reads server.cfg + CLI overrides, hosts, then adds the shared
## Session at /root/Session. The server has no camera and no player body.
## Started without --headless (the editor's Run Instances, a terminal) it still gets a window, which
## it doesn't render (_windowed).
## A player's game can start this server itself, for "Play solo" and "Host a game"
## (client/local_server.gd). It then passes, besides --config: --bind 127.0.0.1 (solo: nobody else can
## reach it), --port 0 (any free port), --ready-file PATH (written once the server listens:
## {"port": N, "version": V}, or {"error": "port", "port": N} if it can't), --owner-pid PID (stop when
## that game is gone) and --host-token T (Session.host_token: the server closes when the host leaves).
## The VPS launcher (server/launcher/launcher.gd) starts one per online game, with no host token and
## two more: --status-file PATH (Session.public_info() every ServerProcess.STATUS_EVERY_S, for the
## launcher's game list) and --idle-quit S (quit after S seconds with nobody in the game, counted from
## the start, so a game whose creator never joins goes too).

const SESSION_SCENE: PackedScene = preload("res://common/Session.tscn")
## Extra ENet slots beyond max_players. Without them ENet itself refuses surplus clients, who then
## only see "could not reach the server"; with them they connect and get a clear "Server full".
const EXTRA_SLOTS := 2
const SERVER_NAME_DEFAULT := "HomerSim server"
const WINDOWED_MAX_FPS := 120  ## a windowed server draws nothing, so nothing else paces its main loop
const OWNER_CHECK_S := 2.0  ## --owner-pid: how often to check that the game that started us still runs

var _owner: ProcessWatch
var _session: Session
var _idle_s := 0.0  # --idle-quit: how long nobody has been in the game


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

	var bind_ip := Cli.get_str("bind", "*")
	var err := Net.host(port, max_players + EXTRA_SLOTS, bind_ip)
	if err != OK:
		Log.error("server", "cannot listen on UDP port %d%s: %s" % [port, "" if bind_ip == "*" else " of " + bind_ip,
			error_string(err)])
		_write_file("ready-file", {"error": "port", "port": port})
		get_tree().quit(1)
		return

	var session: Session = SESSION_SCENE.instantiate()
	session.max_players = max_players
	session.match_rules = Config.load_match_rules(path)
	var server_name := ChatService.clean(str(cfg["name"])).substr(0, LanDiscovery.MAX_NAME)
	session.server_name = server_name if server_name != "" else SERVER_NAME_DEFAULT
	session.password = Cli.get_str("password", str(cfg["password"]))
	session.host_token = Cli.get_str("host-token")
	get_tree().root.add_child(session)
	Log.info("server", "'%s' listening on UDP %d%s, max %d players, version %s%s"
		% [session.server_name, Net.port, "" if bind_ip == "*" else " of " + bind_ip, max_players,
		Session.game_version(), ", password protected" if session.password != "" else ""])
	_session = session
	if Cli.has_arg("owner-pid"):
		_watch_owner(Cli.get_int("owner-pid"))
	if Cli.get_int("idle-quit") > 0:
		_add_timer(1.0, _check_idle)
		Log.info("server", "quits after %d s with nobody in the game" % Cli.get_int("idle-quit"))
	if Cli.get_str("status-file") != "":
		_add_timer(ServerProcess.STATUS_EVERY_S, _write_status)
		_write_status()
	_write_file("ready-file", {"port": Net.port, "version": Session.game_version()})


## --ready-file / --status-file: tells the process that started this server that it listens (or why
## it can't), and how its game goes.
func _write_file(flag: String, data: Dictionary) -> void:
	var path := Cli.get_str(flag)
	if path != "" and not ServerProcess.write_json(path, data):
		Log.warn("server", "cannot write the %s %s" % [flag.replace("-", " "), path])


func _write_status() -> void:
	if is_instance_valid(_session) and _session.is_inside_tree():
		_write_file("status-file", _session.public_info())


## --idle-quit: an online game nobody plays in any more stops by itself.
func _check_idle() -> void:
	if not is_instance_valid(_session):
		return
	_idle_s = _idle_s + 1.0 if _session.players.is_empty() else 0.0
	if _idle_s >= Cli.get_int("idle-quit"):
		Log.info("server", "nobody in the game for %d s, stopping" % int(_idle_s))
		get_tree().quit()


## --owner-pid: a server started by a player's game (or by the VPS launcher) stops once that process
## is gone, even if it crashed or was killed (when it quits normally, it stops the server itself).
func _watch_owner(pid: int) -> void:
	_owner = ProcessWatch.new(pid)
	_add_timer(OWNER_CHECK_S, func() -> void:
		if not _owner.alive():
			Log.info("server", "the process that started this server (pid %d) is gone, stopping" % pid)
			get_tree().quit())


func _add_timer(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.autostart = true
	timer.timeout.connect(callback)
	add_child(timer)


func _exit_tree() -> void:
	if _owner != null:
		_owner.finish()


## From source: the project folder. Exported: next to the server binary.
func _default_config_path() -> String:
	if OS.has_feature("editor"):
		return "res://server.cfg"
	return OS.get_executable_path().get_base_dir().path_join("server.cfg")
