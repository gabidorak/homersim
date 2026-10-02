class_name MinigameHost
extends CanvasLayer
## Client: the overlay that runs a repair minigame (ARCHITECTURE §4 Minigames). The server opens it
## (MinigameService.on_open_minigame → open()); it frees the mouse, blocks gameplay input, and sends
## the outcome back with request_minigame_result. Esc cancels (request_minigame_cancel). The server
## can close it at any time (stunned, bitten, walked away: close()).
##
## A won game is only reported once MIN_REPORT_S have passed since it opened (the server refuses
## faster results as a hack): a quick player sees "Fixed!" for the rest of that moment.
## Test bots set `autoplay` and the minigame plays itself through its own methods.

const SCENES := {
	"wrench_rhythm": preload("res://minigames/wrench_rhythm/WrenchRhythm.tscn"),
	"breaker_sequence": preload("res://minigames/breaker_sequence/BreakerSequence.tscn"),
	"valve_rotate": preload("res://minigames/valve_rotate/ValveRotate.tscn"),
}
const TITLES := {
	"wrench_rhythm": "Tighten the bolts",
	"breaker_sequence": "Reset the breakers",
	"valve_rotate": "Turn the valve",
}
const REPORT_MARGIN_S := 0.3  ## on top of the server's minimum
const RESULT_SHOW_S := 0.8  ## the "Fixed!" / "Failed" line after reporting

var autoplay := false  ## test bots
var game: Minigame  ## the open minigame, or null
var target_path := NodePath()

var _dim: ColorRect
var _panel: PanelContainer
var _frame: Control
var _title: Label
var _hint: Label
var _opened_at := 0.0
var _reported := false
var _mouse_before := Input.MOUSE_MODE_CAPTURED

@onready var session: Session = Session.current


func _ready() -> void:
	layer = 5
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	# The panel takes a share of the window (anchors), so it works at any size.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	_dim.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	_frame = Control.new()
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.custom_minimum_size = Vector2(200, 150)
	box.add_child(_frame)
	var esc := Label.new()
	esc.text = "Esc: give up (no penalty)"
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc.modulate = Color(1, 1, 1, 0.6)
	box.add_child(esc)
	visible = false


func is_open() -> bool:
	return game != null


## Server said: play `kind` for the repair point at `path`.
func open(path: NodePath, kind: String, seed_value: int, difficulty: float) -> void:
	_close_game()
	if not SCENES.has(kind):
		Log.error("minigame", "unknown minigame '%s'" % kind)
		session.minigames.request_minigame_cancel.rpc_id(1)
		return
	target_path = path
	game = (SCENES[kind] as PackedScene).instantiate()
	game.finished.connect(_on_finished)
	_frame.add_child(game)
	game.start(seed_value, difficulty)
	_title.text = TITLES.get(kind, kind)
	_opened_at = Net.local_time()
	_reported = false
	visible = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PlayerInput.blocked = true
	Log.info("minigame", "opened %s (seed %d, difficulty %.2f)" % [kind, seed_value, difficulty])


## Server said: it's over (`reason` shown briefly), or the player gave up.
func close(reason: String) -> void:
	if game == null or (game.done and _reported):
		return  # we already reported: the result line closes it shortly
	Log.info("minigame", "closed: %s" % reason)
	_close_game()


func _close_game() -> void:
	if game != null:
		game.queue_free()
		game = null
	visible = false
	if PlayerInput.blocked:
		PlayerInput.blocked = false
		if _mouse_before == Input.MOUSE_MODE_CAPTURED and get_window().has_focus():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if game != null:
		PlayerInput.blocked = false


func _input(event: InputEvent) -> void:
	# Before the camera rig's Esc (free the mouse) and the chat.
	if game != null and not game.done and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Log.info("minigame", "gave up")
		session.minigames.request_minigame_cancel.rpc_id(1)
		_close_game()


func _process(delta: float) -> void:
	if game == null:
		return
	if autoplay and not game.done:
		game.autoplay(delta)
	_hint.text = game.instructions()
	if game.done and not _reported:
		var since := Net.local_time() - _opened_at
		var min_s := session.plant.tuning.minigame_min_s + REPORT_MARGIN_S
		if game.success and since < min_s:
			_hint.text = "Fixed! (wrapping up…)"
			return
		_reported = true
		Log.info("minigame", "%s after %.1f s, reporting" % ["won" if game.success else "lost", since])
		session.minigames.request_minigame_result.rpc_id(1, game.success)
		_hint.text = "Fixed!" if game.success else "Botched it! The repair point jams for a moment"
		var finished_game := game
		get_tree().create_timer(RESULT_SHOW_S).timeout.connect(func() -> void:
			if game == finished_game:
				_close_game())


func _on_finished(won: bool) -> void:
	Sfx.play(self, "ui_confirm" if won else "ui_error")
