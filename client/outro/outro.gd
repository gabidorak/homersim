class_name Outro
extends Cinematic
## The end-of-match cinematics, "Grandma's toast" (8 to 9 s, before the post-match screen, played by
## client/outro/outro_screen.gd): at dawn, in town, a grandma makes her toast with the power from
## Sunny Acres, her grandson's photo on the wall (a supervisor, holding up a donut).
##   SUPERVISORS  the plant made it through the night: DING, a golden slice flips high onto her plate,
##                another lands on it, she hops with joy, gives the photo a thumbs up, CRUNCH, bliss.
##   RATS         the power is failing: the toaster barely warms, two pale slices creep up and one
##                flops over the slot. Then the lights go out all over town. Two green eyes, crunch
##                crunch crunch, a snicker; she strikes a match: the toaster and her plate are empty,
##                a tail slips over the edge of the counter. Fft.
## No words: the animation, the sounds and a few "hmph"s tell it. Never scary: the rats are cheeky.
##
## Built in code like the intro (Cinematic runs both): the set (OutroKitchen), grandma (an IntroActor
## of the generated grandma.glb), the effects (OutroFx). Unlike the intro, everything that moves is a
## pure function of the clock (_pose(t)): grandma plays her performance clip (written frame by frame
## to this clock in tools/blender/grandma.py), the slices follow their ToastPath, the lever, the lamps
## and the clock their curves. So seek(t) shows any moment exactly, and the physics tests
## (tests/unit/test_outro.gd) sample the whole timeline at 1/120 s. The cues only fire what leaves no
## state behind: sounds, particles, hearts. The camera keeps still between its cuts (no shake).

enum Ending { SUPERVISORS, RATS }

const LENGTHS := {Ending.SUPERVISORS: 8.3, Ending.RATS: 9.3}  ## s
## Grandma's performance for each ending (tools/blender/grandma.py writes them to this clock).
const CLIPS := {Ending.SUPERVISORS: "outro_supervisors", Ending.RATS: "outro_rats"}
const MUSIC := {Ending.SUPERVISORS: "res://assets/audio/music/outro_supervisors.ogg",
	Ending.RATS: "res://assets/audio/music/outro_rats.ogg"}
const MUSIC_DB := 0.0
const FADE_IN := 0.6
const FADE_OUT := 0.45
## Hit points. Grandma's performances (tools/blender/grandma.py A_*, B_*) and the scores
## (tools/audio/music.py OUTRO_*) hit the same times: move one, move it there too.
const A_PRESS := 0.8  ## her palm meets the lever's knob...
const A_CLICK := 0.9  ## ...and pushes it down: click (on a frame of her clip: her palm is all the way down)
const A_DING := 3.8
const A_SECOND := 0.2  ## the second slice pops this much after the first
const A_JOY := 5.05
const A_SPARKLE := 6.05
const A_GRAB := 6.55  ## her left hand takes the top slice
const A_BITE := 6.95
const B_FLICKER := 0.4
const B_PRESS := 0.8
const B_CLICK := 0.9
const B_TAPS: Array[float] = [3.08, 3.32]
const B_PWOMP := 3.8
const B_UP := 4.3  ## the pale slices have crept up
const B_FOLDED := 4.62  ## the limp one lies folded over the slot
const B_SHOCK := 4.6
const B_TILT := 5.45  ## her grandson's photo starts tilting
const B_BLACKOUT := 5.8
const B_RAT := 6.6  ## the rat is there (in the dark)
const B_EYES := 6.8
const B_CRUNCHES: Array[float] = [7.2, 7.4, 7.6]
const B_SNICKER := 7.72
const B_LEAP := 7.8  ## the rat dives over the counter's front edge, hangs there (its tail over it)...
const B_SLIP := 8.38  ## ...and slips away as she sees it
const B_STRIKE := 7.85
const B_LIGHT := 7.9
const B_BLOW := 8.8
## The toaster (tools/blender/kitchen.py): a slice's bottom above the toaster's base with the lever
## down and up, and how high the pale ones creep (TOAST_LIMP_UP).
const TOAST_DOWN := 0.047
const TOAST_UP := 0.12
const TOAST_LIMP_UP := 0.172
const TOASTER_TOP := 0.197
const RAT_SCALE := 0.42
## The matches in her hands, in the hand bones' space (their palm is 4 cm down the bone).
const MATCHBOX_GRIP := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.01, -0.045, 0.045))
const MATCH_GRIP := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, -0.03, 0.05))
const GOO := Color(0.61, 1.0, 0.18)  ## the rat's eyes (the intro's goo)
## Her hand (tools/blender/grandma.py _hand: a box rounded by HAND_ROUND, its centre 4.2 cm down the
## hand bone; in the bone's axes) and the lever's knob (kitchen.py KNOB): the lever goes down as far
## as her palm pushes it.
const PALM := Vector3(0.0, -0.042, 0.0)
const HAND_HALF := Vector3(0.036, 0.045, 0.044)
const HAND_ROUND := 0.03
const KNOB_HALF := Vector3(0.015, 0.011, 0.025)
const KNOB_ROUND := 0.008

