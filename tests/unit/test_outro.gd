extends GutTest
## The end-of-match cinematics (client/outro/): who sees them, that what their timelines ask for
## exists, that their hit points agree with grandma's performances (tools/blender/grandma.py) and
## the scores (tools/audio/music.py), the skip, and the physics of both timelines: each is seeked
## every 1/120 s by OutroPhysics (tests/helpers/outro_physics.gd), which finds anything going
## through anything, resting things that sink or float, a lever moving by itself, slices flying
## against gravity and a camera inside the set. Last, the checks themselves: broken copies of a
## timeline (a slice pushed 5 cm into the plate...) must fail them.

const SCRIPTS: Array[String] = ["res://client/outro/outro.gd", "res://client/outro/outro_kitchen.gd",
	"res://client/outro/outro_fx.gd"]
## Parts the cinematics look up by name, per model (tools/blender/kitchen.py).
const PARTS := {"toaster": ["Body", "Lever", "Glow", "Slot1", "Slot2"], "toast_limp": ["Middle", "Top"],
	"plate": ["Surface"], "teacup": ["Steam"], "butter_dish": ["Butter", "ButterBitten"], "photo_frame": ["Picture"],
	"cat_clock": ["Pupils", "SecondHand", "Tail"], "ceiling_lamp": ["Bulb"], "match": ["Flame"]}
const MARKS: Array[String] = ["MarkIsland", "MarkToaster", "MarkPlate", "MarkTeacup", "MarkButter", "MarkPhoto"]
## Outro's hit points and where else they are written: grandma.py's name, music.py's name ("" none).
const HITS := {
	"A_CLICK": ["A_CLICK", "OUTRO_A_CLICK"], "A_DING": ["A_DING", "OUTRO_A_DING"], "A_JOY": ["A_JOY", "OUTRO_A_JOY"],
	"A_SPARKLE": ["", "OUTRO_A_SPARKLE"], "A_GRAB": ["A_GRAB", ""], "A_BITE": ["A_BITE", "OUTRO_A_BITE"],
	"B_FLICKER": ["", "OUTRO_B_FLICKER"], "B_CLICK": ["B_CLICK", "OUTRO_B_CLICK"], "B_PWOMP": ["B_PWOMP", "OUTRO_B_PWOMP"],
	"B_SHOCK": ["B_SHOCK", "OUTRO_B_SHOCK"], "B_BLACKOUT": ["B_BLACKOUT", "OUTRO_B_BLACKOUT"],
	"B_EYES": ["", "OUTRO_B_EYES"], "B_STRIKE": ["B_STRIKE", ""], "B_LIGHT": ["", "OUTRO_B_LIGHT"],
	"B_BLOW": ["B_BLOW", "OUTRO_B_BLOW"]}

const PostMatch := preload("res://client/post_match.gd")

var _outro: Outro


func _make(ending: Outro.Ending) -> Outro:
	_outro = Outro.new(ending)
	_outro.playing = false
	add_child_autofree(_outro)
	return _outro


# --- Who sees it ----------------------------------------------------------------------------------------

func test_plays_on_windowed_clients_only() -> void:
	assert_true(OutroScreen.should_play({}, false, false), "a windowed client: players and spectators alike")
	assert_true(OutroScreen.should_play({"name": "Alice", "settings": "x.cfg"}, false, false), "other flags don't matter")
	assert_false(OutroScreen.should_play({}, true, false), "never built headless")
	assert_false(OutroScreen.should_play({}, false, true), "nor on a server")
	assert_false(OutroScreen.should_play({}, true, true), "a dedicated server")
	assert_false(OutroScreen.should_play({"no-outro": true}, false, false), "--no-outro")
	OutroScreen.enabled = false
	assert_false(OutroScreen.should_play({}, false, false), "off for a run (tests that drive the post-match screen)")
	OutroScreen.enabled = true
	assert_false(OutroScreen.wanted(), "this test process is headless")


func test_the_winners_get_their_ending() -> void:
	assert_eq(OutroScreen.ending_for(MatchRulesModel.Team.SUPERVISORS), Outro.Ending.SUPERVISORS)
	assert_eq(OutroScreen.ending_for(MatchRulesModel.Team.RATS), Outro.Ending.RATS)


