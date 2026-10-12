class_name Vfx
extends RefCounted
## Cosmetic effects (M7): GPU particles built in code from the Kenney particle pack (CC0) sprites,
## and camera shake. Client only and never part of gameplay: the headless server skips them (every
## factory returns null there), so callers check for null.
##
## One-shot effects free themselves. Continuous ones (steam, motes, arcs) are returned stopped;
## set `emitting`. Colours follow the palette's gameplay code (ASSETS §1).

const TEX := "res://assets/third_party/kenney_particle-pack/%s.png"
const STEAM := Color(0.95, 0.97, 1.0, 0.6)
const SPARK := Color(1.0, 0.85, 0.3)
const ARC := Color(0.55, 0.85, 1.0)
const RAD_GREEN := Color(0.61, 1.0, 0.18)
const DUST := Color(0.62, 0.58, 0.52, 0.7)
const STAR := Color(1.0, 0.86, 0.24)
const SPIT := Color(0.74, 0.93, 0.5)
const SPIT_SPEED := 10.0  ## m/s
const INK := Color("1b1b1f")
const PUDDLE_SIZE := 0.45  ## m across (a random 0.8–1.2 of it)
const PUDDLE_SHAPES := 3

static var _materials: Dictionary[String, StandardMaterial3D] = {}
static var _puddles: Array[ImageTexture] = []  # spit puddle textures (a few shapes)


## Drops the cached materials (Session does it when it leaves, so nothing is held at exit).
static func clear_cache() -> void:
	_materials.clear()
	_puddles.clear()


static func enabled() -> bool:
	return not Art.headless()


## An unshaded, camera-facing sprite material for particles (vertex colour = the particle colour).
static func sprite_material(texture: String, additive := false) -> StandardMaterial3D:
	var key := texture + ("+" if additive else "")
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(TEX % texture)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.disable_receive_shadows = true
		_materials[key] = mat
	return _materials[key]


static func _particles(texture: String, size: float, additive := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = sprite_material(texture, additive)
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = ParticleProcessMaterial.new()
	return p


static func _fade_ramp(color: Color, grow := 1.0) -> Array:
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, grow))
	var ctex := CurveTexture.new()
	ctex.curve = curve
	return [tex, ctex]


static func _one_shot(parent: Node, p: GPUParticles3D, pos: Vector3) -> GPUParticles3D:
	p.one_shot = true
	p.explosiveness = 0.9
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# --- One-shots ------------------------------------------------------------------------------------

## A soft puff of smoke/dust (impacts, landings, trap snaps).
static func puff(parent: Node, pos: Vector3, color: Color = DUST, amount := 10, size := 0.5) -> GPUParticles3D:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return null
	var p := _particles("smoke_04", size)
	p.amount = amount
	p.lifetime = 0.6
	var m := p.process_material as ParticleProcessMaterial
	m.direction = Vector3.UP
	m.spread = 90.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.6
	m.gravity = Vector3(0, 0.4, 0)
	m.damping_min = 2.0
	m.damping_max = 3.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	var ramps := _fade_ramp(color, 1.6)
	m.color_ramp = ramps[0]
	m.scale_curve = ramps[1]
	return _one_shot(parent, p, pos)


## A burst of sparks (sabotage, electric hazards, broken cameras).
static func sparks(parent: Node, pos: Vector3, amount := 16, color: Color = SPARK) -> GPUParticles3D:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return null
	var p := _particles("spark_05", 0.12, true)
	p.amount = amount
	p.lifetime = 0.5
	var m := p.process_material as ParticleProcessMaterial
	m.direction = Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.5
	m.gravity = Vector3(0, -9.0, 0)
	var ramps := _fade_ramp(color, 0.3)
	m.color_ramp = ramps[0]
	m.scale_curve = ramps[1]
	return _one_shot(parent, p, pos)


## A cartoon impact: a ring of stars and a puff (BONK).
static func bonk(parent: Node, pos: Vector3) -> void:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return
	var p := _particles("star_06", 0.22, true)
	p.amount = 8
	p.lifetime = 0.45
	var m := p.process_material as ParticleProcessMaterial
	m.direction = Vector3.UP
	m.spread = 180.0
	m.flatness = 0.8
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 2.6
	m.damping_min = 4.0
	m.damping_max = 4.0
	var ramps := _fade_ramp(STAR, 0.6)
	m.color_ramp = ramps[0]
	m.scale_curve = ramps[1]
	_one_shot(parent, p, pos)
	puff(parent, pos, Color(1, 1, 1, 0.8), 6, 0.4)