var ending := Ending.SUPERVISORS
var set_: OutroKitchen
var grandma: IntroActor
var fx: OutroFx
var playing := true  ## false: the clock only moves with seek() (tests, screenshots)
var toasts: Array[Node3D] = []  ## each slice's pivot (its centre)
var paths: Array[ToastPath] = []
var toast_size := Vector3(0.105, 0.118, 0.0152)  ## a slice's box (from the model)
var rat: IntroActor
var match_: Node3D
var matchbox: Node3D

var _bitten: Node3D  # the top slice once she has bitten it (SUPERVISORS)
var _whole: Node3D
var _limp_middle: Node3D  # the limp slice's hinged parts (RATS)
var _limp_top: Node3D
var _flame: Node3D
var _match_light: OmniLight3D
var _face_light: OmniLight3D  # the match's glow on her face (between the flame and the camera)
var _crumbs: Array[MeshInstance3D] = []  # what the rat left on her plate and by the toaster
var _eye_glints: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D
var _grip := Transform3D.IDENTITY  # the top slice in her left hand, from the moment she takes it
var _grip_known := false
var _hum: AudioStreamPlayer
var _bed: AudioStreamPlayer  # birdsong or crickets


func _init(p_ending := Ending.SUPERVISORS) -> void:
	ending = p_ending
	name = "Outro"


func _ready() -> void:
	log_tag = "outro"
	var started_ms := Time.get_ticks_msec()
	_rng.seed = 6
	grandma = IntroActor.create(self, "grandma", Vector3.ZERO, 0.0, "idle")
	set_ = OutroKitchen.new(ending, _marks())
	set_.name = "Kitchen"
	add_child(set_)
	_make_camera()
	camera.near = 0.02
	fx = OutroFx.new()
	fx.name = "Fx"
	fx.camera = camera
	add_child(fx)
	_cast()
	_build_overlay()
	_make_music(MUSIC[ending], MUSIC_DB)
	_start_timeline()
	seek(0.0)
	if not Art.headless():
		fx.tea_steam(set_.teacup)
		_prewarm.call_deferred()
	Log.info("outro", "set built in %d ms" % (Time.get_ticks_msec() - started_ms))


func length() -> float:
	return LENGTHS[ending]


## Compiles the effects' shaders behind the black of the first frames (only when it plays: a seek
## shows a moment, and the prewarm would sit in front of the camera).
func _prewarm() -> void:
	if playing and is_inside_tree():
		fx.prewarm()


func _process(delta: float) -> void:
	if playing:
		super(delta)


func _exit_tree() -> void:
	Art.clear_cache()


## Shows the moment `time` (s) exactly: every pose, light and slice, and the camera. Cues before it
## count as fired (their sounds and particles don't play).
func seek(time: float) -> void:
	t = time
	_next_cue = 0
	while _next_cue < _cues.size() and _cues[_next_cue][0] < t:
		_next_cue += 1
	_pose(t)
	_place_camera(0.0)


func _tick(_delta: float) -> void:
	_pose(t)


func _finish() -> void:
	leaving = true
	for player: AudioStreamPlayer in [_hum, _bed]:
		if player != null:
			player.stop()
	finished.emit()


## Grandma's marks (tools/blender/grandma.py): name -> transform in the world.
func _marks() -> Dictionary[String, Transform3D]:
	var out: Dictionary[String, Transform3D] = {}
	if grandma.model == null:
		return out
	for node in grandma.model.find_children("Mark*", "Node3D", true, false):
		out[node.name] = (node as Node3D).global_transform
	return out


# --- The cast: the slices, the rat, the matches -------------------------------------------------------

