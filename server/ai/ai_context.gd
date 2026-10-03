class_name AiContext
extends RefCounted
## Everything one AI bot's goals work with (M10): its body, driver, senses and team blackboard, the
## level's targets (AiDirector.World), the tuning, its skill and its own random numbers.
## Clocks: `now` is Time.get_ticks_msec() in seconds (the AI's own timers); synced cooldowns
## (ConsoleAction.ready_at, RepairPoint.lockout_until, hazards) are on Net.server_time(). Never mix them.
## Teammates are fair game (the map shows your own team); enemies are only known through `senses`.

const PATH_CACHE_S := 3.0  ## a cached path length is reused this long…
const PATH_CACHE_MOVE := 4.0  ## …unless the bot moved this far since

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

var _paths: Dictionary = {}  # key -> [length, from, at]
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
		if now - float(entry[2]) < PATH_CACHE_S and from.distance_to(entry[1]) < PATH_CACHE_MOVE:
			return entry[0]
	var path := nav.path(role, from, to, has_keycard())
	var length := INF
	if not path.is_empty() and _flat_distance(path.end(), to) < 1.0 and absf(path.end().y - to.y) < 0.6:
		length = path.length
	if key != "":
		_paths[key] = [length, from, now]
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


## The other living bodies of our team (bots and humans).
func teammates() -> Array[Player]:
	var out: Array[Player] = []
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p != body and p.role == role and not p.is_queued_for_deletion() \
				and not p.status.has(StatusComponent.Status.ELIMINATED):
			out.append(p)
	return out


func can_act() -> bool:
	return body.status.can_act() and not body.movement.locked


## A log line when the server runs with --ai-log.
func log_line(text: String) -> void:
	if director.log_decisions:
		Log.info("ai", "%s: %s" % [body.display_name, text])


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
