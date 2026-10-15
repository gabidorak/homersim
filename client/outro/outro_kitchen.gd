class_name OutroKitchen
extends Node3D
## The end-of-match cinematics' set (client/outro/outro.gd): grandma's 1950s kitchen in town, at
## dawn. Butter-yellow walls over mint tiles, a black and white floor, mint cabinets with chrome
## pulls. Grandma stands behind the counter (the island) with the toaster, her plate, the butter and
## her tea; behind her the sink counter under the window, the window showing Sunny Acres on its hill
## past the roofs of the town, her grandson's photo on the wall, the cat clock, the fridge. Built in
## code from the generated models (tools/blender/kitchen.py), like the intro's IntroSet, whose helpers
## it shares (IntroSet.box, IntroSet.flat).
##
## Coordinates: grandma's origin is the world origin and she faces +Z, so her marks (empties in
## grandma.glb, see tools/blender/grandma.py) are world positions: the props stand on them. The back
## wall (window, photo) is at z = BACK, the camera looks at her from +Z.
##
## Two moods (Outro.Ending): SUPERVISORS, sunrise: a golden sky, the sun low behind the plant shining
## in through the window, the lamp on, a hamster cage on the sink counter (a rat sulks in it: the
## director poses it). RATS, before dawn: a deep blue sky with stars and the moon, the lamp on; the
## director puts the town's lights out one by one (set_town_lights: the plant first, then the houses
## from the farthest in) and cuts the kitchen's power last (set_power): a cartoon night is left, the
## moon through the window and a cool blue fill, dark but every shape readable.

const WALL := Color("f8e3a1")  ## butter (the palette's)
const TILES := Color("b5e2cc")  ## mint, below the wainscot
const FLOOR_A := Color("f4f1e8")
const FLOOR_B := Color("26262c")
const BACK := -0.8  ## the back wall's face
const LEFT := -1.65
const RIGHT := 2.35
const FRONT := 3.4
const HEIGHT := 2.35
const THICK := 0.15
const WINDOW_X := Vector2(0.1, 1.1)  ## the window's opening in the back wall
const WINDOW_Y := Vector2(0.95, 2.0)
const SINK := Vector3(0.2, 0.0, BACK + 0.25)  ## the sink counter, against the back wall
const FRIDGE := Vector3(1.95, 0.0, BACK + 0.31)
const CAT_CLOCK := Vector3(1.45, 1.58, BACK)
const CALENDAR := Vector3(-1.2, 1.62, BACK)
const LAMP := Vector3(0.05, HEIGHT, 0.42)  ## the pendant's ceiling rose, over the counter
const LAMP_COLOR := Color(1.0, 0.82, 0.58)
const WINDOW_CENTRE := Vector3(0.6, 1.475, BACK)
const SILL := Vector3(0.6, 0.92, BACK + 0.07)  ## the middle of the windowsill's top (kitchen.py build_window)
const COUNTER_TOP := 0.65  ## the counters' tops (kitchen.py COUNTER_H)
const VIEW_EYE := Vector3(0.05, 1.38, 2.45)  ## the opening shot's eye: the view is composed for it
const GROUND_Y := -0.4  ## outside
const TOWER_SCALE := 1.45  ## the cooling towers (22 m models): up to 8 degrees, in the window
## The toaster's glow inside its slots, at full heat.
const GLOW_COLOR := Color(1.0, 0.45, 0.12)
## How far the toaster's lever goes down: the slices' carriage moves with it (tools/blender/kitchen.py
## LEVER_TRAVEL = TOAST_UP - TOAST_DOWN).
const LEVER_TRAVEL := 0.073
## The hamster cage (tools/blender/intro_props.py's, shrunk) on the sink counter, between the sink and
## the canisters, in front of the window (SUPERVISORS).
const CAGE := Vector3(0.9, 0.65, -0.52)
const CAGE_SCALE := 0.58
## Her grandson's photo, as it comes alive (the director picks one, set_photo): proud with his donut,
## winking back at her, biting it, chewing (happy, the donut bitten).
enum Photo { PROUD, WINK, BITE, BITTEN }
## The photo studio: where his donut is (in his head bone's space: held up by his face, its icing to the
## camera and its bite on top; or at his mouth), how big (bigger than life, so the bite reads), where
## his eyes are (head space too).
const PHOTO_DONUT := Vector3(-0.4, 0.12, 0.38)
const PHOTO_DONUT_BITE := Vector3(0.0, 0.02, 0.5)
const PHOTO_DONUT_SCALE := 1.9
const PHOTO_EYE := Vector3(0.156, 0.31, 0.352)
const PHOTO_EYE_R := 0.066
## The cartoon night once the power is cut (RATS): the ambient light and a cool fill from the room's
## front, so grandma, the toaster and the rats read as shapes (the goo-green eyes stay the brightest).
const NIGHT_AMBIENT := 0.07
const NIGHT_AMBIENT_COLOR := Color(0.36, 0.45, 0.9)
const NIGHT_FILL := 0.16
const NIGHT_FILL_COLOR := Color(0.5, 0.62, 1.0)
const TOWN_NIGHT_GLOW := 1.8  ## the town's windows at night, brighter (they go out one by one)

