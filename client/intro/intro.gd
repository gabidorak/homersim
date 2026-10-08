class_name Intro
extends Node3D
## The intro cinematic (about 18 s), played when the game starts, before the main menu (main.gd):
## how the rats came to Sunny Acres. In the good old days the supervisors kept hamsters in open cages
## on their desk, played with them and shared their donuts. Then the new guy, carrying a yellow bottle
## of radioactive goo, tripped over the wet floor sign: the goo rained on the hamsters and POOF, rats.
## Crazy ones: they bite, wreck the desk, chew through the wiring (the alarm goes off) and run off into
## the vents, the supervisors on their tails.
## Any click (or key, or gamepad button) skips straight to the menu.
##
## Everything is built in code: the set (IntroSet), the characters (IntroActor), the effects
## (IntroFx). The timeline is a list of cues (a time and what happens then, see _script()) and of
## camera shots (_shot_list()); the music (tools/audio/music.py, intro) is written to the same clock.

const SCENE := "res://client/intro/Intro.tscn"
const MENU := "res://client/MainMenu.tscn"
const MUSIC := "res://assets/audio/music/intro.ogg"
const LENGTH := 18.6  ## s: the menu comes then
const SKIP_FADE := 0.3
const MUSIC_DB := 2.0  ## the score leads here: a little over the Music bus mix level
const GOO := Color(0.61, 1.0, 0.18)
const GOO_TINT := Color(0.72, 1.0, 0.6)  ## hamsters dripping with goo
const OVERLAY_LAYER := 10
const BAR_HEIGHT := 58.0  ## the letterbox bars, in pixels at 720p
const VENT := Vector3(IntroSet.RIGHT - 0.3, 0.0, IntroSet.VENT_Z)  ## the vent's mouth
## Where the broom guy swings at the last rat...
const SWING_SPOT := Vector3(2.6, 0.0, -2.0)
const FALL_TOWARDS := Vector3(3.07, 0.0, -0.53)  ## ...where his head lands after the BONK (sideways on to the camera)
const STARTLE_STEP := 0.18  ## the startle and cower clips step back this much (m)
## Times the music (tools/audio/music.py, intro) hits too: move one, move it there as well.
const TRIP := 5.9
const SPLASH := 7.55
const REVEAL := 9.95
const ALARM := 13.45
const BONK := 15.89

var set_: IntroSet
var fx: IntroFx
var camera: Camera3D
var t := 0.0  ## the clock: seconds since the intro started
var leaving := false

# The cast.
var sup_a: IntroActor  ## left: plays with the begging hamster, gets bitten
var sup_b: IntroActor  ## right: shares his donuts, grabs the broom and leads the chase
var sup_c: IntroActor  ## the new guy, with the bottle
var hamsters: Array[IntroActor] = []  ## golden (on the wheel), cocoa (begging), cream (nibbling)
var rats: Array[IntroActor] = []  ## what each hamster becomes
var bottle: Node3D

var _cues: Array[Array] = []  # [time, Callable], sorted by time
var _next_cue := 0
var _shots: Array[Dictionary] = []
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var _fade: ColorRect
var _caption: TextureRect
var _caption_box: VBoxContainer
var _skip_hint: Label
var _goo_lights: Array[OmniLight3D] = []
var _trail: Array[Node3D] = []  # goo blobs pouring out of the flying bottle
var _trail_points: Array[Vector3] = []
var _started := false


## Whether the game should open with the intro: a windowed client with no reason to go straight
## somewhere else (`--connect`, `--no-intro`, the menu and client test hooks of debug builds).
static func wanted() -> bool:
	return should_play(Cli.args, DisplayServer.get_name() == "headless", OS.is_debug_build())


## wanted(), from the command line's user `args` (Cli.parse()), whether the process is headless and
## whether it is a debug build (only those honour the test hooks).
static func should_play(args: Dictionary, headless: bool, debug_build: bool) -> bool:
	if headless or args.has("no-intro") or args.has("connect"):
		return false
	if debug_build:
		for flag in MenuTestHooks.FLAGS + DebugHooks.FLAGS:
			if args.has(flag):
				return false
	return true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_go_to_menu.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var started_ms := Time.get_ticks_msec()
	_rng.seed = 2024
	set_ = IntroSet.new()
	set_.name = "Set"
	add_child(set_)
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	fx = IntroFx.new()
	fx.name = "Fx"
	fx.camera = camera
	add_child(fx)
	_cast()
	_build_overlay()
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = MUSIC_DB
	_music.stream = load(MUSIC) if ResourceLoader.exists(MUSIC) else null
	add_child(_music)
	_shots = _shot_list()
	_script()
	_cues.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_place_camera(0.0)
	fx.prewarm()
	Log.info("intro", "set built in %d ms" % (Time.get_ticks_msec() - started_ms))


