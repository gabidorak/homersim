class_name AiGoal
extends RefCounted
## One thing an AI bot can decide to do (M10): a small state machine scored by utility. AiBot asks
## every goal for its score() at the bot's think rate and runs the best one: start(), then tick()
## every physics tick until it returns DONE or FAILED (or a better goal takes over: stop()).
## score() also picks the goal's target (the best machine, the nearest cage…), which start() uses.
## Scores are about 0..1 (AiScoring); the running goal gets BotTuning.commitment_bonus on top.
## A goal acts only through ctx.driver and knows enemies only through ctx.senses.

enum Result { RUNNING, DONE, FAILED }

const STRATEGIC_RESCORE_S := 0.6

var ctx: AiContext
var id := "Goal"  ## the name in logs and --ai-goals ("Sabotage", "Repair"…)
var target_label := ""  ## what it is about right now ("pumps"…), for the label
var reflex := false  ## a reflex goal (flee, rescue): a big enough score interrupts at once, between thinks
## Strategic goals (where to sabotage, repair, lay a trap…) are scored again at most this often; 0 = at
## every think (goals that react to what the senses just saw). Scoring every target is the AI's main cost.
var rescore_s := 0.0

var _score := 0.0
var _scored_at := -INF


func _init(p_ctx: AiContext) -> void:
	ctx = p_ctx


## How much the bot wants this now (0 = not at all). Picks the target too.
func score() -> float:
	return 0.0


## score(), or its last result if that is less than rescore_s old (AiBot._think).
func cached_score(now: float) -> float:
	if now - _scored_at >= rescore_s:
		_score = score()
		_scored_at = now
	return _score


## The next cached_score() scores again (the goal just ended).
func rescore() -> void:
	_scored_at = -INF


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
