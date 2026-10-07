extends GutTest
## User settings (M8): values are cleaned, survive a save + load, and key bindings round-trip.
## Works on a temporary file; the real user://settings.cfg is never touched (headless processes
## don't load or save it).

const PATH := "user://test_user_settings.cfg"

var _saved := {}


func before_each() -> void:
	_saved.clear()
	for key: String in Config.SECTIONS:
		_saved[key] = Config.get(key)
	_saved["favourites"] = Config.favourites.duplicate(true)
	_saved["seen_hints"] = Config.seen_hints.duplicate()
	_saved["bindings"] = Config.bindings.duplicate()


func after_each() -> void:
	for key: String in Config.SECTIONS:
		Config.set(key, _saved[key])
	Config.favourites = _saved["favourites"]
	Config.seen_hints = _saved["seen_hints"]
	Config.bindings = _saved["bindings"]
	for action in Keys.REBINDABLE:
		Config._apply_binding(action)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_headless_processes_dont_persist() -> void:
	assert_false(Config.is_persistent(), "the test runner is headless: no settings.cfg")


func test_clean_value_clamps_and_converts() -> void:
	assert_eq(Config.clean_value("fov", 200.0), 110.0)
	assert_eq(Config.clean_value("fov", 75), 75.0, "an int becomes a float")
	assert_eq(Config.clean_value("volume_music", -1.0), 0.0)
	assert_eq(Config.clean_value("render_scale", 0.1), 0.5)
	assert_eq(Config.clean_value("window_mode", 9), Config.WindowMode.size() - 1)
	assert_eq(Config.clean_value("outlines", -3), Config.Outlines.FULL_SCREEN)
	assert_eq(Config.clean_value("resolution", Vector2(1920, 1080)), Vector2i(1920, 1080))
	assert_eq(Config.clean_value("language", "klingon"), "")
	assert_eq(Config.clean_value("renderer", "vulkan_magic"), "forward_plus")
	assert_eq(Config.clean_value("vsync", "yes"), Config.default_value("vsync"), "wrong type: the default")
	assert_eq(Config.clean_value("player_name", "  [b]Bob[/b]  "), "bBob/b")
	assert_eq(Config.clean_value("player_name", "   "), "", "a blank name stays unset")
	assert_eq(Config.clean_value("host_supervisors", 7), MatchRules.SUPERVISORS_LIMIT)
	assert_eq(Config.clean_value("solo_rats", 0), 1)
	assert_eq(Config.clean_value("host_bots", 6), true, "an old 'fill up to 6' setting: bots on (the default)")


func test_save_and_load_round_trip() -> void:
	Config.fov = 95.0
	Config.invert_y = true
	Config.volume_music = 0.25
	Config.window_mode = Config.WindowMode.FULLSCREEN
	Config.resolution = Vector2i(1600, 900)
	Config.language = "fr"
	Config.player_name = "Chloé"
	Config.favourites = [{"name": "Friday", "address": "10.0.0.5:7777"}] as Array[Dictionary]
	Config.seen_hints = PackedStringArray(["lobby", "caged"])
	Config.bindings = {&"jump": "key:%d" % KEY_F, &"emote": ""}
	assert_eq(Config.save_settings(PATH), OK)
	for key: String in Config.SECTIONS:
		Config.set(key, Config.default_value(key))
	Config.favourites.clear()
	Config.seen_hints.clear()
	Config.bindings.clear()
	assert_true(Config.load_settings(PATH))
	assert_eq(Config.fov, 95.0)
	assert_true(Config.invert_y)
	assert_eq(Config.volume_music, 0.25)
	assert_eq(Config.window_mode, Config.WindowMode.FULLSCREEN)
	assert_eq(Config.resolution, Vector2i(1600, 900))
	assert_eq(Config.language, "fr")
	assert_eq(Config.player_name, "Chloé")
	assert_eq(Config.favourites.size(), 1)
	assert_eq(Config.favourites[0]["address"], "10.0.0.5:7777")
	assert_eq(Array(Config.seen_hints), ["lobby", "caged"])
	assert_eq(Config.bindings.get(&"jump"), "key:%d" % KEY_F)
	assert_eq(Config.bindings.get(&"emote"), "", "an unbound action stays unbound")