var ending := 0  ## Outro.Ending
var environment: Environment
var marks: Dictionary[String, Transform3D] = {}
var island: Node3D
var sink_counter: Node3D
var fridge: Node3D
var window: Node3D  ## its frame, sill, geraniums and curtains
var toaster: Node3D
var lever: Node3D
var glow: Node3D
var plate: Node3D
var teacup: Node3D
var butter: Node3D
var butter_bitten: Node3D
var photo: Node3D  ## the frame (it tilts about its nail, the origin)
var picture: MeshInstance3D  ## the photo itself
var photos: Array[Texture2D] = []  ## the photo in each Photo state
var cage: Node3D  ## SUPERVISORS
var cat_tail: Node3D
var cat_pupils: Node3D
var cat_second: Node3D
var lamp_bulb: Node3D
var lamp_light: OmniLight3D
var sun: DirectionalLight3D  ## the sun (SUPERVISORS) or the moon (RATS), through the window
var fill: OmniLight3D  ## soft light from the room on grandma's face (the lamp's bounce)
var toaster_light: OmniLight3D
var night: DirectionalLight3D  ## the cartoon night's fill (RATS: on as the power goes)
## The lit windows of the plant and the town, in the order the power cut reaches them: the plant, then
## each house from the farthest to the nearest, then the garden's lantern (town_distances: how far each
## is from the opening shot's eye, m).
var town_lights: Array[Node3D] = []
var town_distances: Array[float] = []
var tower_tops: Array[Vector3] = []  ## where the cooling towers' puffs come out (world)

var _lever_rest := Vector3.ZERO
var _chrome: ShaderMaterial
var _pupils_rest := Vector3.ZERO
var _lamp_energy := 0.0
var _sun_energy := 0.0
var _fill_energy := 0.0
var _ambient := 0.0
var _ambient_color := Color.WHITE
var _town_glows: Array[OmniLight3D] = []  # the light each of the town's lights casts (or null)


## `marks`: grandma's marks (name -> transform in the world).
func _init(p_ending: int, p_marks: Dictionary[String, Transform3D]) -> void:
	ending = p_ending
	marks = p_marks


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_furniture()
	_build_breakfast()
	_build_wall_pieces()
	_build_view()
	_build_lights()
	if ending == 0:
		cage = Art.add(self, "hamster_cage", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * CAGE_SCALE), CAGE))
		_thin_outlines(cage)


# --- What the director changes ---------------------------------------------------------------------

## The ceiling lamp: 0 off .. 1 full (its bulb glows with it; the room's fill light follows).
func set_lamp(level: float) -> void:
	lamp_light.light_energy = _lamp_energy * level
	fill.light_energy = _fill_energy * (0.35 + 0.65 * level)
	Art.set_glow(lamp_bulb, level)


## The toaster's elements: 0 cold .. 1 glowing orange.
func set_toaster_glow(level: float) -> void:
	Art.set_glow(glow, level)
	Art.set_tint(glow, GLOW_COLOR.lerp(Color.WHITE, 0.15 * level))
	toaster_light.light_energy = 0.9 * level


