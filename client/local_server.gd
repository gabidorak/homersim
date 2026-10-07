class_name LocalServer
extends Node
## A server this game starts itself, for "Play solo" and "Host a game": the same dedicated server
## (server/server_main.gd), run in the background as a second, headless copy of this executable. The
## menu starts it, waits until it listens, then joins 127.0.0.1 like any other server.
##
## Solo: it listens on 127.0.0.1 only (nobody else can reach it), on any free port, for one player, off
## the LAN, and bots fill the match. Host: it listens on the chosen port and announces itself on the
## LAN (unless turned off), with the chosen name, password, player count, teams and bots.
##
## The host's client proves it is the host with a random token (Session.host_token): when the host
## leaves, the server sends everyone back to their menu and quits by itself. The server also stops:
##   - when the session it serves ends (stop(): after STOP_GRACE_S it is killed if still there);
##   - at once when the player cancels while it starts, or quits the game then;
##   - by itself when this game is gone, even after a crash (--owner-pid, see server_main.gd).
##
## Files: user://local_server/server_<pid>_<n>.cfg (the settings, read with --config) and
## ready_<pid>_<n>.json (written by the server once it listens: {"port"}, or {"error": "port"}), <pid>
## being this game's process and <n> counting its starts, so neither several copies of the game nor a
## server still stopping share them. The server logs to user://logs/local_server.log
## (on Linux its output also shows in this game's terminal).
## The server.cfg, the command line and the ready file are shared with the VPS launcher
## (common/server_process.gd). Debug builds pass --level on, and add --local-server-args "…" to the
## server's arguments (tests).

signal started(port: int)  ## the server listens: join 127.0.0.1:port
signal failed(code: LeaveReason.Code, detail: String)

enum Mode { SOLO, HOST }
enum State { IDLE, STARTING, RUNNING, STOPPING, DONE }

const DIR := "user://local_server"
const LOG_PATH := "user://logs/local_server.log"
const START_TIMEOUT_S := 45.0  ## the first start after an install can be slow (shader cache, disk)
const STOP_GRACE_S := 2.0
const SOLO_BIND := "127.0.0.1"
## Network interfaces friends can't reach (Docker, virtual machines, WSL), by a word in their name.
const VIRTUAL_INTERFACES: Array[String] = ["docker", "br-", "veth", "virbr", "vbox", "virtualbox", "vmnet",
	"vmware", "vethernet", "hyper-v", "wsl", "lxc", "lxd", "podman", "cni"]

## The newest one (an older one may still be stopping).
static var current: LocalServer
static var _starts := 0

var mode := Mode.SOLO
var state := State.IDLE
var pid := -1
var port := 0  ## the UDP port it listens on, once RUNNING
var token := ""  ## the host token (Session.host_token)
var ready_as := -1  ## solo: the role preference the player readies up with (Session.ready_as)

var _session: Session
var _deadline_ms := 0
var _cfg_path := ""
var _ready_path := ""


# --- What to start (pure, unit tested) ---------------------------------------------

## Solo, from the saved choices (Config.solo_*): bots take every seat but yours.
static func solo_options() -> Dictionary:
	return {
		"name": TranslationServer.translate("Solo game"),
		"password": "",
		"port": 0,
		"max_players": 1,
		"supervisors": Config.solo_supervisors,
		"rats": Config.solo_rats,
		"bots": Config.solo_supervisors + Config.solo_rats,
		"difficulty": Config.solo_difficulty,
		"lan": false,
		"bind": SOLO_BIND,
		"role": Config.solo_role,
	}


## Host a game, from the saved choices (Config.host_*). `player` names the game when no name was typed.
static func host_options(player: String) -> Dictionary:
	return {
		"name": Config.host_name if Config.host_name != "" else default_host_name(player),
		"password": Config.host_password,
		"port": Config.host_port,
		"max_players": Config.host_max_players,
		"supervisors": Config.host_supervisors,
		"rats": Config.host_rats,
		"bots": Config.host_supervisors + Config.host_rats if Config.host_bots else 0,
		"difficulty": Config.host_difficulty,
		"lan": Config.host_lan,
		"bind": "*",
		"role": -1,
	}


static func default_host_name(player: String) -> String:
	return TranslationServer.translate("%s's plant") % (player if player != "" else JoinRules.DEFAULT_NAME)


## Where friends on the local network reach this computer: the private IPv4 addresses of
## `interfaces` (IP.get_local_interfaces()), 192.168/16 first, then 10/8, then 172.16/12 (where Docker
## puts its bridges), leaving out the interfaces of Docker, virtual machines and WSL.
static func lan_addresses(interfaces: Array) -> PackedStringArray:
	var found: Array = []  # [rank, ip]
	for interface: Dictionary in interfaces:
		var names := ("%s %s" % [interface.get("name", ""), interface.get("friendly", "")]).to_lower()
		if VIRTUAL_INTERFACES.any(func(word: String) -> bool: return names.contains(word)):
			continue
		for ip: String in interface.get("addresses", []):
			var rank := _private_rank(ip)
			if rank >= 0:
				found.append([rank, ip])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result := PackedStringArray()
	for pair: Array in found:
		result.append(pair[1])
	return result


