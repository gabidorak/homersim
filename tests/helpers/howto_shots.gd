extends Node
## Renders the How to play illustrations (M8), windowed: four little staged scenes built from the
## generated models, each rendered in its own SubViewport and saved as a PNG.
##   godot tests/helpers/HowToShots.tscn -- [--out /tmp/howto] [--only NAME]
## Shots: supervisor_repair, supervisor_catch, rat_sabotage, rat_bite. Copy the PNGs into
## assets/ui/howto/, then run `godot --headless --import`.

const SIZE := Vector2i(720, 405)
const SETTLE_S := 1.0

# name, camera eye, camera target, builder method
const SHOTS := [
	["supervisor_repair", Vector3(2.9, 1.5, 1.6), Vector3(-0.3, 0.9, -0.5), "_stage_repair"],
	["supervisor_catch", Vector3(1.2, 1.5, 3.6), Vector3(0.1, 0.8, 0.0), "_stage_catch"],
	["rat_sabotage", Vector3(1.9, 1.1, 2.4), Vector3(-0.2, 0.45, 0.0), "_stage_sabotage"],
	["rat_bite", Vector3(2.2, 1.3, 2.9), Vector3(0.0, 0.6, 0.0), "_stage_bite"],
]


func _ready() -> void:
	var out := Cli.get_str("out", "user://howto_shots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for shot: Array in SHOTS:
		if Cli.has_arg("only") and shot[0] != Cli.get_str("only"):
			continue
		var viewport := SubViewport.new()
		viewport.size = SIZE
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var root := Node3D.new()
		viewport.add_child(root)
		_world(root)
		call(shot[3], root)
		var camera := Camera3D.new()
		camera.fov = 50.0
		root.add_child(camera)
		camera.look_at_from_position(shot[1], shot[2])
		camera.make_current()
		await get_tree().create_timer(SETTLE_S).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [out, shot[0]]
		var err := viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		Log.info("howto", "%s: %s" % [path, error_string(err)])
		viewport.queue_free()
	get_tree().quit()


func _world(root: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.22, 0.36)
	sky_material.sky_horizon_color = Color(0.32, 0.38, 0.5)
	sky_material.ground_bottom_color = Color(0.1, 0.1, 0.12)
	sky_material.ground_horizon_color = Color(0.32, 0.38, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.17, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 2.5, 3.0)
	fill.light_energy = 1.2
	fill.omni_range = 9.0
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	ground.material_override = load("res://levels/plant/materials/floor_controlroom.tres")
	root.add_child(ground)


func _prop(root: Node3D, model: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	return Art.add(root, model, Transform3D(Basis(Vector3.UP, yaw), pos))


## A character (models face +Z) frozen at `at` (0..1) of `clip`.
func _actor(root: Node3D, model: String, pos: Vector3, yaw: float, clip: String, at: float = 0.4,
		broom: bool = false) -> Node3D:
	var visual := CharacterVisual.new()
	visual.model_name = model
	visual.with_broom = broom
	visual.position = pos
	visual.rotation.y = yaw + PI  # CharacterVisual turns the model to face -Z; face +Z again
	root.add_child(visual)
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim := players[0] as AnimationPlayer
		if anim.has_animation(clip):
			anim.play(clip)
			anim.seek(anim.current_animation_length * at, true)
			anim.pause()
	return visual


func _stage_repair(root: Node3D) -> void:
	_prop(root, "machine_pumps", Vector3(-0.4, 0, -1.6))
	_prop(root, "repair_panel", Vector3(-0.4, 1.0, -0.3))
	_prop(root, "toolbox", Vector3(0.7, 0, -0.1), 0.5)
	_actor(root, "supervisor", Vector3(-0.35, 0, 0.45), PI + 0.5, "interact", 0.3)
	_prop(root, "wet_floor_sign", Vector3(1.5, 0, 0.9), -0.4)


func _stage_catch(root: Node3D) -> void:
	_prop(root, "cage", Vector3(1.5, 0, -0.9), -0.4)
	_actor(root, "supervisor", Vector3(-0.2, 0, 0.0), 0.35, "carry_idle", 0.2, true)
	_actor(root, "rat", Vector3(0.12, 0.72, 0.45), 0.35, "dangle", 0.5)
	_actor(root, "rat", Vector3(-1.3, 0, 1.1), 1.2, "stunned", 0.3)
	_prop(root, "snap_trap", Vector3(0.9, 0, 1.4), 0.3)


func _stage_sabotage(root: Node3D) -> void:
	_prop(root, "machine_turbine", Vector3(-0.6, 0, -1.8))
	_prop(root, "sabotage_box", Vector3(-0.1, 0.25, -0.62))
	_actor(root, "rat", Vector3(-0.05, 0, -0.1), PI, "gnaw", 0.3)
	_prop(root, "lever", Vector3(1.2, 0, -0.7), -0.2)
	_actor(root, "rat", Vector3(1.25, 0, -0.15), PI - 0.2, "gnaw", 0.7)
	_prop(root, "vent_grille", Vector3(-1.7, 0, -0.4), 0.6)


func _stage_bite(root: Node3D) -> void:
	_actor(root, "supervisor", Vector3(0.0, 0, -0.2), 0.4, "knocked", 0.55)
	_actor(root, "rat", Vector3(0.62, 0, 0.35), -2.2, "bite", 0.3)
	_actor(root, "rat", Vector3(-0.62, 0, 0.4), 2.3, "bite", 0.55)
	_actor(root, "rat", Vector3(-1.5, 0, 1.0), 0.5, "squeak", 0.4)
	_prop(root, "keycard", Vector3(1.05, 0.02, 1.4), 0.6)
