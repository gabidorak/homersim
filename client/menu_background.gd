class_name MenuBackground
extends Node3D
## The main menu's backdrop (M8): a little night diorama outside the plant, built from the generated
## models. A supervisor naps on a bench with his coffee and donuts while, right behind him, one rat
## gnaws at the generator's junction box, another keeps watch on a crate and a third scurries back and
## forth; the cooling towers loom in the fog. The camera drifts slowly from side to side.
## (The real plant can't be loaded here: its interactables and props expect a running Session.)
## Built in code so it needs no scene file; nothing is built in a headless process.

const DRIFT_PERIOD_S := 46.0
const DRIFT_ANGLE := 0.32  ## radians either side
const CAMERA_RADIUS := 8.6
const CAMERA_HEIGHT := 2.3
const TARGET := Vector3(0.2, 0.9, -0.6)
const SCURRY_FROM := Vector3(-4.6, 0, 2.2)
const SCURRY_TO := Vector3(-0.8, 0, 2.6)
const SCURRY_SPEED := 2.2

var camera: Camera3D
var _time := 0.0
var _scurrier: Node3D
var _scurry_t := 0.0
var _fade: ColorRect


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_build_world()
	_build_set()
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.h_offset = -2.4  # the scene sits right of centre, beside the menu column
	add_child(camera)
	camera.make_current()
	_place_camera()
	# Fade in from black, so the first frames (models loading) don't flash.
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.06)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	create_tween().tween_property(_fade, "modulate:a", 0.0, 1.2).set_delay(0.15)


func _process(delta: float) -> void:
	_time += delta
	_place_camera()
	_scurry(delta)


func _place_camera() -> void:
	var angle := sin(_time / DRIFT_PERIOD_S * TAU) * DRIFT_ANGLE
	var bob := sin(_time * 0.37) * 0.12
	var eye := TARGET + Vector3(sin(angle) * CAMERA_RADIUS, CAMERA_HEIGHT - TARGET.y + bob, cos(angle) * CAMERA_RADIUS)
	camera.look_at_from_position(eye, TARGET)


## The third rat runs from one end of its path to the other, turns, and runs back.
func _scurry(delta: float) -> void:
	if _scurrier == null:
		return
	var length := SCURRY_FROM.distance_to(SCURRY_TO)
	_scurry_t = fmod(_scurry_t + delta * SCURRY_SPEED / length, 2.0)
	var forward := _scurry_t < 1.0
	var t := _scurry_t if forward else 2.0 - _scurry_t
	_scurrier.position = SCURRY_FROM.lerp(SCURRY_TO, smoothstep(0.0, 1.0, t))
	var dir := (SCURRY_TO - SCURRY_FROM) * (1.0 if forward else -1.0)
	_scurrier.rotation.y = atan2(dir.x, dir.z)  # models face +Z


func _build_world() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.02, 0.03, 0.08)
	sky_material.sky_horizon_color = Color(0.1, 0.12, 0.2)
	sky_material.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_material.ground_horizon_color = Color(0.1, 0.12, 0.2)
	sky_material.sun_angle_max = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.72)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.tonemap_white = 1.6
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.11, 0.2)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	Config.apply_environment(env)
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(-0.8727, 0.5236, 0)
	moon.light_color = Color(0.6, 0.7, 1)
	moon.light_energy = 0.4
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 40.0
	add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	ground.mesh = plane
	ground.material_override = load("res://levels/plant/materials/floor_yard.tres")
	add_child(ground)


func _build_set() -> void:
	# The skyline.
	_prop("cooling_tower", Vector3(-22, 0, -62), 0.3)
	_prop("cooling_tower", Vector3(10, 0, -78), -0.2)
	_prop("exhaust_stack", Vector3(26, 0, -50))
	_prop("transformer", Vector3(-8.5, 0, -7), 0.4)
	_prop("insulator_post", Vector3(-6.2, 0, -9))
	_prop("tank_vertical", Vector3(8.5, 0, -8), -0.3)
	# The supervisor's break: bench, coffee, donuts, and a wet floor sign for safety.
	_prop("bench", Vector3(1.7, 0, 0.6))
	_character("supervisor", Vector3(1.45, 0.43, 0.55), 0.0, "sit")  # the clip sits on the floor: lift to the seat
	_prop("donut_box", Vector3(2.35, 0.47, 0.55), 0.2)
	_prop("k_coffee_cup", Vector3(0.75, 0.47, 0.6))
	_prop("wet_floor_sign", Vector3(3.6, 0, 1.6), -0.6)
	# Behind his back: the generator, its junction box, and the rats.
	_prop("generator", Vector3(-1.4, 0, -2.6), 0.15)
	_prop("sabotage_box_broken", Vector3(-1.0, 0, -1.4), 0.15)
	_prop("warning_sign_high_voltage", Vector3(-2.9, 0, -2.0), 0.4)
	_character("rat", Vector3(-0.9, 0, -0.85), PI + 0.15, "gnaw")
	_prop("crate", Vector3(-3.3, 0, 0.3), 0.3)
	_character("rat", Vector3(-3.3, 0.9, 0.3), 0.5, "idle")
	_scurrier = _character("rat", SCURRY_FROM, 0.0, "run")
	# Clutter and light.
	_prop("barrels_cluster", Vector3(5.2, 0, -2.8), 0.5)
	_prop("pallet_flat", Vector3(-5.6, 0, -1.2), 0.2)
	_prop("traffic_cone", Vector3(4.4, 0, 2.6))
	_prop("traffic_cone", Vector3(-5.2, 0, 3.4), 0.5)
	_prop("cable_spool", Vector3(-4.6, 0, -3.6), 0.8)
	_prop("floodlight", Vector3(6.2, 0, 1.2), -2.2)
	var flood := SpotLight3D.new()
	flood.light_color = Color(1.0, 0.86, 0.62)
	flood.light_energy = 3.5
	flood.spot_range = 22.0
	flood.spot_angle = 38.0
	flood.shadow_enabled = true
	add_child(flood)
	flood.look_at_from_position(Vector3(6.0, 4.2, 1.6), Vector3(-0.4, 0.4, -0.6))
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 0.85, 0.55)  # the junction box's sickly glow
	rim.light_energy = 1.6
	rim.omni_range = 4.0
	rim.position = Vector3(-1.0, 1.0, -1.0)
	add_child(rim)


func _prop(model: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	return Art.add(self, model, Transform3D(Basis(Vector3.UP, yaw), pos))


## A character model playing `clip` on a loop (the models face +Z).
func _character(model: String, pos: Vector3, yaw: float, clip: String) -> Node3D:
	var node := _prop(model, pos, yaw)
	if node == null:
		return null
	var players := node.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim := players[0] as AnimationPlayer
		if anim.has_animation(clip):
			anim.play(clip)
			anim.seek(randf() * anim.current_animation_length)
	return node
