class_name HeatmapRecorder
extends Node
## Server, playtest instrumentation (M5): while a match is PLAYING, writes every player's position
## every SAMPLE_S to user://heatmap_<date-time>.csv, one row per body:
##   t (s since PLAYING), peer, name, role, x, y, z, area (the POI, "Vents", or "")
## tools/heatmap.py draws these over the layout plan (docs/map/plant_layout_v1.png).
## Only on the plant, and not with `--no-heatmap` (the integration tests pass it).

const SAMPLE_S := 2.0

var _file: FileAccess
var _since_sample := 0.0
var _started_ms := 0

@onready var session: Session = Session.current


func _ready() -> void:
	set_process(false)
	if Session.level_id() != "plant" or Cli.has_arg("no-heatmap"):
		return
	session.match_manager.state_changed.connect(_on_state_changed)


func _on_state_changed(state: MatchManager.State) -> void:
	if state == MatchManager.State.PLAYING:
		_open()
	elif _file != null:
		_close()


func _open() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var path := "user://heatmap_%s.csv" % stamp
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		Log.warn("heatmap", "cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	_file.store_line("t,peer,name,role,x,y,z,area")
	_started_ms = Time.get_ticks_msec()
	_since_sample = SAMPLE_S  # a first sample right away
	set_process(true)
	Log.info("heatmap", "recording positions to %s" % ProjectSettings.globalize_path(path))


func _close() -> void:
	_file.close()
	_file = null
	set_process(false)


func _process(delta: float) -> void:
	_since_sample += delta
	if _since_sample < SAMPLE_S:
		return
	_since_sample = 0.0
	var t := (Time.get_ticks_msec() - _started_ms) / 1000.0
	for node in session.players_root.get_children():
		var player := node as Player
		if player == null or player.is_queued_for_deletion():
			continue
		var pos := player.global_position
		var area := "Vents" if VentVolume.contains(player) else Poi.name_at(get_tree(), pos)
		_file.store_line("%.1f,%d,%s,%s,%.2f,%.2f,%.2f,%s" % [t, player.peer_id, player.display_name.replace(",", " "),
			Role.display_name(player.role).to_lower(), pos.x, pos.y, pos.z, area])
	_file.flush()
