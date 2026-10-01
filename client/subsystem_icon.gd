class_name SubsystemIcon
extends Control
## One plant subsystem on the HUD: a box filled from the bottom by its health (green → red),
## a dark overlay with the seconds left while it's on sabotage cooldown, and "OFF" with a red
## frame when it needs a reboot. Critical subsystems (2-rat levers) get a "!!" tag.

var label := "???"
var critical := false
var health := 100.0  ## 0..100
var cooldown := 0.0  ## s
var offline := false


func set_state(p_health: float, p_cooldown: float, p_offline: bool) -> void:
	if p_health == health and ceilf(p_cooldown) == ceilf(cooldown) and p_offline == offline:
		return
	health = p_health
	cooldown = p_cooldown
	offline = p_offline
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.55))
	var fraction := clampf(health / 100.0, 0.0, 1.0)
	var fill := Color(0.95, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.35), fraction)
	draw_rect(Rect2(0, size.y * (1.0 - fraction), size.x, size.y * fraction), fill.darkened(0.15))
	var font := get_theme_default_font()
	var font_size := 14
	draw_string(font, Vector2(0, 18), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.WHITE)
	if critical:
		draw_string(font, Vector2(0, size.y - 6), "!!", HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3, 11, Color(1, 0.9, 0.3))
	if cooldown > 0.0:
		draw_rect(rect, Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(0, size.y * 0.5 + 10), "%d" % ceili(cooldown), HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 18, Color(1, 0.6, 0.3))
	if offline:
		draw_string(font, Vector2(0, size.y - 6), "OFF", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1, 0.3, 0.3))
	draw_rect(rect, Color(1, 0.2, 0.2) if offline else Color(1, 1, 1, 0.5), false, 2.0 if offline else 1.0)