## The server keeps POST_MATCH for post_match_s: the longest wait for the cinematic (a meltdown's
## boom, the fade to black, the rats' ending) and the result's MIN_SHOW_S must fit, with time to read.
func test_post_match_leaves_time_for_the_cinematic_and_the_result() -> void:
	var rules: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	var longest := maxf(Outro.LENGTHS[Outro.Ending.SUPERVISORS], Outro.LENGTHS[Outro.Ending.RATS])
	var cinematic := PostMatch.MELTDOWN_BOOM_S + OutroScreen.LEAD_IN + longest
	assert_lt(cinematic, 12.0, "the cinematic keeps the wait short")
	assert_gte(rules.post_match_s - cinematic, PostMatch.MIN_SHOW_S + 8.0, "the result stays up long enough to read")


# --- The timeline -----------------------------------------------------------------------------------------

func test_each_ending_lasts_5_to_10_s() -> void:
	for ending: Outro.Ending in [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]:
		var length: float = Outro.LENGTHS[ending]
		assert_between(length, 5.0, 10.0)
		var music := load(Outro.MUSIC[ending]) as AudioStream
		assert_not_null(music, Outro.MUSIC[ending])
		if music != null:
			assert_almost_eq(music.get_length(), length, 0.05, "tools/audio/music.py: the score is as long")
		var grandma := Art.instance("grandma")
		var player := grandma.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		assert_true(player.has_animation(Outro.CLIPS[ending]), Outro.CLIPS[ending])
		if player.has_animation(Outro.CLIPS[ending]):
			assert_almost_eq(player.get_animation(Outro.CLIPS[ending]).length, length, 1.0 / 30.0,
				"tools/blender/grandma.py: her performance is as long")
		grandma.free()


func test_hit_points_agree_with_the_performances_and_the_scores() -> void:
	var perf := _python_constants("res://tools/blender/grandma.py")
	var score := _python_constants("res://tools/audio/music.py")
	assert_almost_eq(float(perf["A_LENGTH"]), Outro.LENGTHS[Outro.Ending.SUPERVISORS], 0.001)
	assert_almost_eq(float(perf["B_LENGTH"]), Outro.LENGTHS[Outro.Ending.RATS], 0.001)
	assert_almost_eq(float(score["OUTRO_A_S"]), Outro.LENGTHS[Outro.Ending.SUPERVISORS], 0.001)
	assert_almost_eq(float(score["OUTRO_B_S"]), Outro.LENGTHS[Outro.Ending.RATS], 0.001)
	var constants := (Outro as Script).get_script_constant_map()
	for hit: String in HITS:
		for i in 2:
			var other: String = HITS[hit][i]
			var source: Dictionary = perf if i == 0 else score
			if other != "":
				assert_true(source.has(other), "%s is missing" % other)
				assert_almost_eq(float(source.get(other, -1.0)), float(constants[hit]), 0.001,
					"Outro.%s and %s's %s" % [hit, ["grandma.py", "music.py"][i], other])
	var taps: Array = perf["B_TAPS"]
	assert_eq(taps.size(), Outro.B_TAPS.size())
	for i in taps.size():
		assert_almost_eq(float(taps[i]), Outro.B_TAPS[i], 0.001, "B_TAPS")
	# The score's plops come as the slices land (their flights decide when).
	var outro := _make(Outro.Ending.SUPERVISORS)
	var lands: Array = score["OUTRO_A_LANDS"]
	for k in 2:
		assert_almost_eq(float(lands[k]), float(outro.paths[k].flights()[0]["t_land"]), 0.06,
			"music.py OUTRO_A_LANDS: slice %d lands" % (k + 1))


func test_shots_start_at_zero_in_order_inside_the_room() -> void:
	for ending: Outro.Ending in [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]:
		var outro := Outro.new(ending)
		var shots := outro._shot_list()
		assert_between(shots.size(), 2, 4, "one to three cuts")
		assert_eq(shots[0]["start"], 0.0)
		for i in shots.size():
			if i > 0:
				assert_gt(shots[i]["start"], shots[i - 1]["start"])
			assert_lt(shots[i]["start"], Outro.LENGTHS[ending])
			for eye: Vector3 in shots[i]["eye"]:
				assert_true(eye.x > OutroKitchen.LEFT and eye.x < OutroKitchen.RIGHT and eye.y > 0.0
					and eye.y < OutroKitchen.HEIGHT and eye.z > OutroKitchen.BACK and eye.z < OutroKitchen.FRONT,
					"shot %d's eye %s is in the kitchen" % [i, eye])
		outro.free()


