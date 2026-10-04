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
@export var trap_notice_radius := 6.0  ## m: rats may notice a trap this close, in sight (BotSkill.trap_notice)
@export var cctv_range := 15.0  ## m: a seated supervisor sees rats this close to an unbroken camera's lens…
@export var cctv_fov_deg := 110.0  ## …inside its view (full angle)
@export var camera_seen_radius := 15.0  ## m: whether a camera is broken is seen from this close

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
@export var flee_radius := 10.0  ## m: a known supervisor closer than this (and closing) → flee
@export var flee_search_radius := 20.0  ## m: escape spots (vents, vent exits) within this
@export var flee_candidates := 6
@export var flee_min_s := 2.5  ## flee at least this long once started
@export var sabotage_supervisor_radius := 8.0  ## m: a known supervisor this near a camera or a cage: not now
@export var danger_radius := 16.0  ## m: a known supervisor this close to a target makes it less appealing…
@export var danger_memory_s := 15.0  ## …while it was seen (or heard) this recently
@export var opening_danger_s := 30.0  ## everyone knows supervisors start in the Break Room: rats keep away
@export var opening_danger_radius := 30.0  ## …from this far around it (fully within half), fading out over the second half of this long
@export var lever_wait_s := 15.0  ## the first rat at a lever waits this long for its partner
@export var harass_keep_away := 3.0  ## m: while the bite cools down
@export var free_safe_radius := 10.0  ## m: no known supervisor this near a cage before freeing
@export var squeak_chance := 0.25  ## after a sabotage, and now and then while lurking
@export var steal_radius := 10.0  ## m: a supervisor standing still, facing away, this close can be robbed
@export var camera_detour_s := 8.0  ## a camera this many seconds away is worth half as much (rats break them on the way)
@export var gang_radius := 12.0  ## m: two rat bots this close to the same supervisor bite it together…
@export var gang_s := 10.0  ## …for this long (renewed while they stay close)
@export var gang_cage_radius := 12.0  ## m: never start a fight this close to a cage (a stun there is a capture)
@export var trap_clearance := 0.6  ## m: a rat's path passes a trap it noticed at least this far
@export var sabotage_rest_s := 0.0  ## after a sabotage, a rat lurks this long before the next one (balance)

@export_group("Supervisors")
@export var chase_radius := 12.0  ## m: a known rat closer than this can be chased
@export var chase_give_up := 6.0  ## m: a fleeing rat farther than this isn't worth chasing (rats are faster)
@export var swing_margin := 0.2  ## m added to the broom's range for the reflex
@export var swing_cone_deg := 30.0  ## the reflex swings when the rat is within this of the facing
@export var carry_spare_s := 1.5  ## a grab only if a cage is reachable before the carry ends, with this to spare
@export var patrol_revisit_s := 60.0  ## a room not visited for this long is worth a full patrol score
@export var snap_radius := 25.0  ## m: a supervisor this close to a SNAP goes to look…
@export var snap_answer_s := 8.0  ## …while it is this recent
@export var investigate_radius := 35.0  ## m: a rat heard, called out or seen on CCTV this close is worth a look
@export var thief_chase_radius := 20.0  ## m: a rat seen stealing a keycard is chased this far
@export var trap_spot_spacing := 3.0  ## m: a new trap spot this close to another trap is taken already
@export var cctv_max_s := 20.0  ## a supervisor watches the cameras this long at most…
@export var cctv_rest_s := 45.0  ## …and not again for this long
@export var guard_cages_max_s := 25.0  ## a supervisor guards the occupied cages this long at most (on watch)…
@export var guard_cages_rest_s := 40.0  ## …then no supervisor bot guards them for this long (the rats' chance)
@export var coolant_temp := 650.0  ## core_temp above this: emergency coolant (if the grid has power)
@export var scram_temp := 760.0  ## core_temp above this, or meltdown above scram_meltdown: SCRAM (+30 s of shift)
@export var scram_meltdown := 50.0
@export var donut_detour_m := 12.0  ## a donut is worth this many metres out of the way

@export_group("Hazards")
@export var hazard_cross_s := 1.2  ## a bot waits at a steam jet or a puddle that is live, or goes live sooner than this
@export var radiation_limit_s := 3.0  ## exposure: a bot that isn't just passing through leaves the zone after this
@export var debris_margin := 0.6  ## m beyond the warning circle: step away from it


static func load_default() -> BotTuning:
	return load(PATH)


## The preset for MatchRules.bot_difficulty (0 easy, 1 normal, 2 hard), clamped.
func skill(difficulty: int) -> BotSkill:
	return skills[clampi(difficulty, 0, skills.size() - 1)]
