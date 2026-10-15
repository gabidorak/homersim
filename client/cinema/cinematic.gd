class_name Cinematic
extends Node3D
## A cinematic's director, shared by the intro (client/intro/intro.gd) and the end-of-match
## cinematics (client/outro/outro.gd): the clock, the cues, the camera shots, the letterbox overlay
## and the skip.
##
## The clock (`t`) starts on the first frame after loading (that frame took the loading), together
## with the music. The timeline is a list of cues, a time and what happens then (_at, _sfx, filled in
## _script()), and of camera shots (_shot_list()): from its start each shot eases its eye, target and
## field of view from a first value to a second one, until the next shot cuts in. Any mouse button,
## key or gamepad button skips (is_skip_event: the subclass, or whoever hosts it, calls skip()): a
## short fade to black, the music fading with it, then _finish(). The cinematic also finishes by
## itself at length(). Subclasses build their set, cast and effects in _ready, then call
## _start_timeline(), and say what comes next in _finish().

signal finished  ## the cinematic is over (played to the end or skipped), the screen is black

const SKIP_FADE := 0.3
const OVERLAY_LAYER := 10
const BAR_HEIGHT := 58.0  ## the letterbox bars, in pixels at 720p

var camera: Camera3D
var t := 0.0  ## the clock: seconds since the cinematic started
var leaving := false
var log_tag := "cinematic"

var _cues: Array[Array] = []  # [time, Callable], sorted by time
var _next_cue := 0
var _shots: Array[Dictionary] = []
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var _overlay: CanvasLayer
var _fade: ColorRect
var _skip_hint: Label
var _started := false


## True for an input that skips a cinematic: any mouse button, key or gamepad button going down.
static func is_skip_event(event: InputEvent) -> bool:
	return (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton) \
		and event.is_pressed() and not event.is_echo()


## The cinematic's length (s): it finishes then.
func length() -> float:
	return 0.0


## What comes after the cinematic (the menu, the post-match screen...). The screen is black.
func _finish() -> void:
	leaving = true
	finished.emit()


## Called every frame once the clock runs, after the cues and before the camera moves.
func _tick(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	if not _started:
		# The first frame took the loading: start the clock (and the music) from here.
		_started = true
		if _music != null and _music.stream != null:
			_music.play()
		return
	t += delta
	_fire_cues()
	_tick(delta)
	_place_camera(delta)
	if t >= length() and not leaving:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if is_skip_event(event):
		get_viewport().set_input_as_handled()
		skip()


## Ends the cinematic now: a short fade, then _finish().
func skip() -> void:
	if leaving:
		return
	leaving = true
	Log.info(log_tag, "skipped at %.1f s" % t)
	var tween := create_tween().set_parallel()
	tween.tween_property(_fade, ^"color:a", 1.0, SKIP_FADE)
	if _music != null and _music.playing:
		tween.tween_property(_music, ^"volume_db", -40.0, SKIP_FADE)
	tween.chain().tween_callback(_finish)


# --- Building ---------------------------------------------------------------------------------------

func _make_camera() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	return camera


## The score, on the Music bus, `db` over its mix level (it starts with the clock).
func _make_music(path: String, db: float) -> AudioStreamPlayer:
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = &"Music"
	_music.volume_db = db
	_music.stream = load(path) if ResourceLoader.exists(path) else null
	add_child(_music)
	return _music


## Builds the shots and the cues, then puts the camera on its first shot.
func _start_timeline() -> void:
	_shots = _shot_list()
	_script()
	_cues.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_place_camera(0.0)


## The letterbox bars, the "Click to skip" hint (it fades in after a second) and the fade (black at
## first), on a CanvasLayer of their own. Returns the layer, so a subclass can add to it under the
## hint and the fade (captions).
func _build_overlay() -> CanvasLayer:
	_overlay = CanvasLayer.new()
	_overlay.name = "Overlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	for top: bool in [true, false]:  # letterbox bars
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -BAR_HEIGHT
		bar.offset_bottom = BAR_HEIGHT if top else 0.0
		_overlay.add_child(bar)
	_skip_hint = Label.new()
	_skip_hint.text = tr("Click to skip")
	_skip_hint.theme_type_variation = &"MutedLabel"
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -320.0
	_skip_hint.offset_top = -BAR_HEIGHT + 8.0
	_skip_hint.offset_right = -24.0
	_skip_hint.offset_bottom = -8.0
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skip_hint.modulate.a = 0.0
	_overlay.add_child(_skip_hint)
	_skip_hint.create_tween().tween_property(_skip_hint, ^"modulate:a", 0.8, 0.6).set_delay(1.0)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)
	return _overlay


# --- The timeline -----------------------------------------------------------------------------------

## The cues: subclasses fill them with _at and _sfx.
func _script() -> void:
	pass


func _at(time: float, what: Callable) -> void:
	_cues.append([time, what])


func _sfx(time: float, sound: String, db := 0.0) -> void:
	_at(time, func() -> void: Sfx.play(self, sound, db))


## Runs `what` in `seconds` (game time: it stops with a paused tree).
func _after(seconds: float, what: Callable) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(what)


func _fire_cues() -> void:
	while _next_cue < _cues.size() and _cues[_next_cue][0] <= t:
		(_cues[_next_cue][1] as Callable).call()
		_next_cue += 1


# --- Camera -----------------------------------------------------------------------------------------

## The shots, one after the other: from `start` s the camera eases from its first eye position and
## target (and field of view) to its second ones.
func _shot_list() -> Array[Dictionary]:
	return []


func _shot(start: float, eye_a: Vector3, eye_b: Vector3, look_a: Vector3, look_b: Vector3, fov_a: float,
		fov_b: float) -> Dictionary:
	return {"start": start, "eye": [eye_a, eye_b], "look": [look_a, look_b], "fov": [fov_a, fov_b]}


## The shot at `time`, and how far into it (0..1, eased): [shot, u].
func _shot_at(time: float) -> Array:
	var index := 0
	for i in _shots.size():
		if time >= _shots[i]["start"]:
			index = i
	var shot := _shots[index]
	var end: float = _shots[index + 1]["start"] if index + 1 < _shots.size() else length()
	var u := clampf((time - shot["start"]) / (end - shot["start"]), 0.0, 1.0)
	return [shot, u * u * (3.0 - 2.0 * u)]


func _place_camera(delta: float) -> void:
	if _shots.is_empty():
		return
	var at := _shot_at(t)
	var shot: Dictionary = at[0]
	var u: float = at[1]
	var eye: Vector3 = (shot["eye"][0] as Vector3).lerp(shot["eye"][1], u)
	var look: Vector3 = (shot["look"][0] as Vector3).lerp(shot["look"][1], u)
	camera.fov = lerpf(shot["fov"][0], shot["fov"][1], u)
	if _shake > 0.0:
		if Config.camera_shake:  # (Settings, or --no-shake, turn it off)
			var amount := _shake * _shake * 0.12
			eye += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * amount
		_shake = maxf(_shake - delta * 1.6, 0.0)
	camera.look_at_from_position(eye, look)
