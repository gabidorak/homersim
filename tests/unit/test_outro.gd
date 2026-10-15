extends GutTest
## The end-of-match cinematics (client/outro/): who sees them, that what their timelines ask for
## exists, that their hit points agree with grandma's performances (tools/blender/grandma.py) and
## the scores (tools/audio/music.py), the skip, and the physics of both timelines: each is seeked
## every 1/120 s by OutroPhysics (tests/helpers/outro_physics.gd), which finds anything going
## through anything, resting things that sink or float, a lever moving by itself, slices flying
## against gravity and a camera inside the set. Last, the checks themselves: broken copies of a
## timeline (a slice pushed 5 cm into the plate...) must fail them. And the rats: the caged rat in its
## cage, the rats in the dark on their spots with their eyes in sight, one pair per winning rat, the
## town's lights going out towards her.

const SCRIPTS: Array[String] = ["res://client/outro/outro.gd", "res://client/outro/outro_kitchen.gd",
	"res://client/outro/outro_fx.gd"]
## Parts the cinematics look up by name, per model (tools/blender/kitchen.py).
const PARTS := {"toaster": ["Body", "Lever", "Glow", "Slot1", "Slot2"], "toast_limp": ["Middle", "Top"],
	"plate": ["Surface"], "teacup": ["Steam"], "butter_dish": ["Butter", "ButterBitten"], "photo_frame": ["Picture"],
	"cat_clock": ["Pupils", "SecondHand", "Tail"], "ceiling_lamp": ["Bulb"], "match": ["Flame"], "garden_lamp": ["Lamp"],
	"house_blue": ["Windows"], "plant_building": ["Windows"]}
const MARKS: Array[String] = ["MarkIsland", "MarkToaster", "MarkPlate", "MarkTeacup", "MarkButter", "MarkPhoto"]
## Outro's hit points and where else they are written: grandma.py's name, music.py's name ("" none).
const HITS := {
	"A_CLICK": ["A_CLICK", "OUTRO_A_CLICK"], "A_DING": ["A_DING", "OUTRO_A_DING"], "A_HEART": ["", "OUTRO_A_HEART"],
	"A_JOY": ["A_JOY", "OUTRO_A_JOY"], "A_SPARKLE": ["A_SPARKLE", "OUTRO_A_SPARKLE"], "A_HER_WINK": ["A_HER_WINK", ""],
	"A_WINK": ["", "OUTRO_A_WINK"], "A_GRAB": ["A_GRAB", ""], "A_BITE": ["A_BITE", "OUTRO_A_BITE"],
	"A_HMPH": ["", "OUTRO_A_HMPH"],
	"B_FLICKER": ["", "OUTRO_B_FLICKER"], "B_CLICK": ["B_CLICK", "OUTRO_B_CLICK"], "B_PWOMP": ["B_PWOMP", "OUTRO_B_PWOMP"],
	"B_SHOCK": ["B_SHOCK", "OUTRO_B_SHOCK"], "B_COUGH": ["B_COUGH", "OUTRO_B_COUGH"], "B_ROLL": ["B_ROLL", ""],
	"B_BLACKOUT": ["B_BLACKOUT", "OUTRO_B_BLACKOUT"], "B_EYES": ["", "OUTRO_B_EYES"], "B_SNICKER": ["", "OUTRO_B_SNICKER"],
	"B_STRIKE": ["B_STRIKE", ""], "B_LIGHT": ["B_LIGHT", "OUTRO_B_LIGHT"], "B_BLOW": ["B_BLOW", "OUTRO_B_BLOW"],
	"B_BUTTON": ["B_BUTTON", "OUTRO_B_BUTTON"]}
## Each ending's gags, in order: their hits stand apart (MIN_BEAT), but for those that go together
## (TOGETHER: the lever's press and click, the DING's pops, the strike and its flare).
const BEATS := {
	Outro.Ending.SUPERVISORS: ["A_PRESS", "A_CLICK", "A_DING", "A_HEART", "A_JOY", "A_SPARKLE", "A_HER_WINK", "A_WINK",
		"A_GRAB", "A_BITE", "A_COPY", "A_HMPH"],
	Outro.Ending.RATS: ["B_FLICKER", "B_PRESS", "B_CLICK", "B_PWOMP", "B_UP", "B_SHOCK", "B_TILT", "B_COUGH", "B_ROLL",
		"B_BLACKOUT", "B_EYES", "B_SNICKER", "B_STRIKE", "B_LIGHT", "B_LEAP", "B_SLIP", "B_BLOW", "B_BUTTON"]}
