class_name AiGoalRepair
extends AiGoal
## Supervisor: repair a damaged machine (GDD §4.4). Machine health and offline machines are on the HUD
## for everyone. AiScoring.repair: how broken × heat weight, ×2 offline, the alarm level, the walk.
## Skips a machine a teammate bot claimed ("repair:<sub>") or a human is fixing (someone holds its
## repair point, or plays its minigame). At the repair point: reboot first if it's offline (3 s), then
## hold-repair (6 s, +35) again while it needs it; a jammed point is waited out. Bots never play the
## minigames: the server accepts the hold repair whatever the setting.

var point: RepairPoint
var _key := ""
var _holding := false


func _init(p_ctx: AiContext) -> void:
	super(p_ctx)
	id = "Repair"
	rescore_s = AiGoal.STRATEGIC_RESCORE_S


func score() -> float:
	point = null
	var best := 0.0
	var plant := ctx.plant()
	for rp in ctx.world.repair_points:
		if rp.index == -1 or not rp.needs_repair():
			continue
		var key := "repair:%s" % rp.subsystem_id
		if ctx.board.claimed_by_other(key, ctx.peer, ctx.now) or ctx.blacklisted(key) or _human_at(rp):
			continue
		var t := ctx.path_time(ctx.world.stand(rp, Role.Kind.SUPERVISOR), "rep%d" % rp.get_instance_id())
		var s := AiScoring.repair(plant.data(rp.index).heat_weight, plant.health(rp.index), plant.needs_reboot(rp.index),
			plant.alarm, t)
		if s > best:
			best = s
			point = rp
	return best


## A human supervisor is fixing it already.
func _human_at(rp: RepairPoint) -> bool:
	if rp.minigame_user != 0 and not Session.is_ai_id(rp.minigame_user):
		return true
	for peer: int in rp.holders:
		if not Session.is_ai_id(peer):
			return true
	return false


func start() -> void:
	_key = "repair:%s" % point.subsystem_id
	target_label = String(point.subsystem_id)
	_holding = false


func tick(_delta: float) -> Result:
	if point == null:
		return Result.FAILED
	if not point.needs_repair():
		return Result.DONE
	if not claim(_key) or (not _holding and _human_at(point)):
		return Result.FAILED
	var driver := ctx.driver
	if not _holding:
		var stand := ctx.world.stand(point, Role.Kind.SUPERVISOR)
		var urgent := ctx.plant().needs_reboot(point.index) or ctx.body.global_position.distance_to(stand) > 20.0
		driver.go_to(stand, urgent, 0.4)
		if driver.failed():
			ctx.blacklist(_key)
			return Result.FAILED
		if driver.arrived():
			driver.face(point.global_position)
			if point.lockout_left() <= 0.0:
				driver.hold(point)
				_holding = true
		return Result.RUNNING
	if driver.hold_state != AiDriver.Hold.ENDED:
		return Result.RUNNING
	_holding = false  # completed (repaired or rebooted): go again while it needs it; else retry
	if driver.hold_reason != "completed" and not driver.hold_reason.contains("not available"):
		if driver.hold_reason.begins_with("refused"):
			ctx.blacklist(_key)
		return Result.FAILED
	return Result.RUNNING if point.needs_repair() else Result.DONE


func stop() -> void:
	super()
	release(_key)
