class_name EventFeed
extends CanvasLayer
## The event feed (M8, ClientOnly), top right: one line per big moment of the match, sent by the server
## (MatchManager.feed → Events.feed_event): cages, rescues, bonks, knockdowns, traps, stolen keycards,
## sabotages, machines offline or fixed, the swarm bonus. Names take their team's colour. Each line
## fades out after LINE_S.

const LINE_S := 7.0
const FADE_S := 0.8
const MAX_LINES := 6
const SUPERVISOR_COLOR := "ffc93c"
const RAT_COLOR := "7bd389"
const SUBSYSTEM_COLOR := "7fb7e6"
## kind -> English line ("%s" are the names, in order). Translated when shown.
const LINES := {
	"caged": "%s caged %s!",
	"eliminated": "%s caught %s again: out of the match!",
	"freed": "%s freed %s!",
	"bonk": "BONK! %s stunned %s",
	"knockdown": "The rats knocked %s down!",
	"trap_snap": "SNAP! %s stepped in a trap",
	"trap_lure": "%s sniffed the cheese lure: revealed!",
	"stolen": "A rat stole %s's keycard!",
	"sabotaged": "%s sabotaged!",
	"offline": "%s is offline! It needs a reboot",
	"repaired": "%s repaired",
	"rebooted": "%s is back online",
	"swarm": "SWARM! Every supervisor is down: meltdown +%s%%",
}
const SUBSYSTEM_KINDS: Array[String] = ["sabotaged", "offline", "repaired", "rebooted"]

var _box: VBoxContainer


func _ready() -> void:
	layer = 6
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_box.offset_left = -434
	_box.offset_right = -14
	_box.offset_top = MapOverlay.feed_top()  # (under the minimap)
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	Events.feed_event.connect(add_line)
	Config.changed.connect(func(key: String) -> void:
		if key == "show_minimap":
			_box.offset_top = MapOverlay.feed_top())
	Events.match_state_changed.connect(func(state: int) -> void:
		if state == MatchManager.State.LOBBY:
			clear())


func clear() -> void:
	for child in _box.get_children():
		child.queue_free()


## Shows the line for `kind` with the names `a` and `b`.
func add_line(kind: String, a: String, b: String) -> void:
	var text := format_line(kind, a, b)
	if text == "":
		return
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.custom_minimum_size = Vector2(420, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("outline_size", 6)
	line.add_theme_font_size_override("normal_font_size", 17)
	line.text = "[right]%s[/right]" % text
	_box.add_child(line)
	while _box.get_child_count() > MAX_LINES:
		var oldest := _box.get_child(0)
		_box.remove_child(oldest)
		oldest.queue_free()
	var tween := line.create_tween()
	line.modulate.a = 0.0
	tween.tween_property(line, "modulate:a", 1.0, 0.15)
	tween.tween_interval(LINE_S)
	tween.tween_property(line, "modulate:a", 0.0, FADE_S)
	tween.tween_callback(line.queue_free)


## The line as BBCode, translated, with coloured names ("" for an unknown kind).
func format_line(kind: String, a: String, b: String) -> String:
	if not LINES.has(kind):
		return ""
	var pattern: String = tr(LINES[kind])
	var names: Array = []
	if kind in SUBSYSTEM_KINDS:
		names = ["[color=#%s]%s[/color]" % [SUBSYSTEM_COLOR, _subsystem_name(a)]]
	elif kind == "swarm":
		names = [a]
	else:
		for who in [a, b]:
			if who != "":
				names.append(_name(who))
	if pattern.count("%s") != names.size():
		return ""
	return pattern % names


## A player's name in their team's colour (names are cleaned of BBCode brackets by the server).
func _name(who: String) -> String:
	var mm := Session.current.match_manager
	for peer: int in mm.roster:
		if mm.roster[peer]["name"] == who:
			match mm.roster[peer]["role"]:
				Role.Kind.SUPERVISOR:
					return "[color=#%s]%s[/color]" % [SUPERVISOR_COLOR, who]
				Role.Kind.RAT:
					return "[color=#%s]%s[/color]" % [RAT_COLOR, who]
	return who


func _subsystem_name(id: String) -> String:
	var plant := Session.current.plant
	for i in plant.count():
		if String(plant.data(i).id) == id:
			return tr(plant.data(i).display_name)
	return id
