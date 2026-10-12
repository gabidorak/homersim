class_name MatchScore
extends RefCounted
## A player's score for a match (the post-match tables): points for what they did, by role (POINTS),
## plus WIN_BONUS when their team won, never below 0. One number players can compare from match to
## match. Pure logic, so GUT can test it. Tuned on bot matches (tests/integration/ai_balance.sh prints
## each role's average score): a supervisor and a rat score about the same on average, and a winner
## more than a loser of the same role.

const WIN_BONUS := 300
## Role -> {stat (MatchManager.STAT_KEYS): points for each}. Stats not listed are worth nothing.
const POINTS := {
	# Repairs are many and small (about 10 a match, more in a long losing one): worth little each.
	Role.Kind.SUPERVISOR: {"repairs": 20, "catches": 200, "bonks": 50, "hazard_hits": -10},
	Role.Kind.RAT: {"sabotages": 100, "bites": 30, "knockdowns": 75, "frees": 150, "steals": 75, "caught": -25,
		"hazard_hits": -10},
}


## The score of a result row ({"role", <stat>: count}) in a match that `winner` won.
static func of(row: Dictionary, winner: MatchRulesModel.Team) -> int:
	var role: int = row.get("role", Role.Kind.NONE)
	var points: Dictionary = POINTS.get(role, {})
	var total := 0
	for stat: String in points:
		total += int(row.get(stat, 0)) * int(points[stat])
	if team_of(role) == winner and winner != MatchRulesModel.Team.NONE:
		total += WIN_BONUS
	return maxi(total, 0)


static func team_of(role: int) -> MatchRulesModel.Team:
	match role:
		Role.Kind.SUPERVISOR:
			return MatchRulesModel.Team.SUPERVISORS
		Role.Kind.RAT:
			return MatchRulesModel.Team.RATS
	return MatchRulesModel.Team.NONE
