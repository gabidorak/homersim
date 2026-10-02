extends Node
## Self-update from GitHub releases. Only active in exported CI builds (BuildInfo.NUMBER > 0).
##
## Every branch has one rolling GitHub release, tagged `build-<branch>` (see
## .github/workflows/build.yml). It holds one binary per platform and role, plus build.json:
## the build number and the SHA-256 of every binary. At startup the game reads build.json of the
## branch it follows (its own branch, or `--branch NAME`). If that build is newer, or comes from
## another branch, the game downloads its own binary, checks the hash, puts it in place of the
## running executable and restarts.
##
## Client: main.gd shows the progress, then starts the new binary with the same arguments and quits.
## Server: Ctrl+C must still stop the server, but Godot starts child processes in their own
## session, so a relaunched server would survive it. So the first server process only supervises:
## it runs the real server as a child (`--update-supervisor PID`) and starts it again whenever it
## exits with EXIT_RESTART. The child quits when the supervisor is gone. While nobody is connected,
## the child checks for an update every UPDATE_INTERVAL_S.
##
## Flags: --branch NAME, --no-update, --update-url URL (test server instead of GitHub releases),
## --update-interval S.

signal status_changed(text: String)

const EXIT_RESTART := 75  ## server child -> supervisor: "new binary installed, start me again"
const SUPERVISOR_ARG := "update-supervisor"
const UPDATE_INTERVAL_S := 300.0
const STALL_TIMEOUT_S := 20.0  ## give up a request that received no data for this long
const MANIFEST := "build.json"

var status := ""
## Path of this executable, read once at startup: on Linux, OS.get_executable_path() follows the
## file, so after a swap it would point to the renamed old binary.
var exe_path := OS.get_executable_path()

var _cancelled := false
var _busy := false
var _restart_pending := false  # server child: new binary installed, restart once the server is empty
var _worker_pid := -1  # supervisor: the server child
var _supervisor_alive := true
var _watch_task := -1  # Windows: background `tasklist` call


func _ready() -> void:
	if BuildInfo.NUMBER > 0:
		Log.info("update", "build %d of branch '%s' (%s)" % [BuildInfo.NUMBER, BuildInfo.BRANCH, BuildInfo.COMMIT.left(8)])
	if not is_enabled():
		return
	_remove_old_binaries()
	if is_supervised():
		_add_timer(2.0, _watch)
		_add_timer(Cli.get_float("update-interval", UPDATE_INTERVAL_S), _check_while_idle)


static func is_enabled() -> bool:
	return OS.has_feature("template") and BuildInfo.NUMBER > 0 and not Cli.has_arg("no-update")


static func is_server() -> bool:
	return OS.has_feature("dedicated_server") or Cli.has_arg("server")


## True in the server child that a supervisor started.
static func is_supervised() -> bool:
	return Cli.has_arg(SUPERVISOR_ARG)


## The branch whose builds this binary follows.
static func channel() -> String:
	return Cli.get_str("branch", BuildInfo.BRANCH)


## Release tag of a branch: `build-` + the name with anything but letters, digits, `.`, `_` and `-`
## turned into `-`. Must match the tag computed in .github/workflows/build.yml.
static func tag_for(branch: String) -> String:
	return "build-" + RegEx.create_from_string("[^A-Za-z0-9._-]").sub(branch, "-", true)


## Release asset that replaces this binary. Must match the names in .github/workflows/build.yml.
static func asset_name() -> String:
	var role := "homersim-server" if OS.has_feature("dedicated_server") else "homersim"
	if OS.get_name() == "Windows":
		return "%s-windows-x86_64.exe" % role
	return "%s-linux-x86_64" % role


## Installs the newest build of channel() if it differs from this one. Returns true when the
## executable was replaced: the caller then restarts. Any failure (offline, no write access, bad
## hash) just means no update.
func update() -> bool:
	if _busy:
		return false
	_busy = true
	_cancelled = false
	var installed := await _update()
	_busy = false
	return installed


## Client: Esc on the update screen.
func cancel() -> void:
	_cancelled = true


func is_busy() -> bool:
	return _busy


## Client: starts the (new) executable with the same arguments. The caller quits right after.
func relaunch() -> void:
	if OS.create_process(exe_path, _relaunch_args([])) < 0:
		Log.error("update", "could not start the new build, please start the game again")