func _exit_tree() -> void:
	Art.clear_cache()  # the goo tints: nothing else uses them


func _process(delta: float) -> void:
	if not _started:
		# The first frame took the loading: start the clock (and the music) from here.
		_started = true
		if _music.stream != null:
			_music.play()
		return
	t += delta
	while _next_cue < _cues.size() and _cues[_next_cue][0] <= t:
		(_cues[_next_cue][1] as Callable).call()
		_next_cue += 1
	_place_camera(delta)
	_update_trail()
	if t >= LENGTH and not leaving:
		_go_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton) \
		and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


## Ends the intro now: a short fade, then the menu.
func skip() -> void:
	if leaving:
		return
	leaving = true
	Log.info("intro", "skipped at %.1f s" % t)
	var tween := create_tween().set_parallel()
	tween.tween_property(_fade, ^"color:a", 1.0, SKIP_FADE)
	if _music.playing:
		tween.tween_property(_music, ^"volume_db", -40.0, SKIP_FADE)
	tween.chain().tween_callback(_go_to_menu)


func _go_to_menu() -> void:
	leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)


# --- The cast -----------------------------------------------------------------------------------

func _cast() -> void:
	sup_a = IntroActor.create(set_, "supervisor", Vector3(-IntroSet.SEAT_X, IntroSet.SEAT_Y, IntroSet.SEAT_Z), 0.1,
		"sit")
	sup_b = IntroActor.create(set_, "supervisor", Vector3(IntroSet.SEAT_X, IntroSet.SEAT_Y, IntroSet.SEAT_Z), -0.1,
		"sit")
	sup_c = IntroActor.create(set_, "supervisor", Vector3(IntroSet.DOOR_X, 0.0, IntroSet.BACK - 0.9), 0.0, "idle")
	var hat := Art.part(sup_c.model, "HardHat")
	if hat != null:
		Art.set_tint(hat, Color(1.0, 0.6, 0.22))  # the new guy's hat is orange
	bottle = Art.add(self, "rad_bottle")
	if bottle != null:  # (a bit bigger than life, so it reads from across the room)
		sup_c.attach(bottle, "torso", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.25), Vector3(0.0, 0.1, 0.42)))
	hamsters = [
		IntroActor.create(set_, "hamster", set_.wheel_spot(), 0.12, "run"),
		IntroActor.create(set_, "hamster_cocoa", Vector3(-0.55, IntroSet.DESK_TOP, -2.25), 0.2, "beg"),
		IntroActor.create(set_, "hamster_cream", Vector3(0.55, IntroSet.DESK_TOP, -2.25), -0.2, "nibble"),
	]
	hamsters[0].set_speed(1.3)
	set_.wheel_speed = 5.5
	for h in hamsters:
		# The wheel's rat stands on the desk: its cage won't be there any more (_burst_cage).
		var at := IntroSet.CAGE_A if h == hamsters[0] else h.position
		var rat := IntroActor.create(set_, "rat", at, h.rotation.y, "idle")
		rat.visible = false
		rats.append(rat)
		var light := OmniLight3D.new()  # the goo's glow on each hamster
		light.light_color = GOO
		light.light_energy = 0.0
		light.omni_range = 0.65
		light.position = h.position + Vector3(0, 0.14, 0.2)
		set_.add_child(light)
		_goo_lights.append(light)


# --- The timeline ---------------------------------------------------------------------------------

func _at(time: float, what: Callable) -> void:
	_cues.append([time, what])


func _sfx(time: float, sound: String, db := 0.0) -> void:
	_at(time, func() -> void: Sfx.play(self, sound, db))


