class_name ProgressRing
extends Control
## A radial progress ring around the crosshair, for hold interactions.

const THICKNESS := 6.0

var value := 0.0:  ## 0..1
	set(v):
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()


func _draw() -> void:
	if value <= 0.0:
		return
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - THICKNESS
	draw_arc(centre, radius, 0.0, TAU, 64, Color(0, 0, 0, 0.45), THICKNESS + 2.0, true)
	draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * value, 64, Color(1, 0.9, 0.3), THICKNESS, true)
