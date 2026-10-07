class_name Launcher
extends Node
## The launcher (online games): runs on the VPS, always on, and starts one dedicated server
## (server/server_main.gd) per online game, with the settings its creator picked on the Host a game
## card. The same server binary, started with `--launcher --config launcher.cfg`; the auto-updater's
## supervisor keeps it up to date like any server (autoload/updater.gd). The API is in
## common/online_api.gd, served by HttpServer; on the VPS, Caddy puts HTTPS in front of it
## (docs/HOSTING.md).
##
## A game's server gets a free UDP port of `game_ports`, no host (the game goes on when its creator
## leaves), --idle-quit `idle_quit_s` (it stops by itself once nobody played in it for that long),
## --status-file (its name, players and state, for the list) and --owner-pid (it stops if the launcher
## goes). The launcher answers the creator once the server listens, and forgets the game once its
## process is gone.
##
## launcher.cfg ([launcher] section, see launcher.cfg.example): port, bind, key (the friends key:
## required), max_games, game_ports, idle_quit_s, game_host (the address games are joined at; "" =
## the one players reached the launcher at). Files: user://launcher/game_<port>.cfg, ready_<port>.json,
## status_<port>.json; each game's log is user://logs/game_<port>.log.

const DEFAULTS := {
	"port": OnlineApi.DEFAULT_PORT,
	"bind": "*",
	"key": "",
	"max_games": 4,
	"game_ports": "7800-7809",
	"idle_quit_s": 180,
	"game_host": "",
}
const DIR := "user://launcher"
const LOG_DIR := "user://logs"
const START_TIMEOUT_S := 45.0  ## a game's server must listen within this
const CHECK_S := 1.0  ## how often running games are checked (still there? their status)
const MAX_FPS := 20  ## nothing here needs more
const CREATES_PER_MINUTE := 6  ## for everyone together: a runaway client can't start games in a loop
const MIN_KEY_LENGTH := 12

## The running launcher (the auto-updater asks it whether games are running), or null.
static var current: Launcher

var settings: Dictionary = DEFAULTS.duplicate()
## Games by UDP port: {port, pid, name, started_ms, client_version, exchange (the creator's request,
## until answered), ready (listening), status (its last status file)}.
var games: Dictionary[int, Dictionary] = {}

var _http: HttpServer
var _pool: Array[int] = []
var _last_port := 0
var _creates: Array[int] = []  # when the last games were started (ticks, ms)
var _dir := ""


## Reads the [launcher] section of `path` over DEFAULTS (missing keys keep theirs).
static func load_settings(path: String) -> Dictionary:
	var result := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		Log.warn("launcher", "cannot read %s (%s), using the defaults" % [path, error_string(err)])
		return result
	for key: String in result:
		result[key] = cfg.get_value("launcher", key, result[key])
	result["port"] = clampi(int(result["port"]), 0, 65535)
	result["max_games"] = clampi(int(result["max_games"]), 1, 32)
	result["idle_quit_s"] = clampi(int(result["idle_quit_s"]), 5, 3600)
	for key: String in ["bind", "key", "game_ports", "game_host"]:
		result[key] = str(result[key]).strip_edges()
	return result


func _enter_tree() -> void:
	current = self


func _ready() -> void:
	OS.low_processor_usage_mode = true
	Engine.max_fps = MAX_FPS
	if DisplayServer.get_name() != "headless":
		# Started without --headless: nothing to draw, and V-Sync on a hidden window would pace it at the
		# compositor's whim (about 1 fps on Wayland, see server_main.gd).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.render_loop_enabled = false
	var path := Cli.get_str("config", _default_config_path())
	settings = load_settings(path)
	_pool = OnlineApi.parse_port_range(str(settings["game_ports"]))
	if str(settings["key"]) == "":
		_give_up("no friends key: set key= in %s (for example the output of: openssl rand -hex 16)" % path)
		return
	if str(settings["key"]).length() < MIN_KEY_LENGTH:
		Log.warn("launcher", "the friends key is short (%d characters): anyone who guesses it can start games" % str(settings["key"]).length())
	if _pool.is_empty():
		_give_up("game_ports=\"%s\" in %s is not a port range like 7800-7809" % [settings["game_ports"], path])
		return
	_dir = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	for file in DirAccess.get_files_at(_dir):  # left over from an earlier run
		DirAccess.remove_absolute(_dir.path_join(file))
	_http = HttpServer.new()
	_http.name = "HttpServer"
	add_child(_http)
	var err := _http.listen(int(settings["port"]), str(settings["bind"]))
	if err != OK:
		_give_up("cannot listen on TCP port %d: %s" % [settings["port"], error_string(err)])
		return
	_http.request_received.connect(_on_request)
	var timer := Timer.new()
	timer.wait_time = CHECK_S
	timer.autostart = true
	timer.timeout.connect(_check_games)
	add_child(timer)
	Log.info("launcher", "listening on TCP %d%s, version %s: up to %d games on UDP %d-%d, idle games stop after %d s"
		% [_http.port, "" if settings["bind"] == "*" else " of " + str(settings["bind"]), Session.game_version(),
		settings["max_games"], _pool[0], _pool[-1], settings["idle_quit_s"]])