func _script() -> void:
	var h_wheel := hamsters[0]
	var h_cocoa := hamsters[1]
	var h_cream := hamsters[2]
	var r_wheel := rats[0]
	var r_cocoa := rats[1]
	var r_cream := rats[2]

	# 1. The good old days (0 - 4.4 s): a hamster running on its wheel, one begging for a treat,
	#    one nibbling a donut crumb next to the supervisor eating his.
	_at(0.0, func() -> void:
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, ^"color:a", 0.0, 0.7).set_delay(0.05))
	_at(0.45, func() -> void: _show_caption(tr("THE GOOD OLD DAYS"), tr("Sunny Acres plant"), 3.3))
	_at(0.5, func() -> void: sup_b.play_upper("eat"))
	_sfx(0.95, "munch", -4.0)
	_at(0.9, func() -> void: sup_a.play_upper("interact"))
	_sfx(1.2, "intro_squeak", -6.0)
	_at(1.65, func() -> void:
		sup_a.play_upper("")
		h_cocoa.play("hop", 0.1))
	_at(1.8, func() -> void: fx.hearts(h_cocoa.position + Vector3(0, 0.33, 0.05), 2, 0.9))
	_sfx(1.8, "intro_sparkle", -8.0)
	_at(1.9, func() -> void: sup_b.play_upper(""))
	_at(2.25, func() -> void:
		h_cocoa.play("beg")
		sup_a.play_upper("cheer"))
	_at(2.5, func() -> void:
		sup_b.play_upper("cheer")
		fx.hearts(h_cream.position + Vector3(0, 0.3, 0.05), 2, 0.9))
	_sfx(2.5, "intro_sparkle", -9.0)
	_sfx(2.9, "intro_squeak", -7.0)

	# 2. The new guy (4.4 - 6.2 s) comes in whistling with the bottle, onto the freshly mopped floor,
	#    and straight into the wet floor sign.
	var trip := IntroSet.SIGN + Vector3(0.0, 0.0, -0.35)
	_at(4.2, func() -> void:
		create_tween().tween_property(set_.door, ^"position:y", 1.3 + 2.6, 0.45).set_trans(Tween.TRANS_QUAD))
	_sfx(4.2, "door_open", -6.0)
	_at(4.35, func() -> void:
		sup_a.play_upper("")
		sup_b.play_upper("")
		sup_c.play("carry_walk", 0.1, 1.15)
		sup_c.move_to(trip, 1.55, false))
	_sfx(4.5, "whistle_emote", -8.0)
	_at(TRIP, func() -> void:
		sup_c.play("trip", 0.08)
		_kick_sign())
	_sfx(TRIP, "intro_whoa", -7.0)
	_at(6.0, _throw_bottle)

	# 3. Slow motion (6.2 - 7.8 s): the bottle tumbles over the supervisors' heads, pouring goo; they
	#    and the hamsters can only watch. Thud: the new guy lands flat on his face.
	_at(6.2, func() -> void:
		for actor: IntroActor in [sup_a, sup_b]:
			actor.play_upper("startle", 0.15)
			actor.set_speed(0.3)
		h_wheel.play("look_up", 0.3, 0.3)
		h_cocoa.play("look_up", 0.3, 0.3)
		h_cream.play("look_up", 0.3, 0.3)
		create_tween().tween_property(set_, ^"wheel_speed", 0.0, 0.8))
	for i in 3:
		_at(6.3 + i * 0.08, func() -> void: fx.exclaim(hamsters[i].position + Vector3(0, 0.4, 0), 0.6, 1.1))
	_sfx(6.55, "land", -6.0)
	_sfx(6.65, "ow", -8.0)
	_at(6.8, func() -> void: sup_c.play("faceplant", 0.2))
	_at(SPLASH, _splash)
	_sfx(7.62, "intro_glug", -3.0)
	_at(7.95, _tip_bottle)

	# 4. The transformation (7.8 - 10.4 s): trembling, glowing, the lamps stutter, the counter drops
	#    to 0... POOF, POOF, POOF.
	_at(7.8, func() -> void:
		for actor: IntroActor in [sup_a, sup_b]:
			actor.set_speed(1.0)
			actor.play_upper("", 0.3)
		for h in hamsters:
			h.play("shiver", 0.1)
			h.set_speed(1.0)
		var glow := create_tween().set_parallel()
		for light in _goo_lights:
			glow.tween_property(light, ^"light_energy", 1.0, 1.3)
		glow.tween_property(set_, ^"flicker", 1.0, 1.2))
	for k in 14:  # the Geiger counter goes wild
		_sfx(7.85 + 1.35 * (1.0 - pow(1.0 - k / 14.0, 1.6)), "click", -5.0)
	_at(8.5, func() -> void: set_.set_days(0))
	_sfx(8.5, "intro_flip", -2.0)
	_at(8.05, func() -> void:
		fx.exclaim(sup_a.bone_position("head", Vector3(0, 0.95, 0)), 0.8, 0.9)
		fx.exclaim(sup_b.bone_position("head", Vector3(0, 0.95, 0)), 0.8, 0.9))
	for i in 3:
		_at(9.2 + i * 0.25, _transform.bind(i, i))
	_at(9.22, func() -> void:
		sup_a.play_upper("cower", 0.1)
		sup_b.play_upper("cower", 0.1))
	_at(9.9, func() -> void: set_.flicker = 0.0)
	_at(REVEAL, func() -> void: r_cocoa.play("squeak", 0.1))
	_at(10.05, func() -> void: r_cream.play("squeak", 0.1))
	_sfx(10.0, "squeak", -3.0)

	# 5. Crazy rats (10.4 - 12.6 s): EEK! The supervisors jump up onto their chairs, one gets bitten
	#    anyway, the mug goes over the edge, a rat runs off to the junction box.
	_at(10.45, func() -> void:
		for sup: IntroActor in [sup_a, sup_b]:
			sup.play_upper("", 0.1)
			sup.play("startle", 0.12)  # (standing up where it sat: on the seat)
			# The clip jumps back 0.18 m: forward as much, so the feet land on the seat, not its back.
			create_tween().tween_property(sup, ^"position", sup.position + sup.basis.z * STARTLE_STEP, 0.3)
		fx.exclaim(sup_a.bone_position("head", Vector3(0, 1.0, 0)), 1.0, 0.8)
		fx.exclaim(sup_b.bone_position("head", Vector3(0, 1.0, 0)), 1.0, 0.8))
	_sfx(10.5, "intro_eek", -5.0)
	_at(10.7, func() -> void:  # to the desk's front edge, down, round the desk's end, to the box
		r_cream.play("run", 0.08, 1.2)
		r_cream.move_to(Vector3(0.55, IntroSet.DESK_TOP, IntroSet.DESK_FRONT - 0.15), 0.25).tween_callback(func() -> void:
			r_cream.play("jump", 0.05)
			r_cream.hop_to(Vector3(0.75, 0.0, -1.3), 0.35, 0.38).tween_callback(func() -> void:
				r_cream.play("run", 0.08, 1.2)
				r_cream.move_to(Vector3(2.05, 0.0, -1.3), 0.4).tween_callback(func() -> void:
					r_cream.move_to(IntroSet.JUNCTION + Vector3(-0.32, -IntroSet.JUNCTION.y, 0.0), 0.55)))))
	_at(10.75, func() -> void:
		r_wheel.play("jump", 0.05)
		r_wheel.hop_to(Vector3(-0.95, IntroSet.DESK_TOP, -2.4), 0.35, 0.38))
	_at(11.2, func() -> void:
		r_wheel.face_towards(sup_a.position, 0.08)
		r_wheel.play("bite", 0.05, 1.0, true))
	_sfx(11.32, "chomp", -3.0)
	_at(11.38, func() -> void:
		sup_a.play("ouch", 0.08)
		fx.exclaim(sup_a.bone_position("head", Vector3(0, 1.0, 0)), 1.1, 0.7))
	_sfx(11.42, "ow", -5.0)
	_at(10.95, func() -> void: sup_b.play("cower", 0.15))
	_at(11.25, func() -> void:
		r_cocoa.face_towards(set_.mug.position, 0.06)
		r_cocoa.play("bite", 0.05, 1.0, true))
	_at(11.4, _knock_mug)
	_at(12.3, func() -> void:
		r_cream.face_towards(IntroSet.JUNCTION, 0.1)
		r_cream.play("gnaw", 0.1, 1.3))
	_at(12.15, func() -> void: r_cocoa.play("squeak", 0.1))
	_sfx(12.2, "squeak", -4.0)

	# 6. Sabotage (12.6 - 13.7 s): the rat at the junction box chews through the wiring: sparks, the
	#    box gives up, the lamps stutter and the alarm goes off.
	_at(12.65, func() -> void: fx.sparks(IntroSet.JUNCTION + Vector3(-0.2, 0.05, 0.0), 10))
	_sfx(12.65, "spark", -5.0)
	_at(12.95, func() -> void: fx.sparks(IntroSet.JUNCTION + Vector3(-0.2, -0.05, 0.05), 12))
	_sfx(12.95, "spark", -5.0)
	_at(13.2, func() -> void:
		set_.break_junction()
		fx.sparks(IntroSet.JUNCTION + Vector3(-0.25, 0.0, 0.0), 26)
		set_.flicker = 1.0
		r_cream.play("squeak", 0.1))
	_sfx(13.2, "zap", -4.0)
	_at(ALARM, func() -> void:
		set_.flicker = 0.0
		set_.sound_alarm())
	_sfx(ALARM, "klaxon", -9.0)

	# 7. The escape (13.7 - 18.6 s): to the desk's edge, down, across the floor in two lanes (far
	#    enough apart not to run into each other), into the vent. The donut guy jumps off his chair,
	#    grabs the broom and gives chase, the bitten one follows; the last rat squeaks a taunt and slips
	#    in just as the broom comes down. BONK.
	var lane_wheel := -1.45
	var lane_cocoa := -0.95
	_at(13.55, func() -> void:
		r_cream.play("run", 0.08, 1.2)
		r_cream.move_to(VENT, 0.7))
	_at(14.3, func() -> void: _into_vent(r_cream))
	_at(13.2, func() -> void:
		r_wheel.play("run", 0.08, 1.2)
		r_wheel.move_to(Vector3(-0.88, IntroSet.DESK_TOP, IntroSet.DESK_FRONT - 0.15), 0.3)
		r_cocoa.play("run", 0.08, 1.2)
		r_cocoa.move_to(Vector3(-0.35, IntroSet.DESK_TOP, IntroSet.DESK_FRONT - 0.15), 0.3))
	_at(13.5, func() -> void:
		r_wheel.play("jump", 0.05)
		r_wheel.hop_to(Vector3(-0.75, 0.0, lane_wheel), 0.4, 0.4)
		r_cocoa.play("jump", 0.05)
		r_cocoa.hop_to(Vector3(-0.2, 0.0, lane_cocoa), 0.5, 0.45))
	_at(13.95, func() -> void:
		r_cocoa.play("run", 0.1, 1.3)
		r_cocoa.move_to(Vector3(3.0, 0.0, lane_cocoa), 0.95).tween_callback(func() -> void:
			r_cocoa.move_to(VENT, 0.2).tween_callback(func() -> void: _into_vent(r_cocoa)))
		r_wheel.play("run", 0.1, 1.2)
		r_wheel.move_to(Vector3(2.95, 0.0, lane_wheel), 1.25).tween_callback(func() -> void:
			r_wheel.move_to(VENT + Vector3(-0.35, 0.0, 0.0), 0.12).tween_callback(func() -> void:
				r_wheel.face_towards(r_wheel.position + Vector3(-1, 0, 0.35), 0.15)
				r_wheel.play("squeak", 0.1))))
	_sfx(15.35, "squeak", -4.0)
	_at(15.85, func() -> void: _into_vent(r_wheel))
	_at(13.55, func() -> void:  # off the chair (beside it, not through its back), the broom, the chase
		sup_b.play("jump", 0.08)
		sup_b.hop_to(Vector3(IntroSet.SEAT_X + 0.63, 0.0, IntroSet.SEAT_Z + 0.1), 0.3, 0.3).tween_callback(func() -> void:
			sup_b.play("run", 0.1, 1.15)
			sup_b.move_to(Vector3(1.98, 0.0, -3.1), 0.25).tween_callback(func() -> void:
				_grab_broom(sup_b)
				sup_b.play("chase", 0.12, 1.15)
				sup_b.move_to(SWING_SPOT, 0.6).tween_callback(func() -> void:
					sup_b.play("idle", 0.15)
					sup_b.face_towards(VENT, 0.12)))))
	_at(13.85, func() -> void:  # off the chair, behind both chairs, and up behind the broom guy
		sup_a.play("jump", 0.08)
		sup_a.hop_to(Vector3(-IntroSet.SEAT_X + 0.57, 0.0, IntroSet.SEAT_Z + 0.1), 0.3, 0.3).tween_callback(func() -> void:
			sup_a.play("run", 0.12, 1.0)
			sup_a.move_to(Vector3(-0.15, 0.0, -3.85), 0.3).tween_callback(func() -> void:
				sup_a.move_to(Vector3(1.75, 0.0, -3.85), 0.7).tween_callback(func() -> void:
					sup_a.move_to(Vector3(1.75, 0.0, -3.4), 0.25).tween_callback(func() -> void:
						sup_a.play("idle", 0.2)
						sup_a.face_towards(VENT, 0.15))))))
	_at(15.59, func() -> void: sup_b.play("swing", 0.08))
	_at(BONK, func() -> void: _bonk(VENT + Vector3(0.05, 0.68, 0.0)))
	_sfx(BONK, "bonk", -2.0)
	_at(15.95, func() -> void:  # the BONK spins him round (well clear of his friend)...
		sup_b.play("fall", 0.1)
		var away := atan2(FALL_TOWARDS.x - SWING_SPOT.x, FALL_TOWARDS.z - SWING_SPOT.z) + PI
		create_tween().tween_property(sup_b, ^"rotation:y",
			sup_b.rotation.y + wrapf(away - sup_b.rotation.y, -PI, PI) + TAU, 0.35).set_trans(Tween.TRANS_QUAD))
	_at(16.3, func() -> void:  # ...and he goes down flat on his back, on the open floor
		sup_b.play("knocked", 0.1)
		sup_a.play("emote_no", 0.15))
	_sfx(16.5, "land", -6.0)
	_at(16.65, func() -> void: _dizzy(sup_b))
	_sfx(16.45, "squeak", -10.0)
	_sfx(16.7, "squeak", -11.0)
	_sfx(16.9, "squeak", -12.0)

	# The end: a last word, then the menu.
	_at(16.35, func() -> void: _show_caption(tr("...and the night shift was never the same again."), "", 2.2, true))
	_at(17.6, func() -> void: create_tween().tween_property(_fade, ^"color:a", 1.0, 0.9))
	_at(18.0, func() -> void: create_tween().tween_property(_music, ^"volume_db", -30.0, 0.6))