## The kitchen's power: 1 on, 0 cut (the room's fill, the chrome's glint; the moonlight and the
## cartoon night's ambient and fill stay). The lamp has its own level (set_lamp), the town its lights.
func set_power(level: float) -> void:
	fill.light_energy = _fill_energy * level
	if ending == 1:
		environment.ambient_light_energy = lerpf(NIGHT_AMBIENT, _ambient, level)
		environment.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(_ambient_color, level)
		night.light_energy = NIGHT_FILL * (1.0 - level)
	sun.light_energy = _sun_energy * (lerpf(0.75, 1.0, level) if ending == 1 else 1.0)
	if _chrome != null:
		_chrome.set_shader_parameter(&"glint", lerpf(0.35, 0.9, level) if ending == 1 else 0.9 * level)


## The plant's and the town's windows, each 0 dark .. 1 lit (`levels` in town_lights' order).
func set_town_lights(levels: Array[float]) -> void:
	for k in town_lights.size():
		var level := levels[k] if k < levels.size() else 1.0
		Art.set_glow(town_lights[k], level * (TOWN_NIGHT_GLOW if ending == 1 else 1.0))
		if _town_glows[k] != null:
			_town_glows[k].light_energy = 1.2 * level


## Her grandson's photo in a Photo state.
func set_photo(state: Photo) -> void:
	var mat := picture.material_override as StandardMaterial3D
	if state < photos.size() and mat.albedo_texture != photos[state]:
		mat.albedo_texture = photos[state]


## The lever: 0 up .. 1 all the way down.
func set_lever(down: float) -> void:
	lever.position = _lever_rest + Vector3.DOWN * LEVER_TRAVEL * down


## How far down the lever is now (0 up .. 1 down).
func lever_down() -> float:
	return (_lever_rest.y - lever.position.y) / LEVER_TRAVEL


## The lever's knob (its centre) with the lever up, in the world.
func knob_up() -> Vector3:
	return lever.get_parent_node_3d().global_transform * _lever_rest


## The cat clock's eyes, in the world: the middle of each white eye's face (the rats' ending puts a
## rat's eyes there, glowing, its pupils hidden: set_cat_pupils).
func cat_eyes() -> Array[Vector3]:
	var clock := cat_pupils.get_parent_node_3d()
	return [clock.global_transform * Vector3(-0.04, 0.172, 0.069), clock.global_transform * Vector3(0.04, 0.172, 0.069)]


func set_cat_pupils(shown: bool) -> void:
	cat_pupils.visible = shown


## The cat clock at `seconds`: the tail swings, the eyes look the other way, the second hand ticks.
## `watch` (0..1) stills the tail and turns the eyes to `gaze` (their slide, m: the cat watches
## something).
func set_cat_clock(seconds: float, watch := 0.0, gaze := 0.0) -> void:
	var swing := sin(seconds * PI)  # one swing a second, side to side
	cat_tail.rotation.z = 0.42 * swing * (1.0 - watch)
	cat_pupils.position.x = _pupils_rest.x + lerpf(-0.011 * swing, gaze, watch)
	cat_second.rotation.z = -TAU * floorf(seconds) / 60.0


# --- Building ---------------------------------------------------------------------------------------

func _build_environment() -> void:
	environment = Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	if ending == 0:
		sky_material.sky_top_color = Color(0.5, 0.74, 0.95)
		sky_material.sky_horizon_color = Color(1.0, 0.8, 0.52)
		sky_material.ground_horizon_color = Color(1.0, 0.8, 0.52)
		sky_material.ground_bottom_color = Color(0.4, 0.42, 0.3)
		sky_material.sky_curve = 0.09
		sky_material.sun_angle_max = 8.0
		sky_material.sun_curve = 0.06
		_ambient = 0.42
		environment.ambient_light_color = Color(1.0, 0.9, 0.78)
	else:
		sky_material.sky_top_color = Color(0.03, 0.05, 0.16)
		sky_material.sky_horizon_color = Color(0.13, 0.22, 0.42)
		sky_material.ground_horizon_color = Color(0.13, 0.22, 0.42)
		sky_material.ground_bottom_color = Color(0.03, 0.04, 0.08)
		sky_material.sky_curve = 0.2
		sky_material.sun_angle_max = 3.0
		sky_material.sun_curve = 0.02
		_ambient = 0.32
		environment.ambient_light_color = Color(0.45, 0.55, 0.95)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = _ambient
	_ambient_color = environment.ambient_light_color
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.95 if ending == 0 else 0.88
	environment.tonemap_white = 1.8
	environment.ssao_enabled = true
	environment.ssao_radius = 0.35
	environment.ssao_intensity = 1.4
	environment.ssao_light_affect = 0.2
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.05
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	Config.apply_environment(environment)


