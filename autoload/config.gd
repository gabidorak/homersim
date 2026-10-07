extends Node
## User settings and server config loading.
##
## User settings (M8) live in `user://settings.cfg` (`--settings PATH` picks another file): video,
## controls and key bindings, audio, gameplay, the server favourites, the first-time hints already
## shown, the last choices made for "Play solo" and "Host a game", and the friends key of the online
## server (client/online_client.gd). The settings screen calls set_value(), which applies the change
## at once, saves the file (a moment later, so dragging a slider doesn't write it 60 times a second)
## and emits `changed`.
## Headless processes (the dedicated server, test bots) never read or write the file: they run on
## the defaults, so a player's settings can't change what a test does.
##
## The renderer can only change at startup, so it goes to `user://override.cfg` instead: project.godot
## points `application/config/project_settings_override` at that file, which Godot reads before it
## opens the window.

signal changed(key: String)  ## a user setting changed (and was applied)

enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }
enum Shadows { LOW, MEDIUM, HIGH }
## Ink lines: drawn over the whole screen from the depth and normal buffers (Forward+ only), as a hull
## around each model (the original look), or not at all.
enum Outlines { FULL_SCREEN, PER_OBJECT, OFF }

const DEFAULT_MATCH_RULES := "res://data/match_rules.tres"
const SERVER_DEFAULTS := {
	"port": 7777,
	"max_players": 6,
	"name": "HomerSim server",
	"password": "",
}
const SETTINGS_PATH := "user://settings.cfg"
const OVERRIDE_PATH := "user://override.cfg"
const RENDERER_SETTING := "rendering/renderer/rendering_method"
const RENDERERS: Array[String] = ["forward_plus", "gl_compatibility"]
const LANGUAGES := {"": "Automatic", "en": "English", "fr": "Français"}
const BASE_SENSITIVITY := 0.0025  ## radians per pixel at sensitivity 1
const SAVE_DELAY_S := 0.4
const MAX_FAVOURITES := 50
const AUDIO_BUSES := {
	"volume_master": &"Master",
	"volume_music": &"Music",
	"volume_sfx": &"SFX",
	"volume_ui": &"UI",
	"volume_ambience": &"Ambience",
}
## Each setting and its section in settings.cfg. A setting's default is the value its var starts with.
const SECTIONS := {
	"window_mode": "video", "resolution": "video", "vsync": "video", "max_fps": "video",
	"render_scale": "video", "shadows": "video", "ssao": "video", "glow": "video", "outlines": "video",
	"sensitivity_fp": "controls", "sensitivity_tp": "controls", "invert_y": "controls", "fov": "controls",
	"head_bob": "controls", "camera_shake": "controls", "minigame_repairs": "controls",
	"volume_master": "audio", "volume_music": "audio", "volume_sfx": "audio", "volume_ui": "audio",
	"volume_ambience": "audio",
	"player_name": "gameplay", "chat_filter": "gameplay", "show_fps": "gameplay", "language": "gameplay",
	"show_minimap": "gameplay", "minimap_rotate": "gameplay",
	"last_address": "servers",
	"solo_role": "solo", "solo_difficulty": "solo", "solo_supervisors": "solo", "solo_rats": "solo",
	"host_name": "host", "host_password": "host", "host_port": "host", "host_max_players": "host",
	"host_supervisors": "host", "host_rats": "host", "host_bots": "host", "host_difficulty": "host",
	"host_lan": "host", "host_online": "host",
	"online_key": "online",
}
## Host a game: the choices for the most players (client/game_setup.gd).
const HOST_MAX_PLAYERS := 16

