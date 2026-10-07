class_name OnlineApi
extends RefCounted
## Online games: the little HTTP API between the game and the launcher on the VPS
## (server/launcher/launcher.gd), shared by both sides. Pure functions, unit tested
## (tests/unit/test_online.gd).
##
##   GET  /         -> 200 {"game": "homersim", "version": V}   (no key needed: a health check)
##   GET  /games    -> 200 {"version": V, "host": H, "games": [{id, name, players, max, state, locked,
##                     version, port}, …]}
##   POST /games    {"version", "name", "password", "max_players", "bots", "difficulty"}
##                  -> 200 {"host": H, "port": N, "version": V} once the new game's server listens
##   anything else  -> an HTTP error status with {"error": CODE} (the ERR_* below)
## /games needs "Authorization: Bearer <friends key>". H is the launcher's game_host setting; "" means
## "the host you reached me at", so the game joins H:N, or the online URL's host:N.
## On the VPS, Caddy serves this over HTTPS (docs/HOSTING.md); the launcher itself speaks plain HTTP.

## Where the game finds the launcher (`--online-url URL` overrides it for one run).
const DEFAULT_URL := "https://homersim.mooo.com"
const DEFAULT_PORT := 7790  ## the launcher's own (TCP) port, behind Caddy
const GAMES_PATH := "/games"
const MAX_HEADER_BYTES := 8192
const MAX_BODY_BYTES := 4096
const MAX_PASSWORD := 40  ## as Config's host_password

## {"error": …} codes. The client shows them with LeaveReason.Code.ONLINE.
const ERR_KEY := "key"  ## 401: no friends key, or the wrong one
const ERR_FULL := "full"  ## 503: the most games the VPS runs at once are running
const ERR_BUSY := "busy"  ## 429: too many games started in a short time
const ERR_START := "start"  ## 500: the game's server didn't start
const ERR_VERSION := "version"  ## 409: the new game runs another build than the player's (+ "version")
const ERR_BAD_REQUEST := "bad_request"  ## 400
const ERR_NOT_FOUND := "not_found"  ## 404
const ERR_UNREACHABLE := "unreachable"  ## client side only: no (usable) answer

const REASONS := {
	200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 408: "Request Timeout",
	409: "Conflict", 411: "Length Required", 413: "Payload Too Large", 429: "Too Many Requests",
	431: "Request Header Fields Too Large", 500: "Internal Server Error", 503: "Service Unavailable",
}


# --- Both sides ----------------------------------------------------------------

## The options of a new game as the launcher accepts them, whatever the request said: the same
## limits as the Host a game card (Config.clean_value of the host_* settings).
static func sanitize_options(raw: Dictionary) -> Dictionary:
	var game_name := ChatService.clean(str(raw.get("name", ""))).strip_edges().substr(0, LanDiscovery.MAX_NAME)
	var bots := _int(raw.get("bots"), 0)
	return {
		"name": game_name if game_name != "" else "Online game",
		"password": str(raw.get("password", "")).strip_edges().substr(0, MAX_PASSWORD),
		"max_players": clampi(_int(raw.get("max_players"), 6), 2, Config.HOST_MAX_PLAYERS),
		"bots": 0 if bots < 2 else mini(bots, Config.BOT_FILL_MAX),
		"difficulty": clampi(_int(raw.get("difficulty"), 1), 0, 2),
	}


## One game of the list, from a game server's status file (Session.public_info()), with every field
## of the right type. `port` is the game's UDP port (its id too).
static func game_entry(status: Dictionary, port: int) -> Dictionary:
	return {
		"id": port,
		"name": str(status.get("name", "?")).substr(0, LanDiscovery.MAX_NAME),
		"players": maxi(_int(status.get("players"), 0), 0),
		"max": maxi(_int(status.get("max"), 0), 0),
		"state": str(status.get("state", "lobby")),
		"locked": status.get("locked") is bool and status["locked"],
		"version": str(status.get("version", "")),
		"port": port,
	}


