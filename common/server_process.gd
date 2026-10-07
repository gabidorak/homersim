class_name ServerProcess
extends RefCounted
## A dedicated server (server/server_main.gd) started as a child process by another copy of this
## executable: by a player's game for "Play solo" and "Host a game" (client/local_server.gd), and by
## the VPS launcher for online games (server/launcher/launcher.gd). Pure helpers, shared by both: the
## server.cfg the child reads, its command line, and the JSON files it writes for its parent.
##
## Files the child writes (write_json(): under another name, then renamed, so the parent never reads
## half a file):
##   --ready-file PATH   once it listens: {"port": N, "version": V}, or {"error": "port", "port": N}
##   --status-file PATH  every STATUS_EVERY_S: Session.public_info() (name, players, state…)

const MAX_FPS := 60  ## a headless server has nothing else to pace its main loop
const STATUS_EVERY_S := 2.0


## The server.cfg for `options` (see server.cfg.example): name, password, port, max_players, bots,
## difficulty.
static func config_for(options: Dictionary) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "name", str(options.get("name", "")))
	cfg.set_value("server", "password", str(options.get("password", "")))
	cfg.set_value("server", "port", int(options.get("port", Net.DEFAULT_PORT)))
	cfg.set_value("server", "max_players", int(options.get("max_players", 6)))
	cfg.set_value("match", "bot_fill_to", int(options.get("bots", 0)))
	cfg.set_value("match", "bot_difficulty", int(options.get("difficulty", 1)))
	return cfg


## The child's arguments: engine arguments, then `--` and the game's own. `host_token` "" = no host
## (online games keep going when their creator leaves). Optional `options` keys: "bind" (an IP, "*" =
## every address), "lan" (false: --no-lan), "status_file" (a path), "idle_quit_s" (> 0: quit after
## that long without players).
static func server_args(options: Dictionary, cfg_path: String, ready_path: String, log_path: String,
		owner_pid: int, host_token: String) -> PackedStringArray:
	var args := PackedStringArray(["--headless", "--max-fps", str(MAX_FPS), "--log-file", log_path, "--",
		"--server", "--config", cfg_path, "--ready-file", ready_path, "--owner-pid", str(owner_pid),
		"--no-update", "--no-heatmap"])
	if host_token != "":
		args.append_array(["--host-token", host_token])
	if str(options.get("bind", "*")) != "*":
		args.append_array(["--bind", str(options["bind"])])
	if not options.get("lan", true):
		args.append("--no-lan")
	if str(options.get("status_file", "")) != "":
		args.append_array(["--status-file", str(options["status_file"])])
	if int(options.get("idle_quit_s", 0)) > 0:
		args.append_array(["--idle-quit", str(int(options["idle_quit_s"]))])
	if OS.is_debug_build():
		if Cli.has_arg("level"):
			args.append_array(["--level", Cli.get_str("level")])
		args.append_array(Cli.get_str("local-server-args").split(" ", false))
	return args


## [executable, arguments] to start `args` with this executable. From source (an editor build), the
## engine also needs the project folder.
static func command(args: PackedStringArray) -> Array:
	var full := PackedStringArray()
	if not OS.has_feature("template"):
		full.append_array(["--path", ProjectSettings.globalize_path("res://")])
	full.append_array(args)
	return [Updater.exe_path, full]


## Writes `data` as JSON to `path`: first to `path`.part, then renamed. Returns false if it couldn't.
static func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path + ".part", path) == OK


## The JSON object in `path`, or {} if there is none (or not a readable one).
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