const TOGETHER: Array[String] = ["A_PRESS A_CLICK", "landing 1 landing 2", "B_PRESS B_CLICK", "B_UP B_SHOCK",
	"B_STRIKE B_LIGHT"]
const MIN_BEAT := 0.3  ## s between two gags' hits
const MIN_SHOT := 1.1  ## s: the shortest shot (a gag needs its lead-in, its hit and a hold)
const MIN_ROLL_GAP := 0.2  ## s between two of the town's lights going out (house by house, not a flicker)
## The clips the outro plays on its rats (tools/blender/rat.py): the spots' and the caged rat's, and the dive.
const RAT_CLIPS: Array[String] = ["sulk", "hmph", "crawl"]
## What of grandma may come between us and her eyes (tools/blender/grandma.py's bones): her face's
## parts (her lids apart), seen straight on; her hands, seen from the cinematic's camera.
const EYE_COVERS: Array[String] = ["head", "glasses", "brow_l", "brow_r", "cheek_l", "cheek_r"]
const EYE_HANDS: Array[String] = ["hand_l", "hand_r", "thumb_l", "thumb_r"]
const EYE_SHOWN := 0.5  ## the least of an open eye's front that must show

const PostMatch := preload("res://client/post_match.gd")

var _outro: Outro


func _make(ending: Outro.Ending, rats := Outro.DEFAULT_RATS) -> Outro:
	_outro = Outro.new(ending, rats)
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
## The wait from the whistle to the result stays under 17.5 s (each gag of the rats' ending got its
## own beat), and the result keeps the ~14 s it had before the cinematic.
func test_post_match_leaves_time_for_the_cinematic_and_the_result() -> void:
	var rules: MatchRules = load(Config.DEFAULT_MATCH_RULES)
	var longest := maxf(Outro.LENGTHS[Outro.Ending.SUPERVISORS], Outro.LENGTHS[Outro.Ending.RATS])
	var cinematic := PostMatch.MELTDOWN_BOOM_S + OutroScreen.LEAD_IN + longest
	assert_lt(cinematic, 17.5, "the cinematic keeps the wait short")
	assert_gte(rules.post_match_s - cinematic, PostMatch.MIN_SHOW_S + 8.5, "the result stays up long enough to read")


# --- The timeline -----------------------------------------------------------------------------------------

## Long enough for each gag to read in a beat of its own, short enough not to drag (the post-match
## budget above).
func test_each_ending_lasts_13_to_16_s() -> void:
	for ending: Outro.Ending in [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]:
		var length: float = Outro.LENGTHS[ending]
		assert_between(length, 13.0, 16.0)
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
	# The score's steps down come as each of the town's lights goes out.
	var rats := _make(Outro.Ending.RATS)
	var rolls: Array = score["OUTRO_B_ROLLS"]
	var times := rats.roll_times()
	assert_eq(rolls.size(), times.size(), "music.py OUTRO_B_ROLLS: one per light out there")
	for i in mini(rolls.size(), times.size()):
		assert_almost_eq(float(rolls[i]), times[i], 0.001, "music.py OUTRO_B_ROLLS[%d]" % i)
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
		assert_between(shots.size(), 2, 8, "one to seven cuts")
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


## Every shot is long enough to read: its gag's lead-in, the hit and a hold.
func test_no_shot_is_too_short() -> void:
	for ending: Outro.Ending in [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]:
		var outro := Outro.new(ending)
		var shots := outro._shot_list()
		for i in shots.size():
			var end: float = shots[i + 1]["start"] if i + 1 < shots.size() else Outro.LENGTHS[ending]
			assert_gte(end - float(shots[i]["start"]), MIN_SHOT - 1e-6, "%s: shot %d (%.2f - %.2f s)" % [
				Outro.CLIPS[ending], i, shots[i]["start"], end])
		outro.free()


## Each gag reads in a beat of its own: no two hits closer than MIN_BEAT, but for those that go
## together (TOGETHER). The slices' landings count (their flights decide when).
func test_each_gag_has_a_beat_of_its_own() -> void:
	var constants := (Outro as Script).get_script_constant_map()
	for ending: Outro.Ending in BEATS:
		var hits: Array[Array] = []  # [time, name]
		for hit: String in BEATS[ending]:
			hits.append([float(constants[hit]), hit])
		if ending == Outro.Ending.SUPERVISORS:
			var outro := _make(ending)
			for k in 2:
				hits.append([float(outro.paths[k].flights()[0]["t_land"]), "landing %d" % (k + 1)])
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in range(1, hits.size()):
			if "%s %s" % [hits[i - 1][1], hits[i][1]] in TOGETHER:
				continue
			assert_gte(hits[i][0] - hits[i - 1][0], MIN_BEAT - 1e-6, "%s at %.2f s and %s at %.2f s" % [hits[i - 1][1],
				hits[i - 1][0], hits[i][1], hits[i][0]])