## Server, first process: run the real server as a child and restart it after each update.
func supervise() -> void:
	OS.low_processor_usage_mode = true
	Engine.max_fps = 10
	Log.info("update", "auto-update on, following branch '%s'; the server runs as a child process" % channel())
	_start_worker()
	_add_timer(0.5, _check_worker)


func _update() -> bool:
	var tag := tag_for(channel())
	var base := "%s/%s" % [Cli.get_str("update-url", "https://github.com/%s/releases/download" % BuildInfo.REPO), tag.uri_encode()]
	_set_status(tr("Checking for updates..."))
	var got := await _fetch(base + "/" + MANIFEST, "")
	if not got["error"].is_empty():
		Log.info("update", "no update info for branch '%s' (%s)" % [channel(), got["error"]])
		return false
	var manifest: Variant = JSON.parse_string((got["body"] as PackedByteArray).get_string_from_utf8())
	if not manifest is Dictionary:
		Log.warn("update", "unreadable %s for branch '%s'" % [MANIFEST, channel()])
		return false
	var number := int(manifest.get("number", 0))
	if tag == tag_for(BuildInfo.BRANCH) and number <= BuildInfo.NUMBER:
		Log.info("update", "up to date (newest build of '%s' is %d)" % [channel(), number])
		return false
	var assets: Dictionary = manifest.get("assets", {})
	var sha := str(assets.get(asset_name(), {}).get("sha256", ""))
	if sha.is_empty():
		Log.warn("update", "build %d of '%s' has no %s" % [number, channel(), asset_name()])
		return false

	Log.info("update", "downloading build %d of '%s'" % [number, channel()])
	var exe := exe_path
	var download := exe + ".download"
	got = await _fetch(base + "/" + asset_name(), download)
	if not got["error"].is_empty():
		Log.warn("update", "download failed (%s)" % got["error"])
		DirAccess.remove_absolute(download)
		return false
	if FileAccess.get_sha256(download) != sha:
		Log.warn("update", "downloaded file is damaged (SHA-256 mismatch), keeping this build")
		DirAccess.remove_absolute(download)
		return false
	if not _swap(exe, download):
		return false
	Log.info("update", "installed build %d of '%s'" % [number, channel()])
	_set_status(tr("Starting the new version..."))
	return true


## GET `url` into memory, or into `file` when given. Returns {"error": "" or reason, "body": bytes}.
func _fetch(url: String, file: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.download_file = file
	http.use_threads = true
	add_child(http)
	var response: Array = []
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		response.assign([result, code, body]))
	var error := ""
	var err := http.request(url)
	if err != OK:
		error = error_string(err)
	var last_bytes := -1
	var idle := 0.0
	while error.is_empty() and response.is_empty():
		await get_tree().create_timer(0.25).timeout
		var bytes := http.get_downloaded_bytes()
		idle = 0.0 if bytes != last_bytes else idle + 0.25
		last_bytes = bytes
		if _cancelled:
			error = "cancelled"
		elif idle > STALL_TIMEOUT_S:
			error = "no data for %d s" % STALL_TIMEOUT_S
		elif not file.is_empty() and http.get_body_size() > 0:
			_set_status(tr("Downloading the update... %d / %d MB") % [bytes >> 20, http.get_body_size() >> 20])
	if not error.is_empty():
		http.cancel_request()
	elif response[0] == HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
		error = "no write access to %s" % file.get_base_dir()
	elif response[0] != HTTPRequest.RESULT_SUCCESS:
		error = "request failed, HTTPRequest result %d" % response[0]
	elif response[1] != 200:
		error = "HTTP %d" % response[1]
	http.queue_free()
	return {"error": error, "body": response[2] if error.is_empty() else PackedByteArray()}