func _cast() -> void:
	var probe := Art.instance("toast")
	if probe != null:
		for mesh in Art.meshes(probe):
			toast_size = mesh.get_aabb().size
		probe.free()
	var rats := ending == Ending.RATS
	for k in 2:
		var pivot := Node3D.new()
		pivot.name = "Toast%d" % (k + 1)
		set_.add_child(pivot)
		var model := "toast_limp" if rats and k == 0 else ("toast_pale" if rats else "toast")
		var slice := Art.add(pivot, model, Transform3D(Basis.IDENTITY, Vector3(0, -toast_size.y * 0.5, 0)))
		if rats and k == 0 and slice != null:
			_limp_middle = Art.part(slice, "Middle")
			_limp_top = Art.part(slice, "Top")
		if not rats and k == 1 and slice != null:
			_whole = slice
			_bitten = Art.add(pivot, "toast_bitten", slice.transform)
			if _bitten != null:
				_bitten.visible = false
		toasts.append(pivot)
	paths = _paths()
	if rats:
		_cast_rats()


func _cast_rats() -> void:
	rat = IntroActor.create(set_, "rat", _rat_spot(), 0.15, "idle")
	rat.scale = Vector3.ONE * RAT_SCALE
	rat.visible = false
	for side: float in [-1.0, 1.0]:  # the goo-green eyes (the intro's radioactive glint)
		var glint := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.055
		glint.mesh = quad
		glint.material_override = _eye_material()
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_.add_child(glint)
		_eye_glints.append(glint)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = GOO
	_eye_light.omni_range = 0.1
	_eye_light.light_energy = 0.0
	set_.add_child(_eye_light)
	matchbox = Art.add(set_, "matchbox")
	match_ = Art.add(set_, "match")
	if match_ != null:
		_flame = Art.part(match_, "Flame")
		_match_light = OmniLight3D.new()
		_match_light.light_color = Color(1.0, 0.62, 0.3)
		_match_light.omni_range = 1.5
		_match_light.omni_attenuation = 1.4
		_match_light.shadow_enabled = true
		_match_light.light_energy = 0.0
		match_.add_child(_match_light)
		_match_light.position = Vector3(0, 0.1, 0)
		_face_light = OmniLight3D.new()
		_face_light.light_color = Color(1.0, 0.66, 0.36)
		_face_light.omni_range = 0.55
		_face_light.light_energy = 0.0
		set_.add_child(_face_light)
	_cast_crumbs()


## Crumbs: what the rat leaves of the slices, on her plate and by the toaster (there from when it eats).
func _cast_crumbs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var plate := Art.part(set_.plate, "Surface")
	var top := plate.global_position if plate != null else set_.plate.global_position + Vector3(0, 0.01, 0)
	var spots: Array[Vector3] = []
	for i in 9:  # on the plate's flat middle
		var a := rng.randf() * TAU
		spots.append(top + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.07))
	var counter := set_.toaster.global_position
	for i in 7:  # by the toaster, where the rat sat
		spots.append(counter + Vector3(rng.randf_range(0.17, 0.3), 0.0, rng.randf_range(0.1, 0.24)))
	for at in spots:
		var crumb := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := rng.randf_range(0.004, 0.009)
		box.size = Vector3(size, size * 0.7, size * rng.randf_range(0.8, 1.3))
		crumb.mesh = box
		crumb.material_override = IntroSet.flat(Color("d8953e") if rng.randf() < 0.6 else Color("f4e9cf"))
		crumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_.add_child(crumb)
		crumb.global_position = at + Vector3(0, size * 0.35, 0)  # (resting on it)
		crumb.rotation.y = rng.randf() * TAU
		crumb.visible = false
		_crumbs.append(crumb)


## The rat's eyes: the intro's goo glint, keeping its size when scaled (they blink and squint).
func _eye_material() -> StandardMaterial3D:
	var mat := fx.glint_material().duplicate() as StandardMaterial3D
	mat.billboard_keep_scale = true
	return mat


## A bone's transform in the world, right now (from the skeleton's pose, which a seek has just set).
static func bone_xform(actor: IntroActor, bone: String) -> Transform3D:
	var skel := actor.skeleton
	if skel == null or skel.find_bone(bone) < 0:
		return actor.global_transform
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))


## Where the rat sits (in the dark): just right of the toaster, facing the room.
func _rat_spot() -> Vector3:
	var toaster := set_.toaster.global_position
	return Vector3(toaster.x + 0.23, toaster.y, toaster.z + 0.18)


