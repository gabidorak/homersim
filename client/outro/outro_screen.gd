class_name OutroScreen
extends CanvasLayer
## Plays the end-of-match cinematic (Outro) over the game, before the post-match screen (client/
## post_match.gd starts it when POST_MATCH begins): the game fades to black, the cinematic plays in a
## world of its own (a SubViewport drawn at the window's own resolution, so the plant's lights, sky
## and alarms stay out of it), then `finished`. Any mouse button, key or gamepad button skips it (as
## the intro), but not in its first GRACE s: a player still swinging the broom at the whistle doesn't
## skip it by accident. While it covers the screen the main view draws no 3D and plays no positional
## sound (the plant behind it is still there, alarms and all). Everyone sees the winners' ending: both
## teams and the spectators. Never built in a headless process or on a server (wanted()).

signal finished

const LAYER := 30  ## over the game's UI (HUD, feed, scoreboard at 15, the pause menu at 20)
const LEAD_IN := 0.45  ## s: the game fades to black, then the cinematic fades in
const GRACE := 0.75  ## s into the cinematic before input can skip it

## Off for a whole run: tests that drive the post-match screen themselves (tests/helpers/ui_tour.gd).
static var enabled := true

var outro: Outro
var _ending := Outro.Ending.SUPERVISORS
var _rats := Outro.DEFAULT_RATS
var _delay := 0.0
var _fade: ColorRect
var _view: SubViewport
var _picture: TextureRect
var _done := false
var _covering := false  # the cinematic covers the screen: the main view is switched off
var _mouse_was := Input.MOUSE_MODE_VISIBLE


## Whether this process plays the end-of-match cinematics: a windowed client (not a server, not
## headless), unless --no-outro.
static func wanted() -> bool:
	return should_play(Cli.args, DisplayServer.get_name() == "headless", Net.is_server)


static func should_play(args: Dictionary, headless: bool, server: bool) -> bool:
	return enabled and not headless and not server and not args.has("no-outro")


## The ending the winner gets: the supervisors' golden toast, or the rats' power cut.
static func ending_for(winner: MatchRulesModel.Team) -> Outro.Ending:
	return Outro.Ending.RATS if winner == MatchRulesModel.Team.RATS else Outro.Ending.SUPERVISORS


## How many rats played the match `result` (MatchManager.result: its stats have a row per player,
## bots too): the rats' ending shows a pair of eyes for each (Outro clamps it to its spots).
static func rats_in(result: Dictionary) -> int:
	var count := 0
	for row: Dictionary in result.get("stats", []):
		if row.get("role") == Role.Kind.RAT:
			count += 1
	return count


## Plays the cinematic for `winner` over everything under `parent`, after `delay` s (a meltdown's
## boom lands first); `rats`: how many rats won (the rats' ending). Free once it has finished.
static func play(parent: Node, winner: MatchRulesModel.Team, delay := 0.0, rats := Outro.DEFAULT_RATS) -> OutroScreen:
	var screen := OutroScreen.new()
	screen.name = "OutroScreen"
	screen._ending = ending_for(winner)
	screen._rats = rats
	screen._delay = delay
	parent.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP  # (no click reaches the game meanwhile)
	add_child(_fade)
	var tween := create_tween()
	tween.tween_interval(_delay)
	tween.tween_property(_fade, ^"color:a", 1.0, LEAD_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_start)
	Events.outro_started.emit()
	Log.info("outro", "the %s ending in %.1f s" % ["rats' (%d rats)" % clampi(_rats, 1, Outro.MAX_RATS)
		if _ending == Outro.Ending.RATS else "supervisors'", _delay + LEAD_IN])


func _exit_tree() -> void:
	_uncover()


## The screen is black: the cinematic takes over, in its own world.
func _start() -> void:
	if _done:
		return
	var root := get_tree().root
	_view = SubViewport.new()
	_view.name = "Cinema"
	_view.own_world_3d = true
	_view.handle_input_locally = false
	_view.msaa_3d = root.msaa_3d
	_view.screen_space_aa = root.screen_space_aa
	_view.use_taa = root.use_taa
	_view.scaling_3d_mode = root.scaling_3d_mode
	_view.scaling_3d_scale = root.scaling_3d_scale
	_view.positional_shadow_atlas_size = root.positional_shadow_atlas_size
	_view.size_2d_override_stretch = true
	_resize()
	add_child(_view)
	_picture = TextureRect.new()
	_picture.texture = _view.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	move_child(_fade, -1)
	outro = Outro.new(_ending, _rats)
	outro.finished.connect(_on_finished)
	_view.add_child(outro)
	_fade.color.a = 0.0  # (the cinematic fades in from black itself)
	_cover()
	root.size_changed.connect(_resize)


## The cinematic draws at the window's real size (the game's UI is scaled up from 1280 x 720: so is
## the cinematic's letterbox and hint).
func _resize() -> void:
	if _view == null:
		return
	var root := get_tree().root
	_view.size = root.size
	_view.size_2d_override = Vector2i(root.get_visible_rect().size)


## Every input is the cinematic's while it plays: a press skips it (after the grace), nothing reaches
## the game (the chat, the pause menu, the scoreboard, the look).
func _input(event: InputEvent) -> void:
	if _done or not (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton
			or event is InputEventJoypadMotion or event is InputEventMouseMotion):
		return
	get_viewport().set_input_as_handled()
	if Cinematic.is_skip_event(event) and outro != null and outro.t >= GRACE:
		outro.skip()


## Ends it now (the next match is starting): no fade, `finished` at once.
func stop() -> void:
	if _done:
		return
	if outro != null and not outro.leaving:
		outro.leaving = true
	_on_finished()


func _on_finished() -> void:
	if _done:
		return
	_done = true
	_uncover()
	finished.emit()
	queue_free()


## While the cinematic covers the screen: the main view draws no 3D and plays no positional sound.
func _cover() -> void:
	var root := get_tree().root
	root.disable_3d = true
	root.audio_listener_enable_3d = false
	_mouse_was = Input.mouse_mode
	if _mouse_was == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_covering = true


func _uncover() -> void:
	if not _covering or not is_inside_tree():
		return
	_covering = false
	var root := get_tree().root
	root.disable_3d = false
	root.audio_listener_enable_3d = true
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = _mouse_was
