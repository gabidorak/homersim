class_name OutroFx
extends IntroFx
## The end-of-match cinematics' effects (client/outro/outro.gd), on top of the intro's (IntroFx:
## hearts, flashes, bursts): the cooling towers' puffs, the heart they puff when the slice flies
## (SUPERVISORS), their goo-green cough (RATS) and the heat haze over the toaster, all drawn from the
## clock like everything that moves in the outro (towers(), heart_cloud(), cough(), shimmer()), and
## one-shots the cues fire: crumbs, the photo's sparkle, a heart of steam over the tea, the rats'
## scatter. The tea steams all along.

const HAZE: Shader = preload("res://shaders/heat_haze.gdshader")
const CRUMBS: Array[Color] = [Color("d8953e"), Color("9c5a25"), Color("e2c48f")]
const PUFFS := 7  ## per tower
## The towers' heart: its balls round a heart's outline and inside it (in heart units: x -1..1, y
## -1..0.75, the point at the bottom), its height (m: it reads at the window's size), where it floats;
## it forms in HEART_FORM s, beats, drifts up and goes in HEART_LIFE.
const HEART_OUTLINE := 20
const HEART_INSIDE: Array[Vector2] = [Vector2(-0.5, 0.35), Vector2(0.5, 0.35), Vector2(0.0, 0.0), Vector2(-0.3, -0.3),
	Vector2(0.3, -0.3), Vector2(0.0, -0.55), Vector2(-0.45, 0.0), Vector2(0.45, 0.0)]
const HEART_HEIGHT := 34.0
## Where the heart's middle floats: OutroKitchen.view_spot's yaw and pitch (up right of the towers).
const HEART_AT := Vector2(9.4, 12.2)
const HEART_FORM := 0.38
const HEART_LIFE := 2.9
const COUGH_BALLS := 9  ## per tower
const COUGH_LIFE := 1.7

var _puffs: Array[MeshInstance3D] = []
var _puff_mat: ShaderMaterial
var _heart: Array[MeshInstance3D] = []
var _cough: Array[MeshInstance3D] = []
var _haze: MeshInstance3D
var _steam: GPUParticles3D
var _steam_material: StandardMaterial3D  # (its own: the steam dims with the light)


## The cooling towers' clouds at `time`: puffs rise from each top, swell and fade, calm and regular;
## `sputtering` (the power's failing): smaller, uneven, some missing. None starts after `until` (the
## plant is down): the last ones rise and fade.
func towers(tops: Array[Vector3], time: float, sputtering: bool, until := INF) -> void:
	if _puffs.is_empty():
		_puff_mat = ShaderMaterial.new()
		_puff_mat.shader = TOON
		_puff_mat.set_shader_parameter(&"albedo", Color(1.0, 0.98, 0.95))
		_puff_mat.set_shader_parameter(&"emission", Color(1.0, 0.86, 0.7) if not sputtering else Color(0.45, 0.55, 0.8))
		_puff_mat.set_shader_parameter(&"emission_energy", 0.32 if not sputtering else 0.12)
		_puff_mat.next_pass = OUTLINE
		for i in tops.size() * PUFFS:
			var ball := MeshInstance3D.new()
			ball.mesh = _ball_mesh
			ball.material_override = _puff_mat
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ball)
			_puffs.append(ball)
	for k in tops.size():
		for i in PUFFS:
			var ball := _puffs[k * PUFFS + i]
			var period := 4.2 if not sputtering else 2.6 + 1.3 * fmod(i * 0.618 + k * 0.31, 1.0)
			var age := fposmod(time / period + float(i) / PUFFS + k * 0.37, 1.0)
			var size := 7.0 + 9.0 * sqrt(age)
			var missing := sputtering and fmod(i * 0.41 + k * 0.7, 1.0) < 0.35
			if sputtering:
				size *= 0.55 + 0.25 * fmod(i * 0.77, 1.0)
			var fade := 1.0 - smoothstep(0.75, 1.0, age)
			missing = missing or time - age * period > until
			ball.scale = Vector3.ONE * size * fade * (0.0 if missing else 1.0)
			ball.position = tops[k] + Vector3(4.0 + 22.0 * age * (1.0 + 0.3 * sin(i * 2.1)), 3.0 + 16.0 * sqrt(age),
				-2.0 * age + 3.0 * sin(i * 1.7 + k))


