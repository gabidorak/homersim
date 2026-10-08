extends GutTest
## The intro cinematic (client/intro/): when it plays, and that everything its timeline asks for
## exists. The timeline only runs windowed (the set, the actors and the effects are built then), so
## the clips, sounds, models, parts and bones it names are collected from the scripts' text, the way
## test_translations.gd collects tr() literals: a renamed clip or sound fails here instead of quietly
## doing nothing in the intro (IntroActor and Sfx skip what they can't find).

const SCRIPTS: Array[String] = ["res://client/intro/intro.gd", "res://client/intro/intro_set.gd",
	"res://client/intro/intro_fx.gd", "res://client/intro/intro_actor.gd"]
## The cast: a clip the intro plays must exist in at least one of them.
const CHARACTERS: Array[String] = ["supervisor", "hamster", "hamster_cream", "hamster_cocoa", "rat"]
## Parts the intro looks up by name, per model.
const PARTS := {"hamster_cage": ["Door", "Roof", "Wheel"], "hamster_cage_house": ["Door"],
	"alarm_beacon": ["Reflector"], "supervisor": ["HardHat"]}


func test_plays_for_a_plain_windowed_start() -> void:
	assert_true(Intro.should_play({}, false, false))
	assert_true(Intro.should_play({}, false, true))
	assert_true(Intro.should_play({"name": "Alice", "settings": "x.cfg"}, false, true), "other flags don't matter")


func test_skipped_when_something_else_comes_first() -> void:
	assert_false(Intro.should_play({}, true, false), "headless")
	assert_false(Intro.should_play({"no-intro": true}, false, false))
	assert_false(Intro.should_play({"connect": "127.0.0.1:7777"}, false, false), "straight into a server")
	for flag in MenuTestHooks.FLAGS + DebugHooks.FLAGS:
		assert_false(Intro.should_play({flag: true}, false, true), "test hook --%s (debug build)" % flag)
		assert_true(Intro.should_play({flag: true}, false, false), "release builds ignore --%s" % flag)


func test_length_and_hit_points() -> void:
	assert_between(Intro.LENGTH, 12.0, 20.0, "about 12 to 20 s")
	var hits: Array[float] = [Intro.TRIP, Intro.SPLASH, Intro.REVEAL, Intro.ALARM, Intro.BONK]
	for i in hits.size():
		assert_between(hits[i], 0.0, Intro.LENGTH)
		if i > 0:
			assert_gt(hits[i], hits[i - 1], "the hit points come in order")


func test_music_matches_the_timeline() -> void:
	assert_true(ResourceLoader.exists(Intro.MUSIC), Intro.MUSIC)
	var music := load(Intro.MUSIC) as AudioStream
	if music != null:
		assert_almost_eq(music.get_length(), Intro.LENGTH, 0.1, "tools/audio/music.py INTRO_S is Intro.LENGTH")


func test_shots_are_in_order() -> void:
	var intro := Intro.new()
	var shots := intro._shot_list()
	assert_gt(shots.size(), 3)
	assert_eq(shots[0]["start"], 0.0, "the first shot starts the intro")
	for i in range(1, shots.size()):
		assert_gt(shots[i]["start"], shots[i - 1]["start"])
		assert_lt(shots[i]["start"], Intro.LENGTH)
	intro.free()


func test_clips_exist() -> void:
	var clips := _literals([r'\.play(?:_upper)?\(\s*"([a-z_]+)"', r'IntroActor\.create\([^\n]*,\s*"([a-z_]+)"\)'])
	assert_gt(clips.size(), 10)
	var players: Array[AnimationPlayer] = []
	var models: Array[Node] = []
	for character in CHARACTERS:
		var model := Art.instance(character)
		assert_not_null(model, character)
		if model != null:
			models.append(model)
			players.append(model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer)
	for clip: String in clips:
		assert_true(players.any(func(p: AnimationPlayer) -> bool: return p.has_animation(clip)),
			"clip '%s' (%s) is in none of %s" % [clip, clips[clip], CHARACTERS])
	for model in models:
		model.free()


func test_looping_clips_loop() -> void:
	var loops := {"supervisor": ["sit", "carry_walk", "faceplant", "cheer", "cower", "ouch", "chase", "run"],
		"hamster": ["idle", "nibble", "run", "beg", "shiver", "wash", "look_up"], "rat": ["idle", "run", "gnaw", "crawl"]}
	for character: String in loops:
		var model := Art.instance(character)
		var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip: String in loops[character]:
			assert_ne(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s: %s should loop" % [character, clip])
		model.free()


func test_sounds_exist() -> void:
	var sounds := _literals([r'_sfx\([^,]+,\s*"([a-z0-9_%]+)"', r'Sfx\.play\(self,\s*"([a-z0-9_%]+)"'])
	assert_gt(sounds.size(), 10)
	for sound: String in sounds:
		for name in ([sound] if not sound.contains("%d") else [sound % 1, sound % 2, sound % 3]):
			assert_true(Sfx.has_sound(name), "sound '%s' (%s) is not in Sfx.SOUNDS" % [name, sounds[sound]])


func test_models_and_parts_exist() -> void:
	var models := _literals([r'Art\.add\([^,\n]+,\s*"([a-z0-9_]+)"', r'_prop\("([a-z0-9_]+)"',
		r'IntroActor\.create\([^,\n]+,\s*"([a-z0-9_]+)"'])
	assert_gt(models.size(), 20)
	for model: String in models:
		assert_true(Art.exists(model), "assets/generated/%s.glb is missing (%s)" % [model, models[model]])
	for model: String in PARTS:
		var node := Art.instance(model)
		for part: String in PARTS[model]:
			assert_not_null(Art.part(node, part), "%s has no part '%s'" % [model, part])
		node.free()


func test_bones_exist() -> void:
	var bones := _literals([r'\.attach\([^,\n]+,\s*"([a-z_-]+)"', r'bone_position\(\s*"([a-z_-]+)"'])
	assert_gt(bones.size(), 2)
	var skeletons: Array[Skeleton3D] = []
	var models: Array[Node] = []
	for character in CHARACTERS:
		var model := Art.instance(character)
		models.append(model)
		skeletons.append(model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D)
	for bone: String in bones:
		assert_true(skeletons.any(func(s: Skeleton3D) -> bool: return s.find_bone(bone) >= 0),
			"bone '%s' (%s) is in no character's skeleton" % [bone, bones[bone]])
	for model in models:
		model.free()


## Every string the patterns' first group catches in the intro's scripts (value -> script file).
func _literals(patterns: Array[String]) -> Dictionary:
	var found := {}
	for path in SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		for pattern in patterns:
			for m in RegEx.create_from_string(pattern).search_all(source):
				if m.get_string(1) != "":
					found[m.get_string(1)] = path.get_file()
	return found
