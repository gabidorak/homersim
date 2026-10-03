class_name AiBot
extends Node
## One AI bot (M10, ARCHITECTURE §6 AI bots), server only: AiDirector adds one per bot body when a
## match starts. It runs before the body's MovementComponent every physics tick (priority −10):
##   1. the senses update (AiSenses, at their own rate);
##   2. reflexes act at once: bite a carrier, swing the broom at a rat in reach, turn to a biter;
##   3. at the skill's think rate (staggered across bots) every goal is scored (AiScoring) and the
##      best one runs; the running goal gets a commitment bonus so bots don't flip-flop, and a
##      reflex goal (flee, rescue) with a big enough score interrupts between thinks;
##   4. the running goal's tick() asks the driver for actions;
##   5. the driver (AiDriver) writes the body's MoveIntent and sync_anim.
## The AI never moves the body itself and never skips a rule: everything goes through the same
## server checks as a player's requests. With --ai-log every change of goal is one log line
## ("Gus: Repair(pumps) 0.82 > Patrol 0.30").

const REFLEX_INTERRUPT := 0.8  ## a reflex goal scoring this much takes over before the next think
const RESCUE_BITE_M := 1.1  ## m from a carried teammate: its carrier is in bite reach
const RETRY_AFTER_FAIL_S := 1.5  ## a goal that just failed sits out this long

var director: AiDirector
var body: Player
var peer := 0
var ctx: AiContext
var goals: Array[AiGoal] = []
var current: AiGoal
## What this bot did this match, for AiDirector.report().
var stats: Dictionary = {}

var _next_think := 0.0
var _next_trace := 0.0
var _resting: Dictionary = {}  # goal -> until when it sits out (it just failed)


func setup(p_director: AiDirector, p_body: Player) -> void:
	director = p_director
	body = p_body
	peer = body.peer_id
	ctx = AiContext.new()
	ctx.bot = self
	ctx.peer = peer
	ctx.body = body
	ctx.role = body.role
	ctx.session = director.session
	ctx.director = director
	ctx.world = director.world
	ctx.nav = director.nav
	ctx.tuning = director.tuning
	ctx.skill = director.difficulty()
	ctx.board = director.boards[body.role]
	ctx.rng.seed = hash([director.seed_base, peer])  # each bot its own numbers, repeatable with --ai-seed
	ctx.driver = AiDriver.new()
	ctx.driver.setup(ctx)
	ctx.senses = AiSenses.new(ctx)
	goals = _make_goals()
	stats = {"name": body.display_name, "role": body.role, "distance": 0.0, "goals": {}, "decisions": 0,
		"stuck_hard": 0, "path_failures": 0, "max_stall_s": 0.0, "cpu_us": 0, "ticks": 0}


func _ready() -> void:
	process_physics_priority = -10  # before MovementComponent (0) and Player (10)
	body.movement.intent = ctx.driver.intent
	director.session.interactions.hold_ended.connect(_on_hold_ended)
	_next_think = _now() + ctx.rng.randf() / ctx.skill.think_hz  # staggered


func _exit_tree() -> void:
	if current != null:
		current.stop()
	ctx.driver.halt()
	director.forget(peer)
	# Break the reference cycles (context ↔ driver, senses, goals), or they leak.
	current = null
	goals.clear()
	ctx.driver.ctx = null
	ctx.senses.ctx = null
	ctx.driver = null
	ctx.senses = null


## --ai-scenario tour (and path): this bot only visits `targets`, nearest first (or `in_order`).
func start_tour(targets: Array, in_order: bool = false) -> void:
	goals = [AiGoalTour.new(ctx, targets, in_order)]
	current = null


func goal_label() -> String:
	return current.label() if current != null else "-"


func _make_goals() -> Array[AiGoal]:
	var list: Array[AiGoal] = []
	if body.role == Role.Kind.RAT:
		list = [AiGoalFlee.new(ctx), AiGoalRescueCarried.new(ctx), AiGoalSabotage.new(ctx), AiGoalLeverPair.new(ctx),
			AiGoalHarass.new(ctx), AiGoalFreeCaged.new(ctx), AiGoalLurk.new(ctx)]
	elif body.role == Role.Kind.SUPERVISOR:
		list = [AiGoalCapture.new(ctx), AiGoalChase.new(ctx), AiGoalRepair.new(ctx), AiGoalGuardCages.new(ctx),
			AiGoalPatrol.new(ctx)]
	var wanted: Array = director.only_goals.get(body.role, [])
	return list.filter(func(g: AiGoal) -> bool: return wanted.is_empty() or g.id in wanted)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.is_inside_tree():
		queue_free()
		return
	var started_us := Time.get_ticks_usec()
	_tick(delta)
	stats["cpu_us"] += Time.get_ticks_usec() - started_us
	stats["ticks"] += 1