## The plant celebrates (SUPERVISORS): from `start`, both cooling towers puff together and their puffs
## gather into a big heart over them, warm with the sunrise; it gives a beat, drifts up and melts away.
## Toon balls like the towers' puffs, facing the opening shot's eye (the view is composed from there).
func heart_cloud(tops: Array[Vector3], time: float, start: float) -> void:
	if _heart.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = TOON
		mat.set_shader_parameter(&"albedo", Color(1.0, 0.8, 0.82))
		mat.set_shader_parameter(&"emission", Color(1.0, 0.5, 0.52))
		mat.set_shader_parameter(&"emission_energy", 0.5)
		mat.next_pass = OUTLINE
		for i in HEART_OUTLINE + HEART_INSIDE.size():
			var ball := MeshInstance3D.new()
			ball.mesh = _ball_mesh
			ball.material_override = mat
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ball)
			_heart.append(ball)
	var s := time - start
	var middle := OutroKitchen.view_spot(HEART_AT.x, HEART_AT.y, 350.0) + Vector3(0.0, 3.0 * maxf(s, 0.0), 0.0)
	var facing := Basis.looking_at(middle - OutroKitchen.VIEW_EYE, Vector3.UP)  # its x right, y up as seen
	var form := Outro._ramp(s, 0.0, HEART_FORM, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var swell := Outro._ramp(s, 0.0, HEART_FORM, Tween.TRANS_BACK, Tween.EASE_OUT)
	var beat := 1.0 + 0.1 * sin(PI * clampf((s - HEART_FORM - 0.15) / 0.22, 0.0, 1.0))
	var melt := 1.0 - Outro._ramp(s, HEART_LIFE - 0.7, HEART_LIFE, Tween.TRANS_SINE, Tween.EASE_IN)
	var half := HEART_HEIGHT * 0.5
	for i in _heart.size():
		var ball := _heart[i]
		var at := heart_point(i)
		var target := middle + facing * Vector3(at.x * half * 1.05, at.y * half, 0.0) * beat
		var from: Vector3 = tops[0] if at.x < 0.0 else tops[1]
		ball.visible = s >= 0.0 and melt > 0.0
		ball.position = from.lerp(target, form)
		var size := (0.4 if i < HEART_OUTLINE else 0.5) * HEART_HEIGHT * 0.5
		ball.scale = Vector3.ONE * size * swell * beat * melt


## Where the heart's ball `i` sits, in heart units (x -1..1 across, the outline first, then inside).
static func heart_point(i: int) -> Vector2:
	if i >= HEART_OUTLINE:
		return HEART_INSIDE[i - HEART_OUTLINE]
	var a := TAU * i / HEART_OUTLINE
	var x := pow(sin(a), 3.0)
	var y := (13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)) / 16.0
	return Vector2(x, y + 0.1)


## The meltdown (RATS): from `start` the cooling towers cough a goo-green puff, a quick burst out of
## each top that rolls up and away and fades.
func cough(tops: Array[Vector3], time: float, start: float) -> void:
	if _cough.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = TOON
		mat.set_shader_parameter(&"albedo", Color(0.7, 1.0, 0.4))
		mat.set_shader_parameter(&"emission", GOO)
		mat.set_shader_parameter(&"emission_energy", 0.75)
		mat.next_pass = OUTLINE
		for i in tops.size() * COUGH_BALLS:
			var ball := MeshInstance3D.new()
			ball.mesh = _ball_mesh
			ball.material_override = mat
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ball)
			_cough.append(ball)
	var s := time - start
	for k in tops.size():
		for i in COUGH_BALLS:
			var ball := _cough[k * COUGH_BALLS + i]
			var a := TAU * i / COUGH_BALLS + k * 0.7
			var delay := 0.04 * (i % 3)
			var u := clampf((s - delay) / COUGH_LIFE, 0.0, 1.0)
			var burst := Outro._ramp(s - delay, 0.0, 0.16, Tween.TRANS_BACK, Tween.EASE_OUT)
			var fade := 1.0 - smoothstep(0.55, 1.0, u)
			ball.visible = s >= delay and u < 1.0
			var out := Vector3(cos(a) * 11.0, 1.0 + 3.0 * absf(sin(a * 1.3)), sin(a) * 4.0)
			ball.position = tops[k] + out * (0.4 + 1.3 * sqrt(u)) + Vector3(8.0, 4.0, 0.0) * u
			ball.scale = Vector3.ONE * (9.0 + 5.0 * absf(sin(i * 2.3))) * burst * fade * (1.0 + 0.6 * u)


## The heat haze rising over the toaster's slots at `time` (`heat` 0..1: none .. full).
func shimmer(at: Vector3, time: float, heat: float) -> void:
	if _haze == null:
		_haze = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.24, 0.3)
		_haze.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = HAZE
		_haze.material_override = mat
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_haze)
	_haze.visible = heat > 0.02
	_haze.global_position = at + Vector3(0, 0.15, 0)
	_haze.set_instance_shader_parameter(&"strength", heat)
	_haze.set_instance_shader_parameter(&"phase", time)


