class_name BreakerSequence
extends Minigame
## Power grid and ventilation: six breakers; a sequence of 4–5 of them flashes, then flip them in
## the same order. One wrong breaker loses, and so does taking too long.

enum Phase { SHOW, INPUT }

const COUNT := 6
const COLUMNS := 3
const LEAD_S := 0.5  ## before the first flash
const FLASH_S := 0.45
const GAP_S := 0.15
const INPUT_LIMIT_S := 10.0

var sequence: Array[int] = []
var phase := Phase.SHOW
var next_index := 0  ## INPUT: how many breakers were flipped right so far
var _input_started := 0.0
var _lit := -1  # the breaker lit right now (SHOW), or the last one pressed (INPUT)
var _lit_good := true
var _lit_until := 0.0
var _autoplay_wait := 0.0


func instructions() -> String:
	return tr("Watch the breakers flash, then flip them in the same order") if phase == Phase.SHOW \
		else tr("Your turn: flip them in the same order (%d / %d)") % [next_index, sequence.size()]


func _setup() -> void:
	sequence.clear()
	var length := 4 if difficulty < 0.5 else 5
	var last := -1
	while sequence.size() < length:
		var pick := rng.randi_range(0, COUNT - 1)
		if pick != last:
			sequence.append(pick)
			last = pick
	phase = Phase.SHOW
	next_index = 0
	_lit = -1


func show_duration() -> float:
	return LEAD_S + sequence.size() * (FLASH_S + GAP_S)


func _tick(_delta: float) -> void:
	if phase == Phase.SHOW:
		var t := elapsed - LEAD_S
		var slot := floori(t / (FLASH_S + GAP_S)) if t >= 0.0 else -1
		_lit = sequence[slot] if slot >= 0 and slot < sequence.size() and fmod(t, FLASH_S + GAP_S) < FLASH_S else -1
		_lit_good = true
		if elapsed >= show_duration():
			phase = Phase.INPUT
			_input_started = elapsed
			_lit = -1
	elif elapsed - _input_started >= INPUT_LIMIT_S:
		_finish(false)
	if phase == Phase.INPUT and elapsed > _lit_until:
		_lit = -1


## The player flips breaker `index` (ignored while the sequence is still being shown).
func press_breaker(index: int) -> void:
	if done or phase != Phase.INPUT or index < 0 or index >= COUNT:
		return
	_lit = index
	_lit_until = elapsed + 0.25
	_lit_good = index == sequence[next_index]
	if not _lit_good:
		_finish(false)
		return
	next_index += 1
	if next_index >= sequence.size():
		_finish(true)


func autoplay(delta: float) -> void:
	if phase != Phase.INPUT:
		return
	_autoplay_wait -= delta
	if _autoplay_wait <= 0.0:
		_autoplay_wait = 0.3
		press_breaker(sequence[next_index])


func breaker_rect(index: int) -> Rect2:
	var rows := ceili(COUNT / float(COLUMNS))
	var cell := Vector2(size.x * 0.8 / COLUMNS, size.y * 0.7 / rows)
	var origin := Vector2(size.x * 0.1, size.y * 0.15)
	var col := index % COLUMNS
	var row := floori(index / float(COLUMNS))
	return Rect2(origin + Vector2(col * cell.x, row * cell.y), cell).grow(-minf(cell.x, cell.y) * 0.12)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in COUNT:
		if breaker_rect(i).has_point(button.position):
			press_breaker(i)
			accept_event()
			return


func _draw() -> void:
	for i in COUNT:
		var rect := breaker_rect(i)
		var lit := i == _lit
		var color := Color(0.2, 0.22, 0.26)
		if lit:
			color = (Color(1, 0.85, 0.2) if phase == Phase.SHOW else (GOOD if _lit_good else BAD))
		draw_rect(rect, color)
		draw_rect(rect, Color(0.05, 0.05, 0.06), false, 3.0)
		# The switch lever: up when lit / flipped.
		var lever := Rect2(rect.position + rect.size * Vector2(0.4, 0.2 if lit else 0.5), rect.size * Vector2(0.2, 0.3))
		draw_rect(lever, Color(0.85, 0.85, 0.9))
		_text(rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.95), str(i + 1), _font(0.045))
	if phase == Phase.INPUT:
		var left := maxf(INPUT_LIMIT_S - (elapsed - _input_started), 0.0)
		_text(Vector2(size.x * 0.5, size.y * 0.97), "%.0f s" % left, _font(0.05))
