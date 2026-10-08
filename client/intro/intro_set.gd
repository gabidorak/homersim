class_name IntroSet
extends Node3D
## The intro's set (client/intro/intro.gd): the supervisors' corner of the Control Room at Sunny
## Acres, back when the rats were hamsters. The long desk with an open hamster cage at each end and
## a plate of donuts in the middle, the "days without an incident" board, a window on the glowing reactor,
## the door the clumsy supervisor comes in by (it slides up, like the plant's doors) onto a freshly
## mopped floor, and on the right wall the junction box the rats chew up and the vent they leave by. Built in code from the generated models and the plant's own wall and floor
## materials (their patterns come from the world position, so plain boxes look like its rooms).
##
## Coordinates: the floor is y = 0; the back wall (door, board, window) is at z = BACK, the vent and
## the junction box are in the right wall (x = RIGHT). Models face +Z; the camera mostly looks -Z.

const WALL: Material = preload("res://levels/plant/materials/wall_controlroom.tres")
const FLOOR: Material = preload("res://levels/plant/materials/floor_controlroom.tres")
const GLASS: Material = preload("res://shaders/materials/toon_glass.tres")
const TOON: Shader = preload("res://shaders/toon.gdshader")
const DISPLAY_FONT: Font = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

const LEFT := -3.8
const RIGHT := 3.8
const BACK := -4.6
const FRONT := 3.4
const HEIGHT := 3.4
const THICK := 0.3
const DESK := Vector3(0.0, 0.0, -2.2)
const DESK_TOP := 0.76
const DESK_FRONT := -1.78  ## z of the desk's front edge
const SEAT_Y := 0.47  ## where a seated supervisor's model stands (the sit clip sits on its origin)
## The two seats: x = +-SEAT_X. Far enough apart for their 1.2 m wide hard hats, and back from the
## desk so the hats clear the hamsters when they lean in.
const SEAT_X := 0.72
const SEAT_Z := -3.25
const DOOR_X := -2.6  ## the doorway in the back wall: 2.0 wide, 2.6 high, like door_panel
const VENT_Z := -1.4  ## the vent's centre in the right wall (0.7 x 0.6, at the floor)
const JUNCTION := Vector3(RIGHT, 0.42, -3.0)  ## the junction box on the right wall (its back)
const WINDOW_X := Vector2(1.55, 3.45)  ## the window in the back wall: from x to x
const WINDOW_Y := Vector2(0.95, 2.55)
const CAGE_A := Vector3(-1.1, DESK_TOP, -2.12)  ## with the wheel
const CAGE_B := Vector3(1.1, DESK_TOP, -2.12)  ## with the little house
const WHEEL := Vector3(0.12, 0.1, -0.02)  ## a hamster on the wheel's rungs, in cage A's space
const PLATE := Vector3(0.0, DESK_TOP, -2.02)  ## the plate of donuts, mid-desk
const SIGN := Vector3(DOOR_X, 0.0, BACK + 0.85)  ## the wet floor sign, just inside the door
const BEACON_SPIN := TAU * 0.8

var cage_a: Node3D
var cage_b: Node3D
var chairs: Array[Node3D] = []
var wheel: Node3D  ## cage A's wheel (spins about X)
var door: Node3D  ## the door panel (slides up)
var wet_sign: Node3D
var mug: Node3D
var junction: Node3D  ## the junction box (swapped for the broken one when the rats are done)
var broom: Node3D  ## leaning on the desk, until a supervisor grabs it
var board_number: Label3D
var lamps: Array[Light3D] = []
var environment: Environment

var wheel_speed := 0.0  ## radians per second
var alarm := 0.0  ## 0 = off, 1 = the beacon spins and the lights pulse red
var flicker := 0.0  ## 0..1: the lamps stutter (the goo's radiation, the chewed wires)

var _beacon_reflector: Node3D
var _beacon_spot: SpotLight3D
var _beacon_glow: OmniLight3D
var _beacon_spin: Node3D
var _lamp_colors: Array[Color] = []
var _lamp_energies: Array[float] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 11
	_build_environment()
	_build_room()
	_build_desk()
	_build_dressing()
	_build_lights()