# --- Video ---------------------------------------------------------------------
var window_mode := WindowMode.WINDOWED
var resolution := Vector2i(1280, 720)  ## window size in windowed mode
var vsync := true
var max_fps := 0  ## 0 = no cap
var render_scale := 1.0  ## 3D resolution; below 1 it is upscaled with AMD FSR (Forward+ only)
var shadows := Shadows.HIGH
var ssao := true
var glow := true
var outlines := Outlines.PER_OBJECT  ## see outline_style()
## "forward_plus" or "gl_compatibility" (weak GPUs). Saved in override.cfg, used from the next start.
var renderer := "forward_plus"
# --- Controls ------------------------------------------------------------------
var sensitivity_fp := 1.0  ## mouse look, first person (supervisors, lobby, spectators)
var sensitivity_tp := 1.0  ## mouse look, third person (rats)
var invert_y := false
var fov := 80.0  ## degrees (vertical)
var head_bob := true
## Camera shake and hit-stop on BONK, knockdowns and debris (M7); `--no-shake` also turns it off.
var camera_shake := true
## Repairs open a minigame (+50) instead of the 6 s hold (+35). The hold stays as an accessibility
## option; `--hold-repairs` also turns minigames off.
var minigame_repairs := true
# --- Audio: 0..1, on top of each bus's mix level in default_bus_layout.tres ------
var volume_master := 1.0
var volume_music := 1.0
var volume_sfx := 1.0
var volume_ui := 1.0
var volume_ambience := 1.0
# --- Gameplay ------------------------------------------------------------------
var player_name := ""  ## "" until the player picked one (the menu asks at the first start)
var chat_filter := true  ## mask rude words in the chat (client/chat_filter.gd)
var show_fps := false  ## FPS and ping in the corner
var show_minimap := true  ## the minimap in the top right corner (the full map on M is always there)
var minimap_rotate := true  ## the minimap turns with the camera; false = north always up
var language := ""  ## a LANGUAGES key; "" follows the system
var last_address := ""  ## what was last typed in the server browser's address field
# --- Play solo and Host a game (the last choices, client/game_setup.gd) -----------
var solo_role := 0  ## the Role.Kind asked for: 0 any, 1 supervisor, 2 rat
var solo_difficulty := 1  ## bots: 0 easy, 1 normal, 2 hard
## The teams (you and the bots): 1 to MatchRules.SUPERVISORS_LIMIT / RATS_LIMIT.
var solo_supervisors := 2
var solo_rats := 4
var host_name := ""  ## the server's name; "" = "<player name>'s plant"
var host_password := ""  ## "" = anyone may join
var host_port: int = SERVER_DEFAULTS["port"]
var host_max_players := 6
## The teams' seats (MatchRules.max_supervisors / max_rats); without bots, the most of each team.
var host_supervisors := 2
var host_rats := 4
var host_bots := true  ## bots take the seats nobody fills
var host_difficulty := 1
var host_lan := true  ## announce the game on the local network (the server browser's LAN list)
var host_online := false  ## host on the online server (the VPS launcher) instead of this computer
# --- Online games ----------------------------------------------------------------
var online_key := ""  ## the friends key the online server asks for ("" = not typed yet)

## Server favourites: [{"name": String, "address": "host:port"}].
var favourites: Array[Dictionary] = []
## Ids of the first-time hints already shown (client/hints.gd).
var seen_hints: PackedStringArray = []
## Rebound actions: action -> Keys.encode() text ("" = unbound). Others keep project.godot's keys.
var bindings: Dictionary = {}

var _defaults := {}  # setting -> its starting value
var _default_events := {}  # action -> Array[InputEvent] from project.godot
var _bus_base_db := {}  # bus name -> its volume in the layout
var _path := ""  # the settings file; "" = settings are not saved (headless)
var _save_timer: Timer


