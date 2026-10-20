extends Node
## Visual check of the cooling tower's steam (levels/tower_steam.gd), windowed: loads the plant
## offline, looks at the tower from where players see it (the lobby spawns, the yard's far end, the
## vent roof), drives the plume through the plant's states and saves a screenshot of each: calm, the warning, the critical alarm, the meltdown
## meter half and nearly full, then the coolant's sigh as it bursts, rolls and goes.
##   godot tests/helpers/TowerSteamShots.tscn -- [--out DIR] [--hold S]
## (--hold: seconds each state runs before its shot, default 3; with --write-movie, the whole run.)

## [name, heat, goo, sigh: seconds after the coolant (-1 none)]
const STATES := [["0_calm", 0.0, 0.0, -1.0], ["1_warning", 0.29, 0.0, -1.0], ["2_critical", 0.8, 0.1, -1.0],
	["3_meltdown_50", 1.0, 0.5, -1.0], ["4_meltdown_95", 1.0, 0.95, -1.0], ["5_sigh_burst", 0.5, 0.6, 0.3],
	["6_sigh_roll", 0.5, 0.6, 1.0], ["7_sigh_gone", 0.5, 0.6, 2.6]]
## Where players see it from: [suffix, eye, target]: the lobby spawns, the yard's far (west) end and
## the vent roof.
const VIEWS := [["spawn", Vector3(16, 1.7, -25), Vector3(-4, 26, -40)],
	["west", Vector3(-26, 1.7, -23), Vector3(-6, 26, -42)],
	["roof", Vector3(30, 7.7, -30), Vector3(-4, 24, -42)]]

var _out := ""


func _ready() -> void:
	_out = Cli.get_str("out", "user://tower_steam_shots")
	var hold := Cli.get_float("hold", 3.0)
	DirAccess.make_dir_recursive_absolute(_out)
	var session: Session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(session)
	await get_tree().create_timer(1.0).timeout
	for node in session.client_only.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = false
	var steams := session.find_children("*", "TowerSteam", true, false)
	if steams.is_empty():
		Log.error("tower_steam_shots", "no TowerSteam in the level")
		get_tree().quit(1)
		return
	var steam := steams[0] as TowerSteam
	steam.manual = true
	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	for state: Array in STATES:
		steam.target_heat = state[1]
		steam.target_goo = state[2]
		steam.heat = state[1]  # straight there: the shot shows the state, not the easing
		steam.goo = state[2]
		var sigh_at: float = state[3]
		if sigh_at >= 0.0:
			steam.sigh()
			await get_tree().create_timer(sigh_at).timeout
		else:
			await get_tree().create_timer(hold).timeout
		var paused := sigh_at >= 0.0
		steam.set_process(not paused)  # the views share one moment of the sigh
		for view: Array in VIEWS:
			camera.look_at_from_position(view[1], view[2])
			await _shot("%s_%s" % [state[0], view[0]])
		steam.set_process(true)
	Log.info("tower_steam_shots", "saved in %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s.png" % shot_name))
