class_name AiContext
extends RefCounted
## Everything one AI bot's goals work with (M10): its body, driver, senses and team blackboard, the
## level's targets (AiDirector.World), the tuning, its skill and its own random numbers.
## Clocks: `now` is Time.get_ticks_msec() in seconds (the AI's own timers); synced cooldowns
## (ConsoleAction.ready_at, RepairPoint.lockout_until, hazards) are on Net.server_time(). Never mix them.
## Teammates are fair game (the map shows your own team); enemies are only known through `senses`.

const PATH_CACHE_S := 4.0  ## a cached path length is reused this long (± a quarter: staggered)…
const PATH_CACHE_MOVE := 8.0  ## …unless the bot moved this far since (a path costs ~150 µs)
const TEAMMATES_S := 0.5  ## teammates() is gathered this often
const STAND_FOR_S := 0.3  ## stand_for() is worked out again this often
const SIDE_STEP := 0.7  ## m: a stand spot with a trap on it is swapped for one this far to the side
const TRAP_STAND_CLEAR := 0.55  ## m from a trap's centre: a rat standing there doesn't set it off
const CALM_HEALTH := 75.0  ## every machine at least this healthy: the plant is calm
const CALM_RAT_M := 15.0  ## …and no rat known this close

var bot: AiBot
var peer := 0
var body: Player
var role := Role.Kind.NONE
var session: Session
var director: AiDirector
var world: AiDirector.World
var nav: AiNav
var driver: AiDriver
var senses: AiSenses
var board: AiBlackboard
var tuning: BotTuning
var skill: BotSkill
var rng := RandomNumberGenerator.new()
var now := 0.0

var _paths: Dictionary = {}  # key -> [length, from, until]
var _stand_for: Dictionary = {}  # node instance id -> [spot, until]
var _teammates: Array[Player] = []
var _teammates_until := -INF
var _blacklist: Dictionary = {}  # key -> until


func plant() -> PlantSim:
	return session.plant


func playing() -> bool:
	return session.match_manager.state == MatchManager.State.PLAYING


## Path metres from the body to `to` (INF if unreachable), cached under `key` for a few seconds.
func path_length(to: Vector3, key: String = "") -> float:
	var from := body.global_position
	if key != "" and _paths.has(key):
		var entry: Array = _paths[key]
		if now < float(entry[2]) and from.distance_to(entry[1]) < PATH_CACHE_MOVE:
			return entry[0]
	var path := nav.path(role, from, to, has_keycard())
	var length := INF
	if not path.is_empty() and _flat_distance(path.end(), to) < 1.0 and absf(path.end().y - to.y) < 0.6:
		length = path.length
	if key != "":
		_paths[key] = [length, from, now + PATH_CACHE_S * rng.randf_range(0.75, 1.25)]  # (staggered: no burst of queries)
	return length


## Seconds to walk to `to` (INF if unreachable).
func path_time(to: Vector3, key: String = "") -> float:
	return path_length(to, key) / body.role_data.walk_speed


func has_keycard() -> bool:
	return role == Role.Kind.SUPERVISOR and body.inventory.keycard


## `key` (a target a goal failed on) is skipped until a random time in the blacklist range.
func blacklist(key: String) -> void:
	_blacklist[key] = now + rng.randf_range(tuning.blacklist_min_s, tuning.blacklist_max_s)
	log_line("blacklisted %s" % key)


func blacklisted(key: String) -> bool:
	return now < float(_blacklist.get(key, -INF))


## The other living bodies of our team (bots and humans), gathered again every TEAMMATES_S.
func teammates() -> Array[Player]:
	if now < _teammates_until and _all_alive(_teammates):
		return _teammates
	_teammates_until = now + TEAMMATES_S
	var out := _teammates
	out.clear()
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p != body and p.role == role and not p.is_queued_for_deletion() \
				and not p.status.has(StatusComponent.Status.ELIMINATED):
			out.append(p)
	return out


## None of `bodies` was freed or is going (untyped: a freed object can't be read as a Player).
static func _all_alive(bodies: Array) -> bool:
	for body: Variant in bodies:
		if not is_instance_valid(body) or (body as Node).is_queued_for_deletion():
			return false
	return true


