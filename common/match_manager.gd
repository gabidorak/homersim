class_name MatchManager
extends Node
## The match state machine. The logic runs on the server; clients only read the replicated
## state (MatchSync: state, countdown_left, time_left, min_players, roster, result) and send
## lobby requests.
##
##   LOBBY ──ready vote / --debug-start──▶ ROLE_ASSIGN ─▶ COUNTDOWN ─▶ PLAYING ─▶ POST_MATCH ─▶ LOBBY
##     ▲                                                     │
##     └──────────────── too few players left ◀──────────────┘
##
## PLAYING ends with a winner (MatchRulesModel.check_winner): meltdown, rats all caught or gone,
## supervisors all gone, or the timer. POST_MATCH shows the result for post_match_s, then everyone
## goes back to the lobby with the roster kept. Players who join after the lobby spectate until
## the next match.
##
## Test-only server flags (debug builds): --test-duration S (match length), --result-file PATH
## (JSON summary written when the match ends), --exit-after-match (quit right after that).

enum State { LOBBY, ROLE_ASSIGN, COUNTDOWN, PLAYING, POST_MATCH }

## --exit-after-match: how long the server stays up in POST_MATCH before quitting.
const EXIT_DELAY_S := 1.5

signal state_changed(state: State)
signal roster_changed

# --- Replicated by MatchSync (server → clients, when they change) ---------------
# Always assign a modified copy (see _update_entry), never edit `roster` in place: the
# synchronizer compares against what it last sent, and an in-place edit can go unnoticed.
var state := State.LOBBY:
	set(value):
		if value != state:
			state = value
			Log.info("match", "state: %s" % State.keys()[state])
			_state_path.append(State.keys()[state])
			state_changed.emit(state)
			Events.match_state_changed.emit(state)
var countdown_left := 0  ## whole seconds left in COUNTDOWN or POST_MATCH
var time_left := 0  ## whole seconds left in PLAYING
var min_players := 3  ## copied from the rules so the lobby UI can show it
## peer id -> {"name": String, "pref": Role.Kind, "ready": bool, "role": Role.Kind}
var roster: Dictionary = {}:
	set(value):
		roster = value
		roster_changed.emit()
## The last match's outcome, set when POST_MATCH starts:
## {"winner": MatchRulesModel.Team, "reason": String, "stats": Array of
##  {"name", "role", "sabotages", "repairs"}}
var result: Dictionary = {}

# --- Server only ----------------------------------------------------------------
var rules: MatchRules
var _rng := RandomNumberGenerator.new()
var _countdown_end_ms := 0
var _match_end_ms := 0
var _post_end_ms := 0
var _debug_start_at := 0  # --debug-start [N]: start without a vote once N players joined; 0 = vote
var _spawn_counters: Dictionary[int, int] = {}  # role -> next spawn point index
var _team_started: Dictionary[int, int] = {}  # role -> players of that role when PLAYING began
var _stats: Dictionary[int, Dictionary] = {}  # peer -> {"name", "role", "sabotages", "repairs"}
var _state_path: Array[String] = []  # every state entered, for the test result file
var _events: Array[String] = []  # plant events this match, for the test result file

@onready var session: Session = get_parent()


func _ready() -> void:
	if not Net.is_server:
		set_process(false)
		return
	rules = session.match_rules if session.match_rules != null else load(Config.DEFAULT_MATCH_RULES)
	min_players = rules.min_players
	_rng.randomize()
	if Cli.has_arg("debug-start"):
		_debug_start_at = maxi(Cli.get_int("debug-start", 1), 1)
		Log.info("match", "--debug-start: the match starts once %d player(s) joined" % _debug_start_at)
	session.player_added.connect(_on_player_added)
	session.player_removed.connect(_on_player_removed)
	session.plant.subsystem_changed.connect(_on_subsystem_changed)


func entry(peer_id: int) -> Dictionary:
	return roster.get(peer_id, {})


## Client: our role in the current match (NONE in the lobby).
func local_role() -> Role.Kind:
	return entry(session.local_peer_id).get("role", Role.Kind.NONE)


func ready_count() -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if e["ready"]:
			count += 1
	return count


# --- Client → server requests ------------------------------------------------------

