class_name AiGoal
extends RefCounted
## One thing an AI bot can decide to do (M10): a small state machine scored by utility. AiBot asks
## every goal for its score() at the bot's think rate and runs the best one: start(), then tick()
## every physics tick until it returns DONE or FAILED (or a better goal takes over: stop()).
## score() also picks the goal's target (the best machine, the nearest cage…), which start() uses.
## Scores are about 0..1 (AiScoring); the running goal gets BotTuning.commitment_bonus on top.
## A goal acts only through ctx.driver and knows enemies only through ctx.senses.

enum Result { RUNNING, DONE, FAILED }

var ctx: AiContext
var id := "Goal"  ## the name in logs and --ai-goals ("Sabotage", "Repair"…)
var target_label := ""  ## what it is about right now ("pumps"…), for the label
var reflex := false  ## a reflex goal (flee, rescue): a big enough score interrupts at once, between thinks


func _init(p_ctx: AiContext) -> void:
	ctx = p_ctx


## How much the bot wants this now (0 = not at all). Picks the target too.
func score() -> float:
	return 0.0


func start() -> void:
	pass


func tick(_delta: float) -> Result:
	return Result.DONE


## Another goal takes over, or the match stopped: let go of everything.
func stop() -> void:
	ctx.driver.stop_hold()
	ctx.driver.stop()


## Renews (or takes) a team claim for this bot. False if another bot has it.
func claim(key: String) -> bool:
	return ctx.board.claim(key, ctx.peer, ctx.now, ctx.tuning.claim_ttl_s)


func release(key: String) -> void:
	ctx.board.release(key, ctx.peer)


func label() -> String:
	return "%s(%s)" % [id, target_label] if target_label != "" else id