## The rolling blackout goes house by house (at least MIN_ROLL_GAP from one light to the next), all in
## the window's shot; her lamp goes last, in a shot of the kitchen that shows it lit first.
func test_the_blackout_rolls_house_by_house_her_lamp_last() -> void:
	var outro := _make(Outro.Ending.RATS)
	var times := outro.roll_times()
	for k in range(1, times.size()):
		assert_gte(times[k] - times[k - 1], MIN_ROLL_GAP - 1e-6, "lights %d and %d" % [k - 1, k])
	assert_gte(Outro.B_BLACKOUT - times[-1], MIN_ROLL_GAP, "her lamp, after the last light out there")
	var window: Dictionary = outro._shot_at(times[0])[0]
	assert_eq(outro._shot_at(times[-1] + 0.1)[0], window, "the town goes dark in one shot")
	var kitchen: Dictionary = outro._shot_at(Outro.B_BLACKOUT)[0]
	assert_ne(kitchen, window, "her lamp dies in the kitchen's shot")
	assert_lte(float(kitchen["start"]), Outro.B_BLACKOUT - 0.2, "lit a moment before it dies")


## The eyes open one pair at a time, evenly, over the same window whatever the number of rats (closer
## with more, never under MIN_BEAT apart); each rat crunches after its eyes open, all before the snicker.
func test_the_eye_window_is_the_same_for_1_4_and_6_rats() -> void:
	for count: int in [1, Outro.DEFAULT_RATS, Outro.MAX_RATS]:
		var outro := _make(Outro.Ending.RATS, count)
		var gap := Outro.EYE_WINDOW / count
		assert_gte(gap, MIN_BEAT - 1e-6, "%d rats" % count)
		for i in count:
			assert_almost_eq(outro.eyes_at(i), Outro.B_EYES + gap * i, 0.001, "%d rats: pair %d" % [count, i])
			for at: float in outro.gang[i]["spot"]["crunches"]:
				assert_between(at, outro.eyes_at(i) + 0.1, Outro.B_SNICKER - 0.05, "%d rats: pair %d's crunch" % [count, i])
		assert_almost_eq(outro.eyes_at(count - 1) + gap, Outro.B_EYES + Outro.EYE_WINDOW, 0.001, "%d rats" % count)
	assert_lte(Outro.B_EYES + Outro.EYE_WINDOW, Outro.B_SNICKER, "the snicker after the window")


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
	var clips: Array[String] = RAT_CLIPS.duplicate()
	for spot in _make(Outro.Ending.RATS, Outro.MAX_RATS).spots():
		if spot.has("clip"):
			clips.append(spot["clip"])
	for clip in clips:
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
	var sounds := _literals([r'_sfx(?:_pitched)?\([^,]+,\s*"([a-z0-9_]+)"', r'_loop\("([a-z0-9_]+)"'])
	assert_gt(sounds.size(), 20)
	for sound: String in sounds:
		assert_true(Sfx.has_sound(sound), "sound '%s' (%s) is not in Sfx.SOUNDS" % [sound, sounds[sound]])
		for path: String in Sfx.SOUNDS.get(sound, {}).get("files", []):
			assert_true(ResourceLoader.exists(path), path)