func _world_material(pattern: int, base: Color, trim: Color, cell: Vector2, band := 0.95) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon_world.gdshader")
	mat.set_shader_parameter(&"pattern", pattern)
	mat.set_shader_parameter(&"base_color", base)
	mat.set_shader_parameter(&"trim_color", trim)
	mat.set_shader_parameter(&"line_color", Color(0.1, 0.1, 0.12))
	mat.set_shader_parameter(&"line_strength", 0.22)
	mat.set_shader_parameter(&"cell", cell)
	mat.set_shader_parameter(&"line_width", 0.012)
	mat.set_shader_parameter(&"band_height", band)
	mat.set_shader_parameter(&"shade_mid", 0.66)
	mat.set_shader_parameter(&"rim_strength", 0.0)
	return mat


func _build_room() -> void:
	var walls := _world_material(0, WALL, TILES, Vector2(100.0, 2.1))
	var floor_mat := _world_material(6, FLOOR_A, FLOOR_B, Vector2(0.32, 0.32))
	var w := RIGHT - LEFT
	var d := FRONT - BACK
	var cx := (LEFT + RIGHT) * 0.5
	var cz := (BACK + FRONT) * 0.5
	IntroSet.box(self, Vector3(cx, -0.25, cz), Vector3(w + 2 * THICK, 0.5, d + 2 * THICK), floor_mat)
	IntroSet.box(self, Vector3(cx, HEIGHT + 0.15, cz), Vector3(w + 2 * THICK, 0.3, d + 2 * THICK),
		IntroSet.flat(Color("fff3da")))
	# The back wall, with the window's opening; the side walls.
	var bz := BACK - THICK * 0.5
	IntroSet.box(self, Vector3((LEFT + WINDOW_X.x) * 0.5, HEIGHT * 0.5, bz), Vector3(WINDOW_X.x - LEFT, HEIGHT, THICK), walls)
	IntroSet.box(self, Vector3((WINDOW_X.y + RIGHT) * 0.5, HEIGHT * 0.5, bz), Vector3(RIGHT - WINDOW_X.y, HEIGHT, THICK),
		walls)
	var wx := (WINDOW_X.x + WINDOW_X.y) * 0.5
	var ww := WINDOW_X.y - WINDOW_X.x
	IntroSet.box(self, Vector3(wx, WINDOW_Y.x * 0.5, bz), Vector3(ww, WINDOW_Y.x, THICK), walls)
	IntroSet.box(self, Vector3(wx, (WINDOW_Y.y + HEIGHT) * 0.5, bz), Vector3(ww, HEIGHT - WINDOW_Y.y, THICK), walls)
	IntroSet.box(self, Vector3(LEFT - THICK * 0.5, HEIGHT * 0.5, cz), Vector3(THICK, HEIGHT, d), walls)
	IntroSet.box(self, Vector3(RIGHT + THICK * 0.5, HEIGHT * 0.5, cz), Vector3(THICK, HEIGHT, d), walls)
	IntroSet.box(self, Vector3(cx, HEIGHT * 0.5, FRONT + THICK * 0.5), Vector3(w + 2 * THICK, HEIGHT, THICK), walls)
	window = Art.add(self, "kitchen_window", Transform3D(Basis.IDENTITY, Vector3(wx, WINDOW_Y.x, BACK)))
	# A wall outlet behind the toaster's cord, a light switch by the window.
	IntroSet.box(self, Vector3(-0.9, 0.8, BACK + 0.006), Vector3(0.08, 0.12, 0.012), IntroSet.flat(Color("fff3da")))
	var lamp := Art.add(self, "ceiling_lamp", Transform3D(Basis.IDENTITY, LAMP))
	lamp_bulb = Art.part(lamp, "Bulb")
	Art.set_tint(lamp_bulb, Color(1.0, 0.92, 0.75))


func _build_furniture() -> void:
	island = _on_mark("kitchen_island", "MarkIsland")
	sink_counter = Art.add(self, "sink_counter", Transform3D(Basis.IDENTITY, SINK))
	fridge = Art.add(self, "fridge", Transform3D(Basis(Vector3.UP, -0.0), FRIDGE))


