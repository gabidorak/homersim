class_name Outro
extends Cinematic
## The end-of-match cinematics, "Grandma's toast" (14.7 and 15.85 s, before the post-match screen,
## played by client/outro/outro_screen.gd): at dawn, in town, a grandma makes her toast with the power
## from Sunny Acres, her grandson's photo on the wall (a supervisor, holding up a donut).
##   SUPERVISORS  the plant made it through the night: DING, a golden slice flips high onto her plate,
##                another lands on it; she stares at them (behind her the cooling towers puff a heart),
##                hops with joy, gives the photo a thumbs up and a wink, and the photo winks back;
##                CRUNCH, and a beat later her grandson bites his donut too; bliss; in its cage on the
##                sink counter, a caged rat glares at her and turns its back: hmph.
##   RATS         the power is failing: the toaster barely warms, two pale slices creep up and one flops
##                over the slot. The cooling towers cough a goo-green puff, the plant's lights go out,
##                then the town's, house by house towards her, her lamp last. In the dark, a pair of
##                goo-green eyes per winning rat blinks open around the kitchen, crunch crunch crunch, a
##                snicker chorus, a hush; she strikes a match: the rat by the toaster, caught in its
##                light, dives off the counter, the toaster and her plate are empty, its tail slips over
##                the edge. Fft. Near-black, and one more pair of eyes opens by her cheek.
## Each gag has its own beat: a lead-in, the hit, a hold for the reaction (no shot under 1.1 s).
## No words: the animation, the sounds and a few "hmph"s tell it. Never scary: the rats are cheeky.
##
## Built in code like the intro (Cinematic runs both): the set (OutroKitchen), grandma (an IntroActor
## of the generated grandma.glb), the rats, the effects (OutroFx). Unlike the intro, everything that
## moves is a pure function of the clock (_pose(t)): grandma plays her performance clip (written frame by
## frame to this clock in tools/blender/grandma.py), the rats their clips (tools/blender/rat.py) at
## times this script picks, the slices follow their ToastPath, the lever, the lamps, the town's lights,
## the photo and the clock their curves, the towers' puffs (the heart, the cough) theirs. So seek(t)
## shows any moment exactly, and the physics tests (tests/unit/test_outro.gd) sample the whole timeline
## at 1/120 s. The cues only fire what leaves no state behind: sounds, particles, hearts. The camera
## keeps still between its cuts (no shake), framed for 16:9: a narrower window sees more above and below
## (the same width), a wider one more at the sides.

enum Ending { SUPERVISORS, RATS }

const LENGTHS := {Ending.SUPERVISORS: 14.7, Ending.RATS: 15.85}  ## s
## Grandma's performance for each ending (tools/blender/grandma.py writes them to this clock).
const CLIPS := {Ending.SUPERVISORS: "outro_supervisors", Ending.RATS: "outro_rats"}
const MUSIC := {Ending.SUPERVISORS: "res://assets/audio/music/outro_supervisors.ogg",
	Ending.RATS: "res://assets/audio/music/outro_rats.ogg"}
const MUSIC_DB := 0.0
const FADE_IN := 0.6
const FADE_OUT := 0.45
const CUT_OUT := 0.04  ## the rats' ending cuts to black on its last snicker
## The rats' ending shows one pair of eyes per winning rat, each at a spot of its own (spots()): at
## most this many (and at least one); DEFAULT_RATS when nobody says (tests, OutroShots).
const MAX_RATS := 6
const DEFAULT_RATS := 4
## Hit points. Grandma's performances (tools/blender/grandma.py A_*, B_*) and the scores
## (tools/audio/music.py OUTRO_*) hit the same times: move one, move it there too. Each gag has its
## own beat: a lead-in, the hit, a hold for the reaction (tests/unit/test_outro.gd keeps them apart).
const A_PRESS := 0.8  ## her palm meets the lever's knob...
const A_CLICK := 0.9  ## ...and pushes it down: click (on a frame of her clip: her palm is all the way down)
const A_DING := 3.8
const A_SECOND := 0.2  ## the second slice pops this much after the first (they land at 4.56 and 4.8 s)
const A_HEART := 5.12  ## she stares at her slices: behind her, the cooling towers puff a heart
const A_JOY := 5.75
const A_SPARKLE := 6.5  ## her thumbs up to the photo: it twinkles...
const A_HER_WINK := 6.8  ## ...and she winks at it (her left eye shut, her face to us)
const A_WINK := 7.95  ## her grandson winks back from his photo
const A_GRAB := 9.3  ## her left hand takes the top slice
const A_BITE := 9.7  ## CRUNCH
const A_COPY := 10.6  ## ...and a beat later, back on his photo, her grandson bites his donut too
const A_HMPH := 12.0  ## the caged rat turns its back on her bliss
const B_FLICKER := 0.4
const B_PRESS := 0.8
const B_CLICK := 0.9
const B_TAPS: Array[float] = [3.08, 3.32]
const B_PWOMP := 3.8
const B_UP := 4.3  ## the pale slices have crept up
const B_FOLDED := 4.62  ## the limp one lies folded over the slot
const B_SHOCK := 4.6
const B_TILT := 5.6  ## her grandson's photo starts tilting
const B_COUGH := 6.3  ## the cooling towers cough a goo-green puff...
const B_ROLL := 7.0  ## ...the plant's lights go out, then each house's, nearer and nearer (ROLL_GAPS)...
const ROLL_GAPS: Array[float] = [0.28, 0.27, 0.26, 0.25, 0.25, 0.25, 0.25]
const B_BLACKOUT := 9.25  ## ...and her lamp goes last: its dying stutter, then the night
## In the dark the eyes blink open one pair at a time over EYE_WINDOW s from B_EYES, however many rats
## won (eyes_at: more rats, closer together), each rat crunching after its eyes open...
const B_EYES := 9.85
const EYE_WINDOW := 1.8
const B_SNICKER := 11.85  ## ...a snicker chorus; a beat of silence...
const B_STRIKE := 12.85  ## ...she strikes a match...
const B_LIGHT := 12.9  ## ...it flares: the rat by the toaster is caught in its light...
const B_LEAP := 13.2  ## ...dives over the counter's front edge, hangs there (its tail over it)...
const B_SLIP := 13.75  ## ...and slips away as she sees it; she holds her baffled look...
const B_BLOW := 14.4  ## ...and blows the match out: the dark, darker (her eyes were used to the flame)...
const B_BUTTON := 15.0  ## ...a last pair of eyes opens right by her cheek; a snicker; a beat; cut
## The toaster (tools/blender/kitchen.py): a slice's bottom above the toaster's base with the lever
## down and up, and how high the pale ones creep (TOAST_LIMP_UP).
const TOAST_DOWN := 0.047
const TOAST_UP := 0.12
const TOAST_LIMP_UP := 0.172
const TOASTER_TOP := 0.197
const RAT_SCALE := 0.42
## The rat that hangs from the counter's front edge by its tail (RATS): the island's front face (from its
## mark), and its tail's segments' directions (world: up its front, over the edge, its curl along the top).
const ISLAND_FRONT := 0.275
## The bend of its tail over the edge (its last segment's head): this far above the top (its radius there:
## it lies on it) and out from the face (its climbing segment's radius: up along it).
const HOOK_CLEAR := Vector2(0.0115, 0.0155)
const TAIL_TIP := Vector3(0.0, 0.085, -0.075)  ## the tail's last segment, to its tip (rat.py TAIL_END - tail_4)
const TAIL_HOOK: Array[Vector3] = [Vector3(-0.65, 1.0, -0.3), Vector3(0.05, 1.0, -0.06), Vector3(0.7, 1.0, 0.0),
	Vector3(0.85, -0.045, -0.5)]  # (up the face in a curve, then sideways along the top, following its taper: a hook)