## Crumbs (eating a donut).
static func crumbs(parent: Node, pos: Vector3) -> void:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return
	var p := _particles("circle_05", 0.05)
	p.amount = 10
	p.lifetime = 0.6
	var m := p.process_material as ParticleProcessMaterial
	m.direction = Vector3(0, 0.3, -1)
	m.spread = 50.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.2
	m.gravity = Vector3(0, -6, 0)
	m.color_ramp = _fade_ramp(Color(0.89, 0.66, 0.34))[0]
	_one_shot(parent, p, pos)


## A glob of rat spit flying from `from` to `to` in a little arc, leaving a trail of droplets in the
## air; a splash where it lands. Returns how long the flight takes (s), or 0 when effects are off.
static func spit(parent: Node, from: Vector3, to: Vector3) -> float:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return 0.0
	var glob := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SPIT
	mat.roughness = 0.15
	sphere.material = mat
	glob.mesh = sphere
	glob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glob)
	glob.global_position = from
	var trail := _spit_trail()
	glob.add_child(trail)
	trail.emitting = true
	var flight := clampf(from.distance_to(to) / SPIT_SPEED, 0.08, 0.7)
	var arc := from.distance_to(to) * 0.15
	var tween := glob.create_tween()
	tween.tween_method(func(u: float) -> void:
		glob.global_position = from.lerp(to, u) + Vector3.UP * arc * 4.0 * u * (1.0 - u), 0.0, 1.0, flight)
	tween.tween_callback(func() -> void:
		puff(parent, to, Color(SPIT, 0.8), 6, 0.25)
		# The trail outlives the glob: its droplets hang in the air a moment, then fade.
		trail.reparent(parent)
		trail.emitting = false
		parent.get_tree().create_timer(trail.lifetime + 0.1).timeout.connect(trail.queue_free)
		glob.queue_free())
	return flight


## The droplets a flying glob leaves behind (world space, so they stay where they were shed).
static func _spit_trail() -> GPUParticles3D:
	var p := _particles("circle_05", 0.12)
	p.amount = 160
	p.lifetime = 0.5
	p.local_coords = false
	p.fixed_fps = 0  # emit every frame, so a fast glob still draws a continuous streak
	p.interpolate = true
	var m := p.process_material as ParticleProcessMaterial
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.15
	m.gravity = Vector3(0, -1.0, 0)
	var ramps := _fade_ramp(SPIT, 0.3)
	m.color_ramp = ramps[0]
	m.scale_curve = ramps[1]
	return p


## A puddle of spit on the floor at `pos` (a decal, so it follows steps and slopes): it splats in and
## stays until the caller frees it. Null when effects are off.
static func spit_puddle(parent: Node, pos: Vector3) -> Decal:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return null
	if _puddles.is_empty():
		for i in PUDDLE_SHAPES:
			_puddles.append(ImageTexture.create_from_image(_puddle_image(i)))
	var decal := Decal.new()
	decal.texture_albedo = _puddles[randi() % _puddles.size()]
	var size := PUDDLE_SIZE * randf_range(0.8, 1.2)
	decal.size = Vector3(size, 0.3, size)
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	parent.add_child(decal)
	decal.global_position = pos
	decal.rotation.y = randf() * TAU
	decal.scale = Vector3(0.2, 1.0, 0.2)
	decal.create_tween().tween_property(decal, "scale", Vector3.ONE, 0.15).set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)
	return decal