func _kick_sign() -> void:
	var sign_ := set_.wet_sign
	var tween := create_tween().set_parallel()
	tween.tween_property(sign_, ^"rotation:z", -PI * 0.5, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sign_, ^"position", sign_.position + Vector3(0.5, 0.0, 0.08), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sfx.play(self, "clatter", -5.0)


## The bottle leaves his hands and tumbles, in slow motion, over the supervisors onto the donuts.
func _throw_bottle() -> void:
	if bottle == null:
		return
	bottle.reparent(set_)
	var land := IntroSet.PLATE + Vector3(0.0, 0.47, 0.02)
	IntroFx.toss(bottle, land, 1.45, 1.55, Vector3(PI + 0.1, 0.5, 0.3)).set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	for i in 6:  # a stream of goo trailing behind it
		var gob := fx.blob(set_, bottle.position, 0.065 - i * 0.007)
		if gob != null:
			_trail.append(gob)


func _update_trail() -> void:
	if _trail.is_empty() or bottle == null:
		return
	_trail_points.push_front(bottle.to_global(Vector3(0.0, 0.3, -0.02)))
	if _trail_points.size() > 40:
		_trail_points.resize(40)
	for i in _trail.size():
		var k := mini((i + 1) * 3, _trail_points.size() - 1)
		_trail[i].global_position = _trail_points[k] + Vector3.DOWN * 0.02 * i


## SPLASH: the bottle lands upside down on the donuts, goo everywhere, a gob on each hamster.
func _splash() -> void:
	for gob in _trail:
		gob.queue_free()
	_trail.clear()
	var at := IntroSet.PLATE + Vector3(0.0, 0.08, 0.0)
	var puddle := Art.add(set_, "goo_puddle", Transform3D(Basis.IDENTITY, Vector3(at.x, IntroSet.DESK_TOP + 0.005,
		at.z - 0.05)), false)
	if puddle != null:
		puddle.scale = Vector3(0.05, 1.0, 0.05)
		puddle.create_tween().tween_property(puddle, ^"scale", Vector3(1.6, 1.0, 1.0), 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fx.droplets(at + Vector3.UP * 0.15, Vector3.UP, 30, 1.3)
	fx.flash(at + Vector3.UP * 0.3, GOO, 1.6, 2.5, 0.6)
	_shake = 0.25
	Sfx.play(self, "intro_splash", -3.0)
	for h in hamsters:
		var target := h.position + Vector3(0, 0.22, 0)
		var gob := fx.blob(set_, at + Vector3.UP * 0.25, 0.07)
		if gob == null:
			continue
		IntroFx.toss(gob, target, 0.35, 0.22).tween_callback(func() -> void:
			gob.queue_free()
			_goo_on(h))
	for actor: IntroActor in [sup_a, sup_b]:
		actor.set_speed(1.0)


## Glug... the empty bottle tips over and rolls off the desk: clonk.
func _tip_bottle() -> void:
	if bottle == null:
		return
	var floor_spot := Vector3(0.12, 0.09, IntroSet.DESK_FRONT + 0.4)
	IntroFx.toss(bottle, floor_spot, 0.12, 0.42, Vector3(-PI * 0.5, 0.5, 0.9)).set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_IN)
	_after(0.42, func() -> void:
		Sfx.play(self, "intro_clonk", -3.0)
		fx.droplets(floor_spot + Vector3.UP * 0.1, Vector3.UP, 8, 0.6))


## A hamster hit by the goo: green, glowing, gobs on its head and back.
func _goo_on(h: IntroActor) -> void:
	Art.set_tint(h.model, GOO_TINT)
	var head := fx.blob(self, Vector3.ZERO, 0.055)
	if head != null:
		h.attach(head, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.11, -0.01)))
	var back := fx.blob(self, Vector3.ZERO, 0.045)
	if back != null:
		h.attach(back, "body", Transform3D(Basis.IDENTITY, Vector3(0.03, 0.08, -0.07)))
	fx.droplets(h.position + Vector3(0, 0.2, 0), Vector3.UP, 8, 0.6)
	_goo_lights[hamsters.find(h)].light_energy = 0.6


