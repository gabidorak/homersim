class_name ValveRotate
extends Minigame
## Coolant valves and control rods: drag the mouse in circles around the wheel to turn it until
## the needle sits in the green band, then keep it there for 1 s. Overshooting is fine: turn back.
## Clockwise opens. Taking too long loses.

const TOLERANCE := deg_to_rad(20.0)
const HOLD_S := 1.0
const TIME_LIMIT_S := 15.0
const AUTOPLAY_SPEED := TAU * 1.2  ## radians per second

var turned := 0.0  ## radians, clockwise positive
var target := TAU * 2.0
var held := 0.0  ## seconds in the band so far
var _dragging := false
var _last_angle := 0.0


func instructions() -> String:
	return "Drag in circles to turn the wheel into the green, then hold it there"


func _setup() -> void:
	turned = 0.0
	held = 0.0
	target = rng.randf_range(1.25, 1.75 + difficulty * 0.75) * TAU


func in_band() -> bool:
	return absf(turned - target) <= TOLERANCE


## Turns the wheel by `radians` (clockwise positive).
func rotate_by(radians: float) -> void:
	if not done:
		turned = clampf(turned + radians, -TAU, target + TAU)


func _tick(delta: float) -> void:
	held = held + delta if in_band() else 0.0
	if held >= HOLD_S:
		_finish(true)
	elif elapsed >= TIME_LIMIT_S:
		_finish(false)


func autoplay(delta: float) -> void:
	var gap := target - turned
	rotate_by(clampf(gap, -AUTOPLAY_SPEED * delta, AUTOPLAY_SPEED * delta))


func _center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.52)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		_last_angle = (button.position - _center()).angle()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		var offset := motion.position - _center()
		if offset.length() < 4.0:
			return  # too close to the hub to tell the direction
		var angle := offset.angle()
		# Screen y points down, so a growing angle is clockwise on screen.
		rotate_by(wrapf(angle - _last_angle, -PI, PI))
		_last_angle = angle
		accept_event()


func _draw() -> void:
	var c := _center()
	var r := minf(size.x, size.y) * 0.3
	# The gauge around the wheel: how far to turn, the green band, the needle.
	var span := target + TAU * 0.5
	var start := -PI * 0.75
	var sweep := PI * 1.5
	draw_arc(c, r * 1.3, start, start + sweep, 48, Color(0.2, 0.22, 0.26), r * 0.12)
	var band_a := start + sweep * clampf((target - TOLERANCE) / span, 0.0, 1.0)
	var band_b := start + sweep * clampf((target + TOLERANCE) / span, 0.0, 1.0)
	draw_arc(c, r * 1.3, band_a, band_b, 12, GOOD, r * 0.12)
	var needle := start + sweep * clampf(turned / span, 0.0, 1.0)
	draw_line(c + Vector2.from_angle(needle) * r * 1.15, c + Vector2.from_angle(needle) * r * 1.45,
		Color.WHITE if not in_band() else GOOD, r * 0.06)
	# The wheel itself, turning.
	draw_arc(c, r, 0.0, TAU, 48, Color(0.8, 0.25, 0.2), r * 0.14)
	for i in 4:
		var a := turned + i * PI * 0.5
		draw_line(c, c + Vector2.from_angle(a) * r, Color(0.8, 0.25, 0.2), r * 0.1)
	draw_circle(c, r * 0.16, Color(0.6, 0.18, 0.14))
	if held > 0.0:
		draw_arc(c, r * 0.3, -PI * 0.5, -PI * 0.5 + TAU * (held / HOLD_S), 24, GOOD, r * 0.08)
	_text(Vector2(size.x * 0.5, size.y * 0.97), "%.0f s" % maxf(TIME_LIMIT_S - elapsed, 0.0), _font(0.05))