const TAIL_STRETCH := 1.7  ## (a cartoon tail: it stretches as it holds on)
## The caged rat (SUPERVISORS): its size, where it sits in the cage (the cage's own space, unscaled:
## tools/blender/intro_props.py; on its floor, between the wheel and the bowl) and which way it faces
## (towards her and the room; with the hmph it turns its back on her, and on us).
const CAGED_SCALE := 0.28
const CAGED_AT := Vector3(-0.131, 0.08, 0.0)
const CAGED_YAW := -0.45
const CAGED_TURN := -2.1
## The matches in her hands, in the hand bones' space (their palm is 4 cm down the bone).
const MATCHBOX_GRIP := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.01, -0.045, 0.045))
const MATCH_GRIP := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, -0.03, 0.05))
const GOO := Color(0.61, 1.0, 0.18)  ## the rats' eyes (the intro's goo)
## A rat's eyes on its head (the head bone's space, scaled with it), and the last pair by grandma's face
## (her head bone's space: right beside her left cheek, in front of her ear, at her face's depth).
const RAT_EYES: Array[Vector3] = [Vector3(-0.07, 0.09, 0.19), Vector3(0.07, 0.09, 0.19)]
const BUTTON_EYES: Array[Vector3] = [Vector3(0.26, 0.12, 0.13), Vector3(0.335, 0.125, 0.12)]
## Her hand (tools/blender/grandma.py _hand: a box rounded by HAND_ROUND, its centre 4.2 cm down the
## hand bone; in the bone's axes) and the lever's knob (kitchen.py KNOB): the lever goes down as far
## as her palm pushes it.
const PALM := Vector3(0.0, -0.042, 0.0)
const HAND_HALF := Vector3(0.036, 0.045, 0.044)
const HAND_ROUND := 0.03
const KNOB_HALF := Vector3(0.015, 0.011, 0.025)
const KNOB_ROUND := 0.008

var ending := Ending.SUPERVISORS
var rats := DEFAULT_RATS  ## the winning rats (RATS): one pair of eyes each, 1..MAX_RATS
var set_: OutroKitchen
var grandma: IntroActor
var fx: OutroFx
var playing := true  ## false: the clock only moves with seek() (tests, screenshots)
var toasts: Array[Node3D] = []  ## each slice's pivot (its centre)
var paths: Array[ToastPath] = []
var toast_size := Vector3(0.105, 0.118, 0.0152)  ## a slice's box (from the model)
## The rats in the dark (RATS), one per winning rat: {spot (spots()), actor (an IntroActor, or null for
## eyes alone), glints (its eyes), light, held (what it eats, or null)}.
var gang: Array[Dictionary] = []
var cage_rat: IntroActor  ## SUPERVISORS
var match_: Node3D
var matchbox: Node3D