func _build_breakfast() -> void:
	toaster = _on_mark("toaster", "MarkToaster")
	var chrome := ShaderMaterial.new()  # cartoon chrome, its bands tinted by the hour
	chrome.shader = preload("res://shaders/toon_chrome.gdshader")
	chrome.set_shader_parameter(&"sky", Color(0.96, 0.97, 1.0) if ending == 0 else Color(0.7, 0.78, 1.0))
	chrome.set_shader_parameter(&"floor_color", Color(0.7, 0.6, 0.5) if ending == 0 else Color(0.42, 0.42, 0.55))
	_chrome = chrome
	chrome.next_pass = preload("res://shaders/materials/outline.tres")
	for mesh in Art.meshes(Art.part(toaster, "Body")):
		mesh.material_override = chrome
	lever = Art.part(toaster, "Lever")
	_lever_rest = lever.position
	glow = Art.part(toaster, "Glow")
	plate = _on_mark("plate", "MarkPlate")
	teacup = _on_mark("teacup", "MarkTeacup", -0.5)
	var dish := _on_mark("butter_dish", "MarkButter", 0.25)
	butter = Art.part(dish, "Butter")
	butter_bitten = Art.part(dish, "ButterBitten")
	if butter_bitten != null:
		butter_bitten.visible = false


func _build_wall_pieces() -> void:
	photo = _on_mark("photo_frame", "MarkPhoto")
	picture = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.2)
	picture.mesh = quad
	picture.name = "Picture"
	var marker := Art.part(photo, "Picture")
	picture.position = marker.position if marker != null else Vector3(0, -0.2, 0.03)
	photo.add_child(picture)
	for state: Photo in ([Photo.PROUD, Photo.WINK, Photo.BITE, Photo.BITTEN] if ending == 0 else [Photo.PROUD]):
		photos.append(_photo_texture(state))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = photos[Photo.PROUD]
	mat.roughness = 0.35
	mat.metallic_specular = 0.6
	picture.material_override = mat
	var clock := Art.add(self, "cat_clock", Transform3D(Basis.IDENTITY, CAT_CLOCK))
	cat_tail = Art.part(clock, "Tail")
	cat_pupils = Art.part(clock, "Pupils")
	_pupils_rest = cat_pupils.position
	cat_second = Art.part(clock, "SecondHand")
	set_cat_clock(0.0)
	Art.add(self, "calendar", Transform3D(Basis.IDENTITY, CALENDAR))