func test_clips_marks_parts_models_and_sounds_exist() -> void:
	var grandma := Art.instance("grandma")
	var player := grandma.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip: String in ["idle"] + Outro.CLIPS.values():
		assert_true(player.has_animation(clip), "grandma's clip '%s'" % clip)
	assert_ne(player.get_animation("idle").loop_mode, Animation.LOOP_NONE, "her idle loops")
	for mark in MARKS:
		assert_not_null(Art.part(grandma, mark), "grandma.glb's %s" % mark)
	grandma.free()
	var rat := Art.instance("rat")
	var rat_player := rat.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip: String in _literals([r'rat\.pose_at\("([a-z_]+)"']):
		assert_true(rat_player.has_animation(clip), "the rat's clip '%s'" % clip)
	rat.free()
	var models := _literals([r'Art\.(?:add|instance)\([^"\n]*"([a-z0-9_]+)"', r'_on_mark\("([a-z0-9_]+)"'])
	assert_gt(models.size(), 15)
	for model: String in models:
		assert_true(Art.exists(model), "assets/generated/%s.glb is missing (%s)" % [model, models[model]])
	for model: String in PARTS:
		var node := Art.instance(model)
		for part: String in PARTS[model]:
			assert_not_null(Art.part(node, part), "%s has no part '%s'" % [model, part])
		node.free()
	var sounds := _literals([r'_sfx\([^,]+,\s*"([a-z0-9_]+)"', r'_loop\("([a-z0-9_]+)"'])
	assert_gt(sounds.size(), 20)
	for sound: String in sounds:
		assert_true(Sfx.has_sound(sound), "sound '%s' (%s) is not in Sfx.SOUNDS" % [sound, sounds[sound]])
		for path: String in Sfx.SOUNDS.get(sound, {}).get("files", []):
			assert_true(ResourceLoader.exists(path), path)


# --- Physics ---------------------------------------------------------------------------------------------

func test_the_supervisors_ending_is_physically_consistent() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run()
	assert_true(report.is_empty(), "\n" + "\n".join(report))


func test_the_rats_ending_is_physically_consistent() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.RATS)).run()
	assert_true(report.is_empty(), "\n" + "\n".join(report))


## The checks catch what they're for: each broken copy fails with the right complaint.
func test_a_slice_pushed_into_the_plate_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run(func(o: Outro, time: float) -> void:
		if o.paths[0].state_at(time)["state"] == ToastPath.State.REST:
			o.toasts[0].position.y -= 0.05, 4.5, 5.6)
	assert_true(_mentions(report, "Toast1", "plate"), "\n".join(report))


func test_a_slice_hovering_over_the_plate_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run(func(o: Outro, time: float) -> void:
		if o.paths[0].state_at(time)["state"] == ToastPath.State.REST:
			o.toasts[0].position.y += 0.01, 4.5, 5.6)
	assert_true(_mentions(report, "Toast1 on the plate", "floating"), "\n".join(report))


func test_a_slice_through_the_toaster_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.RATS)).run(func(o: Outro, _time: float) -> void:
		o.toasts[1].position.z += 0.02, 0.0, 1.0)
	assert_true(_mentions(report, "Toast2", "toaster's body"), "\n".join(report))


func test_a_lever_moving_by_itself_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run(func(o: Outro, time: float) -> void:
		if time > 2.0 and time < 2.5:
			o.set_.set_lever(1.0 - (time - 2.0)), 1.5, 3.0)
	assert_true(_mentions(report, "lever"), "\n".join(report))


func test_a_slice_flying_without_gravity_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run(func(o: Outro, time: float) -> void:
		var flight: Dictionary = o.paths[0].flights()[0]
		if time > flight["t_rim"] and time < flight["hang"].x:
			o.toasts[0].position.y += 2.0 * pow(time - float(flight["t_rim"]), 2.0), 3.7, 4.8)
	assert_true(_mentions(report, "Toast1", "gravity"), "\n".join(report))


func test_a_camera_inside_the_set_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.RATS)).run(func(o: Outro, _time: float) -> void:
		o.camera.global_position = o.set_.toaster.global_position + Vector3(0.0, 0.1, 0.0), 0.0, 0.2)
	assert_true(_mentions(report, "camera"), "\n".join(report))