var _bitten: Node3D  # the top slice once she has bitten it (SUPERVISORS)
var _whole: Node3D
var _limp_middle: Node3D  # the limp slice's hinged parts (RATS)
var _limp_top: Node3D
var _flame: Node3D
var _match_light: OmniLight3D
var _face_light: OmniLight3D  # the match's glow on her face (between the flame and the camera)
var _tail_light: OmniLight3D  # ...and on the tail slipping over the counter's edge
var _crumbs: Array[Dictionary] = []  # what the rats leave behind: {mesh, from} (shown from that time)
var _button_glints: Array[MeshInstance3D] = []  # the last pair of eyes, by her face (RATS)
var _button_light: OmniLight3D
var _grip := Transform3D.IDENTITY  # the top slice in her left hand, from the moment she takes it
var _grip_known := false
var _hum: AudioStreamPlayer
var _bed: AudioStreamPlayer  # birdsong or crickets


func _init(p_ending := Ending.SUPERVISORS, p_rats := DEFAULT_RATS) -> void:
	ending = p_ending
	rats = clampi(p_rats, 1, MAX_RATS)
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


# --- The cast: the slices, the rats, the matches --------------------------------------------------------

func _cast() -> void:
	var probe := Art.instance("toast")
	if probe != null:
		for mesh in Art.meshes(probe):
			toast_size = mesh.get_aabb().size
		probe.free()
	var in_rats := ending == Ending.RATS
	for k in 2:
		var pivot := Node3D.new()
		pivot.name = "Toast%d" % (k + 1)
		set_.add_child(pivot)
		var model := "toast_limp" if in_rats and k == 0 else ("toast_pale" if in_rats else "toast")
		var slice := Art.add(pivot, model, Transform3D(Basis.IDENTITY, Vector3(0, -toast_size.y * 0.5, 0)))
		if in_rats and k == 0 and slice != null:
			_limp_middle = Art.part(slice, "Middle")
			_limp_top = Art.part(slice, "Top")
		if not in_rats and k == 1 and slice != null:
			_whole = slice
			_bitten = Art.add(pivot, "toast_bitten", slice.transform)
			if _bitten != null:
				_bitten.visible = false
		toasts.append(pivot)
	paths = _paths()
	if in_rats:
		_cast_rats()
	elif set_.cage != null:
		cage_rat = IntroActor.create(set_.cage, "rat", CAGED_AT, CAGED_YAW, "idle")
		cage_rat.name = "CagedRat"
		cage_rat.scale = Vector3.ONE * CAGED_SCALE / OutroKitchen.CAGE_SCALE


## The rats' spots in the dark, in the order their eyes open: by the toaster (eating the pale slice),
## on top of the fridge, at the butter, on the windowsill, in the cat clock's eyes (no rat: its eyes
## alone), on her plate. {name, at (where it sits, world), yaw, clip, holds (a slice), crunches (s:
## after its eyes open, all before the snicker), on (what it sits on, for the tests)}; the cat clock's
## {name, eyes (world), crunches}.
func spots() -> Array[Dictionary]:
	var toaster := set_.toaster.global_position
	var top := toaster.y  # the counter's top
	var butter := set_.butter.get_parent_node_3d().global_position
	var plate := Art.part(set_.plate, "Surface")
	var plate_top := plate.global_position if plate != null else set_.plate.global_position + Vector3(0, 0.01, 0)
	var out: Array[Dictionary] = [
		{"name": "toaster", "at": Vector3(toaster.x + 0.23, top, toaster.z + 0.18), "yaw": 0.15, "clip": "gnaw",
			"holds": true, "crunches": [0.28, 0.52, 0.76, 1.02], "on": "the counter"},
		{"name": "fridge", "at": OutroKitchen.FRIDGE + Vector3(-0.08, 1.45, 0.17), "yaw": -0.35, "clip": "sit_gnaw",
			"holds": true, "crunches": [0.26, 0.5, 0.78], "on": "the fridge"},
		{"name": "butter", "at": butter + Vector3(0.165, 0.0, 0.02), "yaw": -0.95, "clip": "gnaw", "holds": false,
			"crunches": [0.28, 0.56], "on": "the counter"},
		{"name": "sill", "at": OutroKitchen.SILL + Vector3(0.05, 0.0, 0.06), "yaw": 0.1, "clip": "sit_gnaw",
			"holds": false, "crunches": [0.26, 0.5], "on": "the windowsill"},
		{"name": "clock", "eyes": set_.cat_eyes(), "crunches": []},
		{"name": "plate", "at": plate_top, "yaw": -0.2, "clip": "sit_gnaw", "holds": false,
			"crunches": [0.22, 0.42], "on": "the plate"},
	]
	for i in out.size():  # (each rat's crunches, after its eyes)
		var times: Array[float] = []
		for after: float in out[i]["crunches"]:
			times.append(eyes_at(i) + after)
		out[i]["crunches"] = times
	return out


## When rat `i`'s eyes blink open: one pair after the other, evenly over the EYE_WINDOW (the same
## window for any number of rats).
func eyes_at(i: int) -> float:
	return B_EYES + EYE_WINDOW * i / rats


