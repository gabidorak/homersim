extends Node
## Visual check of the end-of-match cinematics (client/outro/), windowed: plays each ending and saves
## a PNG at each of its key moments (and wherever --times says).
##   godot --fixed-fps 60 tests/helpers/OutroShots.tscn -- [--out DIR] [--ending supervisors|rats]
##       [--times 0.5,3.9] [--seek] [--cam x,y,z --look x,y,z [--fov F]]
## --fixed-fps keeps the clock exact (each frame is 1/60 s whatever the machine). --seek jumps
## straight to each moment instead of playing up to it (no particles, faster).

const SHOTS := {
	Outro.Ending.SUPERVISORS: [["a_00_open", 0.5], ["a_01_press", 0.84], ["a_02_wait", 2.2], ["a_03_sniff", 2.9],
		["a_04_ding", 3.95], ["a_05_flip", 4.2], ["a_06_land", 4.8], ["a_07_stack", 5.05], ["a_08_hop", 5.3],
		["a_09_photo", 6.05], ["a_10_bite", 6.8], ["a_11_bliss", 7.4], ["a_12_end", 8.1]],
	Outro.Ending.RATS: [["b_00_open", 0.45], ["b_01_press", 0.84], ["b_02_sniff", 2.3], ["b_03_tap", 3.2],
		["b_04_pwomp", 4.1], ["b_05_flop", 4.55], ["b_06_shock", 4.85], ["b_07_pout", 5.25], ["b_08_photo", 5.75],
		["b_09_dark", 6.4], ["b_10_eyes", 7.0], ["b_11_crunch", 7.4], ["b_12_match", 8.15], ["b_13_tail", 8.5],
		["b_14_blow", 8.85]],
}

var _out := ""


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
		var outro := Outro.new(ending)
		add_child(outro)
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
		await get_tree().process_frame
	Log.info("outro_shots", "saved in %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


static func _vec(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_out.path_join("%s.png" % shot_name))
	get_viewport().get_texture().get_image().save_png(path)
