extends Node
## Visual check of M6, windowed: loads the plant offline, switches hazards on locally, and saves a
## screenshot of each (plus the Control Room consoles and the three minigame overlays).
##   godot tests/helpers/HazardTour.tscn -- [--out DIR] [--only NAME]

const SETTLE_S := 1.0

# name, eye, look at, what to switch on
const VIEWS := [
	["steam_jets", Vector3(-40.5, 1.7, -8.5), Vector3(-47, 0.6, -15), "pumps"],
	["puddles", Vector3(-31, 2.2, -25), Vector3(-41, 0, -29), "grid"],
	["radiation", Vector3(-12, 5.0, -3), Vector3(-24, 0.5, -11), "rods"],
	["debris", Vector3(30, 3.0, -2), Vector3(14, 0, -10), "turbine"],
	["consoles", Vector3(-1, 2.3, 11.0), Vector3(-1, 0.9, 6.2), ""],
	["smoke", Vector3(-12, 1.7, 1.5), Vector3(0, 1.4, 19), "ventilation"],
	["minigame_wrench_rhythm", Vector3(-12, 1.7, 1.5), Vector3(0, 1.4, 19), ""],
	["minigame_breaker_sequence", Vector3(-12, 1.7, 1.5), Vector3(0, 1.4, 19), ""],
	["minigame_valve_rotate", Vector3(-12, 1.7, 1.5), Vector3(0, 1.4, 19), ""],
]

var _session: Session
var _camera: Camera3D


func _ready() -> void:
	var out := Cli.get_str("out", "user://hazard_tour")
	DirAccess.make_dir_recursive_absolute(out)
	_session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_session)
	await get_tree().create_timer(1.0).timeout
	for node in _session.client_only.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is CanvasLayer and not node is MinigameHost:
			(node as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.fov = 80.0
	add_child(_camera)
	_camera.make_current()
	var host := _session.client_only.get_node("MinigameHost") as MinigameHost
	for view: Array in VIEWS:
		if Cli.has_arg("only") and view[0] != Cli.get_str("only"):
			continue
		get_tree().call_group(Hazard.ALL_GROUP, "set", "active", false)
		host.close("next view")
		_camera.look_at_from_position(view[1], view[2])
		var id: String = view[3]
		if id != "":
			for node in get_tree().get_nodes_in_group(Hazard.group_for(StringName(id))):
				var hazard := node as Hazard
				hazard.active = true
				# 0.5 s into a live window at the shot, whatever the phase.
				var period := hazard.on_s + hazard.off_s
				hazard.start_time = Net.server_time() + SETTLE_S - (period - hazard.phase + 0.5)
		if id == "turbine":
			var zone := get_tree().get_first_node_in_group(Hazard.group_for(&"turbine")) as DebrisZone
			zone.on_debris_warning(Vector3(14, 0, -6), Net.server_time() + SETTLE_S + 0.3)
			zone.on_debris_warning(Vector3(20, 0, -15), Net.server_time() + SETTLE_S - 0.25)
		if (view[0] as String).begins_with("minigame_"):
			host.open(NodePath(), (view[0] as String).trim_prefix("minigame_"), 1234, 0.5)
		await get_tree().create_timer(SETTLE_S).timeout
		var path := "%s/%s.png" % [out, view[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("saved %s" % path)
	print("screenshots in %s" % ProjectSettings.globalize_path(out))
	get_tree().quit()