func _tick(delta: float) -> void:
	ctx.now = _now()
	if not ctx.playing():
		if current != null:
			current.stop()
			current = null
		ctx.driver.halt()
		ctx.driver.tick(delta)
		return
	ctx.senses.update(ctx.now)
	if ctx.can_act():
		_reflexes()
	if ctx.now >= _next_think or _reflex_wants_in():
		_think()
	if current != null:
		stats["goals"][current.id] = float(stats["goals"].get(current.id, 0.0)) + delta
		var result := current.tick(delta)
		if result != AiGoal.Result.RUNNING:
			ctx.log_line("%s %s" % [current.label(), "done" if result == AiGoal.Result.DONE else "failed"])
			if result == AiGoal.Result.FAILED:
				_resting[current] = ctx.now + RETRY_AFTER_FAIL_S
			current.stop()
			current = null
			_next_think = ctx.now  # pick something else right away
	ctx.driver.tick(delta)
	if director.trace != "" and ctx.now >= _next_trace and (director.trace == "all" or director.trace == body.display_name):
		_next_trace = ctx.now + 0.25
		_log_trace()
	stats["distance"] = ctx.driver.distance
	stats["path_failures"] = ctx.driver.path_failures
	if ctx.driver.move_state == AiDriver.Move.MOVING and ctx.can_act():
		stats["max_stall_s"] = maxf(stats["max_stall_s"], ctx.driver.stuck.stalled_for(ctx.now))


## --ai-trace: where the bot is and what it is doing, for debugging a spot.
func _log_trace() -> void:
	var d := ctx.driver
	var f := d.follower
	var target := f.points[f.index] if not f.is_done() else Vector3.INF
	Log.info("ai", "trace %s: pos %s vel %s | intent %s%s%s | %s move %s, wp %d/%d -> %s link %s | floor %s wall %s climb %s" % [
		body.display_name, body.global_position.snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.1),
		d.intent.direction.snapped(Vector3.ONE * 0.01), " sprint" if d.intent.sprint else "", " jump" if d.intent.jump else "",
		goal_label(), AiDriver.Move.keys()[d.move_state], f.index, f.points.size(), target.snapped(Vector3.ONE * 0.01),
		AiPathFollower.LinkKind.keys()[f.current_link()], body.is_on_floor(), body.is_on_wall(), body.movement.climbing])


func _think() -> void:
	_next_think = ctx.now + 1.0 / ctx.skill.think_hz
	var best: AiGoal = null
	var best_score := 0.0
	var runner_up := ""
	var runner_score := 0.0
	for goal in goals:
		if ctx.now < float(_resting.get(goal, -INF)):
			continue
		var s := AiScoring.committed(goal.score(), goal == current, ctx.tuning.commitment_bonus)
		if s > best_score:
			if best != null:
				runner_up = best.label()
				runner_score = best_score
			best = goal
			best_score = s
		elif s > runner_score:
			runner_up = goal.label()
			runner_score = s
	if best == current:
		return
	stats["decisions"] += 1
	ctx.log_line("%s %.2f > %s %.2f" % [best.label() if best != null else "idle", best_score,
		runner_up if runner_up != "" else "-", runner_score])
	if current != null:
		current.stop()
	current = best
	if current != null:
		current.start()


## A reflex goal (flee, rescue) that just became urgent takes over without waiting for the next think.
func _reflex_wants_in() -> bool:
	for goal in goals:
		if goal.reflex and goal != current and ctx.now >= float(_resting.get(goal, -INF)) \
				and goal.score() >= REFLEX_INTERRUPT:
			return true
	return false


## Instant reactions, whatever the goal.
##   rats: bite the supervisor carrying a teammate next to us (one bite drops it)
##   supervisors: swing the broom at a rat this bot sees within reach, in front (the server clamps the
##     aim to 45° of the facing, so the body faces first: Chase and Capture turn toward rats); turn
##     toward whoever just bit us
func _reflexes() -> void:
	var here := body.global_position
	if body.role == Role.Kind.RAT:
		if not body.abilities.server_ready(&"bite"):
			return
		for mate in ctx.teammates():
			if mate.status.has(StatusComponent.Status.CARRIED) and mate.global_position.distance_to(here) <= RESCUE_BITE_M:
				if ctx.driver.use(&"bite", mate.global_position - here) == "":
					ctx.log_line("bit %s's carrier" % mate.display_name)
				return
		return
	if body.role != Role.Kind.SUPERVISOR:
		return
	var senses := ctx.senses
	if senses.bitten_by != 0 and ctx.now - senses.bitten_at < 1.5:
		var biter := senses.get_known(senses.bitten_by)
		if biter != null:
			ctx.driver.face(biter.pos)
	if body.status.carrying != 0 or not body.abilities.server_ready(&"broom"):
		return
	var broom := body.role_data.ability(&"broom")
	var facing := Vector2(-sin(body.rotation.y), -cos(body.rotation.y))
	for k in senses.enemies():
		if not k.visible or k.stunned:
			continue
		var to := Vector2(k.pos.x - here.x, k.pos.z - here.z)
		if to.length() > broom.range + ctx.tuning.swing_margin:
			break  # (nearest first)
		if absf(facing.angle_to(to)) > deg_to_rad(ctx.tuning.swing_cone_deg) and to.length() > HitCheck.POINT_BLANK:
			continue
		var error := deg_to_rad(ctx.rng.randf_range(-ctx.skill.aim_error_deg, ctx.skill.aim_error_deg))
		var aim := Vector3(to.x, 0.0, to.y).rotated(Vector3.UP, error)
		if ctx.driver.use(&"broom", aim) == "":
			ctx.log_line("swung at %s" % ctx.session.name_of(k.peer))
		return


func _on_hold_ended(who: int, path: NodePath, reason: String) -> void:
	if who == peer:
		ctx.driver.on_hold_ended(path, reason)