## The grandson's portrait: a supervisor in his white shirt, red tie and yellow hard hat, proudly holding
## up a donut in front of a studio backdrop. Each Photo state is rendered once, in a little world of its
## own: the same picture come alive (a wink, a bite, then chewing, the donut bitten).
func _photo_texture(state: Photo) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "PhotoStudio%d" % state
	viewport.size = Vector2i(300, 400)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var studio := Node3D.new()
	viewport.add_child(studio)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("7fb7e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.95, 0.9)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.5, 0.5, 0.0)
	key.light_energy = 1.2
	studio.add_child(key)
	var backdrop := MeshInstance3D.new()  # a soft spot of light behind him, school-portrait style
	var disc := SphereMesh.new()
	backdrop.mesh = disc
	backdrop.material_override = IntroSet.flat(Color("bfe3f2"), 0.6)
	backdrop.scale = Vector3(1.6, 1.6, 0.1)
	backdrop.position = Vector3(0.0, 1.35, -1.2)
	studio.add_child(backdrop)
	var grandson := IntroActor.create(studio, "supervisor", Vector3.ZERO, 0.25, "idle")
	grandson.pose_at("eat", 0.27 if state == Photo.BITE else 0.13)
	var donut := Art.add(studio, "donut_bitten" if state == Photo.BITTEN else "donut")
	if donut != null:  # (standing up, icing to the camera, the bite on top)
		var up := Basis(Vector3.BACK, PI) * Basis(Vector3.RIGHT, PI * 0.5)
		var tilt := Basis(Vector3.BACK, -0.45 if state == Photo.BITTEN else (0.25 if state != Photo.BITE else 0.0))
		grandson.attach(donut, "head", Transform3D((tilt * up).scaled(Vector3.ONE * PHOTO_DONUT_SCALE),
			PHOTO_DONUT_BITE if state == Photo.BITE else PHOTO_DONUT))
	var face := Node3D.new()  # what the picture adds to his face, on his head
	grandson.attach(face, "head")
	match state:
		Photo.WINK:
			_photo_lid(face, -1.0)
		Photo.BITE, Photo.BITTEN:
			_photo_lid(face, -1.0)
			_photo_lid(face, 1.0)
			if state == Photo.BITTEN:
				for side: float in [-1.0, 1.0]:  # cheeks full of donut
					var cheek := MeshInstance3D.new()
					var ball := SphereMesh.new()
					ball.radius = 0.06
					ball.height = 0.1
					cheek.mesh = ball
					cheek.material_override = IntroSet.flat(Color("f2a1a4"))  # blush
					cheek.scale = Vector3(1.0, 0.8, 0.45)
					cheek.position = Vector3(side * PHOTO_EYE.x * 1.2, PHOTO_EYE.y - 0.12, PHOTO_EYE.z)
					face.add_child(cheek)
	var cam := Camera3D.new()
	cam.fov = 38.0
	studio.add_child(cam)
	cam.look_at_from_position(Vector3(0.05, 1.38, 2.5), Vector3(-0.08, 1.16, 0.0))
	cam.current = true
	return viewport.get_texture()


## A closed, happy eye over one of his (side: -1 his right, nearer the camera; 1 his left): a lid of
## his skin and a dark arch, grandma's "^".
func _photo_lid(face: Node3D, side: float) -> void:
	var at := Vector3(side * PHOTO_EYE.x, PHOTO_EYE.y, PHOTO_EYE.z)
	var lid := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = PHOTO_EYE_R
	ball.height = PHOTO_EYE_R * 2.0
	lid.mesh = ball
	lid.material_override = IntroSet.flat(Color("d9a27a"))  # the palette's skin
	lid.scale = Vector3(1.15, 1.05, 0.3)
	lid.position = at
	face.add_child(lid)
	var points: Array[Vector3] = []
	for i in 7:
		var u := -1.0 + i / 3.0
		points.append(at + Vector3(u * PHOTO_EYE_R * 0.95, PHOTO_EYE_R * (0.45 * (1.0 - u * u) - 0.15), PHOTO_EYE_R * 0.3))
	var ink := IntroSet.flat(Color("141414"))  # eye_black
	for i in points.size() - 1:
		var stroke := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.011
		rod.bottom_radius = 0.011
		rod.height = points[i].distance_to(points[i + 1]) + 0.011
		rod.radial_segments = 6
		stroke.mesh = rod
		stroke.material_override = ink
		face.add_child(stroke)
		stroke.position = (points[i] + points[i + 1]) * 0.5
		stroke.basis = Basis(Quaternion(Vector3.UP, (points[i + 1] - points[i]).normalized()))


## Thinner ink on `model` (its outlines are as thick on screen as everyone's: on a shrunk cage's wires
## they'd hide the rat inside).
static func _thin_outlines(model: Node3D) -> void:
	if model == null or Art.headless():
		return
	var thin := (preload("res://shaders/materials/outline.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	thin.set_shader_parameter(&"outline_width", 0.004)
	for mesh in Art.meshes(model):
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as ShaderMaterial
			if source != null and source.next_pass != null:
				var copy := source.duplicate() as ShaderMaterial
				copy.next_pass = thin
				mesh.set_surface_override_material(i, copy)


## A prop standing on one of grandma's marks, turned by `yaw`.
func _on_mark(model: String, mark: String, yaw := 0.0) -> Node3D:
	var at: Transform3D = marks.get(mark, Transform3D.IDENTITY)
	return Art.add(self, model, Transform3D(Basis(Vector3.UP, yaw), at.origin))


# --- The view through the window ---------------------------------------------------------------------

## Where something `distance` m away, `yaw` degrees right of the window's centre and `pitch` degrees
## above the horizon, as seen from the opening shot's eye, stands. The view is composed from there
## (real distances, so it moves right when the camera does).
static func view_spot(yaw: float, pitch: float, distance: float) -> Vector3:
	var to_window := WINDOW_CENTRE - VIEW_EYE
	var a := atan2(to_window.x, -to_window.z) + deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	return VIEW_EYE + Vector3(sin(a) * cos(p), sin(p), -cos(a) * cos(p)) * distance


## What the window shows, bottom to top (pitch from the opening shot's eye): the back garden and its
## picket fence (to -4 degrees), the town's roofs and trees (to +1.5), the hill (+3), Sunny Acres on
## it, its cooling towers up to +8, their puffs and the sky above. A power line runs from the plant
## down into town.
func _build_view() -> void:
	var dawn := ending == 0
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1000)
	ground.mesh = plane
	ground.material_override = IntroSet.flat(Color("9dbb7f") if dawn else Color("1b2f2b"))
	ground.position = Vector3(0, GROUND_Y, -480)
	add_child(ground)
	var hill := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 2.0
	dome.radial_segments = 48
	dome.rings = 24
	hill.mesh = dome
	hill.material_override = IntroSet.flat(Color("86ad74") if dawn else Color("22403a"))
	var top := view_spot(2.0, 3.0, 360.0)
	hill.scale = Vector3(300.0, top.y - GROUND_Y + 40.0, 120.0)
	hill.position = Vector3(top.x, GROUND_Y - 40.0, top.z)
	add_child(hill)
	# Sunny Acres on the hill: the turbine hall and the reactor's dome, two cooling towers, the stack.
	var plant := view_spot(2.5, 2.75, 336.0)
	var hall := Art.add(self, "plant_building", Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3.ONE * 0.6), plant))
	var hall_windows := Art.part(hall, "Windows")
	_town_light(hall_windows, plant)
	for k in 2:
		var at := view_spot(-3.5 + 9.0 * k, 2.55, 352.0 + 14.0 * k)
		Art.add(self, "cooling_tower", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * TOWER_SCALE), at))
		tower_tops.append(at + Vector3(0, 22.0 * TOWER_SCALE, 0))
	Art.add(self, "exhaust_stack", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.6), view_spot(9.5, 2.7, 330.0)))
	# The town: roofs over the fence, trees between and beside them; the houses from the farthest to the
	# nearest (the order the power cut reaches them), all in the window, the nearest lower and bigger.
	var houses := [["house_yellow", -8.0, 135.0, 0.5], ["house_blue", 5.4, 125.0, -0.35], ["house_pink", -0.6, 112.0, 0.25],
		["house_yellow", 3.2, 92.0, -0.45], ["house_blue", -4.4, 76.0, 0.4], ["house_pink", 6.6, 62.0, -0.2]]
	for h: Array in houses:
		var at := view_spot(h[1], 0.0, h[2])
		var house := Art.add(self, h[0], Transform3D(Basis(Vector3.UP, h[3]).scaled(Vector3.ONE * 0.6),
			Vector3(at.x, GROUND_Y, at.z)))
		_town_light(Art.part(house, "Windows"), at)
	for tree: Vector2 in [Vector2(-9.5, 82.0), Vector2(1.6, 128.0), Vector2(9.6, 96.0), Vector2(-13.0, 70.0),
			Vector2(14.0, 74.0), Vector2(-2.8, 140.0)]:
		var at := view_spot(tree.x, 0.0, tree.y)
		Art.add(self, "tree_round", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.62), Vector3(at.x, GROUND_Y, at.z)))
	# The garden's lantern by the fence: the last light out there before her lamp.
	var lantern := view_spot(1.6, 0.0, 7.6)
	var post := Art.add(self, "garden_lamp", Transform3D(Basis.IDENTITY, Vector3(lantern.x, GROUND_Y, lantern.z)))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.5)
	glow.omni_range = 3.5
	glow.light_energy = 0.0 if dawn else 1.2
	glow.position = Vector3(lantern.x, GROUND_Y + 1.95, lantern.z + 0.3)
	add_child(glow)
	_town_light(Art.part(post, "Lamp"), lantern, glow)
	# The power line: from the plant, pole by pole, down to the street (the cut runs along it).
	var poles: Array[Vector3] = []
	for k in 4:
		var at := view_spot(12.0 - 2.0 * k, 0.0, 40.0 + 65.0 * k * k)
		var hill_rise := 0.0 if k < 2 else (top.y - GROUND_Y) * (0.25 if k == 2 else 0.85)
		poles.append(Vector3(at.x, GROUND_Y + hill_rise, at.z))
		Art.add(self, "power_pole", Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3.ONE * 0.8), poles[k]))
	var wire := IntroSet.flat(Color("3a3a40") if dawn else Color("0c0f18"))
	for i in poles.size() - 1:
		for side: float in [-0.8, 0.8]:
			_wire(poles[i] + Vector3(side, 6.9, 0), poles[i + 1] + Vector3(side, 6.9, 0), wire)
	_fence()
	if not dawn:
		_stars()


