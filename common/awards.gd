class_name Awards
extends RefCounted
## The post-match awards (M8): "Most bonks", "Sneakiest rat", "Donut addict"… picked from a match
## result's per-player stats (MatchManager.result["stats"]). Pure logic, so GUT can test it.
## Each award goes to the player with the highest count (at least the award's minimum); ties go to
## the first name in alphabetical order. Up to MAX awards, preferring players without one yet.

const MAX := 4

## id, stat, English title, English detail ("%d" = the count), minimum count, role (NONE = anyone).
## Order = priority when there are more candidates than slots.
const LIST: Array = [
	["bonks", "bonks", "Most bonks", "%d bonks", 1, Role.Kind.SUPERVISOR],
	["sneaky", "sabotages", "Sneakiest rat", "%d sabotages, never caught", 1, Role.Kind.RAT],
	["donuts", "donuts", "Donut addict", "%d donuts", 1, Role.Kind.SUPERVISOR],
	["catcher", "catches", "Rat catcher", "%d rats caged", 1, Role.Kind.SUPERVISOR],
	["biter", "bites", "Ankle biter", "%d bites", 2, Role.Kind.RAT],
	["fixer", "repairs", "Fix-it hero", "%d repairs", 1, Role.Kind.SUPERVISOR],
	["jailbreak", "frees", "Jailbreaker", "%d friends freed", 1, Role.Kind.RAT],
	["pickpocket", "steals", "Pickpocket", "%d keycards stolen", 1, Role.Kind.RAT],
	["saboteur", "sabotages", "Chief saboteur", "%d sabotages", 1, Role.Kind.RAT],
	["clumsy", "hazard_hits", "Accident prone", "%d hazard hits", 2, Role.Kind.NONE],
]


## The awards for `stats` (rows: {"name", "role", <stat>: count}): [{"id", "title", "detail",
## "name", "role", "count"}], titles and details in English (translate them when shown).
static func compute(stats: Array) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for def: Array in LIST:
		var best: Dictionary = {}
		for row: Dictionary in stats:
			if def[5] != Role.Kind.NONE and row.get("role", Role.Kind.NONE) != def[5]:
				continue
			if def[0] == "sneaky" and int(row.get("caught", 0)) > 0:
				continue
			var count := int(row.get(def[1], 0))
			if count < def[4]:
				continue
			if best.is_empty() or count > best["count"] or (count == best["count"]
					and str(row["name"]).naturalnocasecmp_to(best["name"]) < 0):
				best = {"id": def[0], "title": def[2], "detail": def[3], "name": str(row["name"]),
					"role": row.get("role", Role.Kind.NONE), "count": count}
		if not best.is_empty():
			candidates.append(best)
	# "Chief saboteur" only when the sneakiest rat didn't take that crown already.
	var sneaky := candidates.filter(func(c: Dictionary) -> bool: return c["id"] == "sneaky")
	if not sneaky.is_empty():
		candidates = candidates.filter(func(c: Dictionary) -> bool:
			return c["id"] != "saboteur" or c["name"] != sneaky[0]["name"])
	var picked: Array[Dictionary] = []
	var winners: Array[String] = []
	for second_pass in [false, true]:
		for c in candidates:
			if picked.size() >= MAX:
				break
			if picked.has(c) or (not second_pass and winners.has(c["name"])):
				continue
			picked.append(c)
			winners.append(c["name"])
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(a["id"]) < _rank(b["id"]))
	return picked


static func _rank(id: String) -> int:
	for i in LIST.size():
		if LIST[i][0] == id:
			return i
	return LIST.size()
