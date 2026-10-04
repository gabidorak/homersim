class_name RadiationZone
extends Hazard
## A glowing zone around the reactor pool (control rods; GDD §6). Exposure builds while inside
## (and drains as fast outside); once it reaches 5 s the body is slowed to 80% while inside and
## REVEALED (outlined for the enemy team) while inside and for 5 s after leaving.
## Geiger clicks for the local player speed up with its exposure (a local estimate: clients
## don't check overlaps, so it tests the zone's box against our position).

const MAX_CLICKS_PER_S := 18.0
const FLOOR_GAP := 0.03

var _exposure: Dictionary[int, float] = {}  # server: peer → seconds
var _local_exposure := 0.0  # client estimate, for the clicks
var _click_debt := 0.0
var _mat := StandardMaterial3D.new()
var _glow: MeshInstance3D
var _light: OmniLight3D
var _motes: GPUParticles3D


func _init() -> void:
	size = Vector3(10.0, 4.0, 10.0)


func _configure() -> void:
	on_s = 1.0
	off_s = 0.0  # always live while active


func _on_switched(_value: bool) -> void:
	_exposure.clear()


## The exposure model runs for every body, inside or not (exposure drains outside).
func _server_tick(delta: float) -> void:
	if not is_live(Net.server_time()):
		return
	var max_s := tuning.radiation_exposure_s
	for node in Session.current.players_root.get_children():
		var player := node as Player
		if not can_hit(player):
			_exposure.erase(player.peer_id if player != null else 0)
			continue
		var inside := overlaps_body(player)
		var before: float = _exposure.get(player.peer_id, 0.0)
		var now_exposure := HazardRules.exposure_step(before, inside, delta, max_s)
		_exposure[player.peer_id] = now_exposure
		if inside and now_exposure >= max_s:
			if before < max_s:
				_hit(player)  # the moment it starts to bite (log, stat, banner)
			else:
				_affect(player)


func _affect(player: Player) -> void:
	player.status.set_speed_factor(&"radiation", tuning.radiation_slow, 0.3)
	player.status.apply(StatusComponent.Status.REVEALED, tuning.radiation_reveal_after_s)


func hit_text() -> String:
	return "You're glowing! (slowed, visible through walls)"


func _build_look() -> void:
	_glow = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size - Vector3.UP * FLOOR_GAP  # the bottom face just off the floor, or they z-fight
	_glow.mesh = box
	_glow.position.y = (size.y + FLOOR_GAP) * 0.5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(0.45, 1.0, 0.2, 0.12)
	_glow.material_override = _mat
	_glow.visible = false
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.position.y = 1.5
	_light.omni_range = maxf(size.x, size.z)
	_light.light_color = Color(0.5, 1.0, 0.25)
	_light.light_energy = 2.0
	_light.visible = false
	add_child(_light)
	_motes = Vfx.motes(size, Vfx.RAD_GREEN, 60)
	_motes.position.y = size.y * 0.5
	add_child(_motes)


func _update_look(live: bool, delta: float) -> void:
	_glow.visible = live
	_light.visible = live
	_motes.emitting = live
	if live:
		var pulse := 0.5 + 0.5 * sin(Net.server_time() * 2.5)
		_mat.albedo_color.a = 0.08 + 0.08 * pulse
		_light.light_energy = 1.5 + pulse
	var body := Session.current.get_body(Session.current.local_peer_id) if Session.current else null
	var inside := live and body != null and _contains(body.global_position + Vector3.UP * 0.2)
	_local_exposure = HazardRules.exposure_step(_local_exposure, inside, delta, tuning.radiation_exposure_s)
	if _local_exposure <= 0.0 or body == null:
		return
	# Clicks speed up with exposure, at random intervals like a real counter.
	_click_debt += delta * MAX_CLICKS_PER_S * (_local_exposure / tuning.radiation_exposure_s)
	while _click_debt >= 1.0:
		_click_debt -= randf_range(0.5, 1.5)
		Sfx.play_at(self, "click", body.global_position + Vector3.UP, -8.0)


func _contains(world_pos: Vector3) -> bool:
	var local := to_local(world_pos)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 and local.y >= 0.0 and local.y <= size.y