func can_act() -> bool:
	return body.status.can_act() and not body.movement.locked


## Where this bot stands to use `node`: its stand position, or a spot beside it (still in reach) when
## a trap this rat noticed or an active steam jet / puddle is on it. INF when no spot is clear.
## Kept STAND_FOR_S (goals ask every tick).
func stand_for(node: Interactable) -> Vector3:
	var id := node.get_instance_id()
	var cached: Array = _stand_for.get(id, [])
	if not cached.is_empty() and now < float(cached[1]):
		return cached[0]
	var spot := _stand_for_now(node)
	_stand_for[id] = [spot, now + STAND_FOR_S]
	return spot


func _stand_for_now(node: Interactable) -> Vector3:
	var spot := world.stand(node, role)
	if _clear_spot(spot):
		return spot
	var out := Vector3(node.global_basis.z.x, 0.0, node.global_basis.z.z).normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var reach := node.reach_for(role) + Interactable.LAG_TOLERANCE - 0.3
	for offset: Vector3 in [side * SIDE_STEP, -side * SIDE_STEP, side * SIDE_STEP + out * 0.3, -side * SIDE_STEP + out * 0.3]:
		var want := spot + offset
		var alt := nav.closest_point(role, want)
		if _flat_distance(alt, want) < 0.25 and absf(alt.y - spot.y) < 0.4 and _clear_spot(alt) \
				and (alt + Vector3.UP * body.role_data.height * 0.5).distance_to(node.global_position) <= reach:
			return alt
	return Vector3.INF


func _clear_spot(spot: Vector3) -> bool:
	if role == Role.Kind.RAT and senses.trap_near(spot, TRAP_STAND_CLEAR):
		return false
	return world.hazards.blocking(spot, INF, 0.3) == null  # (INF: any active jet or puddle)


## Rats: how dangerous `pos` is (0..1): a supervisor we know of (seen, heard, called out, in the last
## danger_memory_s) within danger_radius of it, the closer the worse; a knocked-down or seated one
## counts less. A trap we noticed there adds a little. At the start of a match, the supervisors' spawn
## (the Break Room: everyone knows it, GDD §3) is dangerous too, less and less for opening_danger_s.
func danger_at(pos: Vector3) -> float:
	var worst := 0.0
	var since := now - director.playing_since
	if since < tuning.opening_danger_s:
		# Full danger within half the radius for the first half of the time, fading out after that.
		var fade := clampf(2.0 - 2.0 * since / tuning.opening_danger_s, 0.0, 1.0)
		var half := tuning.opening_danger_radius * 0.5
		for spawn in director.spawn_spots(Role.Kind.SUPERVISOR):
			var near := clampf((tuning.opening_danger_radius - spawn.distance_to(pos)) / half, 0.0, 1.0)
			worst = maxf(worst, near * fade)
	for k in senses.enemies():
		if k.age(now) > tuning.danger_memory_s:
			continue
		var d := k.pos.distance_to(pos)
		if d >= tuning.danger_radius:
			continue
		var level := 1.0 - d / tuning.danger_radius
		if k.knocked or k.seated:
			level *= 0.4
		elif k.age(now) > 3.0:
			level *= 0.7
		worst = maxf(worst, level)
	if senses.trap_near(pos, 3.0):
		worst = maxf(worst, 0.3)
	return worst


## Supervisors: nothing needs us right now (the alarm is normal, no machine is offline or badly hurt,
## no rat known close by): time for the CCTV, a trap refill.
func calm() -> bool:
	var plant := plant()
	if plant.alarm != PlantModel.Alarm.NORMAL:
		return false
	for i in plant.count():
		if plant.needs_reboot(i) or plant.health(i) < CALM_HEALTH:
			return false
	return senses.nearest(CALM_RAT_M) == null


## A log line when the server runs with --ai-log.
func log_line(text: String) -> void:
	if director.log_decisions:
		Log.info("ai", "%s: %s" % [body.display_name, text])


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
