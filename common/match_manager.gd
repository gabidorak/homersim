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
## the next match. An eliminated rat (CaptureService) loses its body and spectates too: both are
## "ghosts" for the chat (chat_members()).
## Swarm bonus (GDD §2): every supervisor knocked down at once adds swarm_bonus % to the meltdown,
## at most once every swarm_cooldown_s.
## For the UI (M8) it also replicates the server's name and match settings (`server_info`, lobby),
## everyone's ping (`pings`, lobby cards and scoreboard), the stats so far (`live_stats`, scoreboard),
## and sends the event feed (feed(): "Alice caged Bob!", "Turbine sabotaged!", client/event_feed.gd).
##
## Test-only server flags (debug builds): --test-duration S (match length), --result-file PATH
## (JSON summary written when the match ends), --exit-after-match (quit right after that).
## With --allow-debug, bots report the end of their scenario (request_debug_done): once every
## player in the match has, the timer runs out at once, so a test doesn't wait for its full
## --test-duration.
##
## AI bots (M10, GDD §2 Bots): when MatchRules.bot_fill_to is set, _start_match adds bot entries to
## the roster ({…, "bot": true}, negative ids, names from AiDirector) and hands them to assign_roles
## as fillers, so humans get their slots first. Bots are never in the lobby: the ready vote and the
## player counts are about humans (_human_count), and one human is enough. They leave when the match
## ends (_back_to_lobby). A match with no humans left goes back to the lobby. Test-only server flags
## (debug builds): --ai-fill N (overrides bot_fill_to), --ai-only (bots-only matches, back to back),
## --ai-roles rat,rat,supervisor (exactly these bots, whatever the fill).

enum State { LOBBY, ROLE_ASSIGN, COUNTDOWN, PLAYING, POST_MATCH }

## --exit-after-match: how long the server stays up in POST_MATCH before quitting.
const EXIT_DELAY_S := 1.5
## Nodes in this group get reset_for_match() at every match start (server): CCTV cameras, the chair.
const RESET_GROUP := "match_reset"
## Per-player counters in the result. bonks = broom stuns, caught = times caged (or eliminated).
const STAT_KEYS: Array[String] = ["sabotages", "repairs", "catches", "frees", "bites", "knockdowns", "steals",
	"hazard_hits", "bonks", "donuts", "caught"]
const PING_EVERY_S := 2.0
const STATS_EVERY_S := 1.0  ## live_stats goes out at most this often

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
var time_added := 0  ## seconds added to this match's timer (SCRAM penalties), for the HUD
var min_players := 3  ## copied from the rules so the lobby UI can show it
## peer id -> {"name": String, "pref": Role.Kind, "ready": bool, "role": Role.Kind, "eliminated": bool},
## plus "bot": true for an AI bot (M10, negative id)
var roster: Dictionary = {}:
	set(value):
		roster = value
		roster_changed.emit()
## The last match's outcome, set when POST_MATCH starts:
## {"winner": MatchRulesModel.Team, "reason": String, "stats": Array of
##  {"peer", "name", "role", "bot", and one count per STAT_KEYS}}
var result: Dictionary = {}
## {"name", "max_players", "duration_s", "duration_single_s", "min_players", "locked", "bot_fill_to"}:
## the lobby shows it.
var server_info: Dictionary = {}
var pings: Dictionary = {}  ## peer -> round trip in ms
var live_stats: Dictionary = {}  ## peer -> {stat: count} during PLAYING (only the stats that are not 0)

# --- Server only ----------------------------------------------------------------
var rules: MatchRules
var _rng := RandomNumberGenerator.new()
var _countdown_end_ms := 0
var _match_end_ms := 0
var _post_end_ms := 0
var _debug_start_at := 0  # --debug-start [N]: start without a vote once N players joined; 0 = vote
var _spawn_counters: Dictionary[int, int] = {}  # role -> next spawn point index
var _team_started: Dictionary[int, int] = {}  # role -> players of that role when PLAYING began
var _stats: Dictionary[int, Dictionary] = {}  # peer -> {"name", "role", and one count per STAT_KEYS}
var _swapping := false  # bodies are being retired (Session.retire_bodies) before a respawn
var _swap_id := 0  # bumped by each swap, so a superseded one stops after its await
var _swarm_ready_at_ms := 0
var _swarm_was_down := false
var _state_path: Array[String] = []  # every state entered, for the test result file
var _events: Array[String] = []  # plant events this match, for the test result file
var _bots_done: Dictionary[int, bool] = {}  # peers whose test scenario is over (request_debug_done)
var _next_ping_ms := 0
var _next_stats_ms := 0
var _stats_dirty := false
var _ai_only := false  # --ai-only: matches with no humans, back to back (debug builds)
var _ai_roles: Array[Role.Kind] = []  # --ai-roles: exactly these bots (debug builds)

