class_name DebrisZone
extends Hazard
## Falling bolts and panels in the Turbine Hall (turbine; GDD §6). While active, every 8 s the
## server picks a random spot inside `size` (on whatever floor is there: the ground or a catwalk)
## and tells every client (on_debris_warning): a red warning circle shows for 1 s, then the debris
## lands. At impact, supervisors within 1.5 m are knocked down, rats stunned for 2 s.
## The impact time travels on the server clock, so every client drops it at the same moment.

const FIRST_DROP_S := 2.0  ## after switching on
const FALL_S := 0.45  ## the last part of the warning, the debris visibly falls
const DROP_HEIGHT := 6.0  ## m above the impact point

var _rng := RandomNumberGenerator.new()
var _next_drop := 0.0  # server clock
var _pending: Array[Dictionary] = []  # server: {"pos", "at"} impacts still to resolve
var _drops: Array[Dictionary] = []  # client: {"pos", "at", "decal", "piece", "dust", "whistled"}
## What falls from the turbine hall's ceiling (goofy junk, picked at random).
const PIECES: Array[String] = ["pipe_2m", "toolbox", "k_box_small", "traffic_cone", "wall_clock", "k_bucket"]


func _init() -> void:
	size = Vector3(30.0, 8.0, 14.0)


func _checks_overlaps() -> bool:
	return false


func _make_shape() -> CollisionShape3D:
	return null  # the impacts are checked by distance, not overlap


func _ready() -> void:
	super()
	_rng.randomize()
	# Clients keep the list of incoming drops even headless (test bots read it); only the visuals
	# are skipped there.
	set_process(not Net.is_server)


func _on_switched(value: bool) -> void:
	_pending.clear()
	if value:
		_next_drop = Net.server_time() + FIRST_DROP_S


func _server_tick(_delta: float) -> void:
	var now := Net.server_time()
	if now >= _next_drop:
		_next_drop = now + tuning.debris_interval_s
		var pos := _random_spot()
		var at := now + tuning.debris_warning_s
		_pending.append({"pos": pos, "at": at})
		on_debris_warning.rpc(pos, at)
	while not _pending.is_empty() and now >= float(_pending[0]["at"]):
		_impact(_pending.pop_front()["pos"])


## A random floor spot inside the zone (the highest floor under a random point).
func _random_spot() -> Vector3:
	var local := Vector3(_rng.randf_range(-0.5, 0.5) * size.x, size.y, _rng.randf_range(-0.5, 0.5) * size.z)
	var top := to_global(local)
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (size.y + 1.0), PhysicsLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else to_global(Vector3(local.x, 0.0, local.z))


func _impact(pos: Vector3) -> void:
	for node in Session.current.players_root.get_children():
		var player := node as Player
		if not can_hit(player):
			continue
		var offset := player.global_position - pos
		if Vector2(offset.x, offset.z).length() <= tuning.debris_radius and absf(offset.y) < 1.5:
			_hit(player)


func _affect(player: Player) -> void:
	if player.role == Role.Kind.SUPERVISOR:
		player.status.apply(StatusComponent.Status.KNOCKED_DOWN, tuning.debris_knockdown_s)
	else:
		player.status.apply(StatusComponent.Status.STUNNED, tuning.debris_stun_s)


func hit_text() -> String:
	return "CLANG! Something fell on you"


## Server → clients: debris will land at `pos` at server-clock time `at`.
@rpc("authority", "call_remote", "reliable")
func on_debris_warning(pos: Vector3, at: float) -> void:
	if _headless:
		_drops.append({"pos": pos, "at": at, "decal": null, "piece": null, "whistled": true})
		return
	var decal := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = tuning.debris_radius
	ring.bottom_radius = tuning.debris_radius
	ring.height = 0.02
	decal.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.15, 0.1, 0.5)
	decal.material_override = mat
	add_child(decal)
	decal.global_position = pos + Vector3.UP * 0.04
	var piece := Art.add(self, PIECES[randi() % PIECES.size()])
	if piece == null:
		piece = Node3D.new()
		add_child(piece)
	piece.visible = false
	var dust := Vfx.dust_fall(Vector3(tuning.debris_radius, 0.2, tuning.debris_radius))
	add_child(dust)
	dust.global_position = pos + Vector3.UP * DROP_HEIGHT
	dust.emitting = true
	_drops.append({"pos": pos, "at": at, "decal": decal, "piece": piece, "dust": dust, "whistled": false})


func _update_look(_live: bool, _delta: float) -> void:
	var now := Net.server_time()
	for i in range(_drops.size() - 1, -1, -1):
		var drop := _drops[i]
		var left := float(drop["at"]) - now
		if _headless:
			if left <= 0.0:
				_drops.remove_at(i)
			continue
		var decal: MeshInstance3D = drop["decal"]
		var piece: Node3D = drop["piece"]
		var pos: Vector3 = drop["pos"]
		if left <= 0.0:
			Sfx.play_at(self, "crash", pos + Vector3.UP * 0.3)
			Vfx.puff(self, pos + Vector3.UP * 0.1, Vfx.DUST, 14, 0.8)
			var me := Session.current.get_body(Session.current.local_peer_id)
			if me != null and me.global_position.distance_to(pos) < 8.0:
				Vfx.shake(0.6 * (1.0 - me.global_position.distance_to(pos) / 8.0))
			decal.queue_free()
			(drop["dust"] as Node).queue_free()
			# The piece lies there a moment, then goes.
			piece.global_position = pos + Vector3.UP * 0.06
			piece.visible = true
			get_tree().create_timer(2.0).timeout.connect(piece.queue_free)
			_drops.remove_at(i)
			continue
		decal.scale = Vector3.ONE * (1.0 + 0.1 * sin(now * 20.0))
		if left <= FALL_S:
			if not drop["whistled"]:
				drop["whistled"] = true
				Sfx.play_at(self, "whistle", pos + Vector3.UP * 3.0, -6.0)
			piece.visible = true
			piece.global_position = pos + Vector3.UP * (0.06 + DROP_HEIGHT * pow(left / FALL_S, 2.0))
			piece.rotation.y += 0.3
