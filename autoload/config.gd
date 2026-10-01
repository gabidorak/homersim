extends Node
## User settings (`user://settings.cfg`, from M8) and server config loading.

const SERVER_DEFAULTS := {
	"port": 7777,
	"max_players": 6,
	"name": "HomerSim server",
}


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