func _ready() -> void:
	for key: String in SECTIONS:
		_defaults[key] = get(key)
	for action in Keys.REBINDABLE:
		_default_events[action] = InputMap.action_get_events(action) if InputMap.has_action(action) else []
	for key: String in AUDIO_BUSES:
		var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
		_bus_base_db[AUDIO_BUSES[key]] = AudioServer.get_bus_volume_db(bus) if bus >= 0 else 0.0
	renderer = str(ProjectSettings.get_setting(RENDERER_SETTING, "forward_plus"))
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(func() -> void: save_settings(_path))
	add_child(_save_timer)
	if is_persistent():
		_path = Cli.get_str("settings", SETTINGS_PATH)
		load_settings(_path)
	# Command-line switches win over the file, and are not saved.
	if Cli.has_arg("hold-repairs"):
		minigame_repairs = false
	if Cli.has_arg("no-shake"):
		camera_shake = false
	if DisplayServer.get_name() != "headless":
		apply_all()
		get_tree().node_added.connect(_on_node_added)
	else:
		# Headless processes (servers, test bots) show no text, and tests read their logs and prompts:
		# keep them in English whatever the machine's language.
		TranslationServer.set_locale("en")


## True for a windowed client: the only kind of process that reads and saves settings.cfg.
static func is_persistent() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server") \
		and not Cli.has_arg("server")


# --- Reading and changing settings ---------------------------------------------

## Changes one setting (a SECTIONS key): cleans the value, applies it, saves, emits `changed`.
func set_value(key: String, value: Variant) -> void:
	if not SECTIONS.has(key) and key != "renderer":
		push_warning("Config: unknown setting '%s'" % key)
		return
	set(key, clean_value(key, value))
	_apply(key)
	_save_soon()
	changed.emit(key)


func default_value(key: String) -> Variant:
	return _defaults.get(key)


## Puts every setting of `section` ("video", "controls", "audio", "gameplay") back to its default.
## The name stays (it isn't really a preference); "controls" also resets the key bindings.
func reset_section(section: String) -> void:
	for key: String in SECTIONS:
		if SECTIONS[key] == section and key != "player_name":
			set_value(key, _defaults[key])
	if section == "controls":
		reset_bindings()


## The value as the setting accepts it: right type, clamped to its range. Anything unusable gives the
## default.
func clean_value(key: String, value: Variant) -> Variant:
	var fallback: Variant = _defaults.get(key, get(key))
	if key == "renderer":
		return value if value in RENDERERS else "forward_plus"
	if typeof(fallback) == TYPE_FLOAT and typeof(value) == TYPE_INT:
		value = float(value)
	elif typeof(fallback) == TYPE_INT and typeof(value) == TYPE_FLOAT:
		value = int(value)
	elif typeof(fallback) == TYPE_VECTOR2I and typeof(value) == TYPE_VECTOR2:
		value = Vector2i(value)
	if typeof(value) != typeof(fallback):
		return fallback
	match key:
		"window_mode":
			return clampi(value, 0, WindowMode.size() - 1)
		"shadows":
			return clampi(value, 0, Shadows.size() - 1)
		"outlines":
			return clampi(value, 0, Outlines.size() - 1)
		"resolution":
			return Vector2i(clampi(value.x, 640, 7680), clampi(value.y, 360, 4320))
		"max_fps":
			return clampi(value, 0, 1000)
		"render_scale":
			return clampf(value, 0.5, 1.0)
		"sensitivity_fp", "sensitivity_tp":
			return clampf(value, 0.1, 5.0)
		"fov":
			return clampf(value, 60.0, 110.0)
		"player_name":
			var name_text: String = value
			return JoinRules.sanitize_name(name_text) if not name_text.strip_edges().is_empty() else ""
		"language":
			return value if LANGUAGES.has(value) else ""
		"last_address":
			return str(value).strip_edges().substr(0, 120)
		"solo_role":
			return clampi(value, Role.Kind.NONE, Role.Kind.RAT)
		"solo_difficulty", "host_difficulty":
			return clampi(value, 0, 2)
		"solo_supervisors", "host_supervisors":
			return clampi(value, 1, MatchRules.SUPERVISORS_LIMIT)
		"solo_rats", "host_rats":
			return clampi(value, 1, MatchRules.RATS_LIMIT)
		"host_name":
			return str(value).strip_edges().substr(0, LanDiscovery.MAX_NAME)
		"host_password":
			return str(value).strip_edges().substr(0, 40)
		"host_port":
			return clampi(value, 1024, 65535)
		"host_max_players":
			return clampi(value, 2, HOST_MAX_PLAYERS)
		"online_key":
			return str(value).strip_edges().substr(0, 200)
	if key.begins_with("volume_"):
		return clampf(value, 0.0, 1.0)
	return value