## Puts `download` in place of the running executable. Both Linux and Windows allow renaming a
## running executable (Windows doesn't allow deleting it), so the old one becomes `<exe>.old-<time>`
## and is deleted at a later start.
func _swap(exe: String, download: String) -> bool:
	var old := "%s.old-%d" % [exe, int(Time.get_unix_time_from_system() * 1000.0)]
	var err := DirAccess.rename_absolute(exe, old)
	if err != OK:
		Log.warn("update", "cannot replace %s (%s), keeping this build" % [exe, error_string(err)])
		DirAccess.remove_absolute(download)
		return false
	err = DirAccess.rename_absolute(download, exe)
	if err != OK:
		Log.warn("update", "cannot move the new build into place (%s), keeping this build" % error_string(err))
		DirAccess.rename_absolute(old, exe)
		DirAccess.remove_absolute(download)
		return false
	if OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(exe, 0b111_101_101)  # rwxr-xr-x
	return true


func _remove_old_binaries() -> void:
	var dir := exe_path.get_base_dir()
	for file: String in DirAccess.get_files_at(dir):
		if file.begins_with(exe_path.get_file() + ".old-"):
			DirAccess.remove_absolute(dir.path_join(file))  # fails while that binary still runs: fine


## This process's arguments (engine args, then `--` and the user args), minus the supervisor flag,
## plus `extra_user_args`. Godot leaves out the engine args it consumed, so `--headless` is added back
## (other engine flags such as `--fullscreen` are lost).
func _relaunch_args(extra_user_args: Array) -> PackedStringArray:
	var args := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless" and not OS.has_feature("dedicated_server") and not args.has("--headless"):
		args.insert(0, "--headless")
	var user := OS.get_cmdline_user_args()
	var kept: Array = []
	var i := 0
	while i < user.size():
		if user[i] == "--" + SUPERVISOR_ARG:
			i += 2  # flag and its value
			continue
		if not user[i].begins_with("--%s=" % SUPERVISOR_ARG):
			kept.append(user[i])
		i += 1
	kept.append_array(extra_user_args)
	if not kept.is_empty():
		args.append("--")
		args.append_array(PackedStringArray(kept))
	return args


func _start_worker() -> void:
	var args := _relaunch_args(["--" + SUPERVISOR_ARG, str(OS.get_process_id())])
	# No new console: on Windows, Godot attaches to its parent's console at startup, so the child's
	# logs show in this terminal (Linux children inherit stdout anyway).
	_worker_pid = OS.create_process(exe_path, args)
	if _worker_pid < 0:
		Log.error("update", "could not start the server process")
		get_tree().quit(1)


func _check_worker() -> void:
	if _worker_pid < 0 or OS.is_process_running(_worker_pid):
		return
	var code := OS.get_process_exit_code(_worker_pid)
	if code == EXIT_RESTART:
		Log.info("update", "restarting the server on the new build")
		_start_worker()
	else:
		get_tree().quit(code)


## Server child: stop when the supervisor is gone (Ctrl+C, closed terminal, kill), and restart once
## the server is empty after an update was installed.
func _watch() -> void:
	if not _supervisor_alive:
		Log.info("update", "supervisor process is gone, stopping the server")
		get_tree().quit()
		return
	if OS.get_name() == "Windows":
		# A Windows process can only query its own children, so ask tasklist (in the background: it is slow).
		if _watch_task == -1 or WorkerThreadPool.is_task_completed(_watch_task):
			if _watch_task != -1:
				WorkerThreadPool.wait_for_task_completion(_watch_task)
			_watch_task = WorkerThreadPool.add_task(_poll_tasklist.bind(Cli.get_int(SUPERVISOR_ARG)))
	else:
		_supervisor_alive = DirAccess.dir_exists_absolute("/proc/%d" % Cli.get_int(SUPERVISOR_ARG))
	if _restart_pending and _server_empty():
		Log.info("update", "server is empty, restarting on the new build")
		get_tree().quit(EXIT_RESTART)


func _poll_tasklist(pid: int) -> void:
	var out: Array = []
	if OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], out) == 0:
		_supervisor_alive = not out.is_empty() and str(out[0]).contains("\"%d\"" % pid)


func _check_while_idle() -> void:
	if _restart_pending or not _server_empty() or not Net.is_server:
		return
	if await update():
		_restart_pending = true  # _watch restarts once nobody is connected


func _server_empty() -> bool:
	var session := get_node_or_null("/root/Session") as Session
	return session == null or session.players.is_empty()


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


func _add_timer(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.autostart = true
	timer.timeout.connect(callback)
	add_child(timer)