func _cast_rats() -> void:
	var all := spots()
	for i in rats:
		var spot: Dictionary = all[i]
		var member := {"spot": spot, "actor": null, "glints": _make_glints(), "light": null, "held": null}
		if spot.has("clip"):
			var actor := IntroActor.create(set_, "rat", spot["at"], spot["yaw"], "idle")
			actor.name = "Rat_" + spot["name"]
			actor.scale = Vector3.ONE * RAT_SCALE
			actor.visible = false
			member["actor"] = actor
			if spot["holds"]:  # a pale slice, held up at its mouth in both hands
				var held := Art.add(actor, "toast_pale")
				if held != null:
					actor.attach(held, "head", Transform3D(Basis(Vector3.RIGHT, -0.3).scaled(Vector3.ONE * 0.75 / RAT_SCALE),
						Vector3(0.0, -0.27, 0.25)))  # (its top at the rat's teeth, under its eyes)
					member["held"] = held
		var light := OmniLight3D.new()  # the eyes' glow on what's around them
		light.light_color = GOO
		light.omni_range = 0.12
		light.light_energy = 0.0
		set_.add_child(light)
		member["light"] = light
		gang.append(member)
	_button_glints = _make_glints()
	_button_light = OmniLight3D.new()  # (their glow on her cheek, like every pair's)
	_button_light.light_color = GOO
	_button_light.omni_range = 0.15
	_button_light.light_energy = 0.0
	set_.add_child(_button_light)
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
		_tail_light = OmniLight3D.new()
		_tail_light.light_color = Color(1.0, 0.66, 0.36)
		_tail_light.omni_range = 0.3
		_tail_light.light_energy = 0.0
		set_.add_child(_tail_light)
	_cast_crumbs()


## A pair of goo-green eyes: the intro's glint, keeping its size when scaled (they blink and squint).
func _make_glints() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for side in 2:
		var glint := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.075
		glint.mesh = quad
		glint.material_override = _eye_material()
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glint.visible = false
		set_.add_child(glint)
		out.append(glint)
	return out


## Crumbs: what each rat leaves where it ate, from its first crunch: by the toaster and on her plate
## (the rat by the toaster ate the slices), more on her plate (the rat there), on top of the fridge,
## geranium petals on the sink counter (the rat on the windowsill); the rat at the butter bites it. More
## rats, more mess.
func _cast_crumbs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var plate := Art.part(set_.plate, "Surface")
	var top := plate.global_position if plate != null else set_.plate.global_position + Vector3(0, 0.01, 0)
	var counter := set_.toaster.global_position
	for member in gang:
		var spot: Dictionary = member["spot"]
		if spot["crunches"].is_empty():
			continue
		var from: float = spot["crunches"][0]
		match spot["name"]:
			"toaster":
				for i in 7:  # by the toaster, where it sat
					_crumb(rng, counter + Vector3(rng.randf_range(0.17, 0.3), 0.0, rng.randf_range(0.1, 0.24)), from)
				for i in 4:
					_crumb_on_plate(rng, top, from)
			"plate":
				for i in 7:
					_crumb_on_plate(rng, top, from)
			"fridge":
				var at: Vector3 = spot["at"]
				for i in 5:
					_crumb(rng, Vector3(at.x + rng.randf_range(-0.12, 0.12), OutroKitchen.FRIDGE.y + 1.45,
						at.z + rng.randf_range(0.0, 0.12)), from)
			"sill":
				for i in 5:
					var at := Vector3(OutroKitchen.SILL.x + rng.randf_range(-0.3, -0.05), OutroKitchen.COUNTER_TOP,
						OutroKitchen.BACK + rng.randf_range(0.06, 0.16))
					_crumb(rng, at, from, Color("e84a5f"))


func _crumb_on_plate(rng: RandomNumberGenerator, top: Vector3, from: float) -> void:
	var a := rng.randf() * TAU  # (on the plate's flat middle)
	_crumb(rng, top + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.07), from)


func _crumb(rng: RandomNumberGenerator, at: Vector3, from: float, color := Color()) -> void:
	var crumb := MeshInstance3D.new()
	var box := BoxMesh.new()
	var size := rng.randf_range(0.004, 0.009)
	box.size = Vector3(size, size * 0.7, size * rng.randf_range(0.8, 1.3))
	crumb.mesh = box
	if color == Color():
		color = Color("d8953e") if rng.randf() < 0.6 else Color("f4e9cf")
	crumb.material_override = IntroSet.flat(color)
	crumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_.add_child(crumb)
	crumb.global_position = at + Vector3(0, size * 0.35, 0)  # (resting on it)
	crumb.rotation.y = rng.randf() * TAU
	crumb.visible = false
	_crumbs.append({"mesh": crumb, "from": from})


## The rats' eyes: the intro's goo glint, keeping its size when scaled (they blink and squint).
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
			path.gone(B_EYES - 0.12)  # taken in the dark: the rats have them (and eat them)
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
	set_.set_photo(photo_at(time))
	fx.towers(set_.tower_tops, time, false)
	fx.heart_cloud(set_.tower_tops, time, A_HEART)
	_pose_cage_rat(time)


## Her grandson's photo at `time`: proud, then winking back at her, biting his donut a beat after her
## CRUNCH, chewing happily after.
static func photo_at(time: float) -> OutroKitchen.Photo:
	if time >= A_COPY + 0.1:
		return OutroKitchen.Photo.BITTEN
	if time >= A_COPY - 0.06:
		return OutroKitchen.Photo.BITE
	if time >= A_WINK and time < A_WINK + 0.4:
		return OutroKitchen.Photo.WINK
	return OutroKitchen.Photo.PROUD


