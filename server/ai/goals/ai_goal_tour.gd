class_name AiGoalTour
extends AiGoal
## --ai-scenario tour (M10, phase B): walk to each target of this bot's share (AiDirector._plan_tour),
## nearest first, and report each one reached or not. A target counts as reached when the bot stands
## where a player would use it: within reach and in sight (can_interact may only say it's unavailable).

const TIMEOUT_S := 45.0  ## per target

var targets: Array = []  ## [{"name", "pos", "node"}]
var _current: Dictionary = {}
var _since := 0.0
var _finished := false
var _in_order := false


func _init(p_ctx: AiContext, p_targets: Array, p_in_order: bool = false) -> void:
	super(p_ctx)
	id = "Tour"
	targets = p_targets.duplicate()
	_in_order = p_in_order


func score() -> float:
	return 0.0 if _finished else 2.0


func tick(_delta: float) -> Result:
	if _finished:
		return Result.DONE
	if _current.is_empty():
		_next()
		if _finished:
			return Result.DONE
	var pos: Vector3 = _current["pos"]
	ctx.driver.go_to(pos, false, 0.3)
	if ctx.driver.arrived():
		var reason := _check_reach()
		if reason == "":
			ctx.director.tour_result(ctx.bot, _current["name"], true)
		else:
			ctx.director.tour_result(ctx.bot, _current["name"], false, reason)
		_current = {}
	elif ctx.driver.failed() or ctx.now - _since > TIMEOUT_S:
		var why := "%s at %s, target %s" % [ctx.driver.fail_reason if ctx.driver.failed() else "timed out",
			ctx.body.global_position.snapped(Vector3.ONE * 0.1), (_current["pos"] as Vector3).snapped(Vector3.ONE * 0.1)]
		ctx.director.tour_result(ctx.bot, _current["name"], false, why)
		_current = {}
	return Result.RUNNING


## "" if the bot could use the target from where it stands.
func _check_reach() -> String:
	var node := _current["node"] as Interactable
	if node == null:
		return ""
	var reason := node.can_interact(ctx.body)
	return "" if reason in ["", "not available"] else reason


func _next() -> void:
	ctx.driver.stop()
	if targets.is_empty():
		_finished = true
		ctx.director.tour_finished(ctx.bot)
		return
	var here := ctx.body.global_position
	var best := 0
	for i in targets.size() if not _in_order else 0:
		if (targets[i]["pos"] as Vector3).distance_to(here) < (targets[best]["pos"] as Vector3).distance_to(here):
			best = i
	_current = targets.pop_at(best)
	target_label = _current["name"]
	_since = ctx.now