## Mouse look speed in radians per pixel.
func look_speed(third_person: bool) -> float:
	return BASE_SENSITIVITY * (sensitivity_tp if third_person else sensitivity_fp)


## The language actually in use ("en", "fr"…).
func current_language() -> String:
	return TranslationServer.get_locale().substr(0, 2)


# --- Key bindings --------------------------------------------------------------

## What `action` is bound to, as Keys.encode() text ("" = unbound).
func binding_of(action: StringName) -> String:
	if bindings.has(action):
		return bindings[action]
	var events: Array = _default_events.get(action, [])
	return Keys.encode(events[0]) if not events.is_empty() else ""


## Every rebindable action's binding (action -> encoded event), for Keys.conflicts().
func all_bindings() -> Dictionary:
	var result := {}
	for action in Keys.REBINDABLE:
		result[action] = binding_of(action)
	return result


## Binds `action` to `event` alone (null = unbound).
func set_binding(action: StringName, event: InputEvent) -> void:
	if not Keys.REBINDABLE.has(action):
		return
	var encoded := Keys.encode(event) if event != null else ""
	var events: Array = _default_events.get(action, [])
	if events.size() == 1 and Keys.encode(events[0]) == encoded:
		bindings.erase(action)  # back to the default: nothing to store
	else:
		bindings[action] = encoded
	_apply_binding(action)
	_save_soon()
	changed.emit("bindings")


func reset_bindings() -> void:
	bindings.clear()
	for action in Keys.REBINDABLE:
		_apply_binding(action)
	_save_soon()
	changed.emit("bindings")


