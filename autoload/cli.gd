extends Node
## Parses user command-line args (the ones after `--`).
## `--key value` -> {"key": "value"}, `--flag` -> {"flag": true}, `--key=value` also works.

var args: Dictionary = {}


func _init() -> void:
	args = parse(OS.get_cmdline_user_args())


func parse(argv: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var i: int = 0
	while i < argv.size():
		var token: String = argv[i]
		i += 1
		if not token.begins_with("--") or token.length() <= 2:
			continue  # stray positional value: ignore
		var key: String = token.substr(2)
		var eq: int = key.find("=")
		if eq != -1:
			result[key.substr(0, eq)] = key.substr(eq + 1)
		elif i < argv.size() and not argv[i].begins_with("--"):
			result[key] = argv[i]
			i += 1
		else:
			result[key] = true
	return result


func has_arg(key: String) -> bool:
	return args.has(key)


func get_str(key: String, default: String = "") -> String:
	var value: Variant = args.get(key, default)
	if value is String:
		return value
	return default


func get_int(key: String, default: int = 0) -> int:
	var value: String = get_str(key)
	return value.to_int() if value.is_valid_int() else default
