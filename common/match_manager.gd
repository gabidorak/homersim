class_name MatchManager
extends Node
## The match state machine. The logic runs on the server; clients only read the replicated
## state (MatchSync: state, countdown_left, min_players, roster) and send lobby requests.
##
##   LOBBY ──ready vote / --debug-start──▶ ROLE_ASSIGN ─▶ COUNTDOWN ─▶ PLAYING
##     ▲                                                     │            │
##     └──────────────── too few players left ◀──────────────┴────────────┘
##
## M2: PLAYING has no timer or win checks yet (M3), it only means "unfrozen". Players who join
## after the lobby spectate until the next match.

enum State { LOBBY, ROLE_ASSIGN, COUNTDOWN, PLAYING }

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
			state_changed.emit(state)
			Events.match_state_changed.emit(state)
var countdown_left := 0  ## whole seconds
var min_players := 3  ## copied from the rules so the lobby UI can show it
## peer id -> {"name": String, "pref": Role.Kind, "ready": bool, "role": Role.Kind}
var roster: Dictionary = {}:
	set(value):
		roster = value
		roster_changed.emit()

# --- Server only ----------------------------------------------------------------
var rules: MatchRules
var _rng := RandomNumberGenerator.new()
var _countdown_end_ms := 0
var _debug_start_at := 0  # --debug-start [N]: start without a vote once N players joined; 0 = vote
var _spawn_counters: Dictionary[int, int] = {}  # role -> next spawn point index

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
	if state == State.LOBBY:
		_check_start()
	elif _player_count_in_match() < _min_to_continue():
		Log.info("match", "too few players left, back to the lobby")
		_back_to_lobby()


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
	countdown_left = rules.countdown_s
	_countdown_end_ms = Time.get_ticks_msec() + rules.countdown_s * 1000
	state = State.COUNTDOWN


func _process(_delta: float) -> void:
	if state != State.COUNTDOWN:
		return
	var left_ms := _countdown_end_ms - Time.get_ticks_msec()
	countdown_left = maxi(ceili(left_ms / 1000.0), 0)
	if left_ms <= 0:
		for node in session.players_root.get_children():
			(node as Player).status.clear(StatusComponent.Status.LOCKED)
		state = State.PLAYING


func _back_to_lobby() -> void:
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


func _player_count_in_match() -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if e["role"] == Role.Kind.SUPERVISOR or e["role"] == Role.Kind.RAT:
			count += 1
	return count


## A match needs 2 players to go on (1 with --debug-start, for solo testing).
func _min_to_continue() -> int:
	return 1 if _debug_start_at > 0 else 2


func _update_entry(peer_id: int, key: String, value: Variant) -> void:
	var copy := roster.duplicate(true)
	copy[peer_id][key] = value
	roster = copy
