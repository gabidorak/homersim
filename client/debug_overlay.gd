class_name DebugOverlay
extends CanvasLayer
## Playtest instrumentation (M5): F3 shows FPS, ping, position, the POI we are in and draw calls;
## F4 starts / stops a stopwatch that also measures the distance walked (to time routes against
## the map's design rules). `--debug-overlay` shows it from the start (screenshots).

var _label: Label
var _panel: PanelContainer
var _watch_running := false
var _watch_s := 0.0
var _watch_m := 0.0
var _last_pos: Variant = null  # Vector3 while the stopwatch runs


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_panel.add_child(_label)
	_panel.visible = Cli.has_arg("debug-overlay")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		_panel.visible = not _panel.visible
	elif event.is_action_pressed("debug_stopwatch"):
		_watch_running = not _watch_running
		if _watch_running:
			_watch_s = 0.0
			_watch_m = 0.0
			_last_pos = null
		Log.info("debug", "stopwatch %s: %.2f s, %.1f m" % ["started" if _watch_running else "stopped", _watch_s, _watch_m])


func _process(delta: float) -> void:
	var session := Session.current
	var body := session.get_body(session.local_peer_id) if session != null else null
	if _watch_running:
		_watch_s += delta
		if body != null:
			if _last_pos != null:
				var step := body.global_position - (_last_pos as Vector3)
				_watch_m += Vector2(step.x, step.z).length()
			_last_pos = body.global_position
	if not _panel.visible:
		return
	var lines: Array[String] = []
	lines.append("%d fps (%.1f ms)   %d draw calls   %d objects" % [Engine.get_frames_per_second(),
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	var ping := Net.ping_ms()
	lines.append("ping %s   level %s" % ["%d ms" % ping if ping >= 0 else "-", Session.level_id()])
	if body != null:
		var pos := body.global_position
		var where := "in a vent" if VentVolume.contains(body) else Poi.name_at(get_tree(), pos)
		lines.append("pos (%.1f, %.1f, %.1f)   %s" % [pos.x, pos.y, pos.z, where if where != "" else "outside"])
		var notes: Array[String] = [Role.display_name(body.role)]
		if body.movement.climbing:
			notes.append("climbing")
		if body.seated_console() != null:
			notes.append("watching CCTV")
		lines.append("  ·  ".join(notes))
	var watch := "F4: stopwatch"
	if _watch_running or _watch_s > 0.0:
		watch = "stopwatch %.2f s, %.1f m walked%s (F4 %s)" % [_watch_s, _watch_m,
			"" if _watch_running else " [stopped]", "stop" if _watch_running else "restart"]
	lines.append(watch)
	_label.text = "\n".join(lines)
