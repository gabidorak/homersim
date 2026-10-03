class_name AiGoalLurk
extends AiGoal
## Rat, the default: wait in a vent (or at a vent exit) near the machine whose sabotage cooldown ends
## first, ready to pounce; squeak now and then (squeak_chance every SQUEAK_EVERY_S).

const SQUEAK_EVERY_S := 9.0

var _spot := Vector3.INF
var _next_squeak := 0.0
var _failures := 0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Lurk"


func score() -> float:
	return AiScoring.LURK


func start() -> void:
	_failures = 0
	_spot = _pick_spot()
	_next_squeak = ctx.now + SQUEAK_EVERY_S * ctx.rng.randf_range(0.5, 1.5)


func tick(_delta: float) -> Result:
	if _spot == Vector3.INF:
		return Result.FAILED
	ctx.driver.go_to(_spot, false, 0.6)
	if ctx.driver.failed():
		_failures += 1
		_spot = _pick_spot() if _failures < 3 else Vector3.INF
	elif ctx.driver.arrived() and ctx.now >= _next_squeak:
		_next_squeak = ctx.now + SQUEAK_EVERY_S * ctx.rng.randf_range(0.5, 1.5)
		if ctx.rng.randf() < ctx.tuning.squeak_chance:
			ctx.driver.emote()
	return Result.RUNNING


## A vent spot near the sabotage point whose machine is ready again first.
func _pick_spot() -> Vector3:
	var plant := ctx.plant()
	var next: SabotagePoint = null
	var soonest := INF
	for p in ctx.world.sabotage_points:
		if p.index == -1 or plant.health(p.index) <= 0.0:
			continue
		var left := plant.cooldown_left(p.index) + ctx.rng.randf() * 3.0
		if left < soonest:
			soonest = left
			next = p
	var near := next.global_position if next != null else ctx.body.global_position
	var spots: Array[Vector3] = []
	spots.append_array(ctx.world.vent_spots)
	spots.append_array(ctx.world.vent_exits)
	if spots.is_empty():
		return Vector3.INF
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(near) < b.distance_to(near))
	target_label = String(next.subsystem_id) if next != null else ""
	return spots[ctx.rng.randi_range(0, mini(2, spots.size() - 1))]