## The tea's steam, curling up from the cup, all along.
func tea_steam(cup: Node3D) -> void:
	if cup == null or not is_inside_tree():
		return
	var mark := Art.part(cup, "Steam")
	_steam = GPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.06
	_steam_material = _sprite("smoke_07", false).duplicate() as StandardMaterial3D
	quad.material = _steam_material
	_steam.draw_pass_1 = quad
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam.amount = 14
	_steam.lifetime = 1.8
	_steam.preprocess = 2.0
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.1
	m.gravity = Vector3(0, 0.03, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.4
	m.turbulence_noise_scale = 6.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.4))
	var ctex := CurveTexture.new()
	ctex.curve = curve
	m.scale_curve = ctex
	_steam.process_material = m
	add_child(_steam)
	_steam.global_position = mark.global_position if mark != null else cup.global_position + Vector3(0, 0.07, 0)
	_steam.emitting = true


## The tea's steam in this light (1 the room's, 0 the dark: it's barely there).
func steam_light(level: float) -> void:
	if _steam_material != null:
		var c := Color(0.16, 0.2, 0.32).lerp(Color.WHITE, clampf(level, 0.0, 1.0))
		_steam_material.albedo_color = Color(c.r, c.g, c.b, _steam_material.albedo_color.a)


## A heart of steam rising out of the tea, fading (she's happy, the tea is too).
func steam_heart(cup: Node3D) -> void:
	if cup == null:
		return
	var heart := Art.add(self, "heart", Transform3D.IDENTITY, false)
	if heart == null:
		return
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	white.albedo_color = Color(1, 1, 1, 0.55)
	for mesh in Art.meshes(heart):
		mesh.material_override = white
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heart.global_position = cup.global_position + Vector3(0, 0.1, 0)
	_face_camera(heart)
	heart.scale = Vector3.ZERO
	var rise := heart.create_tween()
	rise.tween_property(heart, ^"scale", Vector3.ONE * 0.8, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.parallel().tween_property(heart, ^"global_position:y", heart.global_position.y + 0.22, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.parallel().tween_property(white, ^"albedo_color:a", 0.0, 0.6).set_delay(0.7)
	rise.tween_callback(heart.queue_free)


## A rat scattering in the dark as the match flares: a little puff of dust and a few goo-green
## sparks where it was (no light: the match lights the room).
func scatter(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos
	_burst(holder, "smoke_04", 6, 0.12, Color(0.72, 0.78, 0.95, 0.75), 0.7, 0.45, false, 1.5)
	_burst(holder, "star_06", 5, 0.045, GOO, 1.1, 0.35, true, 0.4)
	get_tree().create_timer(0.8).timeout.connect(holder.queue_free)


## Crumbs flying from `pos` (a landing slice; `falling`: a bite, they rain down onto the plate).
func crumb_puff(pos: Vector3, amount := 10, falling := false) -> void:
	if not is_inside_tree():
		return
	for k in CRUMBS.size():
		var p := GPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.012
		quad.material = _sprite("circle_05", false)
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.amount = maxi(amount / CRUMBS.size(), 2)
		p.lifetime = 0.7
		p.one_shot = true
		p.explosiveness = 0.95
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3.DOWN if falling else Vector3.UP
		m.spread = 50.0 if falling else 75.0
		m.initial_velocity_min = 0.2 if falling else 0.5
		m.initial_velocity_max = 0.6 if falling else 1.2
		m.gravity = Vector3(0, -6.0, 0)
		m.scale_min = 0.6
		m.scale_max = 1.5
		m.color_ramp = _ramp(CRUMBS[k], Color(CRUMBS[k], 0.0))
		p.process_material = m
		add_child(p)
		p.global_position = pos
		p.emitting = true
		p.finished.connect(p.queue_free)


## A glint on the photo's glass: a star that pops and spins, little sparks around it (`size`: smaller
## for a close shot).
func sparkle(pos: Vector3, size := 1.0) -> void:
	if not is_inside_tree():
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos + Vector3(0.04, 0.05, 0.02) * size
	_burst(holder, "star_06", 8, 0.07 * size, STAR, 0.6 * size, 0.45, true, 0.4)
	var star := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.16 * size
	star.mesh = quad
	var mat := _sprite("star_07", true).duplicate() as StandardMaterial3D
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = Color(1.0, 0.95, 0.7)
	star.material_override = mat
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(star)
	star.scale = Vector3.ZERO
	var tween := star.create_tween()
	tween.tween_property(star, ^"scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(star, ^"rotation:z", 1.2, 0.5)
	tween.tween_property(star, ^"scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flash(holder.global_position, Color(1.0, 0.95, 0.75), 0.5 * size, 0.35, 0.25)
	get_tree().create_timer(1.0).timeout.connect(holder.queue_free)
