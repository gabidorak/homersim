class_name MatchRules
extends Resource
## Match flow and team balance (GDD §2, §3). Saved as data/match_rules.tres.
## The server can override any of these in server.cfg's [match] section.

@export var duration_s := 540  ## used from M3
@export var duration_single_supervisor_s := 480  ## used from M3
@export var countdown_s := 10
@export var post_match_s := 15  ## used from M3
@export var min_players := 3  ## the ready vote can't pass with fewer players
@export_range(0.0, 1.0) var ready_fraction := 0.5  ## strictly more than this share must be ready
## Supervisors per player count (index = player count). Counts past the end use the last entry.
@export var supervisors_by_players := PackedInt32Array([1, 1, 1, 1, 1, 2, 2])
@export var max_rats := 4  ## extra players become spectators
@export var swarm_bonus := 15.0  ## meltdown % when every supervisor is knocked down at once
@export var swarm_cooldown_s := 45.0
## AI bots (M10, GDD §2 and §5.5): at role assignment, bots fill the match up to this many players.
## 0 = no bots (the default); otherwise 2..6. Humans always get their slots first.
@export var bot_fill_to := 0
@export_range(0, 2) var bot_difficulty := 1  ## 0 easy, 1 normal, 2 hard (BotTuning.skills)


func supervisors_for(player_count: int) -> int:
	if supervisors_by_players.is_empty():
		return 1
	return supervisors_by_players[clampi(player_count, 0, supervisors_by_players.size() - 1)]
