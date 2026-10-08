class_name IntroFx
extends Node3D
## The intro's effects (client/intro/intro.gd), in the game's cartoon look: the transformation's
## POOF (puffy toon balls that swell and pop, smoke, stars, a flash), hearts, "!" marks, goo blobs
## and droplets, and arcs to toss things along. Built from the generated models (heart, goo_blob,
## exclaim) and the Kenney particle sprites (CC0, like client/vfx.gd), with materials of its own: they
## go away with the intro instead of staying in a static cache.

const SPRITES := "res://assets/third_party/kenney_particle-pack/%s.png"
const TOON: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE: Material = preload("res://shaders/materials/outline.tres")
const GOO := Color(0.61, 1.0, 0.18)  ## the palette's rad_green
const STAR := Color(1.0, 0.86, 0.24)

var camera: Camera3D  ## "!" marks and hearts turn to face it

var _ball_mesh: SphereMesh
var _cloud_mat: ShaderMaterial
var _sprites: Dictionary[String, StandardMaterial3D] = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7  # the same intro every time
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.5
	_ball_mesh.height = 1.0
	_ball_mesh.radial_segments = 16
	_ball_mesh.rings = 8
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = TOON
	_cloud_mat.set_shader_parameter(&"albedo", Color(0.95, 1.0, 0.93))
	_cloud_mat.set_shader_parameter(&"emission", Color(0.55, 0.85, 0.45))
	_cloud_mat.set_shader_parameter(&"emission_energy", 0.35)
	_cloud_mat.next_pass = OUTLINE


## Runs every effect once, tiny, in front of the camera: their shaders compile while the screen is
## still black, so nothing stutters later.
func prewarm() -> void:
	if camera == null:
		return
	var pos := camera.global_position - camera.global_basis.z * 1.5
	poof(pos, 0.05)
	hearts(pos, 1, 0.05)
	exclaim(pos, 0.05, 0.1)
	droplets(pos, Vector3.UP, 4, 0.05)
	sparks(pos, 2)
	stars(pos)
	var spill := splat(pos, Color.BLACK, 0.01)
	var glint := MeshInstance3D.new()
	glint.mesh = QuadMesh.new()
	glint.material_override = glint_material()
	glint.scale = Vector3.ONE * 0.01
	add_child(glint)
	glint.global_position = pos
	var blob := Art.add(self, "goo_blob")
	if blob != null:
		blob.global_position = pos
		blob.scale = Vector3.ONE * 0.05
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		glint.queue_free()
		spill.queue_free()
		if blob != null:
			blob.queue_free())