## POOF: hamster `i` becomes a rat (the `n`-th pop: each one higher).
func _transform(i: int, n: int) -> void:
	var h := hamsters[i]
	var rat := rats[i]
	fx.poof(h.position + Vector3(0, 0.18, 0), 0.6)
	Sfx.play(self, "intro_poof_%d" % (n + 1), -2.0)
	_shake = maxf(_shake, 0.3)
	h.visible = false
	rat.visible = true
	rat.scale = Vector3.ONE * 0.3
	rat.create_tween().tween_property(rat, ^"scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC) \
		.set_ease(Tween.EASE_OUT)
	rat.play("squeak", 0.0)
	var light := _goo_lights[i]
	light.light_energy = 1.8
	light.create_tween().tween_property(light, ^"light_energy", 0.0, 1.8)
	_glowing_eyes(rat)
	if i == 0:
		_burst_cage()


## The wheel's cage can't hold a rat: the POOF blows it off the desk (the rat stands where it was),
## its roof and its wheel flying off on their own. Each lands on clear floor, left of the desk.
func _burst_cage() -> void:
	var cage := set_.cage_a
	var roof := Art.part(cage, "Roof")
	if roof != null:
		roof.reparent(set_)
		IntroFx.toss(roof, Vector3(-1.15, 0.0, -1.25), 0.8, 0.65, Vector3(2.0 * PI, 0.6, 0.0))
	if set_.wheel != null:
		var wheel := set_.wheel
		set_.wheel = null
		wheel.reparent(set_)
		IntroFx.toss(wheel, Vector3(-1.1, 0.19, -0.6), 0.6, 0.6, Vector3(8.6, 0.0, 0.0))  # (rolling)
	IntroFx.toss(cage, Vector3(-1.85, 0.0, -0.75), 0.7, 0.6, Vector3(0.0, 2.0, 2.0 * PI))
	_after(0.6, func() -> void: Sfx.play(self, "metal_heavy", -7.0))


## Two green glints in a rat's eyes, fading out over a few seconds.
func _glowing_eyes(rat: IntroActor) -> void:
	for side: float in [-1.0, 1.0]:
		var glint := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.1
		glint.mesh = quad
		glint.material_override = fx.glint_material()
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rat.attach(glint, "head", Transform3D(Basis.IDENTITY, Vector3(side * 0.07, 0.085, 0.17)))
		glint.create_tween().tween_property(glint, ^"transparency", 1.0, 1.4).set_delay(2.6)


func _knock_mug() -> void:
	var mug := set_.mug
	IntroFx.toss(mug, Vector3(mug.position.x - 0.25, 0.04, IntroSet.DESK_FRONT + 0.55), 0.25, 0.42,
		Vector3(2.4, 0.0, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_after(0.42, func() -> void:
		Sfx.play(self, "glass_break", -5.0)
		fx.splat(mug.position, Color(0.29, 0.18, 0.12), 0.55)
		mug.visible = false)


## The rat dives into the vent and is gone.
func _into_vent(rat: IntroActor) -> void:
	var inside := Vector3(IntroSet.RIGHT + 0.5, 0.0, IntroSet.VENT_Z)
	rat.face_towards(inside, 0.06)
	rat.play("crawl", 0.08, 1.4)
	rat.move_to(inside, 0.35, false).tween_callback(func() -> void: rat.visible = false)


func _grab_broom(actor: IntroActor) -> void:
	actor.attach(set_.broom, "arm-right", Transform3D(Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-45.0))),
		Vector3(-0.5, -0.02, 0.06)))