## The games of a GET /games answer (anything malformed left out).
static func parse_games(answer: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var games: Variant = answer.get("games", [])
	if not games is Array:
		return result
	for game: Variant in games:
		if game is Dictionary and _int(game.get("port"), 0) > 0:
			result.append(game_entry(game, _int(game["port"], 0)))
	return result


## The JSON object in `text`, or {} (quietly: JSON.parse_string logs an error for anything else).
static func parse_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return json.data


## An int from a JSON value (numbers arrive as floats), or `fallback`.
static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(value)
	return fallback


# --- Client side ---------------------------------------------------------------

## "https://homersim.mooo.com:8443/x" -> "homersim.mooo.com" ("" if there is none).
static func host_of(url: String) -> String:
	var rest := url.strip_edges()
	var scheme := rest.find("://")
	if scheme != -1:
		rest = rest.substr(scheme + 3)
	for cut in ["/", "?", "#"]:
		if rest.contains(cut):
			rest = rest.substr(0, rest.find(cut))
	if rest.begins_with("["):  # [IPv6]:port
		return rest.substr(1, rest.find("]") - 1) if rest.contains("]") else ""
	return rest.substr(0, rest.rfind(":")) if rest.contains(":") else rest


## The launcher's base URL without a trailing slash, with http:// added when no scheme was given.
static func base_url(url: String) -> String:
	var clean := url.strip_edges().trim_suffix("/")
	if clean != "" and not clean.contains("://"):
		clean = "http://" + clean
	return clean


## Where a created game is: the launcher's game_host, or else the host of the online URL.
static func game_address(answer: Dictionary, url: String) -> String:
	var host := str(answer.get("host", ""))
	return "%s:%d" % [host if host != "" else host_of(url), _int(answer.get("port"), 0)]


# --- Launcher side -------------------------------------------------------------

## Parses one HTTP/1.1 request from the bytes received so far:
##   {"done": false}                                    more bytes needed
##   {"error": STATUS}                                  give up and answer with that HTTP status
##   {"done": true, "method", "path", "headers", "body"}  headers have lower-case names; the path has
##                                                      no query string; the body is UTF-8 text
static func parse_request(bytes: PackedByteArray) -> Dictionary:
	var end := _header_end(bytes)
	if end == -1:
		return {"error": 431} if bytes.size() > MAX_HEADER_BYTES else {"done": false}
	if end > MAX_HEADER_BYTES:
		return {"error": 431}
	var lines := bytes.slice(0, end).get_string_from_ascii().split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/1.") or first[1] == "" or not first[1].begins_with("/"):
		return {"error": 400}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon <= 0:
			return {"error": 400}
		headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	if headers.has("transfer-encoding"):
		return {"error": 411}  # (no chunked bodies: Godot and Caddy send a Content-Length)
	var length := 0
	if headers.has("content-length"):
		var text: String = headers["content-length"]
		if not text.is_valid_int() or text.to_int() < 0:
			return {"error": 400}
		length = text.to_int()
	if length > MAX_BODY_BYTES:
		return {"error": 413}
	var body_start := end + 4
	if bytes.size() < body_start + length:
		return {"done": false}
	var path := first[1]
	if path.contains("?"):
		path = path.substr(0, path.find("?"))
	return {"done": true, "method": first[0], "path": path, "headers": headers,
		"body": bytes.slice(body_start, body_start + length).get_string_from_utf8()}


## Where the blank line after the headers starts, or -1.
static func _header_end(bytes: PackedByteArray) -> int:
	var at := bytes.find(13)
	while at != -1 and at + 3 < bytes.size():
		if bytes[at + 1] == 10 and bytes[at + 2] == 13 and bytes[at + 3] == 10:
			return at
		at = bytes.find(13, at + 1)
	return -1


## A whole HTTP response carrying `data` as JSON (the connection closes after it).
static func response(status: int, data: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(data).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" \
		% [status, REASONS.get(status, "Error"), body.size()]
	return head.to_utf8_buffer() + body


## The friends key of a request ("Authorization: Bearer KEY"), or "".
static func bearer_key(headers: Dictionary) -> String:
	var value := str(headers.get("authorization", ""))
	return value.substr(7).strip_edges() if value.to_lower().begins_with("bearer ") else ""


## True if `given` is `expected` (compared in constant time). An empty key never matches.
static func keys_match(given: String, expected: String) -> bool:
	if expected == "":
		return false
	var a := given.sha256_buffer()
	var b := expected.sha256_buffer()
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


## The ports of "7800-7809" (or "7800"), or [] if it isn't a usable range (at most 1000 ports).
static func parse_port_range(text: String) -> Array[int]:
	var result: Array[int] = []
	var parts := text.strip_edges().split("-")
	if parts.size() > 2 or not parts[0].strip_edges().is_valid_int() \
			or (parts.size() == 2 and not parts[1].strip_edges().is_valid_int()):
		return result
	var first := parts[0].strip_edges().to_int()
	var last := parts[-1].strip_edges().to_int()
	if first < 1024 or last > 65535 or last < first or last - first >= 1000:
		return result
	for port in range(first, last + 1):
		result.append(port)
	return result


## The next free port of `pool` after `after` (round robin, so a port just freed isn't handed out
## again at once while stray packets of its old game may still arrive), or 0 if all are taken.
static func next_port(pool: Array[int], used: Array, after: int) -> int:
	if pool.is_empty():
		return 0
	var start := pool.find(after) + 1  # (0 when `after` isn't in the pool)
	for i in pool.size():
		var port := pool[(start + i) % pool.size()]
		if not used.has(port):
			return port
	return 0