func _exit_tree() -> void:
	for game: Dictionary in games.values():
		_stop(game)  # (they would stop by themselves, --owner-pid, but not at once)
	if current == self:
		current = null


func _give_up(why: String) -> void:
	Log.error("launcher", why)
	get_tree().quit(1)


## From source: the project folder. Exported: next to the binary.
func _default_config_path() -> String:
	if OS.has_feature("editor"):
		return "res://launcher.cfg"
	return OS.get_executable_path().get_base_dir().path_join("launcher.cfg")


# --- Requests ------------------------------------------------------------------

func _on_request(exchange: HttpServer.Exchange) -> void:
	var request := exchange.request
	var method: String = request["method"]
	var path: String = request["path"]
	if path == "/" and method == "GET":
		exchange.respond(200, {"game": "homersim", "version": Session.game_version()})
		return
	if path != OnlineApi.GAMES_PATH:
		exchange.respond(404, {"error": OnlineApi.ERR_NOT_FOUND})
		return
	if not OnlineApi.keys_match(OnlineApi.bearer_key(request["headers"]), str(settings["key"])):
		Log.info("launcher", "refused a request from %s: wrong friends key" % _who(exchange))
		exchange.respond(401, {"error": OnlineApi.ERR_KEY})
		return
	match method:
		"GET":
			exchange.respond(200, list())
		"POST":
			_create(exchange)
		_:
			exchange.respond(404, {"error": OnlineApi.ERR_NOT_FOUND})


## The GET /games answer: the games that are up.
func list() -> Dictionary:
	var entries: Array[Dictionary] = []
	for game: Dictionary in games.values():
		if game["ready"]:
			var status: Dictionary = game["status"] if not game["status"].is_empty() else {"name": game["name"]}
			entries.append(OnlineApi.game_entry(status, game["port"]))
	return {"version": Session.game_version(), "host": settings["game_host"], "games": entries}


func _create(exchange: HttpServer.Exchange) -> void:
	var body := OnlineApi.parse_object(exchange.request["body"])
	if body.is_empty():
		exchange.respond(400, {"error": OnlineApi.ERR_BAD_REQUEST})
		return
	var now := Time.get_ticks_msec()
	_creates = _creates.filter(func(t: int) -> bool: return now - t < 60000)
	if _creates.size() >= CREATES_PER_MINUTE:
		Log.info("launcher", "refused a new game from %s: %d games started in the last minute" % [_who(exchange), _creates.size()])
		exchange.respond(429, {"error": OnlineApi.ERR_BUSY})
		return
	var port := OnlineApi.next_port(_pool, games.keys(), _last_port)
	if games.size() >= int(settings["max_games"]) or port == 0:
		Log.info("launcher", "refused a new game from %s: %d games already run" % [_who(exchange), games.size()])
		exchange.respond(503, {"error": OnlineApi.ERR_FULL})
		return
	_creates.append(now)
	_last_port = port
	var options := OnlineApi.sanitize_options(body)
	var client_version := str(body.get("version", ""))
	var game := {"port": port, "pid": -1, "name": options["name"], "started_ms": now, "client_version": client_version,
		"exchange": exchange, "ready": false, "status": {}}
	games[port] = game  # (holds the port while an update downloads)
	if client_version != Session.game_version() and Updater.is_enabled():
		Log.info("launcher", "%s plays %s, this launcher %s: checking for a new build first" % [_who(exchange),
			client_version, Session.game_version()])
		await Updater.install_update()
		if not is_same(games.get(port), game):
			return  # (stopped meanwhile)
	options.merge({"port": port, "lan": false, "bind": "*", "status_file": _file("status", port, "json"),
		"idle_quit_s": settings["idle_quit_s"]}, true)
	var cfg_path := _file("game", port, "cfg")
	if ServerProcess.config_for(options).save(cfg_path) != OK:
		_fail(game, "cannot write %s" % cfg_path)
		return
	var cmd := ServerProcess.command(ServerProcess.server_args(options, cfg_path, _file("ready", port, "json"),
		ProjectSettings.globalize_path(LOG_DIR).path_join("game_%d.log" % port), OS.get_process_id(), ""))
	game["pid"] = OS.create_process(cmd[0], cmd[1])
	if game["pid"] < 0:
		_fail(game, "could not start %s" % cmd[0])
		return
	game["started_ms"] = Time.get_ticks_msec()
	Log.info("launcher", "starting '%s' for %s on UDP %d (pid %d, %d player(s), %d v %d, bots %d, %s)" % [options["name"],
		_who(exchange), port, game["pid"], options["max_players"], options["supervisors"], options["rats"], options["bots"],
		"password" if options["password"] != "" else "no password"])


