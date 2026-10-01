class_name MatchRulesModel
extends RefCounted
## Pure match rules (no nodes), so GUT can test them without a scene tree.

enum Team { NONE, SUPERVISORS, RATS }


## Gives every peer a role. Team sizes come from the balance table (GDD §2); within those sizes,
## preferences are honoured where possible: supervisor slots go to players who asked for
## Supervisor, then to "Any", then to rat fans; rat slots the other way round. Ties are broken
## by a shuffle from `rng`, so a fixed seed gives a fixed result. Players beyond the rat cap
## become spectators. A lone player (debug only) simply gets their preference.
static func assign_roles(prefs: Dictionary[int, Role.Kind], rules: MatchRules,
		rng: RandomNumberGenerator) -> Dictionary[int, Role.Kind]:
	var result: Dictionary[int, Role.Kind] = {}
	var peers: Array[int] = prefs.keys()
	peers.sort()  # dictionary order isn't part of the contract; the shuffle must start the same
	for i in range(peers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := peers[i]
		peers[i] = peers[j]
		peers[j] = tmp

	var n := peers.size()
	if n == 1:
		var only := peers[0]
		result[only] = Role.Kind.RAT if prefs[only] == Role.Kind.RAT else Role.Kind.SUPERVISOR
		return result
	if n == 0:
		return result

	var supervisors := mini(rules.supervisors_for(n), n - 1)  # always leave at least one rat
	var rats := mini(n - supervisors, rules.max_rats)

	var remaining := _ordered_by_pref(peers, prefs, [Role.Kind.SUPERVISOR, Role.Kind.NONE, Role.Kind.RAT])
	for i in supervisors:
		result[remaining.pop_front()] = Role.Kind.SUPERVISOR
	remaining = _ordered_by_pref(remaining, prefs, [Role.Kind.RAT, Role.Kind.NONE, Role.Kind.SUPERVISOR])
	for i in rats:
		result[remaining.pop_front()] = Role.Kind.RAT
	for peer in remaining:
		result[peer] = Role.Kind.SPECTATOR
	return result


## `peers` regrouped by preference in the given order, keeping their relative order within a group.
## Any other preference value counts as NONE.
static func _ordered_by_pref(peers: Array[int], prefs: Dictionary[int, Role.Kind], order: Array) -> Array[int]:
	var out: Array[int] = []
	for wanted: Role.Kind in order:
		for peer in peers:
			var pref: Role.Kind = prefs.get(peer, Role.Kind.NONE)
			if pref != Role.Kind.SUPERVISOR and pref != Role.Kind.RAT:
				pref = Role.Kind.NONE
			if pref == wanted:
				out.append(peer)
	return out


## The lobby ready vote (GDD §3): at least `min_players`, and strictly more than
## `ready_fraction` of them ready.
static func ready_vote_passes(player_count: int, ready_count: int, rules: MatchRules) -> bool:
	return player_count >= rules.min_players and ready_count > player_count * rules.ready_fraction


## The winner for a match `state`, or Team.NONE while the match goes on. Keys:
##   meltdown (0..100), time_left (s), supervisors / rats (players of that team still in the
##   match), rats_free (rats neither caged nor eliminated), supervisors_started / rats_started
##   (team sizes when the match began).
## Priority (GDD §2, ARCHITECTURE §6): meltdown → all rats caught (or gone) → all supervisors
## gone → time out. A team only "empties" if it had players at the start, so solo debug matches
## run until the timer.
static func check_winner(state: Dictionary) -> Team:
	return evaluate(state)["team"]


## Like check_winner, plus a human-readable reason: {"team": Team, "reason": String}.
static func evaluate(state: Dictionary) -> Dictionary:
	if float(state.get("meltdown", 0.0)) >= 100.0:
		return {"team": Team.RATS, "reason": "Meltdown!"}
	if int(state.get("rats_started", 0)) > 0:
		if int(state.get("rats", 0)) == 0:
			return {"team": Team.SUPERVISORS, "reason": "All rats left the game"}
		if int(state.get("rats_free", 0)) == 0:
			return {"team": Team.SUPERVISORS, "reason": "Every rat is caught"}
	if int(state.get("supervisors_started", 0)) > 0 and int(state.get("supervisors", 0)) == 0:
		return {"team": Team.RATS, "reason": "All supervisors left the game"}
	if float(state.get("time_left", 1.0)) <= 0.0:
		return {"team": Team.SUPERVISORS, "reason": "The shift is over: the plant survived"}
	return {"team": Team.NONE, "reason": ""}


static func team_name(team: Team) -> String:
	match team:
		Team.SUPERVISORS:
			return "Supervisors"
		Team.RATS:
			return "Rats"
	return "Nobody"


## The match length: shorter with a single supervisor (GDD §2).
static func match_duration(rules: MatchRules, supervisor_count: int) -> int:
	return rules.duration_single_supervisor_s if supervisor_count <= 1 else rules.duration_s