## The caged rat: sulking, arms crossed; when the toast flies it can't help looking (its head follows
## the slices up and down onto her plate); while she chews it glares at her, jealous, then turns its
## back on her with a huff, its nose in the air.
func _pose_cage_rat(time: float) -> void:
	if cage_rat == null:
		return
	if time < A_HMPH:
		cage_rat.pose_at("sulk", fposmod(time - A_HMPH, 3.0))
	else:
		cage_rat.pose_at("hmph", time - A_HMPH)
	var turn := _ramp(time, A_HMPH + 0.02, A_HMPH + 0.24, Tween.TRANS_BACK, Tween.EASE_OUT)
	var hop := sin(PI * clampf((time - A_HMPH) / 0.24, 0.0, 1.0))
	cage_rat.rotation.y = CAGED_YAW + CAGED_TURN * turn
	cage_rat.position = CAGED_AT + Vector3.UP * 0.05 * hop
	# The glance: its head turns up towards the flying slices, then down to her plate, then back.
	var look := _ramp(time, A_DING + 0.05, A_DING + 0.25) * (1.0 - _ramp(time, 5.0, 5.35))
	if look > 0.0:
		var up := 0.5 * (1.0 - _ramp(time, 4.2, 4.65))  # (up while they fly, down as they land)
		_turn_bone(cage_rat, "head", Basis.from_euler(Vector3(-0.55 * up - 0.3, -0.25, 0.0)), look)
	# The glare: its head turns up to her as she chews (the shot cuts to it), then the hmph.
	var glare := _ramp(time, A_HMPH - 0.42, A_HMPH - 0.22) * (1.0 - _ramp(time, A_HMPH, A_HMPH + 0.08))
	if glare > 0.0:
		_turn_bone(cage_rat, "head", Basis.from_euler(Vector3(-0.25, -0.6, 0.0)), glare)


## Turns `bone` by `turn` (in its parent's space) on top of its clip's pose, `amount` of the way.
static func _turn_bone(actor: IntroActor, bone: String, turn: Basis, amount: float) -> void:
	var skel := actor.skeleton
	var index := skel.find_bone(bone) if skel != null else -1
	if index < 0:
		return
	var q := Quaternion.IDENTITY.slerp(turn.get_rotation_quaternion(), amount)
	skel.set_bone_pose_rotation(index, q * skel.get_bone_pose_rotation(index))


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
	set_.set_power(power, _night_at(time))
	set_.set_town_lights(town_lights_at(time))
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
	fx.towers(set_.tower_tops, time, true, B_ROLL)
	fx.cough(set_.tower_tops, time, B_COUGH)
	_pose_gang(time)
	_pose_button(time)
	_pose_match(time)
	for crumb in _crumbs:
		(crumb["mesh"] as MeshInstance3D).visible = time >= float(crumb["from"])
	var butter := _member("butter")
	if set_.butter_bitten != null:  # (the rat there had a nibble)
		var bitten := not butter.is_empty() and time >= float(butter["spot"]["crunches"][0])
		set_.butter_bitten.visible = bitten
		set_.butter.visible = not bitten
	fx.steam_light(power + _match_glow(time))


## The rat at the spot `spot_name`, or {} when fewer rats won.
func _member(spot_name: String) -> Dictionary:
	for member in gang:
		if member["spot"]["name"] == spot_name:
			return member
	return {}


## When the power cut reaches each of the town's lights (the set's town_lights: the plant first, then the
## houses from the farthest in), quicker and quicker; her lamp comes after them all (B_BLACKOUT).
func roll_times() -> Array[float]:
	var out: Array[float] = []
	var at := B_ROLL
	for k in set_.town_lights.size():
		out.append(at)
		at += ROLL_GAPS[mini(k, ROLL_GAPS.size() - 1)]
	return out


## Each of the town's lights at `time` (1 lit .. 0 out): a quick stutter as it goes.
func town_lights_at(time: float) -> Array[float]:
	var out: Array[float] = []
	for at in roll_times():
		var s := time - at
		out.append(1.0 if s < 0.0 else ([0.25, 1.0, 0.1][int(s / 0.03)] if s < 0.09 else 0.0))
	return out


## The rats in the dark: each appears as its eyes blink open (at its spot, eyes_at(i)), eats (crunch,
## crunch), squints with the snicker chorus, and is gone when the match flares; the one by the toaster
## dives off the front of the counter: its tail is left, slipping over the edge.
func _pose_gang(time: float) -> void:
	var lit := time >= B_LIGHT
	for i in gang.size():
		var member := gang[i]
		var spot: Dictionary = member["spot"]
		var actor: IntroActor = member["actor"]
		var from := eyes_at(i)
		var here := time >= from and not (lit and i > 0)
		var open := _ramp(time, from, from + 0.07) * (1.0 - _blink(time, from + 0.42 + 0.11 * i))
		var squint := 0.45 if time >= B_SNICKER + 0.035 * i and time < B_SNICKER + 0.035 * i + 0.28 else 1.0
		var eyes: Array[Vector3] = []
		if actor != null:
			if i == 0:
				open *= 1.0 - _ramp(time, B_LEAP - 0.05, B_LEAP)
				here = time >= from and time < B_SLIP + 0.3
				_pose_toaster_rat(actor, spot, time, from)
			else:
				actor.pose_at(spot["clip"], time - from + 0.1 * i)
			actor.visible = here
			var head := bone_xform(actor, "head")
			for p in RAT_EYES:
				eyes.append(head * p)
			var held: Node3D = member["held"]
			if held != null:
				held.visible = time < B_LEAP
		else:
			eyes = spot["eyes"]
			set_.set_cat_pupils(not here)
		var glints: Array[MeshInstance3D] = member["glints"]
		for k in glints.size():
			glints[k].global_position = eyes[k]
			glints[k].visible = here and open > 0.01
			glints[k].scale = Vector3(1.0, maxf(open * squint, 0.05), 1.0)
		var light: OmniLight3D = member["light"]
		light.global_position = (eyes[0] + eyes[1]) * 0.5 + Vector3(0, 0.0, 0.08)
		light.light_energy = 0.05 * open if here else 0.0