## Both her eyes show whenever they're open, all through both performances (every 1/30 s): at least
## EYE_SHOWN of each eye's front is in front of her face, not under its lid or the glasses' rim (seen
## straight on, along her face) nor behind her hands (seen from the camera). She shuts them both at
## once (a blink, a sniff, bliss), or swaps them for the happy "^ ^"; only her wink shuts one alone.
func test_her_eyes_show_whenever_they_are_open() -> void:
	var report: Array[String] = []
	for ending: Outro.Ending in [Outro.Ending.SUPERVISORS, Outro.Ending.RATS]:
		var outro := _make(ending)
		var skel := outro.grandma.skeleton
		var mesh: MeshInstance3D = null
		for node in outro.grandma.model.find_children("*", "MeshInstance3D", true, false):
			if (node as MeshInstance3D).skin != null:
				mesh = node
		var covers := _bone_triangles(mesh)
		var eyes := OutroPhysics.bone_vertices(mesh)
		var head := skel.find_bone("head")
		var forward := (skel.get_bone_global_rest(head).basis.inverse() * Vector3.BACK).normalized()  # (her face's way)
		var happy := skel.find_bone("eyes_happy")
		var spans := {}  # side -> [from, to, least shown, by]: the times an eye is hidden, together
		for f in int(Outro.LENGTHS[ending] * 30.0) + 1:
			var time := f / 30.0
			outro.seek(time)
			if skel.get_bone_pose_scale(happy).x > 0.3:
				continue  # (the "^ ^" instead)
			var camera := (skel.global_transform * skel.get_bone_global_pose(head)).affine_inverse() \
				* outro.camera.global_position  # (in her head's space)
			var seen := {}
			for side: String in ["l", "r"]:
				seen[side] = _eye_shown(skel, covers, eyes, side, forward, camera)
			for side: String in ["l", "r"]:
				var other := "r" if side == "l" else "l"
				var eye: Dictionary = seen[side]
				var winking := ending == Outro.Ending.SUPERVISORS and side == "l" and time >= Outro.A_HER_WINK - 0.12 \
					and time <= Outro.A_HER_WINK + 0.3
				var shut: bool = eye["lidded"] >= 0.5 and (seen[other]["lidded"] >= 0.5 or winking)
				if eye["shown"] >= EYE_SHOWN or shut:
					continue
				var span: Array = spans.get(side, [])
				if not span.is_empty() and time - span[1] < 0.05:
					span[1] = time
					if eye["shown"] < span[2]:
						span[2] = eye["shown"]
						span[3] = eye["by"]
				else:
					if not span.is_empty():
						report.append(_eye_problem(ending, side, span))
					spans[side] = [time, time, eye["shown"], eye["by"]]
		for side: String in spans:
			report.append(_eye_problem(ending, side, spans[side]))
	assert_true(report.is_empty(), "\n" + "\n".join(report))


static func _eye_problem(ending: Outro.Ending, side: String, span: Array) -> String:
	return "%s %.2f-%.2f s: her %s eye is hidden (%d %% of it shows at worst, behind her %s)" % [Outro.CLIPS[ending],
		span[0], span[1], "left" if side == "l" else "right", roundi(span[2] * 100.0), span[3]]


## How much of her eye on `side` shows now: {shown: the share of its front with none of EYE_COVERS nor
## its lid in front of it seen straight on along her face (`forward`, in her head's space), nor her
## hands seen from `camera` (in her head's space), lidded: the share under its lid, by: what hides
## the most of it}. Its front: its points in front of the middle of its depth (the black and its shine).
static func _eye_shown(skel: Skeleton3D, covers: Dictionary, eyes: Dictionary, side: String, forward: Vector3,
		camera: Vector3) -> Dictionary:
	var to_head := skel.get_bone_global_pose(skel.find_bone("head")).affine_inverse()
	var eye := to_head * skel.get_bone_global_pose(skel.find_bone("eye_" + side))
	var points := PackedVector3Array()
	var depth := Vector2(INF, -INF)
	for v: Vector3 in eyes["eye_" + side]:
		var p := eye * v
		points.append(p)
		depth = Vector2(minf(depth.x, p.dot(forward)), maxf(depth.y, p.dot(forward)))
	var into := {}  # bone -> the head's space into its own (bones squashed flat left out: an open lid)
	for bone: String in EYE_COVERS + EYE_HANDS + ["lid_" + side]:
		var xform := to_head * skel.get_bone_global_pose(skel.find_bone(bone))
		if absf(xform.basis.determinant()) > 1e-6:
			into[bone] = xform.affine_inverse()
	var front := 0
	var shown := 0
	var hiding := {}  # bone -> how many points it hides
	for p in points:
		if p.dot(forward) < (depth.x + depth.y) * 0.5:
			continue
		front += 1
		var hidden := false
		var seen_from := (camera - p).normalized()
		for bone: String in into:
			var inv: Transform3D = into[bone]
			var way := seen_from if bone in EYE_HANDS else forward
			if not (covers[bone] as TriangleMesh).intersect_segment(inv * (p + way * 0.3), inv * (p + way * 0.0015)) \
					.is_empty():
				hidden = true
				hiding[bone] = hiding.get(bone, 0) + 1
		if not hidden:
			shown += 1
	var by := ""
	for bone: String in hiding:
		if by == "" or hiding[bone] > hiding[by]:
			by = bone
	return {"shown": float(shown) / maxi(front, 1), "lidded": float(hiding.get("lid_" + side, 0)) / maxi(front, 1),
		"by": by}


