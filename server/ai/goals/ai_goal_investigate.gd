class_name AiGoalInvestigate
extends AiGoal
## Supervisor: go and look where a rat gave itself away (M10 phase E):
##   snap    a snap trap went off within snap_radius (every supervisor hears the SNAP): a stunned
##           rat lies there, at a sprint (one bot per SNAP)
##   rat     a rat heard, called out by a teammate or seen on the CCTV, within investigate_radius,
##           out of Chase's reach (too far, or not seen for a moment); more when it was sabotaging
##   search  where a rat was last known before we lost track of it (AiSenses.searches)
## On the spot it looks around a moment; a rat in sight is Chase's and Capture's business.

const LOOK_S := 2.0
const OFF_MESH := 2.5  ## m from the supervisors' mesh: out of reach (a rat in a vent)

var spot := Vector3.INF  ## where the running goal goes
var kind := ""
var _key := ""
var _arrived_at := -1.0
var _best := 0.0
var _pick := {}  # score()'s choice, which start() takes


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Investigate"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	_pick = {}
	if ctx.body.status.carrying != 0:
		return 0.0
	var here := ctx.body.global_position
	_best = 0.0
	for e: Dictionary in ctx.board.events:
		if e["kind"] == "snap" and ctx.now - float(e["at"]) <= ctx.tuning.snap_answer_s:
			var pos: Vector3 = e["pos"]
			_consider(AiScoring.investigate("snap", pos.distance_to(here), ctx.tuning.snap_radius), pos, "snap",
				"snap:%d:%d" % [roundi(pos.x), roundi(pos.z)])
	for k in ctx.senses.enemies():
		if k.visible or k.age(ctx.now) > ctx.tuning.memory_s:
			continue
		var s := AiScoring.investigate("rat", k.pos.distance_to(here), ctx.tuning.investigate_radius, k.busy)
		if s > _best and _reachable(k.pos):  # (a mesh query: only for one that would win)
			_consider(s, k.pos, "rat", "look:%d" % k.peer)
	for trace: Dictionary in ctx.senses.searches:
		var pos: Vector3 = trace["pos"]
		var s := AiScoring.investigate("search", pos.distance_to(here), ctx.tuning.investigate_radius)
		if s > _best and _reachable(pos):
			_consider(s, pos, "search", "search:%d:%d" % [roundi(pos.x), roundi(pos.z)])
	return _best


func _consider(s: float, pos: Vector3, what: String, key: String) -> void:
	if s > _best and not ctx.board.claimed_by_other(key, ctx.peer, ctx.now) and not ctx.blacklisted(key):
		_best = s
		_pick = {"pos": pos, "kind": what, "key": key}


func _reachable(pos: Vector3) -> bool:
	var on_mesh := ctx.nav.snap(Role.Kind.SUPERVISOR, pos)
	return Vector2(on_mesh.x - pos.x, on_mesh.z - pos.z).length() < OFF_MESH and absf(on_mesh.y - pos.y) < 1.5


func start() -> void:
	spot = ctx.nav.snap(Role.Kind.SUPERVISOR, _pick["pos"]) if not _pick.is_empty() else Vector3.INF
	kind = _pick.get("kind", "")
	_key = _pick.get("key", "")
	target_label = kind
	_arrived_at = -1.0


func tick(_delta: float) -> Result:
	if spot == Vector3.INF:
		return Result.FAILED
	claim(_key)
	var driver := ctx.driver
	driver.go_to(spot, kind != "search", 1.0)
	if driver.failed():
		ctx.blacklist(_key)
		return Result.FAILED
	if driver.arrived():
		if _arrived_at < 0.0:
			_arrived_at = ctx.now
			ctx.blacklist(_key)  # looked there: not again right away
		# Look around: turn slowly through a full circle.
		var angle := (ctx.now - _arrived_at) / LOOK_S * TAU
		driver.face(ctx.body.global_position + Vector3(sin(angle), 0.0, cos(angle)))
		if ctx.now - _arrived_at > LOOK_S:
			return Result.DONE
	return Result.RUNNING


func stop() -> void:
	super()
	release(_key)