## The rat by the toaster: gnawing its slice; then off the front edge: it hangs there upside down by its
## tail (stretched, cartoon-like), hooked over the edge like a question mark (lit by the match), its body
## below the frame; the hook slips and it drops.
func _pose_toaster_rat(actor: IntroActor, spot: Dictionary, time: float, from: float) -> void:
	var at: Vector3 = spot["at"]
	if time < B_LEAP:
		actor.pose_at(spot["clip"], minf(time, B_LIGHT) - from)  # (frozen, caught in the match's light)
		actor.position = at
		actor.rotation = Vector3(0.0, spot["yaw"], 0.0)
		return
	var u := _ramp(time, B_LEAP, B_LEAP + 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
	# The slip: the tail's hook flicks up off the top (a whip), then the rat drops, its tail flicking
	# over the front.
	var flick := _ramp(time, B_SLIP, B_SLIP + 0.07, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var drop := _ramp(time, B_SLIP + 0.06, B_SLIP + 0.26, Tween.TRANS_QUAD, Tween.EASE_IN)
	actor.pose_at("idle", time - B_LEAP)  # (hanging there, calm, rubbing its hands)
	actor.rotation = Vector3(0.0, spot["yaw"] * (1.0 - u), PI * u)  # (head down, facing the room)
	actor.position = at
	var skel := actor.skeleton
	if skel == null:
		return
	# Where the bend of its hooked tail (tail_4's head) would be with the rat where it stands: then the
	# whole rat moves so the bend sits on the counter's front corner (and drops as the hook slips).
	var stretch := lerpf(1.0, TAIL_STRETCH, u)
	var to_skel := skel.global_transform.basis.orthonormalized().inverse()  # world -> skeleton space (turn)
	var bend := skel.get_bone_global_pose(skel.find_bone("tail_1")).origin
	for k in 3:
		bend += _tail_turn(to_skel, TAIL_HOOK[k], k) * (skel.get_bone_rest(skel.find_bone("tail_%d" % (k + 2))).origin
			* stretch)
	var edge := set_.island.global_position + Vector3(0, OutroKitchen.COUNTER_TOP, ISLAND_FRONT)
	var corner := Vector3(at.x - 0.03, edge.y + HOOK_CLEAR.x, edge.z + HOOK_CLEAR.y)
	actor.position = at.lerp(at + corner - skel.global_transform * bend, u) + Vector3.DOWN * 0.5 * drop
	# The tail: up from its rump along the counter's front, over the edge, its curl sideways on the top;
	# as it slips the hook straightens and slides off.
	skel.set_bone_pose_scale(skel.find_bone("tail_1"), Vector3.ONE * stretch)
	var parent := skel.get_bone_global_pose(skel.find_bone("body")).basis.orthonormalized()
	for k in 4:  # (each turn from its parent's, as set here: the skeleton's own may not be updated yet)
		var bone := skel.find_bone("tail_%d" % (k + 1))
		var dir := TAIL_HOOK[k]
		if k == 3:  # (up off the top, then over the front as it falls: never back through the counter)
			dir = dir.lerp(Vector3.UP, flick).lerp(Vector3(0.3, 0.1, 1.0), drop)
		var want := _tail_turn(to_skel, dir, k)
		var turn := skel.get_bone_pose_rotation(bone).slerp((parent.inverse() * want).get_rotation_quaternion(), u)
		skel.set_bone_pose_rotation(bone, turn)
		parent = parent * Basis(turn)


## A tail segment's turn (skeleton space) pointing it (from its head to the next one's, or to the tip)
## along `dir` (world), its side towards the counter's face for the first two (they climb it), up after.
func _tail_turn(to_skel: Basis, dir: Vector3, k: int) -> Basis:
	var skel: Skeleton3D = gang[0]["actor"].skeleton
	var rest := TAIL_TIP if k == 3 else skel.get_bone_rest(skel.find_bone("tail_%d" % (k + 2))).origin
	var up := Vector3.FORWARD if k < 2 else Vector3.UP
	return Basis.looking_at(to_skel * dir.normalized(), to_skel * up) * Basis(Quaternion(rest.normalized(),
		Vector3.FORWARD))


## The last pair of eyes, right by her cheek: a beat after the fft they blink open, a cheeky squint with
## the snicker, then the cut.
func _pose_button(time: float) -> void:
	var head := bone_xform(grandma, "head")
	var open := _ramp(time, B_BUTTON, B_BUTTON + 0.07)
	var squint := 0.4 if time >= B_BUTTON + 0.16 and time < B_BUTTON + 0.55 else 1.0
	for k in _button_glints.size():
		_button_glints[k].global_position = head * BUTTON_EYES[k]
		_button_glints[k].visible = open > 0.01
		_button_glints[k].scale = Vector3(1.0, maxf(open * squint, 0.05), 1.0)
	if _button_light != null:
		_button_light.global_position = head * ((BUTTON_EYES[0] + BUTTON_EYES[1]) * 0.5 + Vector3(0.0, 0.0, 0.06))
		_button_light.light_energy = 0.03 * open


## The match: the box and the match in her hands in the dark, the strike, the flame (flickering, its
## light on her face), fft.
func _pose_match(time: float) -> void:
	if match_ == null:
		return
	var held := time >= B_STRIKE - 0.7 and time < B_BUTTON
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
		var rat: IntroActor = gang[0]["actor"]
		_tail_light.global_position = bone_xform(rat, "tail_4").origin + Vector3(0.0, 0.05, 0.12)
		_tail_light.light_energy = 0.5 * flare * flicker * dying * (1.0 if time < B_SLIP + 0.3 else 0.0)
	else:
		_match_light.light_energy = 0.0
		_face_light.light_energy = 0.0
		_tail_light.light_energy = 0.0


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


## How much of the cartoon night's light shows at `time` (RATS, 0 .. 1): all of it until she blows the
## match out; then the dark is near-black (her eyes were used to the flame), and lifts a little as the
## last eyes open by her cheek.
static func _night_at(time: float) -> float:
	return 1.0 - 0.92 * _ramp(time, B_BLOW, B_BLOW + 0.12) + 0.22 * _ramp(time, B_BUTTON - 0.1, B_BUTTON + 0.5)


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


## The fade to black at `time`: in from black at the start, out at the end (the rats' ending cuts).
func _fade_at(time: float) -> float:
	var fade_in := 1.0 - smoothstep(0.05, FADE_IN, time)
	var out := FADE_OUT if ending == Ending.SUPERVISORS else CUT_OUT
	var fade_out := smoothstep(length() - out, length(), time)
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
	_sfx(A_HEART, "outro_heart", -2.0)
	for k in 2:
		var land: float = paths[k].flights()[0]["t_land"]
		_sfx(land, "outro_land", -2.0 - 3.0 * k)
		_at(land, func() -> void: fx.crumb_puff(toasts[k].global_position, 8))
	_sfx(A_JOY + 0.02, "outro_ooh")
	_at(A_JOY + 0.12, func() -> void:
		fx.hearts(grandma.bone_position("head", Vector3(-0.26, 0.32, 0.05)), 3, 1.0)  # (beside her head, in the shot)
		fx.steam_heart(set_.teacup))
	_sfx(A_JOY + 0.12, "intro_sparkle", -8.0)
	_sfx(A_JOY + 0.37, "outro_hop", -4.0)
	_at(A_SPARKLE, func() -> void: fx.sparkle(set_.picture.global_position))
	_sfx(A_SPARKLE, "intro_sparkle", -3.0)
	_at(A_WINK, func() -> void: fx.sparkle(set_.picture.global_position + Vector3(-0.03, 0.03, 0.0), 0.5))
	_sfx(A_WINK, "outro_wink")
	_sfx(A_BITE, "outro_crunch")
	_at(A_BITE + 0.02, func() -> void: fx.crumb_puff(grandma.bone_position("head", Vector3(0.0, 0.05, 0.22)), 12, true))
	_sfx(A_BITE + 0.3, "outro_mmm", -2.0)
	_sfx_pitched(A_COPY, "outro_crunch", -6.0, 1.25)  # (his, smaller)
	_sfx(A_HMPH, "outro_rat_hmph", -3.0)


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
	_sfx(B_COUGH, "outro_cough", -1.0)
	_sfx(B_COUGH + 0.15, "outro_hmm", -4.0)
	var rolls := roll_times()
	for k in rolls.size():  # each light going out: a click, nearer (louder) each time
		_sfx_pitched(rolls[k], "outro_click", -12.0 + 9.0 * k / maxf(rolls.size() - 1, 1.0), 0.85 + 0.05 * k)
	_sfx(B_BLACKOUT, "outro_bzzzt", -3.0)
	_at(B_BLACKOUT + 0.05, func() -> void:
		if _bed != null:
			create_tween().tween_property(_bed, ^"volume_db", -60.0, 0.4))
	for i in gang.size():
		_sfx_pitched(eyes_at(i), "outro_blink", -6.0, 1.0 + 0.07 * i)
		for at: float in gang[i]["spot"]["crunches"]:
			_sfx_pitched(at, "outro_nibble", -1.0 - 0.8 * i, 1.0 + 0.06 * ((i * 3) % 5) - 0.1)
		_sfx_pitched(B_SNICKER + 0.035 * i, "outro_snicker", -1.5 * i, 1.0 + 0.09 * ((i * 2) % 5) - 0.12)
	_sfx(B_STRIKE, "outro_strike")
	_at(B_LIGHT, func() -> void:  # the match flares: the rats scatter, each in a little poof
		for i in range(1, gang.size()):
			var glints: Array[MeshInstance3D] = gang[i]["glints"]
			fx.scatter((glints[0].global_position + glints[1].global_position) * 0.5 + Vector3(0, -0.04, 0)))
	_sfx(B_LIGHT + 0.02, "puff", -12.0)
	_sfx(B_LIGHT + 0.2, "outro_huh", -3.0)
	_sfx(B_BLOW, "outro_blow", -2.0)
	_sfx(B_BUTTON, "outro_blink", -8.0)
	_sfx(B_BUTTON + 0.12, "outro_giggle", -2.0)


## A one-shot sound at `pitch` (the gang's voices: each rat a little higher or lower).
func _sfx_pitched(time: float, sound: String, db: float, pitch: float) -> void:
	_at(time, func() -> void:
		if Art.headless() or not Sfx.has_sound(sound) or not is_inside_tree():
			return
		var player := AudioStreamPlayer.new()
		player.stream = Sfx.get_stream(sound)
		player.bus = &"SFX"
		player.volume_db = Sfx.volume_of(sound) + db
		player.pitch_scale = pitch
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play())


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

## Framed for 16:9: a narrower window keeps the shot's width (and sees more above and below), so nothing
## at the sides is cut; a wider one sees more at the sides.
func _place_camera(delta: float) -> void:
	super(delta)
	var view := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var aspect := view.x / maxf(view.y, 1.0)
	if aspect < 16.0 / 9.0 - 0.01:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * 16.0 / 9.0))
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT


