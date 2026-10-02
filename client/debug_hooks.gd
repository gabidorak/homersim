class_name DebugHooks
extends Node
## Test-only client automation, so headless clients can drive the lobby in integration tests.
## Debug builds only. Flags (after `--`):
##   --pref rat|supervisor|any   set the lobby role preference after joining
##   --auto-ready                ready up after joining
##   --say TEXT                  send TEXT to the chat twice in a row (the 2nd tests the rate limit)
##   --screenshot PATH           save the window to PATH (PNG) after --screenshot-delay S (default 8);
##                               with --screenshot-times T1,T2,… (s): one PNG per time, PATH_<T>.png
##   --debug-kick-me             ask the server to kick us (M8: the "kicked" message; server --allow-debug)
## MovementComponent reads --auto-move and --debug-speed N itself.

const FLAGS: Array[String] = ["pref", "auto-ready", "say", "screenshot", "debug-kick-me"]


static func wanted() -> bool:
	for flag in FLAGS:
		if Cli.has_arg(flag):
			return true
	return false


func _ready() -> void:
	Session.current.joined.connect(_on_joined)
	if Cli.has_arg("screenshot"):
		var path := Cli.get_str("screenshot")
		var times := Cli.get_str("screenshot-times").split(",", false)
		if times.is_empty():
			await get_tree().create_timer(Cli.get_float("screenshot-delay", 8.0)).timeout
			_save_screenshot(path)
			return
		var elapsed := 0.0
		for t in times:
			await get_tree().create_timer(maxf(t.to_float() - elapsed, 0.0)).timeout
			elapsed = t.to_float()
			_save_screenshot("%s_%s.png" % [path.trim_suffix(".png"), t])


func _save_screenshot(path: String) -> void:
	var err := get_viewport().get_texture().get_image().save_png(path)
	Log.info("debug", "screenshot %s: %s" % [path, error_string(err)])


func _on_joined() -> void:
	var session := Session.current
	await get_tree().create_timer(0.5).timeout
	if Cli.has_arg("pref"):
		session.match_manager.request_set_pref.rpc_id(1, Role.from_text(Cli.get_str("pref")))
	if Cli.has_arg("auto-ready"):
		session.match_manager.request_set_ready.rpc_id(1, true)
	if Cli.has_arg("say"):
		session.chat.send(Cli.get_str("say"))
		session.chat.send(Cli.get_str("say"))
	if Cli.has_arg("debug-kick-me"):
		await get_tree().create_timer(0.5).timeout
		session.request_debug_kick_me.rpc_id(1)