## One of the town's lights (the power cut reaches them in the order they're added), `at` that far
## (from the opening shot's eye), `glow` the light it casts if any.
func _town_light(part: Node3D, at: Vector3, glow: OmniLight3D = null) -> void:
	if part == null:
		return
	town_lights.append(part)
	town_distances.append(VIEW_EYE.distance_to(at))
	_town_glows.append(glow)


## The back garden's white picket fence, a few metres out.
func _fence() -> void:
	var white := IntroSet.flat(Color("f4f1e8"))
	var a := view_spot(-14.0, 0.0, 9.0)
	var b := view_spot(22.0, 0.0, 9.0)
	var n := 28
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		IntroSet.box(self, Vector3(p.x, GROUND_Y + 0.55, p.z), Vector3(0.09, 1.1, 0.03), white)
	for h: float in [0.35, 0.85]:
		var rail := IntroSet.box(self, (a + b) * 0.5 + Vector3(0, GROUND_Y + h - (a.y + b.y) * 0.5, 0),
			Vector3(a.distance_to(b), 0.07, 0.03), white)
		rail.rotation.y = -atan2(b.z - a.z, b.x - a.x)


func _wire(a: Vector3, b: Vector3, material: Material) -> void:
	var mid := (a + b) * 0.5 + Vector3.DOWN * 0.6
	var pts: Array[Vector3] = [a, mid, b]
	for i in 2:
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = pts[i].distance_to(pts[i + 1])
		cyl.radial_segments = 4
		seg.mesh = cyl
		seg.material_override = material
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		seg.look_at_from_position((pts[i] + pts[i + 1]) * 0.5, pts[i + 1], Vector3.UP, true)
		seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.97, 0.85)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.4
	for i in 70:
		var star := MeshInstance3D.new()
		star.mesh = quad
		star.material_override = mat
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.position = Vector3(rng.randf_range(-120, 260), rng.randf_range(40, 230), -390)
		star.scale = Vector3.ONE * rng.randf_range(0.5, 1.3)
		add_child(star)


