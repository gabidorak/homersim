extends Node
## Visual check of the end-of-match cinematics (client/outro/), windowed: plays each ending and saves
## a PNG at each of its key moments (and wherever --times says).
##   godot --fixed-fps 60 tests/helpers/OutroShots.tscn -- [--out DIR] [--ending supervisors|rats]
##       [--rats N] [--size WxH] [--times 0.5,3.9] [--seek] [--cam x,y,z --look x,y,z [--fov F]]
## --fixed-fps keeps the clock exact (each frame is 1/60 s whatever the machine). --seek jumps
## straight to each moment instead of playing up to it (no particles, faster). --rats: how many rats
## won (the rats' ending: one pair of eyes each, 1 to Outro.MAX_RATS; Outro.DEFAULT_RATS without it).
## --size: render in a viewport of that size (as OutroScreen does in the game), whatever the window
## (a maximized or fullscreen window ignores --resolution): 1680x1050, 2560x1080, 1024x768...

const SHOTS := {
	Outro.Ending.SUPERVISORS: [["a_00_open", 0.5], ["a_01_press", 0.84], ["a_02_wait", 2.2], ["a_03_sniff", 2.9],
		["a_04_ding", 3.86], ["a_05_flip", 4.05], ["a_06_land", 4.6], ["a_07_stack", 4.85], ["a_08_stare", 5.05],
		["a_09_heart", 5.55], ["a_10_joy", 5.85], ["a_11_hop", 6.0], ["a_12_thumbs", 6.55], ["a_13_wink", 6.85],
		["a_14_proud", 7.3], ["a_15_photo", 7.7], ["a_16_wink_back", 8.1], ["a_17_grab", 9.35], ["a_18_bite", 9.75],
		["a_19_chew", 10.1], ["a_20_copy", 10.7], ["a_21_copy_chew", 11.2], ["a_22_glare", 11.85], ["a_23_hmph", 12.12],
		["a_24_back", 12.8], ["a_25_bliss", 13.7], ["a_26_end", 14.5]],
	Outro.Ending.RATS: [["b_00_open", 0.45], ["b_01_press", 0.84], ["b_02_sniff", 2.3], ["b_03_tap", 3.2],
		["b_04_pwomp", 4.1], ["b_05_flop", 4.55], ["b_06_shock", 4.75], ["b_07_pout", 5.25], ["b_08_photo", 5.75],
		["b_09_tilt", 6.1], ["b_10_cough", 6.6], ["b_11_plant", 7.1], ["b_12_houses", 7.9], ["b_13_lantern", 8.88],
		["b_14_lamp", 9.3], ["b_15_dark", 9.7], ["b_16_eyes", 10.0], ["b_17_more_eyes", 10.9], ["b_18_all_eyes", 11.5],
		["b_19_snicker", 11.95], ["b_20_hush", 12.6], ["b_21_strike", 12.88], ["b_22_caught", 13.1], ["b_23_dive", 13.3],
		["b_24_toaster", 13.45], ["b_25_slip", 13.85], ["b_26_baffled", 14.2], ["b_27_blow", 14.45], ["b_28_dark", 14.85],
		["b_29_button", 15.15], ["b_30_snicker", 15.4], ["b_31_end", 15.8]],
}

var _out := ""
var _view: SubViewport  # --size


func _ready() -> void:
	_out = Cli.get_str("out", "user://outro_shots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var endings: Array = [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]
	if Cli.has_arg("ending"):
		endings = [Outro.Ending.RATS if Cli.get_str("ending") == "rats" else Outro.Ending.SUPERVISORS]
	for ending: Outro.Ending in endings:
		var shots: Array = SHOTS[ending]
		if Cli.has_arg("times"):
			shots = []
			for text in Cli.get_str("times").split(",", false):
				shots.append(["%s_%s" % ["a" if ending == Outro.Ending.SUPERVISORS else "b", text], text.to_float()])
		var outro := Outro.new(ending, int(Cli.get_float("rats", Outro.DEFAULT_RATS)))
		if Cli.has_arg("size"):
			var size := Cli.get_str("size").split("x")
			_view = SubViewport.new()
			_view.size = Vector2i(size[0].to_int(), size[1].to_int())
			_view.own_world_3d = true
			_view.msaa_3d = get_viewport().msaa_3d
			_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(_view)
			_view.add_child(outro)
		else:
			add_child(outro)
		outro.set_process_unhandled_input(false)  # (a stray key on the desktop mustn't skip it)
		if Cli.has_arg("cam"):  # a fixed camera of our own (looking at a detail): --cam x,y,z --look x,y,z
			var eye := _vec(Cli.get_str("cam"))
			var look := _vec(Cli.get_str("look", "0,1,0"))
			outro._shots = [outro._shot(0.0, eye, eye, look, look, Cli.get_float("fov", 30.0), Cli.get_float("fov", 30.0))]
		if Cli.has_arg("seek"):
			outro.playing = false
			for shot: Array in shots:
				outro.seek(shot[1])
				await _save(shot[0])
		else:
			for shot: Array in shots:
				while outro.t < float(shot[1]) and is_instance_valid(outro):
					await get_tree().process_frame
				await _save(shot[0])
		outro.queue_free()
		if _view != null:
			_view.queue_free()
			_view = null
		await get_tree().process_frame
	Log.info("outro_shots", "saved in %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


static func _vec(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_out.path_join("%s.png" % shot_name))
	(_view if _view != null else get_viewport()).get_texture().get_image().save_png(path)
