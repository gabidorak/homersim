class_name ProcessWatch
extends RefCounted
## Tells whether another process is still running, one this process didn't start (so
## OS.is_process_running() can't tell). Linux: /proc/<pid>. Windows: a process can only query its own
## children, so it asks `tasklist`, in the background because that is slow; the answer then lags one
## call behind. Other systems: it can't tell, and always answers true.
## Used by the auto-updater's server child (is the supervisor still there?) and by a server that a
## player's game started (is that game still there? see client/local_server.gd).

var pid := 0

var _alive := true
var _task := -1  # Windows: the background `tasklist` call


func _init(watched_pid: int) -> void:
	pid = watched_pid


## Checks again and returns the latest answer.
func alive() -> bool:
	match OS.get_name():
		"Linux":
			_alive = DirAccess.dir_exists_absolute("/proc/%d" % pid)
		"Windows":
			if _task == -1 or WorkerThreadPool.is_task_completed(_task):
				finish()
				_task = WorkerThreadPool.add_task(_poll_tasklist)
	return _alive


## Waits for a background check still running. Call it before dropping the watch.
func finish() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _poll_tasklist() -> void:
	var out: Array = []
	if OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], out) == 0:
		_alive = not out.is_empty() and str(out[0]).contains("\"%d\"" % pid)