@onready var session: Session = get_parent()


func _ready() -> void:
	if not Net.is_server:
		set_process(false)
		return
	rules = session.match_rules if session.match_rules != null else load(Config.DEFAULT_MATCH_RULES)
	_rng.randomize()
	if Cli.has_arg("debug-start"):
		_debug_start_at = maxi(Cli.get_int("debug-start", 1), 1)
		Log.info("match", "--debug-start: the match starts once %d player(s) joined" % _debug_start_at)
	if OS.is_debug_build():
		_read_ai_flags()
	min_players = MatchRulesModel.effective_min_players(rules)
	session.player_added.connect(_on_player_added)
	session.player_removed.connect(_on_player_removed)
	session.plant.subsystem_changed.connect(_on_subsystem_changed)
	server_info = {
		"name": session.server_name,
		"max_players": session.max_players,
		"duration_s": rules.duration_s,
		"duration_single_s": rules.duration_single_supervisor_s,
		"min_players": min_players,
		"locked": session.password != "",
		"bot_fill_to": rules.bot_fill_to if bots_enabled() else 0,
	}


## Test-only (debug builds): --ai-fill N, --ai-only, --ai-roles rat,rat,supervisor.
func _read_ai_flags() -> void:
	if not rules.resource_path.is_empty():
		rules = rules.duplicate()  # (never change the shared resource)
	if Cli.has_arg("ai-fill"):
		rules.bot_fill_to = clampi(Cli.get_int("ai-fill", 6), 0, 6)
	for text in Cli.get_str("ai-roles").split(",", false):
		var role := Role.from_text(text.strip_edges())
		if role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
			_ai_roles.append(role)
	_ai_only = Cli.has_arg("ai-only")
	if (_ai_only or not _ai_roles.is_empty()) and rules.bot_fill_to < 2:
		rules.bot_fill_to = 6
	if _ai_only:
		Log.info("match", "--ai-only: bots-only matches, back to back")


## Bots fill the matches of this server (M10).
func bots_enabled() -> bool:
	return MatchRulesModel.bots_enabled(rules)


func entry(peer_id: int) -> Dictionary:
	return roster.get(peer_id, {})


## Client: our role in the current match (NONE in the lobby).
func local_role() -> Role.Kind:
	return entry(session.local_peer_id).get("role", Role.Kind.NONE)


## A match is under way (roles are assigned): ghosts and team chat apply.
func in_match() -> bool:
	return state in [State.ROLE_ASSIGN, State.COUNTDOWN, State.PLAYING]


## True for players watching the match: eliminated rats and spectators (late joiners).
func is_ghost(peer_id: int) -> bool:
	var e := entry(peer_id)
	return in_match() and (e.get("eliminated", false) or e.get("role", Role.Kind.NONE) == Role.Kind.SPECTATOR)


## For ChatService.route: peer -> {"role", "ghost"} for every joined player.
func chat_members() -> Dictionary:
	var members := {}
	for peer: int in session.players:
		members[peer] = {"role": entry(peer).get("role", Role.Kind.NONE), "ghost": is_ghost(peer)}
	return members


func ready_count() -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if e["ready"]:
			count += 1
	return count


## True for an AI bot's roster entry (M10).
func is_bot(peer_id: int) -> bool:
	return entry(peer_id).get("bot", false)


## The roster has AI bots (a match with bots is under way).
func _has_bots() -> bool:
	for e: Dictionary in roster.values():
		if e.get("bot", false):
			return true
	return false


## Roster entries that are people (spectators included), not bots.
func human_count() -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if not e.get("bot", false):
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


## Test-only (bots): the sender's scenario is over. Refused unless Session.debug_allowed().
@rpc("any_peer", "reliable")
func request_debug_done() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not Session.debug_allowed() or not roster.has(peer):
		Log.warn("match", "refused a debug done from peer %d" % peer)
		return
	if state != State.PLAYING:
		return  # the match already ended by itself (every rat caught…)
	_bots_done[peer] = true
	Log.info("match", "%s finished its test scenario" % roster[peer]["name"])
	for p: int in roster:
		if roster[p]["role"] in [Role.Kind.SUPERVISOR, Role.Kind.RAT] and not _bots_done.has(p) \
				and not roster[p].get("bot", false):  # (AI bots have no scenario to finish)
			return
	Log.info("match", "every bot is done: the timer runs out now")
	_match_end_ms = mini(_match_end_ms, Time.get_ticks_msec())


