class_name TowerSteam
extends Marker3D
## The cooling tower's steam, placed at the top of its mouth: cartoon puffs like the outro's
## (OutroFx.towers), toon balls with the ink outline that swell out of the mouth, rise, drift with
## the wind and fade. It tells how the plant is doing, from the yard and through the cameras: slow,
## calm puffs while the core is cool; quicker, fatter, throbbing ones as it heats up; tinged
## goo-green as the meltdown meter fills (a hint of the cough to come, the RATS ending); and when the
## emergency coolant goes in, one big blue-white sigh of relief. Out of a match (and in the menu's
## diorama, with no session) it puffs calmly. Clients only: the headless server builds nothing.
##
## Everything a puff does comes from a phase that the heat speeds up (puff(), sigh_puff()), so a
## change of pace never makes one jump; the tests check the shapes (test_tower_steam.gd), and
## tests/helpers/TowerSteamShots.tscn shows them.

const TOON: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE: Material = preload("res://shaders/materials/outline.tres")
const PUFFS := 10
const SIGH_BALLS := 10
const SIGH_LIFE := 2.4  ## s
const CALM_PERIOD := 4.2  ## s a puff lives while the core is cool (the outro's calm puffs)
const HOT_PERIOD := 1.4  ## s at full heat: the tower chugs
const STEAM := Color(1.0, 0.99, 0.97)
const GOO := Color(0.61, 1.0, 0.18)  ## the palette's rad_green, like the outro's cough
const GOO_MAX := 0.7  ## how green a full meter gets (the cough itself is all green)
const COLD := Color(0.78, 0.92, 1.0)  ## the coolant's sigh
## The core falling this share of the coolant's amount in one update: the coolant just went in.
const COOLANT_DROP := 0.5
const EASE := 0.8  ## 1/s: how fast the plume follows the plant, so a jump in heat never pops

@export var wind := Vector3(-0.3, 0.0, -1.0)  ## where the plume drifts (any length)

var manual := false  ## tests: target_heat and target_goo are set by hand, not read from the plant
var target_heat := 0.0  ## 0..1 (heat_for)
var target_goo := 0.0  ## 0..1, the meltdown meter
var heat := 0.0  ## what the plume shows, easing towards target_heat
var goo := 0.0

var _phase := 0.0
var _sigh_age := INF
var _last_temp := NAN
var _puffs: Array[MeshInstance3D] = []
var _sigh: Array[MeshInstance3D] = []
var _puff_mat: ShaderMaterial
var _shown_goo := -1.0


func _ready() -> void:
	if Art.headless():
		set_process(false)
		return
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 16
	ball.rings = 8
	_puff_mat = _material(STEAM, Color(0.55, 0.62, 0.8), 0.22)
	var sigh_mat := _material(COLD, COLD, 0.45)
	for i in PUFFS + SIGH_BALLS:
		var mesh := MeshInstance3D.new()
		mesh.mesh = ball
		mesh.material_override = _puff_mat if i < PUFFS else sigh_mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)
		(_puffs if i < PUFFS else _sigh).append(mesh)
	_phase = randf()  # two towers side by side don't puff in step


func _process(delta: float) -> void:
	if not manual:
		_follow_plant()
	var weight := 1.0 - exp(-EASE * delta)
	heat = lerpf(heat, target_heat, weight)
	goo = lerpf(goo, target_goo, weight)
	_phase += delta / period(heat)
	_sigh_age += delta
	var dir := wind.normalized()
	for i in PUFFS:
		var p := puff(i, _phase, heat, dir)
		_puffs[i].position = p[0]
		_puffs[i].scale = Vector3.ONE * maxf(p[1], 0.001)
		_puffs[i].visible = p[1] > 0.01
	for i in SIGH_BALLS:
		var p := sigh_puff(i, _sigh_age, dir)
		_sigh[i].position = p[0]
		_sigh[i].scale = Vector3.ONE * maxf(p[1], 0.001)
		_sigh[i].visible = p[1] > 0.01
	if absf(goo - _shown_goo) > 0.01:
		_shown_goo = goo
		var g := goo_tint(goo)
		_puff_mat.set_shader_parameter(&"albedo", STEAM.lerp(GOO, g))
		_puff_mat.set_shader_parameter(&"emission", Color(0.55, 0.62, 0.8).lerp(GOO, g))
		_puff_mat.set_shader_parameter(&"emission_energy", 0.22 + 0.5 * g)