func test_grandma_sinking_into_the_floor_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.RATS)).run(func(o: Outro, _time: float) -> void:
		o.grandma.position.y = -0.01, 0.0, 0.2)
	assert_true(_mentions(report, "slippers"), "\n".join(report))


# --- The skip ------------------------------------------------------------------------------------------

func test_a_skip_ends_it_at_any_time() -> void:
	var outro := _make(Outro.Ending.RATS)
	watch_signals(outro)
	var times: Array[float] = []
	var time := 0.0
	while time < outro.length() + 0.3:
		times.append(time)
		time += 0.4
	for at in times:
		outro.leaving = false
		outro.seek(at)
		outro.skip()
		assert_true(outro.leaving, "skipped at %.1f s" % at)
		_step_tweens(outro.SKIP_FADE + 0.05)
	assert_signal_emit_count(outro, "finished", times.size(), "each skip finishes it")


func test_it_finishes_by_itself() -> void:
	var outro := _make(Outro.Ending.SUPERVISORS)
	watch_signals(outro)
	outro.playing = true
	outro.seek(outro.length() - 0.05)
	outro._process(0.0)  # (the first frame starts the clock)
	outro._process(0.1)
	assert_signal_emitted(outro, "finished")
	assert_true(outro.leaving)


func test_the_screen_skips_after_its_grace_and_gives_the_view_back() -> void:
	var screen := OutroScreen.play(self, MatchRulesModel.Team.RATS)
	watch_signals(screen)
	_step_tweens(OutroScreen.LEAD_IN + 0.05)  # the game fades to black, the cinematic starts
	assert_not_null(screen.outro, "the cinematic took over")
	assert_true(get_tree().root.disable_3d, "the game's view draws nothing behind it")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen.outro.t = OutroScreen.GRACE * 0.5
	screen._input(key)
	assert_false(screen.outro.leaving, "a press in the first moments doesn't skip it")
	screen.outro.t = OutroScreen.GRACE + 0.1
	screen._input(key)
	assert_true(screen.outro.leaving, "then it does")
	_step_tweens(Cinematic.SKIP_FADE + 0.05)
	assert_signal_emitted(screen, "finished")
	assert_false(get_tree().root.disable_3d, "the game's view is back")
	await get_tree().process_frame  # (it frees itself)


func test_the_screen_stops_at_once_for_the_next_match() -> void:
	var screen := OutroScreen.play(self, MatchRulesModel.Team.SUPERVISORS)
	watch_signals(screen)
	_step_tweens(OutroScreen.LEAD_IN + 0.05)
	screen.stop()
	assert_signal_emitted(screen, "finished")
	assert_false(get_tree().root.disable_3d)
	await get_tree().process_frame  # (it frees itself)


# --- Helpers ---------------------------------------------------------------------------------------------

## Runs every tween forward by `seconds` (the fades) without waiting for them.
func _step_tweens(seconds: float) -> void:
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.custom_step(seconds)


static func _mentions(report: Array[String], a: String, b := "") -> bool:
	return report.any(func(line: String) -> bool: return line.contains(a) and (b == "" or line.contains(b)))


## Every string the patterns' first group catches in the outro's scripts (value -> script file).
func _literals(patterns: Array[String]) -> Dictionary:
	var found := {}
	for path in SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		for pattern in patterns:
			for m in RegEx.create_from_string(pattern).search_all(source):
				if m.get_string(1) != "":
					found[m.get_string(1)] = path.get_file()
	return found


## A Python file's module constants: NAME = number, NAME = (numbers...), A, B = number, number.
static func _python_constants(path: String) -> Dictionary:
	var out := {}
	var line_re := RegEx.create_from_string(r'(?m)^([A-Z][A-Z0-9_]*(?:\s*,\s*[A-Z][A-Z0-9_]*)*)\s*=\s*([-0-9.,\s()]+?)\s*(?:#.*)?$')
	for m in line_re.search_all(FileAccess.get_file_as_string(path)):
		var names := m.get_string(1).replace(" ", "").split(",")
		var values: Array = []
		for text in m.get_string(2).replace("(", "").replace(")", "").split(",", false):
			if text.strip_edges().is_valid_float():
				values.append(text.strip_edges().to_float())
		if names.size() == 1:
			out[names[0]] = values[0] if values.size() == 1 and not m.get_string(2).contains("(") else values
		elif names.size() == values.size():
			for i in names.size():
				out[names[i]] = values[i]
	return out