# --- Lights -----------------------------------------------------------------------------------------

func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun" if ending == 0 else "Moon"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 12.0
	sun.shadow_blur = 1.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	if ending == 0:  # low, golden, from behind the plant: in through the window, onto her back
		sun.light_color = Color(1.0, 0.76, 0.48)
		sun.light_energy = 1.7
		sun.rotation = Vector3(deg_to_rad(-4.0), deg_to_rad(176.0), 0.0)
	else:  # the moon, cool and faint
		sun.light_color = Color(0.55, 0.66, 1.0)
		sun.light_energy = 0.5
		sun.rotation = Vector3(deg_to_rad(-8.5), deg_to_rad(171.0), 0.0)
	_sun_energy = sun.light_energy
	add_child(sun)
	lamp_light = OmniLight3D.new()
	lamp_light.name = "LampLight"
	lamp_light.light_color = LAMP_COLOR
	_lamp_energy = 1.05 if ending == 0 else 0.8
	lamp_light.omni_range = 4.5
	lamp_light.omni_attenuation = 1.2
	lamp_light.position = LAMP + Vector3(0, -0.64, 0)
	add_child(lamp_light)
	fill = OmniLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(1.0, 0.9, 0.78) if ending == 0 else Color(0.7, 0.78, 1.0)
	_fill_energy = 0.55 if ending == 0 else 0.5
	fill.omni_range = 6.0
	fill.omni_attenuation = 1.0
	fill.position = Vector3(0.4, 1.7, 2.2)
	add_child(fill)
	toaster_light = OmniLight3D.new()
	toaster_light.name = "ToasterLight"
	toaster_light.light_color = GLOW_COLOR
	toaster_light.omni_range = 0.6
	toaster_light.light_energy = 0.0
	toaster_light.position = toaster.position + Vector3(0, 0.24, 0)
	add_child(toaster_light)
	night = DirectionalLight3D.new()  # the cartoon night: cool, soft, from the front left (no shadows)
	night.name = "Night"
	night.light_color = NIGHT_FILL_COLOR
	night.light_energy = 0.0
	night.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-38.0), 0.0)
	add_child(night)
	set_lamp(1.0)
	set_power(1.0)
	set_toaster_glow(0.0)