func _shot_list() -> Array[Dictionary]:
	var eye := OutroKitchen.VIEW_EYE
	if ending == Ending.SUPERVISORS:
		return [
			# The kitchen at sunrise; while she waits the camera comes down to her left, low, onto the toaster,
			# her plate and the window (the caged rat sulks on the right).
			_shot(0.0, eye, Vector3(-0.1, 1.1, 1.82), Vector3(0.1, 1.03, -0.3), Vector3(0.1, 1.075, 0.0), 38.0, 42.0),
			# DING: the slices flip up past her face and land on her plate; she stares at them while the
			# cooling towers puff a heart in the window behind her; she hops for joy.
			_shot(A_DING - 0.35, Vector3(-0.1, 1.1, 1.82), Vector3(-0.09, 1.1, 1.74), Vector3(0.1, 1.075, 0.0),
				Vector3(0.1, 1.075, 0.0), 42.0, 41.5),
			# Her thumbs up to the photo and her wink: from her right, her face turned our way, the photo
			# on the wall behind her.
			_shot(A_JOY + 0.45, Vector3(-0.72, 1.3, 1.62), Vector3(-0.68, 1.28, 1.52), Vector3(-0.2, 1.12, -0.25),
				Vector3(-0.18, 1.1, -0.25), 38.0, 36.0),
			# The photo: he winks back.
			_shot(A_WINK - 0.4, Vector3(-0.5, 1.39, -0.12), Vector3(-0.51, 1.39, -0.16), Vector3(-0.62, 1.37, -0.8),
				Vector3(-0.62, 1.37, -0.8), 34.0, 33.0),
			# The bite.
			_shot(A_GRAB - 0.35, Vector3(-0.75, 1.28, 2.25), Vector3(-0.73, 1.27, 2.15), Vector3(-0.3, 1.08, -0.2),
				Vector3(-0.29, 1.07, -0.2), 26.0, 25.0),
			# Back on the photo: a beat later, he bites his donut too.
			_shot(A_COPY - 0.3, Vector3(-0.5, 1.39, -0.12), Vector3(-0.51, 1.39, -0.16), Vector3(-0.62, 1.37, -0.8),
				Vector3(-0.62, 1.37, -0.8), 34.0, 33.0),
			# In its cage, the rat that watched it all glares at her, and turns its back on her: hmph.
			_shot(A_HMPH - 0.5, Vector3(0.77, 0.93, 0.08), Vector3(0.77, 0.92, 0.04), Vector3(0.83, 0.78, -0.52),
				Vector3(0.83, 0.78, -0.52), 30.0, 29.0),
			# Bliss, the rat sulking behind her (a second of it, then the fade).
			_shot(A_HMPH + 1.25, Vector3(0.55, 1.08, 1.35), Vector3(0.54, 1.07, 1.3), Vector3(0.28, 0.95, -0.4),
				Vector3(0.29, 0.95, -0.4), 40.0, 39.0),
		]
	return [
		_shot(0.0, eye, eye + Vector3(0.02, -0.08, -0.45), Vector3(0.1, 1.03, -0.3), Vector3(0.03, 1.04, -0.1),
			38.0, 36.0),
		# The toaster and her face: two pale slices creep up, one flops over; her shock.
		_shot(3.72, Vector3(-0.12, 1.22, 1.35), Vector3(-0.13, 1.2, 1.28), Vector3(-0.22, 0.96, 0.1),
			Vector3(-0.22, 0.95, 0.1), 40.0, 39.0),
		# Her pout, the photo.
		_shot(4.95, Vector3(-0.3, 1.32, 1.95), Vector3(-0.27, 1.3, 1.82), Vector3(-0.14, 0.98, -0.1),
			Vector3(-0.12, 0.97, 0.0), 42.0, 41.0),
		# Out of the window: the plant coughs a green puff; then a slow push in on the town as its lights go
		# out, the plant's, then the houses', nearer and nearer, the garden's lantern last.
		_shot(B_COUGH - 0.04, Vector3(0.25, 1.47, 1.45), Vector3(0.25, 1.47, 1.4), Vector3(0.62, 1.6, -1.66),
			Vector3(0.64, 1.44, -1.66), 22.5, 13.0),
		# The kitchen: she looks round from the window up at her lamp, it dies; in the dark the eyes open all
		# round it, one pair after the other (a slow push in).
		_shot(B_BLACKOUT - 0.3, Vector3(0.75, 1.36, 3.1), Vector3(0.7, 1.3, 2.7), Vector3(0.75, 1.2, -0.4),
			Vector3(0.7, 1.15, -0.4), 36.0, 32.0),
		# Lower, the match: her face, the rat caught in its light, diving off the counter, the empty
		# toaster, the crumbs, the tail hooked over the edge slipping away; fft.
		_shot(B_STRIKE - 0.04, Vector3(0.0, 1.0, 1.98), Vector3(0.0, 0.99, 1.9), Vector3(-0.06, 0.82, 0.3),
			Vector3(-0.06, 0.82, 0.3), 42.0, 41.0),
		# In the dark (cut there), closer on her: a last pair of eyes opens right by her cheek.
		_shot(B_BLOW + 0.3, Vector3(0.16, 1.07, 1.12), Vector3(0.16, 1.07, 1.07), Vector3(0.15, 1.0, 0.0),
			Vector3(0.15, 1.0, 0.0), 34.0, 33.0),
	]