## 0 for 192.168/16, 1 for 10/8, 2 for 172.16/12, -1 for anything else (public, loopback, IPv6).
static func _private_rank(ip: String) -> int:
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return -1
	var parts := ip.split(".")
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	if a == 192 and b == 168:
		return 0
	if a == 10:
		return 1
	if a == 172 and b >= 16 and b <= 31:
		return 2
	return -1


# --- Running it ----------------------------------------------------------------

## Starts the server for `options` (solo_options() / host_options()). Emits started or failed.
func start(as_mode: Mode, options: Dictionary) -> void:
	mode = as_mode
	current = self
	ready_as = int(options.get("role", -1)) if mode == Mode.SOLO else -1
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH).get_base_dir())
	_starts += 1
	_cfg_path = dir.path_join("server_%d_%d.cfg" % [OS.get_process_id(), _starts])
	_ready_path = dir.path_join("ready_%d_%d.json" % [OS.get_process_id(), _starts])
	DirAccess.remove_absolute(_ready_path)
	var err := ServerProcess.config_for(options).save(_cfg_path)
	if err != OK:
		Log.warn("local", "cannot write %s: %s" % [_cfg_path, error_string(err)])
		_fail("spawn")
		return
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	var cmd := ServerProcess.command(ServerProcess.server_args(options, _cfg_path, _ready_path,
		ProjectSettings.globalize_path(LOG_PATH), OS.get_process_id(), token))
	pid = OS.create_process(cmd[0], cmd[1])
	if pid < 0:
		Log.warn("local", "could not start %s" % cmd[0])
		_fail("spawn")
		return
	state = State.STARTING
	_deadline_ms = Time.get_ticks_msec() + int(START_TIMEOUT_S * 1000.0)
	Log.info("local", "starting a %s server (pid %d), log in %s" % ["solo" if mode == Mode.SOLO else "hosted", pid,
		ProjectSettings.globalize_path(LOG_PATH)])


## The menu joined it: this session is the one it serves (it stops when the session ends).
func serve(session: Session) -> void:
	_session = session
	session.host_token = token
	session.ready_as = ready_as
	session.tree_exited.connect(stop)


## True if `session` plays on this server (the lobby and the pause menu adapt to it).
func serves(session: Session) -> bool:
	return session != null and session == _session and state == State.RUNNING


## The server this game started for the current session (solo, hosting), or null.
static func for_session() -> LocalServer:
	return current if current != null and current.serves(Session.current) else null


## Stops the server: at once while it is still starting; otherwise it gets STOP_GRACE_S to quit by
## itself (it does once the host left), then it is killed.
func stop() -> void:
	match state:
		State.STARTING:
			Log.info("local", "stopping the server before it started")
			_kill()
			_done()
		State.RUNNING:
			state = State.STOPPING
			_deadline_ms = Time.get_ticks_msec() + int(STOP_GRACE_S * 1000.0)


func _process(_delta: float) -> void:
	match state:
		State.STARTING:
			if FileAccess.file_exists(_ready_path):
				_read_ready_file()
			elif not OS.is_process_running(pid):
				if FileAccess.file_exists(_ready_path):  # (written just before it stopped)
					_read_ready_file()
				else:
					Log.warn("local", "the server stopped while starting (exit code %d)" % OS.get_process_exit_code(pid))
					_fail("exit|" + ProjectSettings.globalize_path(LOG_PATH))
			elif Time.get_ticks_msec() > _deadline_ms:
				Log.warn("local", "the server took more than %d s to start, stopping it" % START_TIMEOUT_S)
				_kill()
				_fail("timeout|" + ProjectSettings.globalize_path(LOG_PATH))
		State.STOPPING:
			if pid < 0 or not OS.is_process_running(pid):
				Log.info("local", "the server stopped")
				_done()
			elif Time.get_ticks_msec() > _deadline_ms:
				Log.warn("local", "the server didn't stop by itself, killing it")
				_kill()
				_done()


func _read_ready_file() -> void:
	var data := ServerProcess.read_json(_ready_path)
	DirAccess.remove_absolute(_ready_path)
	if data.has("port") and not data.has("error"):
		port = int(data["port"])
		state = State.RUNNING
		Log.info("local", "the server listens on UDP %d" % port)
		started.emit(port)
	elif data.get("error") == "port":
		_fail("port|%d" % int(data["port"]))
	else:
		_fail("exit|" + ProjectSettings.globalize_path(LOG_PATH))


## The game quits: a server that is still starting has nobody to tell, so it goes at once. A running
## one sees its host disconnect, closes the game for the others and quits by itself.
func _exit_tree() -> void:
	if state == State.STARTING:
		_kill()
	_cleanup_files()
	if current == self:
		current = null


## Gives up: tells the menu, and makes sure the process goes (it quits by itself after a port error).
func _fail(detail: String) -> void:
	failed.emit(LeaveReason.Code.SERVER_START, detail)
	if pid >= 0 and OS.is_process_running(pid):
		state = State.STOPPING
		_deadline_ms = Time.get_ticks_msec() + int(STOP_GRACE_S * 1000.0)
	else:
		_done()


func _kill() -> void:
	if pid >= 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _done() -> void:
	state = State.DONE
	if current == self:
		current = null
	queue_free()


func _cleanup_files() -> void:
	for path in [_cfg_path, _ready_path]:
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
