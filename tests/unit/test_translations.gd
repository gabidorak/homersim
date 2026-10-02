extends GutTest
## Localization (M8): every user-facing string must be in translations/strings.csv, with a French
## translation. The keys are the English texts themselves (tr("Ready?")), so a missing key still
## shows English: this test is what catches it. Collected here:
##   - tr("…") and TranslationServer.translate("…") literals in every .gd file
##   - text / placeholder_text / tooltip_text in .tscn files (nodes that auto-translate)
##   - strings the code translates indirectly: feed lines, key and action names, statuses, roles,
##     awards, settings options, data names (subsystems, abilities, cameras), server messages…
## When this fails, add the listed lines to the CSV (keys,en,fr).

const CSV := "res://translations/strings.csv"
const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://tests", "res://tools"]


static func load_csv() -> Dictionary:
	var rows := {}  # key -> {"en": String, "fr": String}
	var file := FileAccess.open(CSV, FileAccess.READ)
	if file == null:
		return rows
	var header := file.get_csv_line()
	var en := header.find("en")
	var fr := header.find("fr")
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 2 or line[0] == "":
			continue
		rows[line[0]] = {"en": line[en] if en >= 0 and en < line.size() else "",
			"fr": line[fr] if fr >= 0 and fr < line.size() else ""}
	return rows


## key -> where it was found.
static func collect_keys() -> Dictionary:
	var keys := {}
	var tr_literal := RegEx.create_from_string("(?:\\btr|TranslationServer\\.translate)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var scene_text := RegEx.create_from_string("^(?:text|placeholder_text|tooltip_text) = \"((?:[^\"\\\\]|\\\\.)*)\"")
	for path in _files("res://", [".gd", ".tscn"]):
		var source := FileAccess.get_file_as_string(path)
		if path.ends_with(".gd"):
			for m in tr_literal.search_all(source):
				_add(keys, _unescape(m.get_string(1)), path)
		else:
			_scene_texts(source, scene_text, keys, path)
	_indirect(keys)
	return keys


static func _scene_texts(source: String, pattern: RegEx, keys: Dictionary, path: String) -> void:
	# Per node: skip nodes with auto_translate_mode = 2 (disabled), they show runtime text.
	for block in source.split("\n[node "):
		if block.contains("auto_translate_mode = 2"):
			continue
		for line in block.split("\n"):
			var m := pattern.search(line)
			if m != null:
				var text := _unescape(m.get_string(1))
				# (lowercase identifiers like "pumps" are placeholders a script replaces)
				if text.strip_edges() != "" and RegEx.create_from_string("[A-Za-z]{2}").search(text) != null \
						and RegEx.create_from_string("^[a-z_]+$").search(text) == null:
					_add(keys, text, path)


