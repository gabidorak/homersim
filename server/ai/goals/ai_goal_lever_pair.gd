class_name AiGoalLeverPair
extends AiGoal
## Rat: a critical sabotage with a partner (GDD §4.3): both levers of the control rods or the turbine
## held together for 6 s. Teamwork (the skill's `teamwork`): easy bots don't do it.
##   - A lever a human rat holds alone is a standing request: take the other one.
##   - A pair a teammate bot opened (AiBlackboard lever pairs) is waiting: join it.
##   - Otherwise open a pair, if a free rat teammate could come.
## The first rat there holds and waits for its partner, lever_wait_s at most.

var sub: StringName = &""
var side := ""
var lever: CriticalLever
var _holding := false
var _hold_since := 0.0


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "LeverPair"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


## The two levers of each critical subsystem: {subsystem: {"A": lever, "B": lever}}.
func _pairs() -> Dictionary:
	var out := {}
	for l in ctx.world.levers:
		if not out.has(l.subsystem_id):
			out[l.subsystem_id] = {}
		out[l.subsystem_id][String(l.name).trim_prefix("Lever")] = l
	return out


func score() -> float:
	if not ctx.skill.teamwork:
		return 0.0
	var best := 0.0
	var plant := ctx.plant()
	var pairs := _pairs()
	for s: StringName in pairs:
		var pair: Dictionary = pairs[s]
		if not pair.has("A") or not pair.has("B"):
			continue
		var a: CriticalLever = pair["A"]
		if a.index == -1 or not plant.can_sabotage(a.index) or ctx.blacklisted("lever:%s" % s):
			continue
		var wanted := _wanted_side(s, pair)
		if wanted == "":
			continue
		var partner := _partner_chance(s, pair)
		var stand := ctx.stand_for(pair[wanted])
		if stand == Vector3.INF:
			continue
		var t := ctx.path_time(stand, "lever%d" % (pair[wanted] as Node).get_instance_id())
		var value := AiScoring.lever_pair(plant.data(a.index).heat_weight, plant.health(a.index), t, partner,
			ctx.danger_at(stand))
		if value > best:
			best = value
			sub = s
			side = wanted
			lever = pair[wanted]
	return best


## The side this bot would take: its own, the one a human or a bot waits on, else the nearer one.
func _wanted_side(s: StringName, pair: Dictionary) -> String:
	var mine := ctx.board.lever_side(s, ctx.peer)
	if mine != "":
		return mine
	for held: String in ["A", "B"]:
		var other := "B" if held == "A" else "A"
		if _human_holds(pair[held]) and (pair[other] as CriticalLever).holder_count == 0:
			return other
	var waiting := ctx.board.lever_waiting_side(s)
	if waiting != "":
		return waiting
	if ctx.board.pairs.has(s):
		return ""  # full
	var here := ctx.body.global_position
	return "A" if (pair["A"] as Node3D).global_position.distance_to(here) <= (pair["B"] as Node3D).global_position.distance_to(here) else "B"


## Above 1 when someone already waits for us, 0.6 when a free teammate bot could come, 0.35 when
## only a human could (it may not), else 0.
func _partner_chance(s: StringName, pair: Dictionary) -> float:
	if ctx.board.lever_partner(s, ctx.peer) != 0 or ctx.board.lever_waiting_side(s) != "":
		return 1.15
	for l: CriticalLever in [pair["A"], pair["B"]]:
		if _human_holds(l):
			return 1.15
	var chance := 0.0
	for mate in ctx.teammates():
		if not mate.status.can_act() or mate.status.has(StatusComponent.Status.CAGED):
			continue
		if not mate.is_bot:
			chance = maxf(chance, 0.35)
		elif ctx.board.lever_side(s, mate.peer_id) == "" and not _in_other_pair(mate.peer_id, s):
			chance = 0.6
	return chance


func _in_other_pair(peer: int, except: StringName) -> bool:
	for s: StringName in ctx.board.pairs:
		if s != except and ctx.board.lever_side(s, peer) != "":
			return true
	return false


## A human rat (not a bot) holds `l`.
func _human_holds(l: CriticalLever) -> bool:
	for peer: int in l.holders:
		if not Session.is_ai_id(peer):
			return true
	return false


func start() -> void:
	target_label = "%s:%s" % [sub, side]
	_holding = false
	if not ctx.board.lever_take(sub, ctx.peer, side, ctx.now, ctx.tuning.lever_wait_s + 30.0):
		lever = null


func tick(_delta: float) -> Result:
	if lever == null or not ctx.plant().can_sabotage(lever.index):
		return Result.DONE if lever != null else Result.FAILED
	claim("lever:%s:%s" % [sub, side])
	var driver := ctx.driver
	if not _holding:
		var stand := ctx.stand_for(lever)
		if stand == Vector3.INF:
			ctx.blacklist("lever:%s" % sub)
			return Result.FAILED
		driver.go_to(stand, false, 0.3)
		if driver.failed():
			ctx.blacklist("lever:%s" % sub)
			return Result.FAILED
		if driver.arrived():
			driver.hold(lever)
			_holding = true
			_hold_since = ctx.now
		return Result.RUNNING
	if driver.hold_state == AiDriver.Hold.ENDED:
		return Result.DONE if driver.hold_reason == "completed" else Result.FAILED
	# Holding: wait for the partner, but not forever.
	if lever.partner != null and lever.partner.holder_count > 0:
		_hold_since = ctx.now
	elif ctx.now - _hold_since > ctx.tuning.lever_wait_s:
		ctx.log_line("nobody came to the other %s lever" % sub)
		ctx.blacklist("lever:%s" % sub)
		return Result.FAILED
	return Result.RUNNING


func stop() -> void:
	super()
	if sub != &"":
		ctx.board.lever_leave(sub, ctx.peer)
		release("lever:%s:%s" % [sub, side])