func _apply_binding(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	if bindings.has(action):
		var event := Keys.decode(bindings[action])
		if event != null:
			InputMap.action_add_event(action, event)
	else:
		for event: InputEvent in _default_events.get(action, []):
			InputMap.action_add_event(action, event)


# --- Favourites and hints ------------------------------------------------------

func add_favourite(fav_name: String, address: String) -> void:
	for fav in favourites:
		if fav["address"] == address:
			return  # already there
	if favourites.size() >= MAX_FAVOURITES:
		return
	favourites.append({"name": fav_name.strip_edges().substr(0, 40), "address": address})
	_save_soon()
	changed.emit("favourites")


func remove_favourite(index: int) -> void:
	if index >= 0 and index < favourites.size():
		favourites.remove_at(index)
		_save_soon()
		changed.emit("favourites")


func rename_favourite(index: int, new_name: String) -> void:
	if index >= 0 and index < favourites.size() and not new_name.strip_edges().is_empty():
		favourites[index]["name"] = new_name.strip_edges().substr(0, 40)
		_save_soon()
		changed.emit("favourites")


func hint_seen(id: String) -> bool:
	return seen_hints.has(id)


func mark_hint_seen(id: String) -> void:
	if not seen_hints.has(id):
		seen_hints.append(id)
		_save_soon()


func reset_hints() -> void:
	seen_hints.clear()
	_save_soon()
	changed.emit("seen_hints")


# --- The settings file ---------------------------------------------------------

## Reads `path` over the current values (missing keys keep theirs). Returns false if there was no
## readable file.
func load_settings(path: String) -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			Log.warn("config", "cannot read %s (%s), using the defaults" % [path, error_string(err)])
		return false
	for key: String in SECTIONS:
		if cfg.has_section_key(SECTIONS[key], key):
			set(key, clean_value(key, cfg.get_value(SECTIONS[key], key)))
	bindings.clear()
	if cfg.has_section("keybinds"):
		for key in cfg.get_section_keys("keybinds"):
			var action := StringName(key)
			var text := str(cfg.get_value("keybinds", key, ""))
			if Keys.REBINDABLE.has(action) and (text == "" or Keys.decode(text) != null):
				bindings[action] = text
	favourites.clear()
	for fav: Variant in cfg.get_value("servers", "favourites", []):
		if fav is Dictionary and fav.has("address") and Net.parse_address(str(fav["address"])) != {}:
			favourites.append({"name": str(fav.get("name", fav["address"])), "address": str(fav["address"])})
	seen_hints = PackedStringArray(cfg.get_value("hints", "seen", PackedStringArray()))
	return true


func save_settings(path: String) -> Error:
	if path.is_empty():
		return OK
	var cfg := ConfigFile.new()
	for key: String in SECTIONS:
		cfg.set_value(SECTIONS[key], key, get(key))
	for action: StringName in bindings:
		cfg.set_value("keybinds", String(action), bindings[action])
	cfg.set_value("servers", "favourites", favourites)
	cfg.set_value("hints", "seen", seen_hints)
	var err := cfg.save(path)
	if err != OK:
		Log.warn("config", "cannot save %s: %s" % [path, error_string(err)])
	return err


func _save_soon() -> void:
	if not _path.is_empty() and is_inside_tree():
		_save_timer.start(SAVE_DELAY_S)


func _exit_tree() -> void:
	if not _save_timer.is_stopped():
		save_settings(_path)  # quitting with a save still pending


# --- Applying settings ---------------------------------------------------------

func apply_all() -> void:
	for key: String in ["window_mode", "vsync", "max_fps", "render_scale", "shadows", "ssao", "outlines", "language"]:
		_apply(key)
	for key: String in AUDIO_BUSES:
		_apply(key)
	for action in Keys.REBINDABLE:
		_apply_binding(action)


func _apply(key: String) -> void:
	if AUDIO_BUSES.has(key):
		var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
		if bus >= 0:
			var volume: float = get(key)
			AudioServer.set_bus_volume_db(bus, _bus_base_db[AUDIO_BUSES[key]] + linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(bus, volume <= 0.001)
		return
	if key == "language":
		TranslationServer.set_locale(language if language != "" else OS.get_locale_language())
		return
	if key == "renderer":
		_write_renderer_override()
		return
	if DisplayServer.get_name() == "headless":
		return
	var root := get_tree().root
	match key:
		"window_mode", "resolution":
			_apply_window()
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = max_fps
		"render_scale":
			# FSR needs Forward+; the Compatibility renderer only scales bilinearly.
			var fsr := render_scale < 0.99 and RenderingServer.get_current_rendering_method() != "gl_compatibility"
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = render_scale
		"shadows":
			var size: int = [1024, 2048, 4096][shadows]
			var quality: int = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][shadows]
			RenderingServer.directional_shadow_atlas_set_size(size, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(quality)
			RenderingServer.positional_soft_shadow_filter_set_quality(quality)
			root.positional_shadow_atlas_size = size
		"outlines":
			RenderingServer.global_shader_parameter_set(&"outline_hull_enabled",
				outline_style() == Outlines.PER_OBJECT)  # ScreenInk nodes follow `changed` themselves
		"ssao", "glow":
			var world := root.find_world_3d()
			if world != null and world.environment != null:
				apply_environment(world.environment)


## Turns the environment's SSAO and glow off when the settings say so (never on when the level
## didn't use them). Levels and the menu background call it once their WorldEnvironment is in.
func apply_environment(env: Environment) -> void:
	if env == null:
		return
	if not env.has_meta(&"level_ssao"):
		env.set_meta(&"level_ssao", env.ssao_enabled)
		env.set_meta(&"level_glow", env.glow_enabled)
	env.ssao_enabled = ssao and env.get_meta(&"level_ssao")
	env.glow_enabled = glow and env.get_meta(&"level_glow")


## The ink lines actually drawn: the full-screen ones need Forward+'s normal buffer, so the
## Compatibility renderer falls back to the per-object hull.
func outline_style() -> Outlines:
	if outlines == Outlines.FULL_SCREEN and running_renderer() == "gl_compatibility":
		return Outlines.PER_OBJECT
	return outlines


## Every 3D world (levels, the menu background, the art gallery…) gets the full-screen ink
## lines next to its WorldEnvironment.
func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		(func() -> void:
			if is_instance_valid(node) and node.get_node_or_null(^"ScreenInk") == null:
				node.add_child(ScreenInk.new())).call_deferred()


func _apply_window() -> void:
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var size := Vector2i(mini(resolution.x, usable.size.x), mini(resolution.y, usable.size.y))
			if DisplayServer.window_get_size() != size:  # (several clients started side by side keep their spots)
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


## Window sizes worth offering: common 16:9 sizes that fit the screen, plus the current setting.
func resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
			Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]:
		if size.x <= screen.x and size.y <= screen.y:
			result.append(size)
	if not result.has(resolution):
		result.append(resolution)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return result


## The renderer this process runs with (the setting only takes effect at the next start).
func running_renderer() -> String:
	return RenderingServer.get_current_rendering_method()


func _write_renderer_override() -> void:
	if not is_persistent():
		return
	var cfg := ConfigFile.new()
	cfg.load(OVERRIDE_PATH)  # keep anything else a player put there
	cfg.set_value("rendering", "renderer/rendering_method", renderer)
	var err := cfg.save(OVERRIDE_PATH)
	if err != OK:
		Log.warn("config", "cannot write %s: %s" % [OVERRIDE_PATH, error_string(err)])
	else:
		Log.info("config", "renderer %s from the next start" % renderer)


# --- Server config -------------------------------------------------------------

## Reads the [server] section of a server.cfg (INI). Missing file or keys fall back to SERVER_DEFAULTS.
func load_server_config(path: String) -> Dictionary:
	var result: Dictionary = SERVER_DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err == ERR_FILE_NOT_FOUND:
		Log.info("config", "no config at %s, using defaults" % path)
		return result
	if err != OK:
		Log.warn("config", "cannot read %s (%s), using defaults" % [path, error_string(err)])
		return result
	for key: String in result:
		result[key] = cfg.get_value("server", key, result[key])
	Log.info("config", "loaded %s" % path)
	return result


## The match rules for this server: the resource named by [match] rules= (default
## data/match_rules.tres), with any other [match] key overriding the property of the same name.
## Returns a copy, so overrides never touch the shared resource.
func load_match_rules(path: String) -> MatchRules:
	var cfg := ConfigFile.new()
	var has_cfg := cfg.load(path) == OK
	var rules_path: String = cfg.get_value("match", "rules", DEFAULT_MATCH_RULES) if has_cfg else DEFAULT_MATCH_RULES
	var base := load(rules_path) as MatchRules if ResourceLoader.exists(rules_path) else null
	if base == null:
		Log.warn("config", "no MatchRules at %s, using %s" % [rules_path, DEFAULT_MATCH_RULES])
		base = load(DEFAULT_MATCH_RULES)
	var rules: MatchRules = base.duplicate()
	if has_cfg and cfg.has_section("match"):
		for key: String in cfg.get_section_keys("match"):
			if key == "rules":
				continue
			if key in rules:
				rules.set(key, cfg.get_value("match", key))
				Log.info("config", "match rule %s = %s" % [key, rules.get(key)])
			else:
				Log.warn("config", "unknown [match] key '%s' in %s" % [key, path])
	return rules