@rpc("any_peer", "reliable")
func request_set_pref(pref: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if state != State.LOBBY or not roster.has(peer) \
			or pref not in [Role.Kind.NONE, Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		return
	_update_entry(peer, "pref", pref)


@rpc("any_peer", "reliable")
func request_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if state != State.LOBBY or not roster.has(peer):
		return
	_update_entry(peer, "ready", is_ready)
	_check_start()


# --- Server ------------------------------------------------------------------------

func _on_player_added(peer_id: int) -> void:
	var late := state != State.LOBBY
	var copy := roster.duplicate(true)
	copy[peer_id] = {
		"name": session.players[peer_id].name,
		"pref": Role.Kind.NONE,
		"ready": false,
		"role": Role.Kind.SPECTATOR if late else Role.Kind.NONE,
	}
	roster = copy
	if late:
		Log.info("match", "%s joined mid-match: spectating until the next one" % roster[peer_id]["name"])
		return
	_spawn(peer_id, Role.Kind.NONE, false)
	_check_start()


func _on_player_removed(peer_id: int) -> void:
	var copy := roster.duplicate(true)
	copy.erase(peer_id)
	roster = copy
	match state:
		State.LOBBY:
			_check_start()
		State.ROLE_ASSIGN, State.COUNTDOWN:
			if _player_count_in_match() < _min_to_continue():
				Log.info("match", "too few players left, back to the lobby")
				_back_to_lobby()
		# PLAYING: an emptied team loses, checked every frame in _process.


func _check_start() -> void:
	if state != State.LOBBY or roster.is_empty():
		return
	if _debug_start_at > 0:
		if roster.size() >= _debug_start_at:
			_start_match()
	elif MatchRulesModel.ready_vote_passes(roster.size(), ready_count(), rules):
		_start_match()


func _start_match() -> void:
	state = State.ROLE_ASSIGN
	var prefs: Dictionary[int, Role.Kind] = {}
	for peer: int in roster:
		prefs[peer] = roster[peer]["pref"]
	var roles := MatchRulesModel.assign_roles(prefs, rules, _rng)
	var copy := roster.duplicate(true)
	var summary: Array[String] = []
	for peer: int in roles:
		copy[peer]["role"] = roles[peer]
		copy[peer]["ready"] = false
		summary.append("%s=%s" % [copy[peer]["name"], Role.display_name(roles[peer])])
	roster = copy
	Log.info("match", "roles: %s" % ", ".join(summary))

	# Lobby bodies out; role bodies in, frozen (LOCKED) until the countdown ends.
	for peer: int in roster:
		session.despawn_body(peer)
	_spawn_counters.clear()
	for peer: int in roles:
		if roles[peer] != Role.Kind.SPECTATOR:
			_spawn(peer, roles[peer], true)
	session.plant.reset()
	countdown_left = rules.countdown_s
	_countdown_end_ms = Time.get_ticks_msec() + rules.countdown_s * 1000
	state = State.COUNTDOWN


func _begin_playing() -> void:
	for node in session.players_root.get_children():
		(node as Player).status.clear(StatusComponent.Status.LOCKED)
	_team_started = {Role.Kind.SUPERVISOR: _count_role(Role.Kind.SUPERVISOR), Role.Kind.RAT: _count_role(Role.Kind.RAT)}
	_stats.clear()
	_events.clear()
	for peer: int in roster:
		var role: Role.Kind = roster[peer]["role"]
		if role == Role.Kind.SUPERVISOR or role == Role.Kind.RAT:
			_stats[peer] = {"name": roster[peer]["name"], "role": role, "sabotages": 0, "repairs": 0}
	var duration := MatchRulesModel.match_duration(rules, _team_started[Role.Kind.SUPERVISOR])
	if OS.is_debug_build() and Cli.has_arg("test-duration"):
		duration = maxi(Cli.get_int("test-duration", duration), 1)
	time_left = duration
	_match_end_ms = Time.get_ticks_msec() + duration * 1000
	session.plant.running = true
	Log.info("match", "playing for %d s" % duration)
	state = State.PLAYING


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	match state:
		State.COUNTDOWN:
			countdown_left = maxi(ceili((_countdown_end_ms - now) / 1000.0), 0)
			if now >= _countdown_end_ms:
				_begin_playing()
		State.PLAYING:
			time_left = maxi(ceili((_match_end_ms - now) / 1000.0), 0)
			var outcome := MatchRulesModel.evaluate(_win_state(_match_end_ms - now))
			if outcome["team"] != MatchRulesModel.Team.NONE:
				_end_match(outcome["team"], outcome["reason"])
		State.POST_MATCH:
			countdown_left = maxi(ceili((_post_end_ms - now) / 1000.0), 0)
			if now >= _post_end_ms:
				_back_to_lobby()


## What check_winner needs, from the current roster, bodies and plant.
func _win_state(ms_left: int) -> Dictionary:
	var rats_free := 0
	for node in session.players_root.get_children():
		var player := node as Player
		if player.role == Role.Kind.RAT and not player.status.has(StatusComponent.Status.CAGED) \
				and not player.status.has(StatusComponent.Status.ELIMINATED):
			rats_free += 1
	return {
		"meltdown": session.plant.meltdown,
		"time_left": ms_left / 1000.0,
		"supervisors": _count_role(Role.Kind.SUPERVISOR),
		"rats": _count_role(Role.Kind.RAT),
		"rats_free": rats_free,
		"supervisors_started": _team_started.get(Role.Kind.SUPERVISOR, 0),
		"rats_started": _team_started.get(Role.Kind.RAT, 0),
	}


func _end_match(winner: MatchRulesModel.Team, reason: String) -> void:
	session.plant.running = false
	for node in session.players_root.get_children():
		(node as Player).status.apply(StatusComponent.Status.LOCKED)
	var stats: Array = []  # plain Array: it travels in MatchSync
	for peer: int in _stats:
		stats.append(_stats[peer].duplicate())
	stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["role"] < b["role"])
	result = {"winner": winner, "reason": reason, "stats": stats}
	Log.info("match", "%s win: %s" % [MatchRulesModel.team_name(winner), reason])
	countdown_left = rules.post_match_s
	_post_end_ms = Time.get_ticks_msec() + rules.post_match_s * 1000
	state = State.POST_MATCH
	if OS.is_debug_build():
		_write_test_result()


## Plant events: stats for the credited players, plus the event log for the test result file.
func _on_subsystem_changed(index: int, what: String, peers: Array[int], before: float, after: float) -> void:
	var names: Array[String] = []
	for peer in peers:
		names.append(_stats[peer]["name"] if _stats.has(peer) else str(peer))
		if _stats.has(peer):
			match what:
				"sabotage":
					_stats[peer]["sabotages"] += 1
				"repair":
					_stats[peer]["repairs"] += 1
	var line := "%s %s by %s: health %d -> %d" % [what, session.plant.data(index).id, " + ".join(names),
		roundi(before), roundi(after)]
	_events.append(line)
	Log.info("match", line)


func _write_test_result() -> void:
	if not Cli.has_arg("result-file"):
		if Cli.has_arg("exit-after-match"):
			_quit_after_match()
		return
	var data := {
		"state_path": ">".join(_state_path),
		"winner": MatchRulesModel.team_name(result["winner"]).to_lower(),
		"reason": result["reason"],
		"events": _events,
		"healths": Array(session.plant.healths),
		"stats": result["stats"],
	}
	var path := Cli.get_str("result-file")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Log.error("match", "cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	else:
		file.store_string(JSON.stringify(data, "  ") + "\n")
		file.close()
		Log.info("match", "result written to %s" % path)
	if Cli.has_arg("exit-after-match"):
		_quit_after_match()


func _quit_after_match() -> void:
	Log.info("match", "--exit-after-match: shutting down in %.1f s" % EXIT_DELAY_S)
	await get_tree().create_timer(EXIT_DELAY_S).timeout  # let clients receive POST_MATCH first
	Net.leave()
	get_tree().quit(0)


func _back_to_lobby() -> void:
	session.plant.running = false
	var copy := roster.duplicate(true)
	for peer: int in copy:
		copy[peer]["role"] = Role.Kind.NONE
		copy[peer]["ready"] = false
		session.despawn_body(peer)
	roster = copy
	state = State.LOBBY
	_spawn_counters.clear()
	for peer: int in roster:
		_spawn(peer, Role.Kind.NONE, false)


func _spawn(peer_id: int, role: Role.Kind, locked: bool) -> void:
	var points := session.spawn_points_for(role)
	if points.is_empty():
		Log.error("match", "no spawn point for %s" % Role.display_name(role))
		return
	var index: int = _spawn_counters.get(role, 0)
	_spawn_counters[role] = index + 1
	session.spawn_body(peer_id, role, points[index % points.size()], locked)


func _count_role(role: Role.Kind) -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if e["role"] == role:
			count += 1
	return count


func _player_count_in_match() -> int:
	return _count_role(Role.Kind.SUPERVISOR) + _count_role(Role.Kind.RAT)


## A match needs 2 players to go on (1 with --debug-start, for solo testing).
func _min_to_continue() -> int:
	return 1 if _debug_start_at > 0 else 2


func _update_entry(peer_id: int, key: String, value: Variant) -> void:
	var copy := roster.duplicate(true)
	copy[peer_id][key] = value
	roster = copy
