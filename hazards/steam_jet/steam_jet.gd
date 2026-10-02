class_name SteamJet
extends Hazard
## A broken pipe that blows steam along its +Z axis (pumps, valves; GDD §6): 3 s on, 3 s off.
## Whoever is in the cone when it blows gets knocked back 6 m/s (plus a little lift) and stunned 1 s.
## Neighbouring jets get different `phase`s so they take turns. A short puff warns before each blast.

const NOZZLE_HEIGHT := 0.6  ## m above the floor
const NEAR_HALF := Vector2(0.25, 0.25)  ## half width / height of the cone at the nozzle
const WARN_S := 0.6  ## the puff before a blast

var _particles: GPUParticles3D
var _nozzle := Vector3.ZERO
var _hiss: AudioStreamPlayer3D
var _was_live := false
var _warned := false


func _init() -> void:
	size = Vector3(1.8, 1.6, 4.0)  # far width, far height, length


func _configure() -> void:
	on_s = tuning.steam_on_s
	off_s = tuning.steam_off_s


## A frustum from the nozzle (small) to `size` at the far end, along +Z.
func _make_shape() -> CollisionShape3D:
	var far := Vector2(size.x, size.y) * 0.5
	var points := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			points.append(Vector3(sx * NEAR_HALF.x, NOZZLE_HEIGHT + sy * NEAR_HALF.y, 0.0))
			points.append(Vector3(sx * far.x, maxf(NOZZLE_HEIGHT + sy * far.y, 0.0), size.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var node := CollisionShape3D.new()
	node.shape = shape
	return node


func _affect(player: Player) -> void:
	var impulse := HazardRules.knockback(global_basis.z, global_position, player.global_position,
		tuning.steam_knockback, tuning.steam_lift)
	player.server_apply_impulse(impulse)
	player.status.apply(StatusComponent.Status.STUNNED, tuning.steam_stun_s)


func hit_text() -> String:
	return "PSSSHHT! Steamed!"


func _build_look() -> void:
	# A burst pipe stub on the wall (a short green pipe with a flange, red-hot at the break).
	_nozzle = Vector3(0, NOZZLE_HEIGHT, 0.25)
	var stub := Art.add(self, "pipe_2m", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.6, 0.6, 0.25)),
		Vector3(0, NOZZLE_HEIGHT, 0.0)))
	if stub != null:
		Art.set_tint(stub, Color(1.0, 0.75, 0.65))
	_particles = Vfx.steam(Vector3(0, 0, 1), size.z)
	_particles.position = _nozzle
	add_child(_particles)
	_hiss = Sfx.loop_player(self, "hiss", -4.0)
	_hiss.position = _nozzle


func _update_look(live: bool, _delta: float) -> void:
	if live != _was_live:
		_was_live = live
		_particles.emitting = live
		if live:
			_hiss.play()
		else:
			_hiss.stop()
	# The warning puff, once per off phase.
	var soon := active and not live and HazardRules.time_to_switch(elapsed(Net.server_time()), on_s, off_s, phase) < WARN_S
	if soon and not _warned:
		Sfx.play_at(self, "puff", _particles.global_position, -6.0)
		Vfx.puff(self, _particles.global_position, Vfx.STEAM, 6, 0.4)
	_warned = soon