## A rigid-skinned mesh's triangles by bone, in their bone's space: bone -> TriangleMesh.
static func _bone_triangles(mesh_instance: MeshInstance3D) -> Dictionary:
	var skin := mesh_instance.skin
	var faces := {}
	for s in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else \
			PackedInt32Array(range(verts.size()))
		for i in range(0, indices.size(), 3):
			var v := indices[i]
			var best := 0
			for j in per:
				if weights[v * per + j] > weights[v * per + best]:
					best = j
			var bind := bones[v * per + best]
			var bone := skin.get_bind_name(bind)
			if not faces.has(bone):
				faces[bone] = PackedVector3Array()
			for k in 3:
				faces[bone].append(skin.get_bind_pose(bind) * verts[indices[i + k]])
	var out := {}
	for bone: String in faces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces[bone]
		var flat := ArrayMesh.new()
		flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out[bone] = flat.generate_triangle_mesh()
	return out


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


# --- The rats ----------------------------------------------------------------------------------------------

## Every spot (the most rats: all six) in the dark: each rat on its surface, in no prop, its eyes in
## sight as they open, and the last pair by her face (the whole sweep covers the default four).
func test_every_rat_spot_is_on_its_surface_and_in_sight() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.RATS, Outro.MAX_RATS)).run(Callable(), Outro.B_EYES - 0.1,
		Outro.LENGTHS[Outro.Ending.RATS])
	assert_true(report.is_empty(), "\n" + "\n".join(report))


## One pair of eyes per winning rat, each at a spot of its own: 1, the default, the most; fewer than
## one or more than the spots clamp. The mess follows: more rats, more crumbs; the butter's bitten when
## its rat (the third) is there.
func test_the_eyes_follow_the_rat_count() -> void:
	var crumbs: Array[int] = []
	for asked: int in [1, Outro.DEFAULT_RATS, Outro.MAX_RATS, 0, -3, Outro.MAX_RATS + 1, 99]:
		var outro := _make(Outro.Ending.RATS, asked)
		var expected := clampi(asked, 1, Outro.MAX_RATS)
		assert_eq(outro.rats, expected, "%d rats asked" % asked)
		assert_eq(_open_eyes(outro, Outro.B_SNICKER - 0.1), expected, "%d rats: one pair each, all open" % asked)
		var spots := {}
		for member in outro.gang:
			spots[member["spot"]["name"]] = true
		assert_eq(spots.size(), expected, "each at a spot of its own")
		assert_eq(_open_eyes(outro, Outro.B_EYES - 0.05), 0, "none before the first")
		crumbs.append(outro._crumbs.size())
		outro.seek(Outro.B_LIGHT + 0.1)
		assert_eq(outro.set_.butter_bitten.visible, expected >= 3,
			"%d rats: the butter's bitten when its rat is there" % asked)
	assert_lt(crumbs[0], crumbs[1], "more rats, more crumbs")
	assert_lt(crumbs[1], crumbs[2], "more rats, more crumbs")


## The plant goes dark first, then each house from the farthest to the nearest, the garden's lantern,
## and her lamp last of all; each light out there is lit until its turn, out after it.
func test_the_lights_go_out_towards_her() -> void:
	var report := _roll_problems(_make(Outro.Ending.RATS))
	assert_true(report.is_empty(), "\n".join(report))


func test_the_caged_rat_stays_in_its_cage_on_its_counter() -> void:
	var outro := _make(Outro.Ending.SUPERVISORS)
	assert_not_null(outro.set_.cage, "the supervisors' kitchen has its hamster cage")
	assert_not_null(outro.cage_rat, "with a rat in it")
	var report := OutroPhysics.new(outro).run(Callable(), 0.0, 0.05)  # (the props' rest, and the rat at the start)
	report.append_array(OutroPhysics.new(outro).run(Callable(), Outro.A_DING, Outro.LENGTHS[Outro.Ending.SUPERVISORS]))
	assert_true(report.is_empty(), "\n".join(report))


## The checks catch what they're for (the rats' too).
func test_a_rat_out_of_its_cage_fails() -> void:
	var report := OutroPhysics.new(_make(Outro.Ending.SUPERVISORS)).run(func(o: Outro, _time: float) -> void:
		o.cage_rat.position.z += 0.3, 7.0, 7.2)  # (through the front bars)
	assert_true(_mentions(report, "caged rat is out of its cage"), "\n".join(report))


