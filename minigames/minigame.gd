class_name Minigame
extends Control
## Base for the repair minigames (GDD §4.4, ARCHITECTURE §4 Minigames): short (about 4–6 s),
## mouse-only, readable at a glance. Client-side only: MinigameHost opens one when the server says
## so (open_minigame), and sends the outcome back; the server checks it (min duration, still there).
##
## Rules for every minigame:
##   - lay out from `size` every frame (anchors fill the host's panel), so any window size works;
##   - advance with real time (advance(delta)), never per frame;
##   - the puzzle comes from `rng`, seeded by the server, so it can't be pre-solved;
##   - Esc cancels (handled by the host);
##   - expose the player's actions as plain methods (press(), press_breaker(i)…), called by the
##     input handlers, by GUT tests, and by autoplay() for the headless test bots.

signal finished(success: bool)

const TEXT_COLOR := Color(0.92, 0.95, 1.0)
const GOOD := Color(0.35, 0.9, 0.4)
const BAD := Color(1.0, 0.3, 0.25)

var rng := RandomNumberGenerator.new()
var difficulty := 0.5  ## 0..1
var elapsed := 0.0
var done := false
var success := false


## Starts a new round. `p_difficulty` 0..1 (the host passes how damaged the subsystem is).
func start(p_seed: int, p_difficulty: float) -> void:
	rng.seed = p_seed
	difficulty = clampf(p_difficulty, 0.0, 1.0)
	elapsed = 0.0
	done = false
	_setup()
	queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Moves time forward (also called by tests).
func advance(delta: float) -> void:
	if done:
		return
	elapsed += delta
	_tick(delta)


## The one-line instruction the host shows above the minigame.
func instructions() -> String:
	return ""


## Test bots: play one step perfectly (called every frame instead of reading the mouse).
func autoplay(_delta: float) -> void:
	pass


func _finish(won: bool) -> void:
	if done:
		return
	done = true
	success = won
	finished.emit(won)


# --- Virtual ---------------------------------------------------------------------------------

func _setup() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


# --- Drawing helpers -------------------------------------------------------------------------------

func _text(pos: Vector2, text: String, font_size: int, color: Color = TEXT_COLOR) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, pos - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A font size that scales with the panel (readable from small windows to 4K).
func _font(fraction: float) -> int:
	return maxi(10, int(minf(size.x, size.y) * fraction))