func _process(delta: float) -> void:
	_time += delta
	if wheel != null:
		wheel.rotation.x += wheel_speed * delta
	_beacon_spin.rotation.y += BEACON_SPIN * delta * alarm
	if _beacon_reflector != null:
		_beacon_reflector.rotation.y = _beacon_spin.rotation.y
	_beacon_spot.visible = alarm > 0.05
	_beacon_glow.light_energy = 1.4 * alarm
	var red := Color(1.0, 0.3, 0.22)
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 1.6)
	var stutter := 1.0
	if flicker > 0.0 and _rng.randf() < 0.35 * flicker:
		stutter = _rng.randf_range(0.25, 0.8)
	for i in lamps.size():
		lamps[i].light_color = _lamp_colors[i].lerp(red, alarm * (0.42 + 0.35 * pulse))
		lamps[i].light_energy = _lamp_energies[i] * stutter * (1.0 - 0.2 * alarm * (1.0 - pulse))


## Puts the board's counter at `days` (the number flips over).
func set_days(days: int, flip := true) -> void:
	if not flip:
		board_number.text = str(days)
		return
	var tween := board_number.create_tween()
	tween.tween_property(board_number, ^"scale:y", 0.0, 0.07)
	tween.tween_callback(func() -> void: board_number.text = str(days))
	tween.tween_property(board_number, ^"scale:y", 1.0, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Turns the alarm on (the beacon spins, the lamps pulse red) over `duration` s.
func sound_alarm(duration := 0.4) -> void:
	if _beacon_reflector != null:
		Art.set_tint(_beacon_reflector, Color(1.0, 0.4, 0.3))
		Art.set_glow(_beacon_reflector, 1.5)
	create_tween().tween_property(self, ^"alarm", 1.0, duration)


## The junction box, chewed up: its broken model takes its place.
func break_junction() -> void:
	if junction == null:
		return
	var at := junction.transform
	junction.queue_free()
	junction = Art.add(self, "sabotage_box_broken", at)


## Where a hamster on cage A's wheel stands (world space).
func wheel_spot() -> Vector3:
	return cage_a.to_global(WHEEL)


# --- Building ---------------------------------------------------------------------------------

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.03, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.62, 0.7)
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.88
	environment.tonemap_white = 1.6
	environment.ssao_enabled = true
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.3
	environment.ssao_light_affect = 0.15
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.18
	environment.adjustment_contrast = 1.06
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	Config.apply_environment(environment)