func _bonk(at: Vector3) -> void:
	fx.stars(at)
	fx.flash(at, Color(1, 0.9, 0.6), 1.5, 2.0, 0.25)
	_shake = 0.45


## Stars circling over a knocked-out head (the game's stun stars), in the world: the body lies flat.
func _dizzy(actor: IntroActor) -> void:
	var stars := Vfx.stun_stars(0.3)
	if stars != null:  # (placed before it enters the tree: it bobs around the height it starts at)
		stars.position = set_.to_local(actor.bone_position("head", Vector3(0.0, 0.4, 0.0)) + Vector3.UP * 0.45)
		set_.add_child(stars)


func _after(seconds: float, what: Callable) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(what)


# --- Camera ---------------------------------------------------------------------------------------

## The shots, one after the other: from `start` s the camera eases from its first eye position and
## target (and field of view) to its second ones.
func _shot_list() -> Array[Dictionary]:
	return [
		# 1. Close on the wheel, pulling back to the whole happy desk.
		_shot(0.0, Vector3(-1.4, 1.0, -1.32), Vector3(0.2, 1.72, 0.6), Vector3(-0.93, 0.9, -2.16),
			Vector3(-0.08, 1.18, -2.75), 44.0, 50.0),
		# 2. Across the room: the new guy comes in at the back and goes flat on his face.
		_shot(4.4, Vector3(-1.2, 1.9, 0.6), Vector3(-1.35, 1.85, 0.4), Vector3(-2.6, 0.95, -4.0),
			Vector3(-2.6, 0.75, -3.1), 50.0, 48.0),
		# 3. The supervisors look up at the bottle tumbling over their heads.
		_shot(6.2, Vector3(0.85, 1.35, -0.25), Vector3(0.72, 1.3, -0.42), Vector3(0.25, 1.62, -3.0),
			Vector3(0.3, 1.2, -2.25), 56.0, 54.0),
		# 4. The hamsters, face on, the supervisors watching: pushing in on the transformation.
		_shot(7.8, Vector3(0.0, 1.3, -0.05), Vector3(0.0, 1.25, -0.32), Vector3(0.0, 1.04, -2.4),
			Vector3(0.0, 1.02, -2.4), 44.0, 44.0),
		# 5. EEK: up on the chairs; the bite, the mug.
		_shot(10.4, Vector3(-0.3, 1.75, 0.35), Vector3(-0.25, 1.7, 0.15), Vector3(-0.1, 1.3, -2.75),
			Vector3(-0.1, 1.28, -2.8), 55.0, 55.0),
		# 6. The junction box on the right wall, in profile: chewed through, sparks, the alarm.
		_shot(12.6, Vector3(3.62, 0.55, -2.15), Vector3(3.6, 0.52, -2.25), Vector3(3.6, 0.42, -3.0),
			Vector3(3.62, 0.42, -3.0), 58.0, 56.0),
		# 7. Across the room at the right wall: the run to the vent, the broom, BONK.
		_shot(13.7, Vector3(-0.4, 2.45, 1.0), Vector3(-0.2, 2.35, 0.85), Vector3(2.9, 0.4, -1.75),
			Vector3(3.0, 0.35, -1.65), 46.0, 46.0),
	]


