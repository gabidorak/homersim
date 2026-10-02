class_name StatusBoardPanel
extends Control
## What the Control Room status board shows (drawn, no child controls): every subsystem's health
## with its cooldown or OFFLINE state, core temperature, meltdown, the alarm light and the shift
## clock, plus the Control Room actions' cooldowns and SCRAM (M6). Reads only synced state
## (PlantSim, MatchManager, ConsoleAction), like the HUD.

const ALARM_COLORS := {
	PlantModel.Alarm.NORMAL: Color(0.35, 0.8, 0.4),
	PlantModel.Alarm.WARNING: Color(1, 0.7, 0.15),
	PlantModel.Alarm.CRITICAL: Color(1, 0.2, 0.15),
}


func _draw() -> void:
	var session := Session.current
	if session == null:
		return
	var plant := session.plant
	var font := ThemeDB.fallback_font
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.09))
	draw_string(font, Vector2(20, 40), tr("SUNNY ACRES  ·  PLANT STATUS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.95, 1))
	var blink := Time.get_ticks_msec() % 800 < 400
	var alarm_color: Color = ALARM_COLORS[plant.alarm]
	var light := alarm_color if plant.alarm == PlantModel.Alarm.NORMAL or blink else alarm_color.darkened(0.7)
	draw_circle(Vector2(w - 40, 30), 18, light)
	var actions: Array[String] = []
	for node in get_tree().get_nodes_in_group(ConsoleAction.GROUP_NAME):
		var console := node as ConsoleAction
		var left := console.cooldown_left()
		var state := "%d s" % ceili(left) if left > 0.0 else (tr("no power") if not console.has_power() else tr("ready"))
		actions.append("%s: %s" % [console.title(), state])
	if plant.scram_left > 0.0:
		actions.append(tr("SCRAM ACTIVE %d s") % ceili(plant.scram_left))
	draw_string(font, Vector2(20, 66), "  ·  ".join(actions), HORIZONTAL_ALIGNMENT_LEFT, w - 40, 16,
		Color(1, 0.4, 0.35) if plant.scram_left > 0.0 else Color(0.75, 0.85, 1))
	var y := 78.0
	for i in plant.count():
		var data := plant.data(i)
		var health := plant.health(i) / plant.tuning.max_health
		draw_string(font, Vector2(20, y + 22), tr(data.display_name), HORIZONTAL_ALIGNMENT_LEFT, 200, 20, Color.WHITE)
		var bar := Rect2(230, y + 4, w - 400, 22)
		draw_rect(bar, Color(0.15, 0.17, 0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color(1, 0.25, 0.2).lerp(Color(0.35, 0.85, 0.4), health))
		var state := "%d%%" % roundi(plant.health(i))
		var state_color := Color.WHITE
		if plant.needs_reboot(i):
			state = tr("OFFLINE")
			state_color = Color(1, 0.3, 0.25) if blink else Color(0.5, 0.15, 0.1)
		elif plant.cooldown_left(i) > 0.0:
			state += "  " + tr("sparks %d s") % ceili(plant.cooldown_left(i))
		draw_string(font, Vector2(w - 160, y + 22), state, HORIZONTAL_ALIGNMENT_LEFT, 150, 18, state_color)
		y += 32
	y += 6
	_gauge(font, y, tr("Core %d°") % roundi(plant.core_temp), inverse_lerp(plant.tuning.min_temp, plant.tuning.max_temp, plant.core_temp), alarm_color)
	_gauge(font, y + 34, tr("Meltdown %d%%") % floori(plant.meltdown), plant.meltdown / 100.0, Color(0.85, 0.15, 0.6))
	var mm := session.match_manager
	if mm.state == MatchManager.State.PLAYING:
		draw_string(font, Vector2(w - 160, 40), "%d:%02d" % [floori(mm.time_left / 60.0), mm.time_left % 60],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)


func _gauge(font: Font, y: float, text: String, fraction: float, color: Color) -> void:
	draw_string(font, Vector2(20, y + 22), text, HORIZONTAL_ALIGNMENT_LEFT, 200, 20, Color.WHITE)
	var bar := Rect2(230, y + 4, size.x - 400, 22)
	draw_rect(bar, Color(0.15, 0.17, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fraction, 0.0, 1.0), bar.size.y)), color)
