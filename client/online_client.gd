class_name OnlineClient
extends Node
## Client side of online games: asks the launcher on the VPS (server/launcher/launcher.gd, API in
## common/online_api.gd) for its games (the server browser's Online tab) or to start one (Host a
## game > Online server). One request at a time; freeing the node drops a request under way.
## The launcher's address is OnlineApi.DEFAULT_URL (`--online-url URL` for one run: tests, a local
## Docker), the friends key Config.online_key (`--online-key K` for one run).

signal listed(games: Array[Dictionary])  ## list(): the games that are up
signal created(address: String)  ## create(): the game listens at "host:port"
signal failed(code: LeaveReason.Code, detail: String)  ## ONLINE (detail: OnlineApi.ERR_*) or VERSION

const LIST_TIMEOUT_S := 10.0
const CREATE_TIMEOUT_S := 180.0  ## the launcher may download a new build before it starts the game

var launcher_host := ""  ## the last list's "host": where its games are ("" = the launcher's own host)

var _http: HTTPRequest
var _busy := false
var _last_problem := ""  # logged once, not at every refresh of the list


static func url() -> String:
	return OnlineApi.base_url(Cli.get_str("online-url", OnlineApi.DEFAULT_URL))


static func key() -> String:
	return Cli.get_str("online-key") if Cli.has_arg("online-key") else Config.online_key


## The online server's name as players see it: homersim.mooo.com.
static func host_label() -> String:
	return OnlineApi.host_of(url())


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)


func is_busy() -> bool:
	return _busy


## Asks for the games: emits listed or failed. Does nothing while a request is under way.
func list() -> void:
	_send(HTTPClient.METHOD_GET, "", LIST_TIMEOUT_S, func(answer: Dictionary) -> void:
		launcher_host = str(answer.get("host", ""))
		listed.emit(OnlineApi.parse_games(answer)))


## Asks for a new game with `options` (LocalServer.host_options(): name, password, max_players, bots,
## difficulty): emits created once it listens, or failed.
func create(options: Dictionary) -> void:
	var body := {"version": Session.game_version()}
	for field: String in ["name", "password", "max_players", "bots", "difficulty"]:
		body[field] = options.get(field)
	_send(HTTPClient.METHOD_POST, JSON.stringify(body), CREATE_TIMEOUT_S, func(answer: Dictionary) -> void:
		created.emit(OnlineApi.game_address(answer, url())))


func _send(method: HTTPClient.Method, body: String, timeout_s: float, on_ok: Callable) -> void:
	if _busy:
		return
	if key() == "":
		failed.emit.call_deferred(LeaveReason.Code.ONLINE, OnlineApi.ERR_KEY)
		return
	_busy = true
	_http.timeout = timeout_s
	var headers := PackedStringArray(["Authorization: Bearer " + key(), "Content-Type: application/json"])
	var err := _http.request(url() + OnlineApi.GAMES_PATH, headers, method, body)
	if err != OK:
		_busy = false
		Log.warn("online", "cannot ask %s: %s" % [url(), error_string(err)])
		failed.emit.call_deferred(LeaveReason.Code.ONLINE, "%s|%s" % [OnlineApi.ERR_UNREACHABLE, host_label()])
		return
	var got: Array = await _http.request_completed
	_busy = false
	var result: int = got[0]
	var status: int = got[1]
	var answer := OnlineApi.parse_object((got[3] as PackedByteArray).get_string_from_utf8())
	if result == HTTPRequest.RESULT_SUCCESS and status == 200:
		_last_problem = ""
		on_ok.call(answer)
		return
	var code := str(answer.get("error", ""))
	if result != HTTPRequest.RESULT_SUCCESS or code == "":
		_log_problem("no answer from %s (HTTPRequest result %d, HTTP %d)" % [url(), result, status])
		failed.emit(LeaveReason.Code.ONLINE, "%s|%s" % [OnlineApi.ERR_UNREACHABLE, host_label()])
	elif code == OnlineApi.ERR_VERSION:
		_log_problem("%s started a game on build %s, ours is %s" % [url(), answer.get("version", "?"), Session.game_version()])
		failed.emit(LeaveReason.Code.VERSION, "%s|%s" % [answer.get("version", "?"), Session.game_version()])
	else:
		_log_problem("%s refused: %s (HTTP %d)" % [url(), code, status])
		failed.emit(LeaveReason.Code.ONLINE, code)


func _log_problem(text: String) -> void:
	if text != _last_problem:
		_last_problem = text
		Log.info("online", text)