## The coolant's sigh of relief: a ring of cold puffs bursting out of the mouth and rolling away.
func sigh() -> void:
	_sigh_age = 0.0


func _follow_plant() -> void:
	var session := Session.current
	var playing := is_instance_valid(session) and session.match_manager != null \
		and session.match_manager.state == MatchManager.State.PLAYING
	if not playing:
		target_heat = 0.0
		target_goo = 0.0
		_last_temp = NAN
		return
	var plant := session.plant
	if not is_nan(_last_temp) and is_coolant(_last_temp, plant.core_temp, plant.tuning):
		sigh()
	_last_temp = plant.core_temp
	target_heat = heat_for(plant.core_temp, plant.tuning)
	target_goo = plant.meltdown / 100.0


func _material(albedo: Color, emission: Color, energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter(&"albedo", albedo)
	mat.set_shader_parameter(&"emission", emission)
	mat.set_shader_parameter(&"emission_energy", energy)
	mat.next_pass = OUTLINE
	return mat


## How hot the plume looks for a core at `temp`: 0 at nominal, 0.8 at the critical alarm, 1 a little
## past it (the tower can't chug any harder).
static func heat_for(temp: float, tuning: PlantTuning) -> float:
	return clampf(remap(temp, tuning.nominal_temp, tuning.critical_temp, 0.0, 0.8), 0.0, 1.0)


## True if the core falling from `before` to `after` in one update is the emergency coolant.
static func is_coolant(before: float, after: float, tuning: PlantTuning) -> bool:
	return before - after >= tuning.coolant_amount * COOLANT_DROP


## Seconds a puff lives at `heat`.
static func period(p_heat: float) -> float:
	return lerpf(CALM_PERIOD, HOT_PERIOD, clampf(p_heat, 0.0, 1.0))


## How green the steam is for a meltdown meter at `p_goo` (0..1): none for the first fifth, then
## more and more, up to GOO_MAX.
static func goo_tint(p_goo: float) -> float:
	return GOO_MAX * smoothstep(0.2, 1.0, p_goo)


## Puff `i` at `phase` (one cycle per period) and `p_heat`: [offset from the mouth, size (m across)].
## It swells out of the mouth, rises, drifts down `dir` (normalised) and fades away at the end of its
## life, so it's nothing both when it starts and when it ends. Hotter: fatter, pushed up higher,
## bent over less, and throbbing.
static func puff(i: int, phase: float, p_heat: float, dir: Vector3) -> Array:
	var age := fposmod(phase + float(i) / PUFFS, 1.0)
	var size := (3.5 + 5.0 * sqrt(age)) * (1.0 + 0.4 * p_heat)
	size *= smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.7, 1.0, age))
	size *= 1.0 + 0.12 * p_heat * sin(TAU * 3.0 * age)
	# A long trail, mostly sideways: from the yard, right under the tower, a plume that mostly rose
	# would be seen from below, its puffs piled into one blob.
	var side := dir.cross(Vector3.UP) * 2.0 * sin(i * 1.7)
	var rise := 1.5 + (13.0 + 8.0 * p_heat) * sqrt(age)
	var drift := (30.0 - 8.0 * p_heat) * age * (1.0 + 0.15 * sin(i * 2.1))
	return [Vector3.UP * rise + dir * drift + side * age, size]


## The sigh's ball `i`, `s` seconds after the coolant went in: [offset from the mouth, size].
## A quick, round burst out of the mouth that rolls up and away down `dir`, and fades.
static func sigh_puff(i: int, s: float, dir: Vector3) -> Array:
	var delay := 0.05 * (i % 3)
	var u := (s - delay) / SIGH_LIFE
	if u <= 0.0 or u >= 1.0:
		return [Vector3.ZERO, 0.0]
	var a := TAU * i / SIGH_BALLS
	var ring := Vector3(cos(a), 0.0, sin(a)) * 5.0
	var burst := smoothstep(0.0, 0.08, u)
	var at := ring * (0.5 + 1.2 * sqrt(u)) + Vector3.UP * (2.0 + 6.0 * absf(sin(a * 1.3)) * u + 10.0 * u) + dir * 10.0 * u
	return [at, (8.0 + 4.0 * absf(sin(i * 2.3))) * burst * (1.0 - smoothstep(0.5, 1.0, u)) * (1.0 + 0.6 * u)]