## A cartoon spit blob like SpitSplat's: a big drop and droplets, ink-outlined, with a shine.
static func _puddle_image(shape: int) -> Image:
	const SIZE := 128
	const OUTLINE := 4.0  ## px
	var r := RandomNumberGenerator.new()
	r.seed = 9100 + shape
	var blobs: Array[Vector3] = [Vector3(SIZE * 0.5, SIZE * 0.5, r.randf_range(30.0, 36.0))]
	for i in r.randi_range(5, 7):
		var a := r.randf() * TAU
		var d := r.randf_range(34.0, 52.0)
		blobs.append(Vector3(SIZE * 0.5 + cos(a) * d, SIZE * 0.5 + sin(a) * d, r.randf_range(4.0, 10.0)))
	var shine := Vector2(SIZE * 0.5 - 11.0, SIZE * 0.5 - 12.0)
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var d := INF  # distance outside the nearest blob's edge (negative inside)
			for b in blobs:
				d = minf(d, Vector2(x - b.x, y - b.y).length() - b.z)
			var alpha := clampf(OUTLINE + 0.5 - d, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var color := INK.lerp(SPIT, clampf(0.5 - d, 0.0, 1.0))
			if Vector2(x, y).distance_to(shine) < 6.0:
				color = color.lerp(Color.WHITE, 0.55)
			image.set_pixel(x, y, Color(color, alpha))
	return image


# --- Continuous -------------------------------------------------------------------------------------

## A steam jet blowing along the node's -Z... set `direction` on the returned node's process material
## for another axis. `length` m long.
static func steam(direction: Vector3, length: float) -> GPUParticles3D:
	if not enabled():
		return null
	var p := _particles("smoke_07", 0.5)
	p.amount = 48
	p.lifetime = 0.6
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4)).expand(direction * length)
	var m := p.process_material as ParticleProcessMaterial
	m.direction = direction
	m.spread = 12.0
	m.initial_velocity_min = length * 1.4
	m.initial_velocity_max = length * 1.9
	m.gravity = Vector3(0, 1.5, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	var ramps := _fade_ramp(STEAM, 3.0)
	m.color_ramp = ramps[0]
	m.scale_curve = ramps[1]
	return p


## Electric arcs crackling over an area of `size` (x, z) (puddles, the grid).
static func arcs(size: Vector2) -> GPUParticles3D:
	if not enabled():
		return null
	var p := _particles("trace_01", 0.6, true)
	p.amount = 14
	p.lifetime = 0.18
	p.emitting = false
	var m := p.process_material as ParticleProcessMaterial
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.y * 0.5)
	m.direction = Vector3.UP
	m.spread = 30.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.3
	m.gravity = Vector3.ZERO
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.scale_min = 0.4
	m.scale_max = 1.2
	m.color_ramp = _fade_ramp(ARC)[0]
	return p


## Glowing motes drifting up through a box of `size` (radiation).
static func motes(size: Vector3, color: Color = RAD_GREEN, amount := 40) -> GPUParticles3D:
	if not enabled():
		return null
	var p := _particles("light_01", 0.18, true)
	p.amount = amount
	p.lifetime = 2.5
	p.emitting = false
	p.preprocess = 2.0
	var m := p.process_material as ParticleProcessMaterial
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = size * 0.5
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.6
	m.gravity = Vector3.ZERO
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return p


## Dust falling from the ceiling over a box of `size` (debris hazard).
static func dust_fall(size: Vector3) -> GPUParticles3D:
	if not enabled():
		return null
	var p := _particles("dirt_02", 0.35)
	p.amount = 30
	p.lifetime = 1.6
	p.emitting = false
	var m := p.process_material as ParticleProcessMaterial
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(size.x * 0.5, 0.1, size.z * 0.5)
	m.direction = Vector3.DOWN
	m.spread = 10.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.5
	m.gravity = Vector3(0, -3.0, 0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.color_ramp = _fade_ramp(DUST)[0]
	return p


## Spinning stars over a stunned head: three star sprites orbiting (not particles, so they stay
## readable and cost nothing when hidden).
static func stun_stars(radius := 0.3) -> Node3D:
	if not enabled():
		return null
	var root := Node3D.new()
	root.name = "StunStars"
	for i in 3:
		var star := Sprite3D.new()
		star.texture = load(TEX % "star_06")
		star.pixel_size = 0.0012
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.modulate = STAR
		star.shaded = false
		star.no_depth_test = false
		var a := TAU * i / 3.0
		star.position = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		root.add_child(star)
	root.set_script(load("res://client/stun_stars.gd"))
	return root


# --- Camera -----------------------------------------------------------------------------------------

## Shakes the local player's camera (BONK, knockdown, debris), unless the player turned it off.
static func shake(strength: float) -> void:
	if not enabled() or not Config.camera_shake or Session.current == null:
		return
	var body := Session.current.get_body(Session.current.local_peer_id)
	if body != null and body.rig != null:
		body.rig.shake(strength)
