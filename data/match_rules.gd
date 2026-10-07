class_name MatchRules
extends Resource
## Match flow and team balance (GDD §2, §3). Saved as data/match_rules.tres.
## The server can override any of these in server.cfg's [match] section.

## The most seats a team can have: the plant has this many spawn points per team (gen_plant.py).
const SUPERVISORS_LIMIT := 3
const RATS_LIMIT := 6

@export var duration_s := 540  ## used from M3
@export var duration_single_supervisor_s := 480  ## used from M3
@export var countdown_s := 10
@export var post_match_s := 15  ## used from M3
@export var min_players := 3  ## the ready vote can't pass with fewer players (nor with more than the seats)
@export_range(0.0, 1.0) var ready_fraction := 0.5  ## strictly more than this share must be ready
## The teams' seats (GDD §2): the most supervisors and rats a match has. With fewer players the teams
## are split in the same proportion (supervisors_for); players past the seats become spectators.
## The host picks them (Play solo, Host a game); 1..SUPERVISORS_LIMIT and 1..RATS_LIMIT.
@export_range(1, 3) var max_supervisors := 2
@export_range(1, 6) var max_rats := 4
@export var swarm_bonus := 15.0  ## meltdown % when every supervisor is knocked down at once
@export var swarm_cooldown_s := 45.0
## AI bots (M10, GDD §2 and §5.5): at role assignment, bots fill the match up to this many players
## (never past the seats). 0 = no bots (the default); otherwise 2 or more. Humans always get their
## slots first. Play solo and Host a game set it to the seats: bots take every empty one.
@export var bot_fill_to := 0
@export_range(0, 2) var bot_difficulty := 1  ## 0 easy, 1 normal, 2 hard (BotTuning.skills)


func supervisor_seats() -> int:
	return clampi(max_supervisors, 1, SUPERVISORS_LIMIT)


func rat_seats() -> int:
	return clampi(max_rats, 1, RATS_LIMIT)


## The most players a match has (more join as spectators).
func seats() -> int:
	return supervisor_seats() + rat_seats()


## Supervisors in a match of `player_count`: the supervisors' share of the seats, rounded to the
## nearest (a half goes to the rats), at least 1 and at most their seats. With the default 2 + 4
## seats this is the GDD §2 table: 1 supervisor up to 4 players, 2 from 5.
func supervisors_for(player_count: int) -> int:
	var share := float(player_count * supervisor_seats()) / seats()
	return clampi(ceili(share - 0.5), 1, supervisor_seats())