## A slice standing in slot `k` (0 front, 1 back) with its bottom `height` above the toaster's base.
func _in_slot(k: int, height: float) -> Transform3D:
	var slot := Art.part(set_.toaster, "Slot%d" % (k + 1))
	var top := slot.global_position if slot != null else set_.toaster.global_position
	var base := set_.toaster.global_position.y
	return Transform3D(Basis.IDENTITY, Vector3(top.x, base + height + toast_size.y * 0.5, top.z))


func _paths() -> Array[ToastPath]:
	var out: Array[ToastPath] = []
	for k in 2:
		var path := ToastPath.new(toast_size)
		path.hold(0.0, _in_slot(k, TOAST_UP), ToastPath.State.SLOT)
		var press := A_PRESS if ending == Ending.SUPERVISORS else B_PRESS
		var click := A_CLICK if ending == Ending.SUPERVISORS else B_CLICK
		# The carriage goes down with the lever (as far as her hand pushes it), and latches.
		var slot := k
		path.follow(press - 0.1, func(_time: float) -> Transform3D:
			return _in_slot(slot, TOAST_UP - (TOAST_UP - TOAST_DOWN) * set_.lever_down()), ToastPath.State.SLOT)
		path.hold(click, _in_slot(k, TOAST_DOWN), ToastPath.State.SLOT)
		if ending == Ending.SUPERVISORS:
			_throw(path, k)
		else:
			path.move(B_PWOMP, B_UP, _in_slot(k, TOAST_DOWN), _in_slot(k, TOAST_LIMP_UP), Tween.TRANS_SINE,
				Tween.EASE_OUT)
			if k == 0:
				path.hold(B_UP, _in_slot(k, TOAST_LIMP_UP), ToastPath.State.DRAPED, "Toaster")
			path.gone(B_CRUNCHES[1] - 0.08 if k == 1 else B_CRUNCHES[2] - 0.08)
		out.append(path)
	return out


## DING: the toaster throws slice `k` onto the plate (the second onto the first), a forward flip and a
## backward one; each lands flat, crust towards the room. The second goes higher: it stays above and
## behind the first all the way, and lands once the first has stopped bouncing. It ends in grandma's
## hand.
func _throw(path: ToastPath, k: int) -> void:
	var plate := set_.plate.global_position
	var surface := Art.part(set_.plate, "Surface")
	var plate_top := surface.global_position.y if surface != null else plate.y + 0.01
	var from := _in_slot(k, TOAST_DOWN)
	var v_up := 3.3 if k == 0 else 3.7
	# The flick at the rim, once its bottom is out of the slot (+2 mm).
	var rise := set_.toaster.global_position.y + TOASTER_TOP + 0.002 - (from.origin.y - toast_size.y * 0.5)
	var rim_s := (v_up - sqrt(v_up * v_up - 2.0 * ToastPath.G * rise)) / ToastPath.G
	var top := plate_top + (toast_size.z if k == 1 else 0.0)
	path.throw(A_DING + A_SECOND * k, from, v_up, Vector2(plate.x, plate.z), top, "Plate" if k == 0 else "Toast1",
		TAU + PI * 0.5 if k == 0 else -PI * 1.5, rim_s, Vector2(0.55, 0.22) if k == 0 else Vector2(0.4, 0.14))
	if k == 1:
		path.follow(A_GRAB, _held)


## The top slice in grandma's left hand: where the hand is, the slice as she took it.
func _held(_time: float) -> Transform3D:
	return _hand_l() * _grip


func _hand_l() -> Transform3D:
	return bone_xform(grandma, "hand_l")


# --- The timeline -----------------------------------------------------------------------------------

## Everything that moves, at `time`.
func _pose(time: float) -> void:
	if not leaving:  # (a skip fades out on its own)
		_fade.color.a = _fade_at(time)
	if ending == Ending.SUPERVISORS and not _grip_known:
		# Where the top slice sits in her hand: once, from her pose when she takes it.
		_grip_known = true
		grandma.pose_at(CLIPS[ending], A_GRAB)
		_grip = _hand_l().affine_inverse() * paths[1].transform_at(A_GRAB - 0.001)
	grandma.pose_at(CLIPS[ending], time)
	set_.set_lever(_lever_at(time))  # (before the slices: they ride on its carriage)
	for k in toasts.size():
		toasts[k].transform = paths[k].transform_at(time)
		toasts[k].visible = paths[k].state_at(time)["state"] != ToastPath.State.GONE
	if ending == Ending.SUPERVISORS:
		_pose_supervisors(time)
	else:
		_pose_rats(time)
	fx.towers(set_.tower_tops, time, ending == Ending.RATS)


