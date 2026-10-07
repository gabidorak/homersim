extends Node
## Renders the hotbar's item icons (HotbarView), windowed: each item's generated model alone on a
## transparent background, lit like the How to play shots, cropped to fit, then given a thick ink
## outline like a sticker (the UI's look: ink outlines with a deeper bottom edge), saved as a PNG.
##   godot tests/helpers/ItemIcons.tscn -- [--out assets/ui/items] [--only NAME]
## Then run `godot --headless --import`.

const RENDER := Vector2i(512, 512)  ## rendered this big, then scaled down (smooth edges)
const SIZE := 128  ## the saved icon, square
const OUTLINE := 4.5  ## px of ink around the item…
const OUTLINE_DROP := 2.5  ## …and this much more below it
const INK := Color("1b1b1f")
const SETTLE_S := 0.5
const FOV := 30.0
const MARGIN := 1.05  ## the bounding sphere fills 1 / MARGIN of the render

# icon name, model, model rotation (degrees about X, then Y, then Z), camera elevation (degrees),
# camera yaw (degrees, 0 = from +Z), model scale
const ICONS := [
	["snap_trap", "snap_trap", Vector3(0, -30, 0), 42.0, 0.0, 1.0],
	["cheese_lure", "cheese_lure", Vector3(0, 35, 0), 30.0, 0.0, 1.0],
	["donut", "k_donut_sprinkles", Vector3(0, 0, 0), 45.0, 0.0, 1.0],  # pinker than ours: reads at a glance
	["keycard", "keycard", Vector3(90, 25, -50), 15.0, 0.0, 1.0],  # stood up, the lanyard up and left
]


func _ready() -> void:
	var out := Cli.get_str("out", "user://item_icons")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	# The per-object hull outlines, whatever this machine's settings say (screen-wide lines would
	# need the main camera).
	RenderingServer.global_shader_parameter_set(&"outline_hull_enabled", true)
	for icon: Array in ICONS:
		if Cli.has_arg("only") and icon[0] != Cli.get_str("only"):
			continue
		var viewport := SubViewport.new()
		viewport.size = RENDER
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.msaa_3d = Viewport.MSAA_8X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var root := Node3D.new()
		viewport.add_child(root)
		_world(root)
		var rot: Vector3 = icon[2]
		var basis := (Basis(Vector3.BACK, deg_to_rad(rot.z)) * Basis(Vector3.UP, deg_to_rad(rot.y))
			* Basis(Vector3.RIGHT, deg_to_rad(rot.x))).scaled(Vector3.ONE * float(icon[5]))
		var model := Art.add(root, icon[1], Transform3D(basis, Vector3.ZERO), false)
		if model == null:
			Log.info("icons", "%s: no model %s" % [icon[0], icon[1]])
			viewport.queue_free()
			continue
		var box := _bounds(model)
		var radius := box.size.length() * 0.5
		var distance := radius * MARGIN / sin(deg_to_rad(FOV) * 0.5)
		var view := Vector3(0, 0, 1).rotated(Vector3.RIGHT, -deg_to_rad(icon[3])).rotated(Vector3.UP, deg_to_rad(icon[4]))
		var camera := Camera3D.new()
		camera.fov = FOV
		camera.near = 0.01
		root.add_child(camera)
		camera.look_at_from_position(box.get_center() + view * distance, box.get_center())
		camera.make_current()
		await get_tree().create_timer(SETTLE_S).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [out, icon[0]]
		var image := _sticker(viewport.get_texture().get_image())
		var err := image.save_png(ProjectSettings.globalize_path(path))
		Log.info("icons", "%s: %s" % [path, error_string(err)])
		viewport.queue_free()
	get_tree().quit()


## The render cropped to the item, scaled into a SIZE square (room left for the outline), with
## an ink outline under it.
func _sticker(render: Image) -> Image:
	render.convert(Image.FORMAT_RGBA8)
	var used := render.get_used_rect()
	var item := render.get_region(used)
	var room := SIZE - 2.0 * ceilf(OUTLINE + 1.0) - ceilf(OUTLINE_DROP)
	var scale := room / float(maxi(used.size.x, used.size.y))
	item.resize(maxi(roundi(used.size.x * scale), 1), maxi(roundi(used.size.y * scale), 1), Image.INTERPOLATE_LANCZOS)
	var at := Vector2i((SIZE - item.get_width()) / 2, roundi((SIZE - OUTLINE_DROP - item.get_height()) * 0.5))
	var icon := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# The ink: for each pixel, how far the nearest solid item pixel is (the drop stretches it downward).
	var solid: Array[Vector2i] = []
	for y in item.get_height():
		for x in item.get_width():
			if item.get_pixel(x, y).a > 0.5:
				solid.append(Vector2i(x, y) + at)
	var reach := ceili(OUTLINE + OUTLINE_DROP + 1.0)
	var near := PackedFloat32Array()
	near.resize(SIZE * SIZE)
	near.fill(INF)
	for p in solid:
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var q := p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= SIZE or q.y >= SIZE:
					continue
				# Below the item the outline reaches OUTLINE_DROP further: squash the distance there.
				var ddy := float(dy) - clampf(float(dy), 0.0, OUTLINE_DROP)
				var d := sqrt(dx * dx + ddy * ddy)
				var i := q.y * SIZE + q.x
				if d < near[i]:
					near[i] = d
	for y in SIZE:
		for x in SIZE:
			var a := clampf(OUTLINE + 0.5 - near[y * SIZE + x], 0.0, 1.0)
			if a > 0.0:
				icon.set_pixel(x, y, Color(INK, a))
	icon.blend_rect(item, Rect2i(Vector2i.ZERO, item.get_size()), at)
	return icon


## The model's box in world space (every mesh, with its transform).
func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in Art.meshes(model):
		var part := mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _world(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.82)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 0.9
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.6, 0)
	fill.light_energy = 0.45
	root.add_child(fill)