# --- Server ------------------------------------------------------------------------

func _on_player_added(peer_id: int) -> void:
	var late := state != State.LOBBY
	var copy := roster.duplicate(true)
	copy[peer_id] = {
		"name": session.players[peer_id].name,
		"pref": Role.Kind.NONE,
		"ready": false,
		"role": Role.Kind.SPECTATOR if late else Role.Kind.NONE,
		"eliminated": false,
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
	if in_match() and _has_bots() and human_count() == 0 and not _ai_only:
		# Only bots left (spectators count as humans): nobody plays or watches, stop.
		Log.info("match", "no humans left in the match, back to the lobby")
		_back_to_lobby()
		return
	match state:
		State.LOBBY:
			_check_start()
		State.ROLE_ASSIGN, State.COUNTDOWN:
			if _player_count_in_match() < _min_to_continue():
				Log.info("match", "too few players left, back to the lobby")
				_back_to_lobby()
		# PLAYING: an emptied team loses, checked every frame in _process.


## AiDirector calls this once the bots can play (the navigation meshes are baked).
func recheck_start() -> void:
	_check_start()


func _check_start() -> void:
	if state != State.LOBBY or _swapping:
		return
	var humans := human_count()
	if bots_enabled() and not session.ai_ready:
		return  # the bots can't walk yet: AiDirector calls recheck_start() after its bake
	if _ai_only:
		_start_match()
	elif humans == 0:
		return
	elif _debug_start_at > 0:
		if humans >= _debug_start_at:
			_start_match()
	elif MatchRulesModel.ready_vote_passes(humans, ready_count(), rules):
		_start_match()


func _start_match() -> void:
	state = State.ROLE_ASSIGN
	var prefs: Dictionary[int, Role.Kind] = {}
	var watchers: Array[int] = []  # --ai-only: humans watch the bots
	for peer: int in roster:
		if _ai_only:
			watchers.append(peer)
		else:
			prefs[peer] = roster[peer]["pref"]
	var copy := roster.duplicate(true)
	# Bots (M10): new entries, given to assign_roles as fillers so the humans choose first.
	var bot_count := _ai_roles.size() if not _ai_roles.is_empty() else MatchRulesModel.bots_needed(prefs.size(), rules)
	var fillers: Array[int] = []
	var taken: Array[String] = []
	for e: Dictionary in roster.values():
		taken.append(e["name"])
	var ai := session.ai_director()
	for i in bot_count:
		var id := AiDirector.FIRST_ID - i
		fillers.append(id)
		var bot_name := ai.bot_name(i, taken) if ai != null else "Bot %d" % (i + 1)
		taken.append(bot_name)
		copy[id] = {"name": bot_name, "pref": Role.Kind.NONE, "ready": false, "role": Role.Kind.NONE,
			"eliminated": false, "bot": true}
	var roles: Dictionary[int, Role.Kind]
	if _ai_roles.is_empty():
		roles = MatchRulesModel.assign_roles(prefs, rules, _rng, fillers)
	else:
		roles = MatchRulesModel.assign_roles(prefs, rules, _rng)
		for i in fillers.size():
			roles[fillers[i]] = _ai_roles[i]
	for peer in watchers:
		roles[peer] = Role.Kind.SPECTATOR
	var summary: Array[String] = []
	for peer: int in fillers:
		if not roles.has(peer):
			copy.erase(peer)  # a filler the table had no slot for
	for peer: int in roles:
		copy[peer]["role"] = roles[peer]
		copy[peer]["ready"] = false
		copy[peer]["eliminated"] = false
		summary.append("%s=%s%s" % [copy[peer]["name"], Role.display_name(roles[peer]), " (bot)" if peer in fillers else ""])
	roster = copy
	Log.info("match", "roles: %s" % ", ".join(summary))

	# Lobby bodies out (cleanly, see Session.retire_bodies); role bodies in, frozen (LOCKED) until
	# the countdown ends.
	var swap := _begin_swap()
	await session.retire_bodies(roster.keys())
	if swap != _swap_id or state != State.ROLE_ASSIGN:
		return  # a player left meanwhile and we went back to the lobby
	_swapping = false
	_spawn_counters.clear()
	for peer: int in roles:
		if roles[peer] != Role.Kind.SPECTATOR:
			_spawn(peer, roles[peer], true)
	session.plant.reset()
	session.captures.reset()
	session.items.clear()
	get_tree().call_group(RESET_GROUP, "reset_for_match")
	countdown_left = rules.countdown_s
	_countdown_end_ms = Time.get_ticks_msec() + rules.countdown_s * 1000
	state = State.COUNTDOWN


func _begin_playing() -> void:
	for node in session.players_root.get_children():
		(node as Player).status.clear(StatusComponent.Status.LOCKED)
	_team_started = {Role.Kind.SUPERVISOR: _count_role(Role.Kind.SUPERVISOR), Role.Kind.RAT: _count_role(Role.Kind.RAT)}
	_stats.clear()
	_events.clear()
	_bots_done.clear()
	live_stats = {}
	for peer: int in roster:
		var role: Role.Kind = roster[peer]["role"]
		if role == Role.Kind.SUPERVISOR or role == Role.Kind.RAT:
			var row := {"peer": peer, "name": roster[peer]["name"], "role": role, "bot": roster[peer].get("bot", false)}
			for key in STAT_KEYS:
				row[key] = 0
			_stats[peer] = row
	_swarm_ready_at_ms = 0
	_swarm_was_down = false
	var duration := MatchRulesModel.match_duration(rules, _team_started[Role.Kind.SUPERVISOR])
	if OS.is_debug_build() and Cli.has_arg("test-duration"):
		duration = maxi(Cli.get_int("test-duration", duration), 1)
	time_left = duration
	time_added = 0
	_match_end_ms = Time.get_ticks_msec() + duration * 1000
	session.plant.running = true
	Log.info("match", "playing for %d s" % duration)
	state = State.PLAYING


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_publish(now)
	if _swapping:
		return  # bodies are being swapped; the state machine resumes when that's done
	match state:
		State.COUNTDOWN:
			countdown_left = maxi(ceili((_countdown_end_ms - now) / 1000.0), 0)
			if now >= _countdown_end_ms:
				_begin_playing()
		State.PLAYING:
			time_left = maxi(ceili((_match_end_ms - now) / 1000.0), 0)
			_check_swarm(now)
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


## Server: count one `key` (STAT_KEYS) for `peer` in this match's stats.
func add_stat(peer: int, key: String, amount: int = 1) -> void:
	if state == State.PLAYING and _stats.has(peer) and _stats[peer].has(key):
		_stats[peer][key] += amount
		_stats_dirty = true


## Server: a line in everyone's event feed. `kind` names the line (client/event_feed.gd words it, in
## each player's language); `a` and `b` are its names or ids.
func feed(kind: String, a: String = "", b: String = "") -> void:
	for peer: int in session.players:
		on_feed.rpc_id(peer, kind, a, b)


@rpc("authority", "reliable")
func on_feed(kind: String, a: String, b: String) -> void:
	Events.feed_event.emit(kind, a, b)


## Test-only (server --ai-labels, M10): each bot's current goal, twice a second ({peer: label}), shown
## under its name tag on clients (a spectating debug client: watch mode).
@rpc("authority", "unreliable")
func on_ai_labels(labels: Dictionary) -> void:
	for peer: int in labels:
		var body := session.get_body(peer)
		if body != null:
			body.show_ai_label(str(labels[peer]))


## Server: refresh the pings and the live stats now and then (they replicate on change).
func _publish(now_ms: int) -> void:
	if now_ms >= _next_ping_ms:
		_next_ping_ms = now_ms + int(PING_EVERY_S * 1000.0)
		var fresh := {}
		for peer: int in session.players:
			fresh[peer] = Net.peer_ping_ms(peer)
		if fresh != pings:
			pings = fresh
	if _stats_dirty and now_ms >= _next_stats_ms:
		_stats_dirty = false
		_next_stats_ms = now_ms + int(STATS_EVERY_S * 1000.0)
		var fresh := {}
		for peer: int in _stats:
			var counts := {}
			for key in STAT_KEYS:
				if _stats[peer][key] != 0:
					counts[key] = _stats[peer][key]
			fresh[peer] = counts
		live_stats = fresh


## Server, tests (M10 AI scenarios): the timer runs out now, like request_debug_done.
func end_timer_now(why: String) -> void:
	if state != State.PLAYING:
		return
	Log.info("match", "%s: the timer runs out now" % why)
	_match_end_ms = mini(_match_end_ms, Time.get_ticks_msec())


## Server (SCRAM): the shift gets `seconds` longer.
func extend_time(seconds: int) -> void:
	if state != State.PLAYING:
		return
	_match_end_ms += seconds * 1000
	time_added += seconds
	time_left = maxi(ceili((_match_end_ms - Time.get_ticks_msec()) / 1000.0), 0)
	_events.append("timer +%d s" % seconds)
	Log.info("match", "timer +%d s (%d s left)" % [seconds, time_left])


## Server (CaptureService): `peer`'s rat is out of the match. Its body goes; it spectates and
## talks in the ghost chat until the next match.
func eliminate(peer: int) -> void:
	if not roster.has(peer):
		return
	_update_entry(peer, "eliminated", true)
	session.retire_bodies([peer])  # not awaited: the body is LOCKED until it goes
	_events.append("eliminated %s" % roster[peer]["name"])


func _check_swarm(now_ms: int) -> void:
	var supervisors := 0
	var down := 0
	for node in session.players_root.get_children():
		var player := node as Player
		if player != null and player.role == Role.Kind.SUPERVISOR:
			supervisors += 1
			if player.status.has(StatusComponent.Status.KNOCKED_DOWN):
				down += 1
	var all_down := supervisors > 0 and down == supervisors
	if all_down and not _swarm_was_down and now_ms >= _swarm_ready_at_ms:
		_swarm_ready_at_ms = now_ms + int(rules.swarm_cooldown_s * 1000.0)
		session.plant.add_meltdown(rules.swarm_bonus)
		var line := "swarm bonus: +%d%% meltdown" % roundi(rules.swarm_bonus)
		_events.append(line)
		Log.info("match", line)
		feed("swarm", str(roundi(rules.swarm_bonus)))
	_swarm_was_down = all_down


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
			_stats_dirty = true
			match what:
				"sabotage":
					_stats[peer]["sabotages"] += 1
				"repair":
					_stats[peer]["repairs"] += 1
	var id := String(session.plant.data(index).id)
	var line := "%s %s by %s: health %d -> %d" % [what, id, " + ".join(names), roundi(before), roundi(after)]
	_events.append(line)
	Log.info("match", line)
	if state != State.PLAYING:
		return
	match what:
		"sabotage":
			feed("offline" if session.plant.needs_reboot(index) else "sabotaged", id)
		"repair":
			if after >= 99.5 and before < 99.5:
				feed("repaired", id)
		"reboot":
			feed("rebooted", id)


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
		"meltdown": snappedf(session.plant.meltdown, 0.1),
		"stats": result["stats"],
	}
	var ai := session.ai_director()
	if ai != null and bots_enabled():
		data["ai"] = ai.report()
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
	session.items.clear()
	var swap := _begin_swap()
	await session.retire_bodies(roster.keys())
	if swap != _swap_id:
		return
	# The roster as it is now: someone may have joined (as a spectator) during the await. The bots
	# leave with the match.
	var copy := roster.duplicate(true)
	for peer: int in copy.keys():
		if copy[peer].get("bot", false):
			copy.erase(peer)
	for peer: int in copy:
		copy[peer]["role"] = Role.Kind.NONE
		copy[peer]["ready"] = false
		copy[peer]["eliminated"] = false
	roster = copy
	live_stats = {}
	Log.info("match", "back to the lobby with %d player(s)" % roster.size())
	state = State.LOBBY
	_spawn_counters.clear()
	for peer: int in roster:
		_spawn(peer, Role.Kind.NONE, false)
	_swapping = false
	_check_start()


func _begin_swap() -> int:
	_swapping = true
	_swap_id += 1
	return _swap_id


func _spawn(peer_id: int, role: Role.Kind, locked: bool) -> void:
	if session.get_body(peer_id) != null:
		return  # already has one (it joined while bodies were being swapped)
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


## Humans with a role in the match (bots don't count, M10).
func _player_count_in_match() -> int:
	var count := 0
	for e: Dictionary in roster.values():
		if e["role"] in [Role.Kind.SUPERVISOR, Role.Kind.RAT] and not e.get("bot", false):
			count += 1
	return count


## A match needs 2 players to go on (1 with --debug-start, for solo testing, or one human with bots).
func _min_to_continue() -> int:
	return 1 if _debug_start_at > 0 or _has_bots() else 2


func _update_entry(peer_id: int, key: String, value: Variant) -> void:
	var copy := roster.duplicate(true)
	copy[peer_id][key] = value
	roster = copy
