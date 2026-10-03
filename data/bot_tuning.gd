class_name BotTuning
extends Resource
## The AI bots' numbers (M10, GDD §5.5, ARCHITECTURE §6 AI bots). Saved as data/bot_tuning.tres.
## These tune how bots *decide*; the game rules they play by (speeds, holds, cooldowns) are the same
## resources humans play by. Whether a server has bots at all (bot_fill_to) and how good they are
## (bot_difficulty) are MatchRules keys, so server.cfg's [match] section can set them.

const PATH := "res://data/bot_tuning.tres"

@export var skills: Array[BotSkill] = []  ## easy, normal, hard
## Bot names (original and goofy; players see a "Bot" badge next to them, so no "Bot" in the name).
@export var names := PackedStringArray()

@export_group("Senses")
@export var senses_hz := 10.0  ## sight and hearing checks per second
@export var fov_supervisor_deg := 110.0  ## full angle, around the body's facing
@export var fov_rat_deg := 220.0  ## a rat's third-person camera sees around it
@export var smoke_view_range := 6.0  ## m, in or into active smoke
@export var hear_rat_walk := 3.0  ## m: a walking rat
@export var hear_rat_sprint := 8.0  ## m: a sprinting rat
@export var hear_supervisor := 10.0  ## m: a moving supervisor
@export var hear_bite := 10.0  ## m
@export var hear_squeak := 12.0  ## m
@export var hear_broom := 12.0  ## m
@export var hear_noise := 2.0  ## m of error on a heard position
@export var memory_s := 8.0  ## a last known position is kept this long, then becomes "search this area"
@export var search_s := 12.0  ## …for this long
@export var share_delay_s := 1.0  ## teammate bots hear about a sighting this much later (a callout)

@export_group("Decisions")
@export var commitment_bonus := 0.15  ## added to the running goal's score, so bots don't flip-flop
@export var claim_ttl_s := 3.0  ## a claim lapses unless its bot renews it
@export var blacklist_min_s := 10.0  ## a target a goal failed on is skipped this long…
@export var blacklist_max_s := 15.0  ## …up to this

@export_group("Movement")
@export var arrive_rat := 0.3  ## m: a waypoint counts as reached
@export var arrive_supervisor := 0.4
@export var slow_radius := 1.5  ## m before the end of a path: walk, don't sprint
@export var stuck_check_s := 0.5  ## progress is compared this often…
@export var stuck_min_progress := 0.15  ## …and less than this (m) while moving counts as stuck
@export var stuck_fail_s := 6.0  ## stuck this long: the goal fails
@export var avoid_radius := 0.8  ## m: a teammate this close ahead…
@export var avoid_shift := 0.4  ## …shifts the steering this much sideways
@export var hold_still_speed := 0.2  ## m/s: slower than this before starting a hold
@export var door_grace_s := 1.0  ## an opening door doesn't count as stuck for this long

@export_group("Rats")
@export var flee_radius := 7.0  ## m: a known supervisor closer than this (and closing) → flee
@export var flee_search_radius := 20.0  ## m: escape spots (vents, vent exits) within this
@export var flee_candidates := 6
@export var flee_min_s := 2.5  ## flee at least this long once started
@export var sabotage_supervisor_radius := 8.0  ## a known supervisor this near a target lowers its score
@export var lever_wait_s := 15.0  ## the first rat at a lever waits this long for its partner
@export var harass_keep_away := 3.0  ## m: while the bite cools down
@export var free_safe_radius := 10.0  ## m: no known supervisor this near a cage before freeing
@export var squeak_chance := 0.25  ## after a sabotage, and now and then while lurking

@export_group("Supervisors")
@export var chase_radius := 12.0  ## m: a known rat closer than this can be chased
@export var chase_give_up := 6.0  ## m: a fleeing rat farther than this isn't worth chasing (rats are faster)
@export var swing_margin := 0.2  ## m added to the broom's range for the reflex
@export var swing_cone_deg := 30.0  ## the reflex swings when the rat is within this of the facing
@export var carry_spare_s := 1.5  ## a grab only if a cage is reachable before the carry ends, with this to spare
@export var patrol_revisit_s := 60.0  ## a room not visited for this long is worth a full patrol score


static func load_default() -> BotTuning:
	return load(PATH)


## The preset for MatchRules.bot_difficulty (0 easy, 1 normal, 2 hard), clamped.
func skill(difficulty: int) -> BotSkill:
	return skills[clampi(difficulty, 0, skills.size() - 1)]