func test_load_ignores_garbage() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "fov", "wide")
	cfg.set_value("audio", "volume_sfx", 7.0)
	cfg.set_value("keybinds", "jump", "banana:3")
	cfg.set_value("keybinds", "not_an_action", "key:70")
	cfg.set_value("servers", "favourites", [{"name": "bad", "address": "no port here:"}, "junk"])
	cfg.save(PATH)
	Config.load_settings(PATH)
	assert_eq(Config.fov, Config.default_value("fov"))
	assert_eq(Config.volume_sfx, 1.0, "clamped")
	assert_false(Config.bindings.has(&"jump"), "unreadable binding ignored")
	assert_false(Config.bindings.has(&"not_an_action"))
	assert_eq(Config.favourites.size(), 0)


func test_missing_file_keeps_values() -> void:
	Config.fov = 99.0
	assert_false(Config.load_settings("user://nope_not_here.cfg"))
	assert_eq(Config.fov, 99.0)


func test_rebinding_changes_the_input_map() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	Config.set_binding(&"interact", key)
	var events := InputMap.action_get_events(&"interact")
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_G)
	assert_eq(Config.binding_of(&"interact"), "key:%d" % KEY_G)
	Config.set_binding(&"interact", null)
	assert_eq(InputMap.action_get_events(&"interact").size(), 0, "unbound")
	Config.reset_bindings()
	assert_eq(Keys.encode(InputMap.action_get_events(&"interact")[0]), "key:%d" % KEY_E, "back to E")
	assert_false(Config.bindings.has(&"interact"), "defaults aren't stored")


func test_binding_back_to_the_default_is_not_stored() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	Config.set_binding(&"interact", key)
	assert_false(Config.bindings.has(&"interact"))


func test_every_rebindable_action_exists_and_is_named() -> void:
	for action in Keys.REBINDABLE:
		assert_true(InputMap.has_action(action), "%s is in project.godot" % action)
		assert_true(Keys.ACTION_NAMES.has(action), "%s has a name in the Controls tab" % action)
	assert_false(Keys.REBINDABLE.has(&"pause"), "Esc can't be rebound (it opens the settings)")


func test_favourites() -> void:
	Config.favourites.clear()
	Config.add_favourite("A", "1.2.3.4:7777")
	Config.add_favourite("A again", "1.2.3.4:7777")
	assert_eq(Config.favourites.size(), 1, "no duplicate addresses")
	Config.rename_favourite(0, "  Renamed ")
	assert_eq(Config.favourites[0]["name"], "Renamed")
	Config.rename_favourite(0, "   ")
	assert_eq(Config.favourites[0]["name"], "Renamed", "a blank name is refused")
	Config.remove_favourite(0)
	assert_eq(Config.favourites.size(), 0)


func test_hints_are_remembered() -> void:
	Config.seen_hints.clear()
	assert_false(Config.hint_seen("lobby"))
	Config.mark_hint_seen("lobby")
	Config.mark_hint_seen("lobby")
	assert_true(Config.hint_seen("lobby"))
	assert_eq(Config.seen_hints.size(), 1)
	Config.reset_hints()
	assert_false(Config.hint_seen("lobby"))


func test_look_speed() -> void:
	Config.sensitivity_fp = 2.0
	Config.sensitivity_tp = 0.5
	assert_almost_eq(Config.look_speed(false), Config.BASE_SENSITIVITY * 2.0, 0.000001)
	assert_almost_eq(Config.look_speed(true), Config.BASE_SENSITIVITY * 0.5, 0.000001)


func test_outline_style_follows_the_setting() -> void:
	Config.outlines = Config.Outlines.PER_OBJECT
	assert_eq(Config.outline_style(), Config.Outlines.PER_OBJECT)
	Config.outlines = Config.Outlines.OFF
	assert_eq(Config.outline_style(), Config.Outlines.OFF)
	Config.outlines = Config.Outlines.FULL_SCREEN
	var expected := Config.Outlines.PER_OBJECT if Config.running_renderer() == "gl_compatibility" \
		else Config.Outlines.FULL_SCREEN
	assert_eq(Config.outline_style(), expected, "full screen needs Forward+")


func test_apply_environment_never_turns_on_what_the_level_has_off() -> void:
	var env := Environment.new()
	env.ssao_enabled = false
	env.glow_enabled = true
	Config.ssao = true
	Config.glow = false
	Config.apply_environment(env)
	assert_false(env.ssao_enabled, "the level had no SSAO")
	assert_false(env.glow_enabled, "the setting turned glow off")
	Config.glow = true
	Config.apply_environment(env)
	assert_true(env.glow_enabled, "and back on")