func _shot(start: float, eye_a: Vector3, eye_b: Vector3, look_a: Vector3, look_b: Vector3, fov_a: float,
		fov_b: float) -> Dictionary:
	return {"start": start, "eye": [eye_a, eye_b], "look": [look_a, look_b], "fov": [fov_a, fov_b]}


func _place_camera(delta: float) -> void:
	var index := 0
	for i in _shots.size():
		if t >= _shots[i]["start"]:
			index = i
	var shot := _shots[index]
	var end: float = _shots[index + 1]["start"] if index + 1 < _shots.size() else LENGTH
	var u := clampf((t - shot["start"]) / (end - shot["start"]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var eye: Vector3 = (shot["eye"][0] as Vector3).lerp(shot["eye"][1], u)
	var look: Vector3 = (shot["look"][0] as Vector3).lerp(shot["look"][1], u)
	camera.fov = lerpf(shot["fov"][0], shot["fov"][1], u)
	if _shake > 0.0:
		if Config.camera_shake:  # (Settings, or --no-shake, turn it off)
			var amount := _shake * _shake * 0.12
			eye += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * amount
		_shake = maxf(_shake - delta * 1.6, 0.0)
	camera.look_at_from_position(eye, look)


# --- Overlay ----------------------------------------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)
	for top: bool in [true, false]:  # letterbox bars
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -BAR_HEIGHT
		bar.offset_bottom = BAR_HEIGHT if top else 0.0
		layer.add_child(bar)
	# Captions sit on a soft dark band at the bottom of the picture.
	_caption = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.6))
	var band := GradientTexture2D.new()
	band.gradient = gradient
	band.fill_from = Vector2(0, 0)
	band.fill_to = Vector2(0, 1)
	band.width = 4
	band.height = 64
	_caption.texture = band
	_caption.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -BAR_HEIGHT - 170.0
	_caption.offset_bottom = -BAR_HEIGHT
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	layer.add_child(_caption)
	_caption_box = VBoxContainer.new()
	_caption_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption_box.offset_bottom = -14.0
	_caption_box.alignment = BoxContainer.ALIGNMENT_END
	_caption_box.add_theme_constant_override(&"separation", 0)
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_caption_box)
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
	layer.add_child(_skip_hint)
	_skip_hint.create_tween().tween_property(_skip_hint, ^"modulate:a", 0.8, 0.6).set_delay(1.0)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


## Shows a caption (a title and a line under it) for `seconds`.
func _show_caption(title: String, line: String, seconds: float, small_title := false) -> void:
	for child in _caption_box.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = title
	head.theme_type_variation = &"HeaderLabel" if small_title else &"TitleLabel"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_theme_font_size_override(&"font_size", 30 if small_title else 56)
	_caption_box.add_child(head)
	if line != "":
		var sub := Label.new()
		sub.text = line
		sub.theme_type_variation = &"SubheaderLabel"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sub.add_theme_font_size_override(&"font_size", 24)
		_caption_box.add_child(sub)
	var tween := _caption.create_tween()
	tween.tween_property(_caption, ^"modulate:a", 1.0, 0.35)
	tween.tween_interval(maxf(seconds - 0.75, 0.0))
	tween.tween_property(_caption, ^"modulate:a", 0.0, 0.4)
