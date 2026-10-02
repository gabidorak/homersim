extends Node
## User settings (`user://settings.cfg`, from M8) and server config loading.

const DEFAULT_MATCH_RULES := "res://data/match_rules.tres"
const SERVER_DEFAULTS := {
	"port": 7777,
	"max_players": 6,
	"name": "HomerSim server",
}

# User settings. Plain defaults for now; the settings menu and settings.cfg arrive in M8.
var mouse_sensitivity := 0.0025  ## radians per pixel
var fov := 80.0  ## degrees (vertical)
var head_bob := true
## Camera shake and hit-stop on BONK, knockdowns and debris (M7). M8 adds the settings toggle;
## until then `--no-shake` turns it off.
var camera_shake := true
## Repairs open a minigame (+50) instead of the 6 s hold (+35). The hold stays as an accessibility
## option: M8 adds the settings toggle; until then `--hold-repairs` turns minigames off.
var minigame_repairs := true


func _ready() -> void:
	if Cli.has_arg("hold-repairs"):
		minigame_repairs = false
	if Cli.has_arg("no-shake"):
		camera_shake = false


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
