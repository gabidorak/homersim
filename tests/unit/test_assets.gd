extends GutTest
## The art and audio the code refers to exists (M7): every sound in the Sfx bank, the music stems,
## every model the code or the level asks for, the clips the AnimationController plays, and the
## named parts the interactables animate. Regenerate with tools/build_assets.sh when one is missing.

const MODELS: Array[String] = [
	"supervisor", "rat", "fp_arms", "broom", "alarm_beacon", "sabotage_box", "sabotage_box_broken", "repair_panel",
	"lever", "cage", "door_panel", "door_panel_keycard", "keycard_reader", "cctv_box", "cctv_conduit", "cctv_head",
	"cctv_head_broken", "cctv_chair", "snap_trap", "cheese_lure", "trap_refill", "keycard", "donut_box",
	"console_coolant", "console_scram", "pipe_2m",
]
## model → parts code looks up by name
const PARTS := {
	"lever": ["Handle"], "cage": ["Door"], "sabotage_box": ["Lamp"], "repair_panel": ["Lamp"],
	"keycard_reader": ["Lamp"], "cctv_head": ["Lamp"], "alarm_beacon": ["Reflector"], "snap_trap": ["Bar"],
	"console_coolant": ["Button"], "console_scram": ["Button", "Cover"], "supervisor": ["HardHat"],
	"machine_valves": ["Wheel1", "Wheel2"], "machine_grid": ["Switch1", "Switch8"], "machine_ventilation": ["Fan"],
	"turbine": ["Shaft"], "reactor_core": ["Rod1", "Rod6"], "roof_fan": ["Fan"], "valve_rack_4m": ["Wheel1", "Wheel4"],
}


func test_every_sound_file_exists() -> void:
	for sound: String in Sfx.SOUNDS:
		var def: Dictionary = Sfx.SOUNDS[sound]
		assert_true(Sfx.KINDS.has(def["kind"]), "%s: unknown kind" % sound)
		for path: String in def["files"]:
			assert_true(ResourceLoader.exists(path), "%s: missing %s" % [sound, path])
		var also: String = def.get("also", "")
		assert_true(also == "" or Sfx.SOUNDS.has(also), "%s: 'also' names an unknown sound" % sound)


func test_music_exists_and_stems_loop_together() -> void:
	var length := -1.0
	for path in MusicDirector.STEMS:
		assert_true(ResourceLoader.exists(path), path)
		var stem := load(path) as AudioStream
		if length < 0.0:
			length = stem.get_length()
		assert_almost_eq(stem.get_length(), length, 0.05, "the stems must be the same length to stay in sync")
	assert_true(ResourceLoader.exists(MusicDirector.LOBBY))


func test_models_exist() -> void:
	for model in MODELS:
		assert_true(Art.exists(model), "assets/generated/%s.glb is missing" % model)


func test_model_parts_exist() -> void:
	for model: String in PARTS:
		var node := Art.instance(model)
		assert_not_null(node, model)
		if node == null:
			continue
		for part: String in PARTS[model]:
			assert_not_null(Art.part(node, part), "%s has no part '%s'" % [model, part])
		node.free()


func test_character_clips_exist() -> void:
	for kind: Role.Kind in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		var model := Art.instance("supervisor" if kind == Role.Kind.SUPERVISOR else "rat")
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "one AnimationPlayer")
		var player := players[0] as AnimationPlayer
		var clips: Dictionary = AnimationController.ROLE_CLIPS[kind]
		for key: String in clips:
			if key == "arms":
				continue
			var clip: String = clips[key]
			assert_true(clip == "" or player.has_animation(clip), "%s: missing clip '%s' (%s)" % [Role.display_name(kind), clip, key])
		for one_shot in (["swing", "place", "eat", "get_up", "emote"] if kind == Role.Kind.SUPERVISOR else ["bite", "squeak"]):
			assert_true(player.has_animation(one_shot), "%s: missing one-shot '%s'" % [Role.display_name(kind), one_shot])
		for looping in ["idle", "run"]:
			assert_ne(player.get_animation(looping).loop_mode, Animation.LOOP_NONE, "%s should loop" % looping)
		model.free()


func test_first_person_arms_clips() -> void:
	var model := Art.instance("fp_arms")
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in ["idle", "swing", "interact", "carry", "eat", "place"]:
		assert_true(player.has_animation(clip), "fp_arms: missing '%s'" % clip)
	model.free()


func test_level_models_exist() -> void:
	# Every model instance in the plant's POI scenes must resolve (the generator falls back to plain
	# boxes when one is missing: those are CSG nodes, which the art pass forbids outside collision).
	for file in DirAccess.get_files_at("res://levels/plant/pois/"):
		if not file.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string("res://levels/plant/pois/" + file)
		assert_false(text.contains("CSG"), "%s still has CSG nodes (a model was missing at generation)" % file)
		for line in text.split("\n"):
			if line.contains("assets/generated/"):
				var path := line.get_slice('path="', 1).get_slice('"', 0)
				assert_true(ResourceLoader.exists(path), "%s: %s" % [file, path])


func test_import_script_gives_models_the_toon_materials() -> void:
	# tools/godot/toon_import.gd is the scene importer's default (project.godot): without it, models
	# keep Blender's plain materials and lose the cartoon look and the outlines.
	var node := Art.instance("crate")
	var mesh := Art.meshes(node)[0]
	var mat := mesh.mesh.surface_get_material(0)
	assert_eq(mat.resource_path, "res://shaders/materials/toon_palette.tres")
	assert_not_null(mat.next_pass, "the outline pass")
	node.free()
	var panel := Art.instance("repair_panel")
	var lamp_mesh := Art.meshes(Art.part(panel, "Lamp"))[0]
	assert_eq((lamp_mesh.mesh.surface_get_material(0) as ShaderMaterial).shader, Art.TINTABLE,
		"emissive parts use the tintable shader")
	panel.free()
