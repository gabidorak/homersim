class_name WrenchRhythm
extends Minigame
## Pumps and turbine: a marker sweeps back and forth along a bar; click while it is inside the
## green zone. Three hits in a row win (the zone moves after each hit). A miss resets the streak;
## the third miss, or running out of time, loses.

const HITS_TO_WIN := 3
const MISSES_TO_LOSE := 3
const TIME_LIMIT_S := 12.0

var marker := 0.0  ## 0..1 along the bar
var zone_center := 0.5
var zone_width := 0.2
var streak := 0
var misses := 0
var _direction := 1.0
var _speed := 0.7  ## bar lengths per second
var _flash := 0.0  # > 0: show the last press (green hit / red miss)
var _flash_good := false


func instructions() -> String:
	return "Click when the marker is in the green zone, %d times in a row" % HITS_TO_WIN


func _setup() -> void:
	marker = 0.0
	_direction = 1.0
	streak = 0
	misses = 0
	_speed = 0.6 + 0.35 * difficulty
	zone_width = 0.22 - 0.08 * difficulty
	_move_zone()


func _move_zone() -> void:
	# Somewhere new, not right under the marker.
	for attempt in 10:
		zone_center = rng.randf_range(zone_width * 0.5 + 0.04, 1.0 - zone_width * 0.5 - 0.04)
		if absf(zone_center - marker) > 0.25:
			return


func in_zone() -> bool:
	return absf(marker - zone_center) <= zone_width * 0.5


## The player clicks.
func press() -> void:
	if done:
		return
	_flash = 0.25
	_flash_good = in_zone()
	if _flash_good:
		streak += 1
		if streak >= HITS_TO_WIN:
			_finish(true)
		else:
			_move_zone()
	else:
		streak = 0
		misses += 1
		if misses >= MISSES_TO_LOSE:
			_finish(false)


func _tick(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	marker += _direction * _speed * delta
	if marker > 1.0:
		marker = 2.0 - marker
		_direction = -1.0
	elif marker < 0.0:
		marker = -marker
		_direction = 1.0
	if elapsed >= TIME_LIMIT_S:
		_finish(false)


func autoplay(_delta: float) -> void:
	if absf(marker - zone_center) < zone_width * 0.2:
		press()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		press()
		accept_event()


func _draw() -> void:
	var bar := Rect2(size.x * 0.08, size.y * 0.42, size.x * 0.84, size.y * 0.16)
	draw_rect(bar, Color(0.12, 0.13, 0.16))
	var zone := Rect2(bar.position.x + (zone_center - zone_width * 0.5) * bar.size.x, bar.position.y,
		zone_width * bar.size.x, bar.size.y)
	draw_rect(zone, GOOD.darkened(0.15))
	var x := bar.position.x + marker * bar.size.x
	var marker_color := Color.WHITE
	if _flash > 0.0:
		marker_color = GOOD if _flash_good else BAD
	draw_rect(Rect2(x - bar.size.y * 0.08, bar.position.y - bar.size.y * 0.25, bar.size.y * 0.16, bar.size.y * 1.5), marker_color)
	# The streak: three bolts to tighten; misses as red crosses.
	var r := size.y * 0.06
	for i in HITS_TO_WIN:
		var c := Vector2(size.x * 0.5 + (i - 1) * r * 3.0, size.y * 0.75)
		draw_circle(c, r, GOOD if i < streak else Color(0.3, 0.32, 0.36))
	_text(Vector2(size.x * 0.5, size.y * 0.92), "misses: %d / %d" % [misses, MISSES_TO_LOSE], _font(0.05),
		BAD if misses > 0 else TEXT_COLOR)
	_text(Vector2(size.x * 0.5, size.y * 0.25), "%.0f s" % maxf(TIME_LIMIT_S - elapsed, 0.0), _font(0.06))