static func _indirect(keys: Dictionary) -> void:
	for text in EventFeed.LINES.values():
		_add(keys, text, "EventFeed.LINES")
	for action in Keys.REBINDABLE:
		_add(keys, Keys.ACTION_NAMES[action], "Keys.ACTION_NAMES")
	for text in Keys.MOUSE_NAMES.values():
		_add(keys, text, "Keys.MOUSE_NAMES")
	# Key names longer than one character (Space, Shift, Escape…) are words to translate.
	for action in Keys.REBINDABLE + [&"pause"]:
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				var text := OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
				if text.length() > 1 and not (key.physical_keycode >= KEY_0 and key.physical_keycode <= KEY_9):
					_add(keys, text, "key names")
	for entry: Array in StatusComponent.describe(0xFFFFFF):
		_add(keys, entry[0], "StatusComponent.describe")
	for kind: int in Role.Kind.values():
		_add(keys, Role.display_name(kind), "Role")
	_add(keys, Role.pref_name(Role.Kind.NONE), "Role")
	for award: Array in Awards.LIST:
		_add(keys, award[2], "Awards.LIST")
		_add(keys, award[3], "Awards.LIST")
	_add(keys, Config.LANGUAGES[""], "Config.LANGUAGES")
	_add(keys, "keycard", "stolen item")
	for path in ["res://client/settings.gd", "res://client/scoreboard.gd", "res://client/post_match.gd",
			"res://client/server_browser.gd", "res://client/minigame_host.gd"]:
		var constants := (load(path) as GDScript).get_script_constant_map()
		for name: String in ["TAB_TITLES", "STAT_TITLES", "STATE_TEXT", "TITLES"]:
			if constants.has(name):
				for text in (constants[name] as Dictionary).values():
					_add(keys, text, "%s %s" % [path.get_file(), name])
		for name: String in ["RENDER_SCALES", "VOLUMES", "SUPERVISOR_COLUMNS", "RAT_COLUMNS"]:
			if constants.has(name):
				for pair: Array in constants[name]:
					_add(keys, pair[1], "%s %s" % [path.get_file(), name])
	for look: Array in Pickup.LOOKS.values():
		if look[3] != "":
			_add(keys, look[3], "Pickup.LOOKS")
	# Data shown to players.
	for path in _files("res://data", [".tres"]):
		var res := load(path)
		for prop in ["display_name", "short_name"]:
			if res != null and prop in res and str(res.get(prop)) != "":
				_add(keys, str(res.get(prop)), path)
	# English strings the server sends for each client to translate, and other returned literals.
	var patterns := {
		"res://common/chat_service.gd": ["\"error\": \"([^\"]+)\"", "tell\\(peer, \"([^\"]+)\""],
		"res://common/session.gd": ["broadcast_system\\(\"([^\"]+)\""],
		"res://common/item_service.gd": ["tell\\([^,]+, \"([^\"]+)\""],
		"res://common/match_rules_model.gd": ["\"reason\": \"([^\"]+)\""],
		"res://interactables/console_action/console_action.gd": ["on_used\\.rpc\\(\"([^\"]+)\""],
		"res://interactables/interactable.gd": ["var prompt := \"([^\"]+)\""],
	}
	for path in _files("res://hazards", [".gd"]):
		patterns[path] = ["func hit_text\\(\\) -> String:\\s*return \"([^\"]+)\""]
	for path in _files("res://interactables", [".gd"]):
		if not patterns.has(path):
			patterns[path] = []
		patterns[path].append("^\\s*prompt = \"([^\"]+)\"")
	for path: String in patterns:
		var source := FileAccess.get_file_as_string(path)
		for pattern: String in patterns[path]:
			var regex := RegEx.new()
			regex.compile("(?m)" + pattern)
			for m in regex.search_all(source):
				if m.get_string(1) != "not allowed":  # (a refusal no real client can trigger)
					_add(keys, m.get_string(1), path)
	for path in _files("res://levels/plant/pois", [".tscn"]):
		var regex := RegEx.create_from_string("(?m)^label = \"([^\"]+)\"")
		for m in regex.search_all(FileAccess.get_file_as_string(path)):
			_add(keys, m.get_string(1), path)


static func _add(keys: Dictionary, text: String, where: String) -> void:
	if text != "" and not keys.has(text):
		keys[text] = where


static func _unescape(text: String) -> String:
	return text.c_unescape()


static func _files(dir: String, extensions: Array) -> Array[String]:
	var out: Array[String] = []
	for skip in SKIP_DIRS:
		if dir.begins_with(skip):
			return out
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for file in da.get_files():
		for ext: String in extensions:
			if file.ends_with(ext):
				out.append(dir.path_join(file))
	for sub in da.get_directories():
		out.append_array(_files(dir.path_join(sub), extensions))
	return out


func test_csv_exists_and_has_the_languages() -> void:
	var file := FileAccess.open(CSV, FileAccess.READ)
	assert_not_null(file, "translations/strings.csv exists")
	if file != null:
		var header := file.get_csv_line()
		assert_eq(Array(header).slice(0, 3), ["keys", "en", "fr"])


func test_every_string_is_in_the_csv() -> void:
	var rows := load_csv()
	var missing: Array[String] = []
	var keys := collect_keys()
	for key: String in keys:
		if not rows.has(key):
			missing.append("%s   <- %s" % [key.c_escape(), keys[key]])
	assert_eq(missing.size(), 0, "strings missing from %s:\n%s" % [CSV, "\n".join(missing)])
	gut.p("%d strings checked" % keys.size())


func test_every_key_has_both_languages() -> void:
	var incomplete: Array[String] = []
	var rows := load_csv()
	for key: String in rows:
		if rows[key]["en"] == "" or rows[key]["fr"] == "":
			incomplete.append(key)
	assert_eq(incomplete.size(), 0, "rows without en or fr: %s" % [incomplete])


func test_format_strings_keep_their_placeholders() -> void:
	# A French line with a different %s / %d count would break `tr(key) % args` at runtime.
	var bad: Array[String] = []
	var spec := RegEx.create_from_string("%[-0-9.]*[sdif%]")
	var rows := load_csv()
	for key: String in rows:
		var want := []
		for m in spec.search_all(key):
			want.append(m.get_string().right(1))
		for lang in ["en", "fr"]:
			var got := []
			for m in spec.search_all(rows[key][lang]):
				got.append(m.get_string().right(1))
			if got != want:
				bad.append("%s [%s]: %s" % [key, lang, rows[key][lang]])
	assert_eq(bad.size(), 0, "placeholders differ:\n%s" % "\n".join(bad))


func test_french_is_loaded() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	assert_eq(TranslationServer.translate("Settings"), "Paramètres")
	assert_eq(TranslationServer.translate("Server full"), "Serveur plein")
	TranslationServer.set_locale(before)