func _pose_supervisors(time: float) -> void:
	var heat := _ramp(time, A_CLICK, A_CLICK + 0.5, Tween.TRANS_QUAD, Tween.EASE_OUT) * (1.0 - _ramp(time, A_DING, A_DING + 0.2))
	set_.set_toaster_glow(heat * (0.9 + 0.1 * sin(time * 23.0)))
	fx.shimmer(set_.toaster.global_position + Vector3(0, TOASTER_TOP, 0), time, heat)
	set_.set_lamp(1.0)
	# The cat clock stops swinging to watch the slice fly, its eyes on it.
	var watch := _ramp(time, A_DING, A_DING + 0.1) * (1.0 - _ramp(time, 4.9, 5.1))
	set_.set_cat_clock(time + 2.0, watch, -0.011 + 0.011 * _ramp(time, A_DING + 0.2, 4.8))
	if _bitten != null:
		_bitten.visible = time >= A_BITE
		_whole.visible = time < A_BITE


func _pose_rats(time: float) -> void:
	var power := 1.0 - _ramp(time, B_BLACKOUT, B_BLACKOUT + 0.25)
	# The lamp: one flicker, dimmer once the toaster draws, a wobble, then a dying stutter.
	var lamp := 1.0
	if time > B_FLICKER and time < B_FLICKER + 0.18:
		lamp = [0.25, 1.0, 0.45, 1.0][int((time - B_FLICKER) / 0.045) % 4]
	lamp *= 1.0 - 0.18 * _ramp(time, B_CLICK, B_CLICK + 0.3) + 0.05 * sin(time * 9.0) * _ramp(time, 1.0, 1.5)
	if time >= B_BLACKOUT:
		lamp *= [0.6, 0.9, 0.35, 0.7, 0.15][mini(int((time - B_BLACKOUT) / 0.05), 4)] * power
	set_.set_lamp(lamp)
	set_.set_power(power)
	var heat := _ramp(time, B_CLICK, B_CLICK + 0.6) * (1.0 - _ramp(time, B_PWOMP, B_PWOMP + 0.3))
	set_.set_toaster_glow(heat * (0.22 + 0.16 * absf(sin(time * 11.0) * sin(time * 4.3))) * power)
	set_.set_cat_clock(minf(time, B_BLACKOUT) + 2.0)
	# The limp slice folds over the front of its slot: the middle onto the top, the end down the front.
	if _limp_middle != null:
		_limp_middle.rotation.x = PI * 0.5 * _settle(_ramp(time, B_UP, B_UP + 0.22, Tween.TRANS_QUAD, Tween.EASE_IN),
			time, B_UP + 0.22)
		_limp_top.rotation.x = PI * 0.5 * _settle(_ramp(time, B_UP + 0.08, B_FOLDED, Tween.TRANS_QUAD, Tween.EASE_IN),
			time, B_FOLDED)
	# Her grandson's photo slowly tilts on its nail.
	var s := maxf(time - B_TILT, 0.0)
	set_.photo.rotation.z = -0.24 * (1.0 - exp(-4.0 * s) * cos(7.0 * s)) if time > B_TILT else 0.0
	_pose_rat(time)
	_pose_match(time)
	for crumb in _crumbs:
		crumb.visible = time >= B_CRUNCHES[0]
	if set_.butter_bitten != null:  # (it had a nibble too)
		set_.butter_bitten.visible = time >= B_CRUNCHES[2]
		set_.butter.visible = time < B_CRUNCHES[2]
	fx.steam_light(power + _match_glow(time))


