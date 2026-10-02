class_name ElectricPuddle
extends Hazard
## A pool of water on the floor (power grid; GDD §6) that goes live for 2 s every 5 s:
## whoever stands in it is stunned 1.5 s, then slowed to 50% for 2 s. Sparks and a blue glow when
## live, a flicker just before.

const FLICKER_S := 0.4

var _water: MeshInstance3D
var _mat := StandardMaterial3D.new()
var _light: OmniLight3D
var _arcs: GPUParticles3D
var _buzz: AudioStreamPlayer3D
var _spark_in := 0.0
var _was_live := false


func _init() -> void:
	size = Vector3(3.0, 0.5, 3.0)


func _configure() -> void:
	on_s = tuning.puddle_live_s
	off_s = maxf(tuning.puddle_period_s - tuning.puddle_live_s, 0.0)


func _affect(player: Player) -> void:
	player.status.apply(StatusComponent.Status.STUNNED, tuning.puddle_stun_s)
	# The slow runs through the stun and on for puddle_slow_s after it.
	player.status.set_speed_factor(&"puddle", tuning.puddle_slow, tuning.puddle_stun_s + tuning.puddle_slow_s)


func hit_text() -> String:
	return "BZZZT! Zapped!"


func _build_look() -> void:
	_water = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(size.x, size.z)
	_water.mesh = quad
	_water.position.y = 0.03
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.metallic = 0.6
	_mat.roughness = 0.05
	_mat.emission_enabled = true
	_water.material_override = _mat
	add_child(_water)
	_light = OmniLight3D.new()
	_light.position.y = 0.6
	_light.omni_range = maxf(size.x, size.z) * 1.2
	_light.light_color = Color(0.35, 0.65, 1.0)
	_light.light_energy = 2.5
	_light.visible = false
	add_child(_light)
	_arcs = Vfx.arcs(Vector2(size.x, size.z))
	_arcs.position.y = 0.05
	add_child(_arcs)
	_buzz = Sfx.loop_player(self, "buzz")
	_buzz.position.y = 0.2


func _update_look(live: bool, delta: float) -> void:
	var t := Net.server_time()
	var soon := active and not live and HazardRules.time_to_switch(elapsed(t), on_s, off_s, phase) < FLICKER_S
	var glow := live or (soon and fmod(t, 0.12) < 0.05)
	_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.85) if glow else Color(0.15, 0.22, 0.3, 0.75)
	_mat.emission = Color(0.3, 0.6, 1.0) if glow else Color.BLACK
	_mat.emission_energy_multiplier = 2.0 if glow else 0.0
	_light.visible = glow
	if live != _was_live:
		_was_live = live
		_arcs.emitting = live
		if live:
			Sfx.play_at(self, "zap", global_position + Vector3.UP * 0.3)
			_buzz.play()
		else:
			_buzz.stop()
	if live:  # sparks jump off the water now and then
		_spark_in -= delta
		if _spark_in <= 0.0:
			_spark_in = randf_range(0.15, 0.4)
			var at := global_position + Vector3(randf_range(-0.5, 0.5) * size.x, 0.05, randf_range(-0.5, 0.5) * size.z)
			Vfx.sparks(self, at, 6, Vfx.ARC)