func _who(exchange: HttpServer.Exchange) -> String:
	var forwarded := str(exchange.request.get("headers", {}).get("x-forwarded-for", ""))
	return forwarded.split(",")[0].strip_edges() if forwarded != "" else exchange.ip


# --- Games ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	for game: Dictionary in games.values():
		if not game["ready"] and game["pid"] >= 0:
			_check_start(game)


## A game whose server is starting: answer its creator once it listens (or why it doesn't).
func _check_start(game: Dictionary) -> void:
	var port: int = game["port"]
	var ready := ServerProcess.read_json(_file("ready", port, "json"))
	if ready.has("port") and not ready.has("error"):
		var version := str(ready.get("version", ""))
		if version != str(game["client_version"]):
			Log.info("launcher", "'%s' runs %s but its creator plays %s: stopping it" % [game["name"], version, game["client_version"]])
			_answer(game, 409, {"error": OnlineApi.ERR_VERSION, "version": version})
			_stop(game)
			_forget(game)
			return
		game["ready"] = true
		game["status"] = ServerProcess.read_json(_file("status", port, "json"))
		Log.info("launcher", "'%s' is up on UDP %d after %.1f s" % [game["name"], port,
			(Time.get_ticks_msec() - game["started_ms"]) / 1000.0])
		_answer(game, 200, {"host": settings["game_host"], "port": port, "version": version})
	elif not ready.is_empty():
		_fail(game, "its server could not listen on UDP %d (port in use?)" % port)
	elif not OS.is_process_running(game["pid"]):
		_fail(game, "its server stopped while starting (exit code %d, log %s)" % [OS.get_process_exit_code(game["pid"]),
			ProjectSettings.globalize_path(LOG_DIR).path_join("game_%d.log" % port)])
	elif Time.get_ticks_msec() - game["started_ms"] > START_TIMEOUT_S * 1000.0:
		_fail(game, "its server took more than %d s to start" % START_TIMEOUT_S)


## Every CHECK_S: forget the games whose server stopped, read the others' status.
func _check_games() -> void:
	for game: Dictionary in games.values():
		if not game["ready"]:
			continue
		if not OS.is_process_running(game["pid"]):
			Log.info("launcher", "'%s' on UDP %d ended after %d min" % [game["name"], game["port"],
				roundi((Time.get_ticks_msec() - game["started_ms"]) / 60000.0)])
			_forget(game)
			continue
		var status := ServerProcess.read_json(_file("status", game["port"], "json"))
		if not status.is_empty():
			game["status"] = status


func _fail(game: Dictionary, why: String) -> void:
	Log.warn("launcher", "'%s' did not start: %s" % [game["name"], why])
	_answer(game, 500, {"error": OnlineApi.ERR_START})
	_stop(game)
	_forget(game)


func _answer(game: Dictionary, status: int, data: Dictionary) -> void:
	var exchange: HttpServer.Exchange = game.get("exchange")
	if exchange != null:
		exchange.respond(status, data)
	game["exchange"] = null


func _stop(game: Dictionary) -> void:
	if game["pid"] >= 0 and OS.is_process_running(game["pid"]):
		OS.kill(game["pid"])


func _forget(game: Dictionary) -> void:
	_answer(game, 500, {"error": OnlineApi.ERR_START})  # (no-op once answered)
	games.erase(game["port"])
	for kind: String in ["game", "ready", "status"]:
		var path := _file(kind, game["port"], "cfg" if kind == "game" else "json")
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".part")


func _file(kind: String, port: int, extension: String) -> String:
	return _dir.path_join("%s_%d.%s" % [kind, port, extension])
