extends Node3D
## Visual check of models (M7), windowed: lines up glTF models under plant-like lighting, saves a
## screenshot and quits.
##   godot tests/helpers/ArtGallery.tscn -- [--files crate,valve,...] [--out PATH] [--anim NAME]
##       [--yaw DEG] [--pitch DEG] [--dist-scale F] [--bright]
## --files: names in assets/generated (without .glb) or full res:// paths; default: every .glb in
## assets/generated. --anim plays that clip on every AnimationPlayer (frozen at --anim-time S).

const GENERATED := "res://assets/generated/"
const GAP := 0.6  ## m between models


func _ready() -> void:
	var files: Array[String] = []
	if Cli.has_arg("files"):
		for f in Cli.get_str("files").split(",", false):
			files.append(f if f.begins_with("res://") else GENERATED + f + ".glb")
	else:
		for f in DirAccess.get_files_at(GENERATED):
			if f.ends_with(".glb"):
				files.append(GENERATED + f)
	_build_environment()
	var x := 0.0
	var top := 0.0
	var depth := 0.0
	for path in files:
		var scene := load(path) as PackedScene
		if scene == null:
			push_error("cannot load " + path)
			continue
		var model := scene.instantiate() as Node3D
		add_child(model)
		var box := _aabb(model)
		model.position.x = x - box.position.x
		model.position.z = -box.get_center().z
		x += box.size.x + GAP
		top = maxf(top, box.end.y)
		depth = maxf(depth, box.size.z)
		var label := Label3D.new()
		label.text = path.get_file().get_basename()
		label.font_size = 32
		label.pixel_size = 0.004
		label.position = Vector3(x - GAP - box.size.x * 0.5, -0.12, box.size.z * 0.5 + 0.2)
		label.rotation.x = -PI * 0.5
		add_child(label)
		if Cli.has_arg("anim"):
			for player in model.find_children("*", "AnimationPlayer", true, false):
				var ap := player as AnimationPlayer
				var anim := Cli.get_str("anim")
				if ap.has_animation(anim):
					ap.play(anim)
					ap.seek(Cli.get_float("anim-time", 0.0), true)
					ap.pause()
	var width := maxf(x - GAP, 0.5)
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	var centre := Vector3(width * 0.5, top * 0.45, 0)
	var dist := maxf(width * 1.25, top * 2.2) * Cli.get_float("dist-scale", 1.0) + depth
	var yaw := deg_to_rad(Cli.get_float("yaw", 20.0))
	var pitch := deg_to_rad(Cli.get_float("pitch", -18.0))
	camera.position = centre + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * dist
	camera.look_at(centre)
	camera.make_current()
	await get_tree().create_timer(Cli.get_float("delay", 1.0)).timeout
	var out := Cli.get_str("out", "user://gallery.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("gallery: %d models, %s" % [files.size(), out])
	get_tree().quit()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.45 if not Cli.has_arg("bright") else 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	add_child(sun)
	for p: Vector3 in [Vector3(-2, 3.5, 3), Vector3(6, 3.5, 3), Vector3(14, 3.5, 3)]:
		var omni := OmniLight3D.new()
		omni.position = p
		omni.omni_range = 12.0
		omni.light_color = Color(1.0, 0.93, 0.82)
		omni.light_energy = 1.2
		omni.shadow_enabled = true
		add_child(omni)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	floor_mesh.material_override = load("res://levels/plant/materials/floor_controlroom.tres")
	add_child(floor_mesh)


func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		var box := vi.global_transform * vi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
