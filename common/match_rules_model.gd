class_name MatchRulesModel
extends RefCounted
## Pure match rules (no nodes), so GUT can test them without a scene tree.


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