## The cartoon POOF of the transformation, `size` m across, tinted radioactive.
func poof(pos: Vector3, size := 1.0) -> void:
	var cloud := Node3D.new()
	cloud.name = "Poof"
	add_child(cloud)
	cloud.global_position = pos
	for i in 11:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 1.0), _rng.randf_range(-1, 1)).normalized()
		if i == 0:
			dir = Vector3.ZERO
		var ball := MeshInstance3D.new()
		ball.mesh = _ball_mesh
		ball.material_override = _cloud_mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.position = dir * 0.15 * size
		ball.scale = Vector3.ZERO
		cloud.add_child(ball)
		var s := (_rng.randf_range(0.3, 0.46) if i > 0 else 0.62) * size
		var delay := _rng.randf_range(0.0, 0.07)
		var grow := ball.create_tween()
		grow.tween_interval(delay)
		grow.tween_property(ball, ^"scale", Vector3.ONE * s, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		grow.tween_interval(0.1 + _rng.randf_range(0.0, 0.12))
		grow.tween_property(ball, ^"scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var drift := ball.create_tween()
		drift.tween_interval(delay)
		drift.tween_property(ball, ^"position", dir * 0.42 * size + Vector3.UP * 0.12 * size, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_burst(cloud, "smoke_04", 14, 0.55 * size, Color(0.92, 1.0, 0.88, 0.85), 1.6 * size, 0.7, false, 1.8)
	_burst(cloud, "star_06", 12, 0.16 * size, STAR, 3.2 * size, 0.55, true, 0.4)
	_burst(cloud, "star_07", 8, 0.12 * size, GOO, 2.4 * size, 0.6, true, 0.4)
	flash(pos, Color(0.75, 1.0, 0.6), 4.0 * size, 1.6 * size + 0.4, 0.3)
	get_tree().create_timer(1.4).timeout.connect(cloud.queue_free)


## A couple of hearts floating up from `pos` and fading away.
func hearts(pos: Vector3, count := 2, size := 1.0) -> void:
	for i in count:
		var heart := Art.add(self, "heart", Transform3D.IDENTITY, false)
		if heart == null:
			return
		heart.global_position = pos + Vector3(_rng.randf_range(-0.06, 0.06), 0.0, _rng.randf_range(-0.04, 0.04))
		_face_camera(heart)
		heart.scale = Vector3.ZERO
		var s := _rng.randf_range(0.8, 1.15) * size
		var delay := i * 0.22
		var rise := heart.create_tween()
		rise.tween_interval(delay)
		rise.tween_property(heart, ^"scale", Vector3.ONE * s, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rise.parallel().tween_property(heart, ^"global_position:y", heart.global_position.y + 0.42 * size, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		rise.parallel().tween_property(heart, ^"rotation:z", _rng.randf_range(-0.35, 0.35), 1.1)
		rise.tween_property(heart, ^"scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		rise.tween_callback(heart.queue_free)


## A red "!" popping over a head for `hold` s.
func exclaim(pos: Vector3, size := 1.0, hold := 0.9) -> void:
	var mark := Art.add(self, "exclaim", Transform3D.IDENTITY, false)
	if mark == null:
		return
	mark.global_position = pos
	_face_camera(mark)
	mark.scale = Vector3.ZERO
	var tween := mark.create_tween()
	tween.tween_property(mark, ^"scale", Vector3.ONE * size * 1.25, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, ^"scale", Vector3.ONE * size, 0.08)
	tween.tween_property(mark, ^"rotation:z", 0.12, 0.06)
	tween.tween_property(mark, ^"rotation:z", -0.12, 0.08)
	tween.tween_property(mark, ^"rotation:z", 0.0, 0.06)
	tween.tween_interval(maxf(hold - 0.38, 0.0))
	tween.tween_property(mark, ^"scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(mark.queue_free)


## Glowing goo droplets thrown from `pos` along `dir` (they fall back down).
func droplets(pos: Vector3, dir: Vector3, amount := 16, size := 1.0) -> void:
	var p := GPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.07 * size
	quad.material = _sprite("circle_05", true)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	var m := ParticleProcessMaterial.new()
	m.direction = dir.normalized()
	m.spread = 55.0
	m.initial_velocity_min = 1.2 * size
	m.initial_velocity_max = 2.6 * size
	m.gravity = Vector3(0, -7.0, 0)
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color_ramp = _ramp(Color(GOO, 1.0), Color(GOO, 0.0))
	p.process_material = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## A goo blob (glowing, outlined) under `parent`, `size` m across, at `local` in its space.
func blob(parent: Node3D, local: Vector3, size: float) -> Node3D:
	var gob := Art.add(parent, "goo_blob", Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU,
		_rng.randf() * TAU, 0.0)), local), false)
	if gob != null:
		gob.scale = Vector3.ONE * size / 0.1
	return gob


## A burst of sparks (the junction box the rat chews up).
func sparks(pos: Vector3, amount := 18) -> void:
	var p := GPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	quad.material = _sprite("spark_05", true)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.5
	m.gravity = Vector3(0, -9.0, 0)
	m.color_ramp = _ramp(Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.2, 0.0))
	p.process_material = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	flash(pos, Color(1.0, 0.85, 0.5), 2.5, 2.0, 0.15)


## A cartoon BONK: a ring of stars and a puff.
func stars(pos: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos
	_burst(holder, "star_06", 10, 0.22, STAR, 2.6, 0.5, true, 0.6)
	_burst(holder, "smoke_04", 6, 0.4, Color(1, 1, 1, 0.8), 1.2, 0.5, false, 1.6)
	get_tree().create_timer(1.0).timeout.connect(holder.queue_free)


## Something spilt on the floor (coffee): a flat splat that spreads to `size` m.
func splat(pos: Vector3, color: Color, size: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.006
	disc.radial_segments = 16
	mesh.mesh = disc
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter(&"albedo", color)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = Vector3(pos.x, 0.005, pos.z)
	mesh.scale = Vector3(0.05, 1.0, 0.05)
	mesh.create_tween().tween_property(mesh, ^"scale", Vector3(size, 1.0, size * 0.8), 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return mesh


## The glowing glint of a radioactive eye (additive, facing the camera).
func glint_material() -> StandardMaterial3D:
	var key := "glint"
	if not _sprites.has(key):
		var mat := _sprite("light_01", true).duplicate() as StandardMaterial3D
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.vertex_color_use_as_albedo = false
		mat.albedo_color = Color(0.7, 1.0, 0.3)
		mat.no_depth_test = false
		_sprites[key] = mat
	return _sprites[key]


## A light that flares to `energy` and dies out in `duration` s.
func flash(pos: Vector3, color: Color, energy: float, range_: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_
	light.shadow_enabled = false
	add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, ^"light_energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


## Tosses `node` along an arc from where it is to `target` (`height` m over the straight line), in
## `duration` s, spinning `spin` radians about each axis on the way.
static func toss(node: Node3D, target: Vector3, height: float, duration: float, spin := Vector3.ZERO) -> Tween:
	var from := node.global_position
	var rot0 := node.rotation
	var tween := node.create_tween()
	tween.tween_method(func(t: float) -> void:
		node.global_position = from.lerp(target, t) + Vector3.UP * height * 4.0 * t * (1.0 - t)
		node.rotation = rot0 + spin * t, 0.0, 1.0, duration)
	return tween


func _burst(parent: Node3D, texture: String, amount: int, size: float, color: Color, speed: float,
		lifetime: float, additive: bool, grow: float) -> void:
	var p := GPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _sprite(texture, additive)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = speed * 0.5
	m.initial_velocity_max = speed
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = speed * 1.5
	m.damping_max = speed * 2.5
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.color_ramp = _ramp(color, Color(color, 0.0))
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, grow))
	var ctex := CurveTexture.new()
	ctex.curve = curve
	m.scale_curve = ctex
	p.process_material = m
	parent.add_child(p)
	p.emitting = true


func _sprite(texture: String, additive: bool) -> StandardMaterial3D:
	var key := texture + ("+" if additive else "")
	if not _sprites.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(SPRITES % texture)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.disable_receive_shadows = true
		_sprites[key] = mat
	return _sprites[key]


static func _ramp(from: Color, to: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


func _face_camera(node: Node3D) -> void:
	if camera == null:
		return
	var to := camera.global_position - node.global_position
	to.y = 0.0
	if to.length() > 0.01:
		node.rotation.y = atan2(to.x, to.z)  # models face +Z