func _build_room() -> void:
	var w := RIGHT - LEFT
	var d := FRONT - BACK
	var cx := (LEFT + RIGHT) * 0.5
	var cz := (BACK + FRONT) * 0.5
	_box(Vector3(cx, -0.25, cz), Vector3(w + 2 * THICK, 0.5, d + 2 * THICK), FLOOR)
	_box(Vector3(cx, HEIGHT + 0.15, cz), Vector3(w + 2 * THICK, 0.3, d + 2 * THICK), WALL)
	# The back wall: the doorway on the left, the window onto the reactor hall on the right.
	var bz := BACK - THICK * 0.5
	var dx0 := DOOR_X - 1.0
	var dx1 := DOOR_X + 1.0
	_box(Vector3((LEFT + dx0) * 0.5, HEIGHT * 0.5, bz), Vector3(dx0 - LEFT, HEIGHT, THICK), WALL)
	_box(Vector3(DOOR_X, (2.6 + HEIGHT) * 0.5, bz), Vector3(2.0, HEIGHT - 2.6, THICK), WALL)
	_box(Vector3((dx1 + WINDOW_X.x) * 0.5, HEIGHT * 0.5, bz), Vector3(WINDOW_X.x - dx1, HEIGHT, THICK), WALL)
	_box(Vector3((WINDOW_X.y + RIGHT) * 0.5, HEIGHT * 0.5, bz), Vector3(RIGHT - WINDOW_X.y, HEIGHT, THICK), WALL)
	var wx := (WINDOW_X.x + WINDOW_X.y) * 0.5
	var ww := WINDOW_X.y - WINDOW_X.x
	_box(Vector3(wx, WINDOW_Y.x * 0.5, bz), Vector3(ww, WINDOW_Y.x, THICK), WALL)
	_box(Vector3(wx, (WINDOW_Y.y + HEIGHT) * 0.5, bz), Vector3(ww, HEIGHT - WINDOW_Y.y, THICK), WALL)
	_box(Vector3(wx, (WINDOW_Y.x + WINDOW_Y.y) * 0.5, bz), Vector3(ww, WINDOW_Y.y - WINDOW_Y.x, 0.04), GLASS, false)
	_window_frame(wx, ww)
	_reactor_hall(wx)
	door = Art.add(self, "door_panel", Transform3D(Basis.IDENTITY, Vector3(DOOR_X, 1.3, BACK - 0.05)))
	var corridor := _flat(Color(0.12, 0.14, 0.16))
	_box(Vector3(DOOR_X, 1.3, BACK - THICK - 1.0), Vector3(2.0, 2.6, 2.0), corridor, false)
	var light := OmniLight3D.new()  # the corridor beyond is lit too
	light.light_color = Color(0.85, 0.9, 1.0)
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.position = Vector3(DOOR_X, 2.2, BACK - 1.2)
	add_child(light)
	# The other walls; the right one has the vent (0.7 x 0.6, at the floor) and the dark duct behind.
	_box(Vector3(cx, HEIGHT * 0.5, FRONT + THICK * 0.5), Vector3(w + 2 * THICK, HEIGHT, THICK), WALL)
	_box(Vector3(LEFT - THICK * 0.5, HEIGHT * 0.5, cz), Vector3(THICK, HEIGHT, d), WALL)
	var rx := RIGHT + THICK * 0.5
	var vz0 := VENT_Z - 0.35
	var vz1 := VENT_Z + 0.35
	_box(Vector3(rx, HEIGHT * 0.5, (BACK + vz0) * 0.5), Vector3(THICK, HEIGHT, vz0 - BACK), WALL)
	_box(Vector3(rx, HEIGHT * 0.5, (vz1 + FRONT) * 0.5), Vector3(THICK, HEIGHT, FRONT - vz1), WALL)
	_box(Vector3(rx, (0.6 + HEIGHT) * 0.5, VENT_Z), Vector3(THICK, HEIGHT - 0.6, 0.7), WALL)
	_box(Vector3(RIGHT + 0.65, 0.3, VENT_Z), Vector3(0.7, 0.6, 0.7), _flat(Color(0.02, 0.02, 0.025)), false)
	Art.add(self, "vent_grille", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(RIGHT - 0.04, 0.0, VENT_Z)))


func _window_frame(wx: float, ww: float) -> void:
	var z := BACK + 0.04
	var h := WINDOW_Y.y - WINDOW_Y.x
	var frame := _flat(Color(0.18, 0.36, 0.38))
	for y: float in [WINDOW_Y.x, WINDOW_Y.y]:
		_box(Vector3(wx, y, z), Vector3(ww + 0.12, 0.08, 0.1), frame)
	for x: float in [WINDOW_X.x, WINDOW_X.y, wx]:
		_box(Vector3(x, (WINDOW_Y.x + WINDOW_Y.y) * 0.5, z), Vector3(0.08, h, 0.1), frame)
	_box(Vector3(wx, WINDOW_Y.x - 0.06, BACK + 0.1), Vector3(ww + 0.2, 0.05, 0.22), frame)  # the sill


## What the window shows: the reactor hall in the dark, the core glowing green in its pool.
func _reactor_hall(wx: float) -> void:
	var hall := Vector3(wx, 0.0, BACK - 6.0)
	var dark := _flat(Color(0.05, 0.08, 0.09))
	_box(hall + Vector3(0, -2.0, 0), Vector3(14, 0.4, 11), dark)  # the hall floor, lower than ours
	_box(hall + Vector3(0, 3.0, -5.6), Vector3(14, 12, 0.4), dark)
	_box(hall + Vector3(-7.0, 3.0, 0), Vector3(0.4, 12, 11), dark)
	_box(hall + Vector3(7.0, 3.0, 0), Vector3(0.4, 12, 11), dark)
	Art.add(self, "reactor_core", Transform3D(Basis(Vector3.UP, 0.4), hall + Vector3(0.6, -1.8, -0.6)))
	var core := OmniLight3D.new()
	core.light_color = Color(0.55, 1.0, 0.35)
	core.light_energy = 2.4
	core.omni_range = 11.0
	core.position = hall + Vector3(0.6, 1.5, 0.4)
	add_child(core)
	var spill := OmniLight3D.new()  # a little of its glow comes through the glass
	spill.light_color = Color(0.5, 1.0, 0.4)
	spill.light_energy = 0.5
	spill.omni_range = 2.8
	spill.position = Vector3(wx, 1.8, BACK + 0.5)
	add_child(spill)