func test_a_floating_cage_fails() -> void:
	var outro := _make(Outro.Ending.SUPERVISORS)
	outro.set_.cage.position.y += 0.01
	var report := OutroPhysics.new(outro).run(Callable(), 0.0, 0.02)
	assert_true(_mentions(report, "cage on the sink counter", "floating"), "\n".join(report))


func test_a_rat_sunk_in_the_fridge_fails() -> void:
	var outro := _make(Outro.Ending.RATS)
	var report := OutroPhysics.new(outro).run(func(o: Outro, _time: float) -> void:
		var actor: IntroActor = o.gang[1]["actor"]
		actor.position.y -= 0.03, outro.eyes_at(1) + 0.05, outro.eyes_at(1) + 0.15)
	assert_true(_mentions(report, "Rat_fridge on the fridge", "sunk in"), "\n".join(report))


func test_eyes_behind_grandma_fail() -> void:
	var outro := _make(Outro.Ending.RATS)
	var report := OutroPhysics.new(outro).run(func(o: Outro, time: float) -> void:
		if time >= o.eyes_at(2):  # the butter rat's eyes, behind her head
			for glint: MeshInstance3D in o.gang[2]["glints"]:
				glint.global_position = Outro.bone_xform(o.grandma, "head") * Vector3(0.0, 0.18, -0.12),
		outro.eyes_at(2) - 0.05, outro.eyes_at(2) + 0.2)
	assert_true(_mentions(report, "eyes at the butter", "hidden"), "\n".join(report))


func test_houses_going_out_out_of_order_fail() -> void:
	var outro := _make(Outro.Ending.RATS)
	var lights := outro.set_.town_lights
	var distances := outro.set_.town_distances
	var near := lights.size() - 2  # the nearest house goes out before a farther one
	lights.insert(1, lights.pop_at(near))
	distances.insert(1, distances.pop_at(near))
	assert_true(_mentions(_roll_problems(outro), "farther"), "\n".join(_roll_problems(outro)))


func test_a_missing_pair_of_eyes_fails() -> void:
	var outro := _make(Outro.Ending.RATS, 3)
	outro.gang.pop_back()  # a rat short
	assert_ne(_open_eyes(outro, Outro.B_SNICKER - 0.1), clampi(outro.rats, 1, Outro.MAX_RATS))


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


## How many pairs of eyes are open in the dark at `time` (both glints of a pair showing).
static func _open_eyes(outro: Outro, time: float) -> int:
	outro.seek(time)
	var open := 0
	for member in outro.gang:
		var glints: Array = member["glints"]
		if glints.all(func(g: MeshInstance3D) -> bool: return g.visible and g.scale.y > 0.3):
			open += 1
	return open


## What's wrong with the rolling blackout: each of the town's lights (the plant first, then nearer and
## nearer) goes out after the one before, lit until then and out after, all before her lamp dies.
static func _roll_problems(outro: Outro) -> Array[String]:
	var out: Array[String] = []
	var times := outro.roll_times()
	var distances := outro.set_.town_distances
	if times.size() != outro.set_.town_lights.size() or times.size() < 7:
		out.append("the plant, the houses and the lantern: %d lights, %d times" % [outro.set_.town_lights.size(),
			times.size()])
		return out
	for k in times.size():
		if k > 0 and times[k] <= times[k - 1]:
			out.append("light %d goes out before light %d" % [k, k - 1])
		if k > 0 and distances[k] > distances[k - 1]:
			out.append("light %d (%.0f m) is farther than light %d (%.0f m) but goes out after it" % [k, distances[k],
				k - 1, distances[k - 1]])
		if times[k] >= Outro.B_BLACKOUT:
			out.append("light %d goes out after her lamp" % k)
		var before: Array[float] = outro.town_lights_at(times[k] - 0.01)
		var after: Array[float] = outro.town_lights_at(times[k] + 0.1)
		if before[k] < 1.0 or after[k] > 0.0:
			out.append("light %d isn't lit until its turn, out after it" % k)
	outro.seek(Outro.B_BLACKOUT - 0.01)
	if outro.set_.lamp_light.light_energy <= 0.0:
		out.append("her lamp is out before its turn")
	outro.seek(Outro.B_BLACKOUT + 0.3)
	if outro.set_.lamp_light.light_energy > 0.0 or outro.set_.town_lights.size() == 0:
		out.append("her lamp is still on after the blackout")
	return out


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
