class_name AiGoalPlaceTrap
extends AiGoal
## Supervisor: lay a trap where rats will step (GDD §5.1): snap traps on the rats' stand spots at the
## most valuable machines and levers, cheese lures a metre into the room from the vent exits near
## those targets and near the cages (AiDirector.World.trap_spots). 3 charges shared by both kinds;
## ItemService checks the rest (within 2 m, on the floor, in sight, 0.6 m from another trap). A spot
## within trap_spot_spacing of a trap already there is done; one bot per spot (its claim key).
## Walks next to the spot, faces it and places the trap.

const PLACE_FROM := 1.4  ## m (flat): place from this close (ItemService allows 2.0 + 0.5)
const PATHED := 5  ## spots that get a real path length each think (the best guesses)
const STRAIGHT_TO_PATH := 1.4  ## a path is about this much longer than the straight line

var spot: Dictionary = {}  ## the running goal's spot
var _stand := Vector3.INF
var _pick: Dictionary = {}  # score()'s choice, which start() takes


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "PlaceTrap"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = {}
	var charges := ctx.body.inventory.trap_charges
	if charges <= 0 or ctx.body.status.carrying != 0:
		return 0.0
	var traps := ctx.world.traps()
	var here := ctx.body.global_position
	var walk := ctx.body.role_data.walk_speed
	# The most promising spots by a straight-line guess first: only those get a real path.
	var open: Array[Dictionary] = []
	for candidate: Dictionary in ctx.world.trap_spots(ctx.nav, ctx.plant()):
		var key: String = candidate["key"]
		if not (ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key) or _taken(candidate["pos"], traps)):
			open.append(candidate)
	var guess := func(c: Dictionary) -> float:
		return AiScoring.place_trap(c["value"], here.distance_to(c["pos"]) * STRAIGHT_TO_PATH / walk, charges)
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return guess.call(a) > guess.call(b))
	var best := 0.0
	for candidate in open.slice(0, PATHED):
		var key: String = candidate["key"]
		var t := ctx.path_time(_stand_near(candidate["pos"]), key)
		var s := AiScoring.place_trap(candidate["value"], t, charges)
		if s > best:
			best = s
			_pick = candidate
	return best


## A trap already lies near `pos`.
func _taken(pos: Vector3, traps: Array[Trap]) -> bool:
	for trap in traps:
		if trap.global_position.distance_to(pos) < ctx.tuning.trap_spot_spacing:
			return true
	return false


## Where the supervisor stands to place a trap at `pos`: the nearest point of its mesh.
func _stand_near(pos: Vector3) -> Vector3:
	return ctx.nav.snap(Role.Kind.SUPERVISOR, pos)


func start() -> void:
	spot = _pick
	target_label = "%s at %s" % ["snap" if spot.get("kind") == &"snap_trap" else "lure",
		(spot.get("pos", Vector3.ZERO) as Vector3).snapped(Vector3.ONE)]
	_stand = _stand_near(spot["pos"]) if not spot.is_empty() else Vector3.INF


func tick(_delta: float) -> Result:
	if spot.is_empty() or _stand == Vector3.INF:
		return Result.FAILED
	var key: String = spot["key"]
	if not claim(key):
		return Result.FAILED
	if ctx.body.inventory.trap_charges <= 0:
		return Result.DONE
	var pos: Vector3 = spot["pos"]
	if _taken(pos, ctx.world.traps()):
		return Result.DONE  # a teammate (or a human) put one there
	var here := ctx.body.global_position
	var driver := ctx.driver
	driver.go_to(_stand, false, 0.6)
	if driver.failed():
		ctx.blacklist(key)
		return Result.FAILED
	if Vector2(here.x - pos.x, here.z - pos.z).length() > PLACE_FROM and not driver.arrived():
		return Result.RUNNING
	driver.stop()
	driver.face(pos)
	if not ctx.body.abilities.server_ready(spot["kind"]):
		return Result.RUNNING
	var reason := driver.place_trap(spot["kind"], pos)
	if reason == "":
		ctx.log_line("placed a %s at %s" % ["snap trap" if spot["kind"] == &"snap_trap" else "cheese lure", pos.snapped(Vector3.ONE * 0.1)])
		return Result.DONE
	ctx.blacklist(key)  # not on a floor, out of sight, too close to another trap…
	return Result.FAILED


func stop() -> void:
	super()
	if not spot.is_empty():
		release(spot["key"])
