extends Node
## Visual check of the plant (M5), windowed: loads the level offline, flies a camera through a list
## of viewpoints, saves a screenshot of each and reports the frame rate there.
##   godot tests/helpers/MapTour.tscn -- [--out DIR] [--only NAME] [--alarm] [--players N] [--no-vsync]
## (`godot --gpu-index 0 ...` picks another GPU, e.g. a laptop's integrated one, for a slow-GPU check.)
## --alarm turns the plant CRITICAL (beacons spin), breaks camera 3 and damages a few subsystems,
## so the status board and the wall screens show something. --players N (M7 performance check) puts
## N animated bodies (half supervisors, half rats, walking on the spot) in front of the camera at
## each viewpoint.

const SETTLE_S := 1.2  ## per viewpoint, before measuring
const MEASURE_S := 1.0

# name, eye, look at
const VIEWS := [
	["overview", Vector3(6, 48, 62), Vector3(0, 0, -2)],
	["yard", Vector3(18, 1.6, -22.5), Vector3(-10, 2.0, -27)],
	["control_room", Vector3(-12, 1.7, 1.5), Vector3(0, 1.4, 19)],
	["wall_screens", Vector3(-1, 1.7, 14), Vector3(-1, 1.9, 19.7)],
	["status_board", Vector3(-7.5, 1.7, 12), Vector3(-13.7, 2.1, 12)],
	["reactor_hall", Vector3(-11.5, 5.7, -18.5), Vector3(-24, 0.5, -8)],
	["turbine_hall", Vector3(32.5, 5.3, -18.5), Vector3(0, 1, -10)],
	["pump_house", Vector3(-39.5, 1.7, -7), Vector3(-48, 1, -16)],
	["valve_corridor", Vector3(-41, 1.7, -4.5), Vector3(-45, 1, 20)],
	["cage_room", Vector3(50.5, 1.7, -4.5), Vector3(40, 0.5, 10)],
	["break_room", Vector3(-36.5, 1.7, 18.5), Vector3(-20, 1, 10)],
	["locker_room", Vector3(12, 1.7, 7.5), Vector3(30, 1, 18)],
	["south_corridor", Vector3(-36, 1.7, 23), Vector3(10, 1.5, 23)],
	["substation", Vector3(-31, 1.7, -25), Vector3(-45, 1, -33)],
	["vent_roof", Vector3(24.6, 7.6, -29), Vector3(40, 6, -29)],
	["rat_nest", Vector3(-34.5, 1.2, 38.5), Vector3(-30, 0.3, 30)],
	["in_a_duct", Vector3(-20, 0.35, 26.75), Vector3(0, 0.3, 26.75)],
	["control_drop", Vector3(-2, 1.0, 13), Vector3(-2, 2.9, 19.8)],
]

var _session: Session
var _camera: Camera3D


func _ready() -> void:
	var out := Cli.get_str("out", "user://map_tour")
	DirAccess.make_dir_recursive_absolute(out)
	_session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_session)
	await get_tree().create_timer(1.0).timeout
	for node in _session.client_only.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false  # no HUD / lobby in the shots
		elif node is CanvasLayer and not node is DebugOverlay:
			(node as CanvasLayer).visible = false
	if Cli.has_arg("alarm"):
		var plant := _session.plant
		plant.healths = PackedFloat32Array([0, 35, 100, 50, 80, 15])
		plant.offline_mask = 1
		plant.core_temp = 780.0
		plant.meltdown = 42.0
		plant.alarm = PlantModel.Alarm.CRITICAL
		for cam in CctvCamera.all_in(get_tree()):
			cam.broken = cam.number == 3
	_camera = Camera3D.new()
	_camera.fov = 80.0
	add_child(_camera)
	_camera.make_current()
	var report: Array[String] = []
	if Cli.has_arg("no-vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var bodies := _spawn_players(Cli.get_int("players", 0))
	for view: Array in VIEWS:
		if Cli.has_arg("only") and view[0] != Cli.get_str("only"):
			continue
		_camera.look_at_from_position(view[1], view[2])
		_place_players(bodies, view[1], view[2])
		await get_tree().create_timer(SETTLE_S).timeout
		var frames := Engine.get_frames_drawn()
		var start := Time.get_ticks_msec()
		await get_tree().create_timer(MEASURE_S).timeout
		var fps := (Engine.get_frames_drawn() - frames) / ((Time.get_ticks_msec() - start) / 1000.0)
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var path := "%s/%s.png" % [out, view[0]]
		get_viewport().get_texture().get_image().save_png(path)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		report.append("%-16s %6.0f fps  %5d draw calls  %7d triangles" % [view[0], fps, draws, prims])
		print(report[-1])
	print("screenshots in %s" % ProjectSettings.globalize_path(out))
	get_tree().quit()


# --- Performance check: animated bodies in view -------------------------------------------------

var _movers: Array[Player] = []


func _spawn_players(count: int) -> Array[Player]:
	var bodies: Array[Player] = []
	for i in count:
		var id := 200 + i
		var role := Role.Kind.SUPERVISOR if i % 2 == 0 else Role.Kind.RAT
		_session.players[id] = PlayerInfo.new(id, "Bot%d" % i)
		var body := _session._spawn_player({"peer": id, "name": "Bot%d" % i, "role": role, "pos": Vector3(0, -50, 0),
			"yaw": 0.0, "locked": false}) as Player
		_session.players_root.add_child(body)
		bodies.append(body)
	_movers = bodies
	return bodies


## Spreads the bodies on the floor 3 to 6 m in front of the camera, toward what it looks at.
func _place_players(bodies: Array[Player], eye: Vector3, target: Vector3) -> void:
	var forward := Vector3(target.x - eye.x, 0, target.z - eye.z).normalized()
	var right := forward.cross(Vector3.UP)
	for i in bodies.size():
		var spot := eye + forward * (3.0 + (i % 3) * 1.5) + right * ((i % 3) - 1) * 1.2 + right * (0.6 if i >= 3 else -0.6)
		var space := get_viewport().world_3d.direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP, spot + Vector3.DOWN * 10.0,
			PhysicsLayers.WORLD))
		if not hit.is_empty():
			spot = hit["position"]
		bodies[i].global_position = spot
		bodies[i].sync_position = spot
		bodies[i].set_meta("home", spot)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _movers.size():
		var body := _movers[i]
		if body.has_meta("home"):
			var home: Vector3 = body.get_meta("home")
			body.sync_position = home + Vector3(sin(t * 3.0 + i), 0, cos(t * 3.0 + i)) * 0.5
			body.sync_yaw = t * 3.0 + i