func _build_desk() -> void:
	Art.add(self, "supervisor_desk", Transform3D(Basis(Vector3.UP, PI), DESK))
	for x: float in [-SEAT_X, SEAT_X]:
		chairs.append(Art.add(self, "k_chair_desk", Transform3D(Basis(Vector3.UP, x * -0.2), Vector3(x, 0.0, SEAT_Z - 0.02))))
	cage_a = Art.add(self, "hamster_cage", Transform3D(Basis(Vector3.UP, 0.12), CAGE_A))
	cage_b = Art.add(self, "hamster_cage_house", Transform3D(Basis(Vector3.UP, -0.12), CAGE_B))
	wheel = Art.part(cage_a, "Wheel")
	for cage: Node3D in [cage_a, cage_b]:  # open cages: the doors swing wide
		var cage_door := Art.part(cage, "Door")
		if cage_door != null:
			cage_door.rotation.y = -1.9
	_plate_of_donuts()
	mug = _prop("k_mug", Vector3(-0.35, DESK_TOP, -1.88), 0.6)
	_prop("k_coffee_cup", Vector3(0.28, DESK_TOP, -2.47), 2.4)
	_prop("papers", Vector3(-0.3, DESK_TOP, -2.48), 0.15)
	_prop("donut", Vector3(0.33, DESK_TOP, -2.2), 0.0)
	broom = Art.add(self, "broom", Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.3)), Vector3(1.72, 1.22, -2.75)))


## The donuts they share: a little stack on a plate.
func _plate_of_donuts() -> void:
	var plate := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.16
	disc.height = 0.025
	disc.radial_segments = 20
	plate.mesh = disc
	plate.material_override = _flat(Color(0.93, 0.92, 0.88))
	plate.position = PLATE + Vector3(0, 0.0125, 0)
	add_child(plate)
	for spot: Vector3 in [Vector3(-0.07, 0.025, 0.04), Vector3(0.08, 0.025, 0.02), Vector3(0.0, 0.025, -0.08),
			Vector3(0.0, 0.068, 0.0)]:
		var donut := Art.add(self, "donut", Transform3D(Basis.from_euler(Vector3(0.0, spot.x * 20.0, 0.0)), PLATE + spot))
		if donut != null and spot.y > 0.05:
			donut.rotation.x = 0.12


func _build_dressing() -> void:
	# The back wall: the board between the supervisors' heads, a clock, a radiation sign.
	var board := Art.add(self, "incident_board", Transform3D(Basis.IDENTITY, Vector3(0.0, 2.25, BACK)))
	if board != null:
		_board_text(board)
	Art.add(self, "wall_clock", Transform3D(Basis.IDENTITY, Vector3(-1.15, 2.62, BACK)))
	Art.add(self, "warning_sign_radiation", Transform3D(Basis.IDENTITY, Vector3(1.05, 2.4, BACK)))
	# The left wall: a fire extinguisher, the water cooler, a bin; the right one: the junction box.
	Art.add(self, "fire_extinguisher", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(LEFT, 1.25, -3.1)))
	_prop("water_cooler", Vector3(LEFT + 0.32, 0.0, -1.7), PI * 0.5)
	_prop("k_trashcan", Vector3(LEFT + 0.3, 0.0, -0.8), 0.3)
	junction = Art.add(self, "sabotage_box", Transform3D(Basis(Vector3.UP, -PI * 0.5), JUNCTION))
	# Plants, a crate of glowing vials (the plant is never far away).
	_prop("k_potted_plant", Vector3(RIGHT - 0.32, 0.0, BACK + 0.3), 0.0)
	_prop("k_potted_plant", Vector3(LEFT + 0.4, 0.0, 2.7), 0.8)
	_prop("radiation_vial_crate", Vector3(LEFT + 0.6, 0.0, 1.4), 1.2)
	# The freshly mopped floor: the bucket by the door, a puddle, and the sign right in the way.
	_prop("mop_bucket", Vector3(LEFT + 0.45, 0.0, BACK + 0.55), 0.5)
	var puddle := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.006
	disc.radial_segments = 20
	puddle.mesh = disc
	puddle.material_override = _flat(Color(0.55, 0.78, 0.92), 0.15)
	puddle.position = SIGN + Vector3(0.0, 0.004, -0.1)
	puddle.scale = Vector3(0.8, 1.0, 1.3)
	add_child(puddle)
	wet_sign = _prop("wet_floor_sign", SIGN, 0.15)
	for x: float in [-1.5, 1.5]:  # ceiling lamps
		Art.add(self, "k_ceiling_lamp", Transform3D(Basis.IDENTITY, Vector3(x, HEIGHT - 0.35, -2.2)))
	# The alarm beacon on the right wall, dark for now.
	var beacon := Node3D.new()
	beacon.position = Vector3(RIGHT - 0.3, HEIGHT - 0.02, -2.3)
	add_child(beacon)
	var model := Art.add(beacon, "alarm_beacon", Transform3D.IDENTITY, false)
	_beacon_reflector = Art.part(model, "Reflector")
	if _beacon_reflector != null:
		Art.set_tint(_beacon_reflector, Color(0.5, 0.45, 0.45))
		Art.set_glow(_beacon_reflector, 0.0)
	_beacon_spin = Node3D.new()
	_beacon_spin.position.y = -0.2
	beacon.add_child(_beacon_spin)
	_beacon_spot = SpotLight3D.new()
	_beacon_spot.light_color = Color(1, 0.1, 0.05)
	_beacon_spot.light_energy = 5.0
	_beacon_spot.spot_range = 9.0
	_beacon_spot.spot_angle = 30.0
	_beacon_spot.rotation.x = -0.5
	_beacon_spot.visible = false
	_beacon_spin.add_child(_beacon_spot)
	_beacon_glow = OmniLight3D.new()
	_beacon_glow.light_color = Color(1, 0.12, 0.06)
	_beacon_glow.omni_range = 4.0
	_beacon_glow.light_energy = 0.0
	_beacon_glow.position.y = -0.3
	beacon.add_child(_beacon_glow)