## The rat: there in the dark, eyes blinking open, eating (crunch, crunch, crunch), a snicker, then a
## dive off the front of the counter: when the match flares, only its tail is left, slipping over
## the edge.
func _pose_rat(time: float) -> void:
	if rat == null:
		return
	rat.visible = time >= B_RAT and time < B_SLIP + 0.3
	var spot := _rat_spot()
	var open := _ramp(time, B_EYES, B_EYES + 0.07) * (1.0 - _blink(time, 7.06)) * (1.0 - _ramp(time, B_LEAP - 0.05, B_LEAP))
	if time < B_CRUNCHES[0] - 0.05:
		rat.pose_at("idle", maxf(time - B_RAT, 0.0))
		rat.position = spot
		rat.rotation = Vector3(0.0, 0.15, 0.0)
	elif time < B_LEAP:
		rat.pose_at("gnaw", time - B_CRUNCHES[0])
		rat.position = spot
		rat.rotation = Vector3(0.0, 0.15, 0.0)
	else:
		# Off the front edge and down it, hanging on, the tail last over the edge.
		var edge := set_.island.global_position + Vector3(0, 0.65, 0.275)
		var u := _ramp(time, B_LEAP, B_LEAP + 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
		var down := _ramp(time, B_SLIP, B_SLIP + 0.25, Tween.TRANS_SINE, Tween.EASE_IN)
		rat.pose_at("crawl", time - B_LEAP)
		rat.rotation = Vector3(PI * 0.5 * u, 0.0, 0.0)
		rat.position = spot.lerp(Vector3(spot.x, edge.y - 0.03, edge.z + 0.012), u) + Vector3.DOWN * 0.45 * down
	# Its eyes, on its head (scaled with it): open, a blink, a cheeky squint at the snicker.
	var head := bone_xform(rat, "head")
	var squint := 0.45 if time >= B_SNICKER and time < B_SNICKER + 0.25 else 1.0
	for i in _eye_glints.size():
		var glint := _eye_glints[i]
		glint.global_position = head * (Vector3(0.07 * (i * 2 - 1), 0.09, 0.19))
		glint.visible = open > 0.01 and rat.visible
		glint.scale = Vector3(1.0, maxf(open * squint, 0.05), 1.0)
	_eye_light.global_position = head * Vector3(0.0, 0.1, 0.34)
	_eye_light.light_energy = 0.04 * open


## The match: the box and the match in her hands in the dark, the strike, the flame (flickering, its
## light on her face), fft.
func _pose_match(time: float) -> void:
	if match_ == null:
		return
	var held := time >= 7.15
	match_.visible = held
	matchbox.visible = held
	# In her hands (placed from her bones, like everything she holds).
	matchbox.global_transform = bone_xform(grandma, "hand_l") * MATCHBOX_GRIP
	match_.global_transform = bone_xform(grandma, "hand_r") * MATCH_GRIP
	var lit := time >= B_LIGHT and time < B_BLOW + 0.06
	_flame.visible = lit
	if lit:
		var flare := 1.0 + 0.6 * exp(-(time - B_LIGHT) * 14.0)
		var dying := 1.0 - _ramp(time, B_BLOW, B_BLOW + 0.06)
		var flicker := 1.0 + 0.08 * sin(time * 37.0) * sin(time * 23.0)
		_flame.scale = Vector3(1.0, flicker, 1.0) * flare * dying
		_match_light.light_energy = 1.15 * flare * flicker * dying
		_face_light.global_position = _flame.global_position + Vector3(0.05, 0.0, 0.16)
		_face_light.light_energy = 0.7 * flare * flicker * dying
	else:
		_match_light.light_energy = 0.0
		_face_light.light_energy = 0.0


## The lever (0 up .. 1 down) at `time`: wherever her right hand pushes it until it latches at the
## click; the toaster pops it at the DING (or lets it creep up with the pale slices).
func _lever_at(time: float) -> float:
	if ending == Ending.SUPERVISORS:
		return (1.0 if time >= A_CLICK else _pushed()) * (1.0 - _ramp(time, A_DING, A_DING + 0.04))
	var creep := _ramp(time, B_PWOMP, B_UP, Tween.TRANS_SINE, Tween.EASE_OUT)
	return (1.0 if time >= B_CLICK else _pushed()) * (1.0 - creep)


## How far her right hand pushes the lever now (0 .. 1): the lowest her hand comes over the knob's
## top (sampled over it), under that top with the lever up. A hand beside the knob pushes nothing.
func _pushed() -> float:
	var hand := bone_xform(grandma, "hand_r")
	var knob := set_.knob_up()
	var top := knob.y + KNOB_HALF.y
	var inv := (hand * Transform3D(Basis.IDENTITY, PALM)).affine_inverse()
	var flat := Vector2(KNOB_HALF.x, KNOB_HALF.z) - Vector2.ONE * KNOB_ROUND  # the knob's flat top
	var deepest := 0.0
	for i in 3:
		for j in 3:
			var at := Vector2(knob.x + flat.x * (i - 1), knob.z + flat.y * (j - 1))
			deepest = maxf(deepest, top - _underside(inv, at, top - OutroKitchen.LEVER_TRAVEL - 0.02, top))
	return clampf(deepest / OutroKitchen.LEVER_TRAVEL, 0.0, 1.0)


## How high her hand's underside is over `at` (x, z) between `from` and `to` (`to` if it isn't
## there): up from `from` to the hand (a rounded box: its distance is exact, each step can go that
## far). `inv` takes the world into the hand's frame (its centre).
static func _underside(inv: Transform3D, at: Vector2, from: float, to: float) -> float:
	var inner := HAND_HALF - Vector3.ONE * HAND_ROUND
	var y := from
	for i in 48:
		var q := (inv * Vector3(at.x, y, at.y)).abs() - inner
		var d := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() \
			+ minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - HAND_ROUND
		if d < 1e-4:
			return y
		y += d
		if y > to:
			break
	return to


## How much the match lights the room at `time` (0 .. about 1).
func _match_glow(time: float) -> float:
	return 0.35 * _ramp(time, B_LIGHT - 0.02, B_LIGHT + 0.05) * (1.0 - _ramp(time, B_BLOW, B_BLOW + 0.06))


## 0 before `from`, 1 after `to`, eased in between.
static func _ramp(time: float, from: float, to: float, trans := Tween.TRANS_SINE,
		ease_ := Tween.EASE_IN_OUT) -> float:
	var u := clampf((time - from) / maxf(to - from, 1e-5), 0.0, 1.0)
	return Tween.interpolate_value(0.0, 1.0, u, 1.0, trans, ease_)


## A limp thing coming to rest at `at` against what stops it: little rebounds away from it (1 at
## rest, never past it).
static func _settle(value: float, time: float, at: float) -> float:
	if time < at:
		return value
	var s := time - at
	return 1.0 - 0.06 * exp(-s * 12.0) * absf(sin(s * 30.0))


## 1 in the middle of a blink at `at`, 0 outside it.
static func _blink(time: float, at: float) -> float:
	return clampf(1.0 - absf(time - at) / 0.05, 0.0, 1.0)


## The fade to black at `time`: in from black at the start, out at the end.
func _fade_at(time: float) -> float:
	var fade_in := 1.0 - smoothstep(0.05, FADE_IN, time)
	var fade_out := smoothstep(length() - FADE_OUT, length(), time)
	return maxf(fade_in, fade_out)


func _script() -> void:
	if ending == Ending.SUPERVISORS:
		_script_supervisors()
	else:
		_script_rats()


func _script_supervisors() -> void:
	_at(0.0, func() -> void: _bed = _loop("outro_birds", -6.0))
	_sfx(A_CLICK - 0.03, "outro_lever")
	_at(A_CLICK + 0.05, func() -> void: _hum = _loop("outro_hum", -14.0))
	for at: float in [1.6, 1.85, 2.1]:
		_sfx(at, "outro_tap", -6.0)
	_sfx(2.72, "outro_sniff", -4.0)
	_sfx(2.97, "outro_sniff", -6.0)
	_at(A_DING, func() -> void:
		if _hum != null:
			_hum.stop())
	_sfx(A_DING, "outro_ding")
	_sfx(A_DING, "outro_pop")
	_sfx(A_DING + A_SECOND, "outro_pop", -3.0)
	for k in 2:
		var land: float = paths[k].flights()[0]["t_land"]
		_sfx(land, "outro_land", -2.0 - 3.0 * k)
		_at(land, func() -> void: fx.crumb_puff(toasts[k].global_position, 8))
	_sfx(A_JOY + 0.02, "outro_ooh")
	_at(A_JOY + 0.12, func() -> void:
		fx.hearts(grandma.bone_position("head", Vector3(0.0, 0.42, -0.05)), 3, 1.2)
		fx.steam_heart(set_.teacup))
	_sfx(A_JOY + 0.12, "intro_sparkle", -8.0)
	_sfx(5.42, "outro_hop", -4.0)
	_at(A_SPARKLE, func() -> void: fx.sparkle(set_.picture.global_position))
	_sfx(A_SPARKLE, "intro_sparkle", -3.0)
	_sfx(A_BITE, "outro_crunch")
	_at(A_BITE + 0.02, func() -> void: fx.crumb_puff(grandma.bone_position("head", Vector3(0.0, 0.05, 0.22)), 12, true))
	_sfx(7.25, "outro_mmm", -2.0)


func _script_rats() -> void:
	_at(0.0, func() -> void: _bed = _loop("crickets", -4.0))
	_sfx(B_FLICKER, "outro_flicker", -4.0)
	_sfx(B_CLICK - 0.03, "outro_lever", -2.0)
	_at(B_CLICK + 0.05, func() -> void: _hum = _loop("outro_hum_weak", -12.0))
	_sfx(2.2, "outro_sniff", -5.0)
	_sfx(2.45, "outro_sniff", -6.0)
	_sfx(2.68, "outro_hmm", -3.0)
	for at in B_TAPS:
		_sfx(at, "outro_tonk", -3.0)
	_at(B_PWOMP, func() -> void:
		if _hum != null:
			_hum.stop())
	_sfx(B_PWOMP, "outro_pwomp")
	_sfx(B_SHOCK, "outro_oh", -2.0)
	_sfx(5.12, "outro_hmph", -2.0)
	_sfx(B_TILT, "outro_creak", -6.0)
	_sfx(B_BLACKOUT, "outro_bzzzt", -3.0)
	_at(B_BLACKOUT + 0.05, func() -> void:
		if _bed != null:
			create_tween().tween_property(_bed, ^"volume_db", -60.0, 0.4))
	_sfx(B_EYES, "outro_blink", -6.0)
	for at in B_CRUNCHES:
		_sfx(at, "outro_nibble", -1.0)
	_sfx(B_SNICKER, "outro_snicker")
	_sfx(B_STRIKE, "outro_strike")
	_sfx(8.1, "outro_huh", -3.0)
	_sfx(B_BLOW, "outro_blow", -2.0)


## A looping sound (a bed or a hum) that the cinematic stops itself.
func _loop(sound: String, db: float) -> AudioStreamPlayer:
	if Art.headless() or not Sfx.has_sound(sound):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = Sfx.get_stream(sound)
	player.bus = &"Ambience" if Sfx.kind_of(sound) == Sfx.Kind.HUM else &"SFX"
	player.volume_db = Sfx.volume_of(sound) + db
	add_child(player)
	player.play()
	return player


# --- Camera -----------------------------------------------------------------------------------------

## Two cuts each (a third in the rats' blackout): the opening shot pushing in slowly, an insert on the
## gag, then grandma.
func _shot_list() -> Array[Dictionary]:
	var eye := OutroKitchen.VIEW_EYE
	if ending == Ending.SUPERVISORS:
		return [
			# The kitchen at sunrise, pushing in a little while she waits; it sees the slices' arc.
			_shot(0.0, eye, eye + Vector3(0.02, -0.08, -0.5), Vector3(0.1, 1.03, -0.3), Vector3(0.03, 1.04, -0.1),
				38.0, 36.0),
			# Down on the plate: the first slice lands, the second on it (her face over it).
			_shot(4.55, Vector3(0.6, 0.99, 1.12), Vector3(0.58, 0.97, 1.04), Vector3(0.25, 0.76, 0.36),
				Vector3(0.25, 0.75, 0.36), 40.0, 39.0),
			# Grandma: joy, the photo over her shoulder, the bite, bliss.
			_shot(5.15, Vector3(-0.15, 1.3, 1.8), Vector3(-0.1, 1.24, 1.42), Vector3(-0.12, 1.1, -0.25),
				Vector3(0.0, 1.0, 0.0), 40.0, 35.0),
		]
	return [
		_shot(0.0, eye, eye + Vector3(0.02, -0.08, -0.45), Vector3(0.1, 1.03, -0.3), Vector3(0.03, 1.04, -0.1),
			38.0, 36.0),
		# The toaster: two pale slices creep up, one flops over (her eyes on them).
		_shot(3.72, Vector3(0.02, 1.1, 1.22), Vector3(0.0, 1.08, 1.14), Vector3(-0.27, 0.88, 0.3),
			Vector3(-0.27, 0.87, 0.3), 38.0, 37.0),
		# Her reaction, the photo, the blackout, the eyes by the toaster.
		_shot(4.62, Vector3(-0.3, 1.32, 1.95), Vector3(-0.25, 1.28, 1.72), Vector3(-0.14, 0.94, -0.1),
			Vector3(-0.12, 0.93, 0.0), 42.0, 40.0),
		# Cut in the dark, lower: the match shows her face, the empty toaster, the crumbs on her plate and
		# the tail slipping over the counter's edge.
		_shot(B_STRIKE - 0.04, Vector3(0.0, 1.06, 1.6), Vector3(0.0, 1.05, 1.52), Vector3(-0.1, 0.84, 0.3),
			Vector3(-0.1, 0.84, 0.3), 44.0, 43.0),
	]