## The board's words and its counter (Label3D in the game's display font, translated).
func _board_text(board: Node3D) -> void:
	var title := _label(tr("DAYS WITHOUT AN INCIDENT"), 40, Color.WHITE, Color(0.1, 0.2, 0.11))
	title.position = Vector3(0.0, 0.215, 0.04)
	title.width = 470.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.line_spacing = -6.0
	board.add_child(title)
	board_number = _label("365", 92, Color(1.0, 0.86, 0.3), Color(0.05, 0.05, 0.05))
	board_number.position = Vector3(-0.12, -0.14, 0.05)
	board_number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	board.add_child(board_number)


func _label(text: String, size: int, color: Color, outline: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = DISPLAY_FONT
	label.font_size = size
	label.pixel_size = 0.0021
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = 10
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _build_lights() -> void:
	var key := SpotLight3D.new()  # the lamp over the desk: the one light with shadows
	key.light_color = Color(1.0, 0.9, 0.76)
	key.light_energy = 1.35
	key.spot_range = 9.0
	key.spot_angle = 55.0
	key.spot_attenuation = 0.7
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	add_child(key)
	key.look_at_from_position(Vector3(0.3, HEIGHT - 0.7, 0.5), Vector3(-0.1, 0.8, -2.7))
	for pos: Vector3 in [Vector3(-1.5, HEIGHT - 0.5, -2.2), Vector3(1.5, HEIGHT - 0.5, -2.2), Vector3(-1.8, HEIGHT - 0.5, 1.0),
			Vector3(1.8, HEIGHT - 0.5, 1.0)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.93, 0.82)
		lamp.light_energy = 0.5
		lamp.omni_range = 6.5
		lamp.omni_attenuation = 0.8
		lamp.position = pos
		add_child(lamp)
		lamps.append(lamp)
	lamps.append(key)
	for lamp in lamps:
		_lamp_colors.append(lamp.light_color)
		_lamp_energies.append(lamp.light_energy)


func _prop(model: String, pos: Vector3, yaw: float) -> Node3D:
	return Art.add(self, model, Transform3D(Basis(Vector3.UP, yaw), pos))


func _box(pos: Vector3, size: Vector3, material: Material, shadows := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	if not shadows:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh


## A plain toon material of one colour (no outline: walls and darkness).
func _flat(color: Color, glow := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter(&"albedo", color)
	if glow > 0.0:
		mat.set_shader_parameter(&"emission", color)
		mat.set_shader_parameter(&"emission_energy", glow)
	return mat
