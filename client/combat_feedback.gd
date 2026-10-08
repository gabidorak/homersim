class_name CombatFeedback
extends Node3D
## Client-only cosmetics for PvP events: broom whoosh and BONK (stars, a puff, a camera shake for
## the two involved), bite chomp, a caged rat's spit (the glob flies with a trail, splats, covers the
## screen of the supervisor it hits, and leaves a puddle on the floor until the match ends, the oldest
## going first past MAX_PUDDLES), and the SNAP of a trap (only supervisors are sent that one). Also
## forwards short lines to the HUD banner through `banner`.

signal banner(text: String)

const MAX_PUDDLES := 40

@onready var session: Session = Session.current

var _splat_layer: CanvasLayer  # under the HUD
var _puddles: Array[Decal] = []  # oldest first


func _ready() -> void:
	session.abilities.broom_swung.connect(_on_broom)
	session.abilities.bitten.connect(_on_bite)
	session.abilities.spat.connect(_on_spit)
	_splat_layer = CanvasLayer.new()
	_splat_layer.name = "SpitSplats"
	_splat_layer.layer = 0
	add_child(_splat_layer)
	Events.match_state_changed.connect(func(state: int) -> void:
		if state == MatchManager.State.LOBBY:
			_clear_puddles())
	session.items.trap_snapped.connect(_on_snap)


func _on_broom(attacker: int, victim: int, stunned: bool) -> void:
	var a := session.get_body(attacker)
	if a != null:
		Sfx.play_at(self, "whoosh", a.global_position + Vector3.UP * 1.2, -6.0)
	var v := session.get_body(victim)
	if v != null and stunned:
		var hit := v.global_position + Vector3.UP * v.role_data.height * 0.8
		Sfx.play_at(self, "bonk", hit)
		Vfx.bonk(self, hit)
		if victim == session.local_peer_id:
			banner.emit(tr("BONK! You're stunned"))
			Vfx.shake(0.7)
		elif attacker == session.local_peer_id:
			Vfx.shake(0.35)


func _on_bite(attacker: int, victim: int, result: int) -> void:
	var v := session.get_body(victim)
	if v == null:
		return
	Sfx.play_at(self, "chomp", v.global_position + Vector3.UP * 1.0)
	Vfx.puff(self, v.global_position + Vector3.UP * 0.4, Color(1, 1, 1, 0.7), 5, 0.3)
	if victim == session.local_peer_id:
		Vfx.shake(0.3)
	if victim == session.local_peer_id and result == StatusRules.Bite.KNOCKED_DOWN:
		banner.emit(tr("The rats knocked you down!"))
	elif attacker == session.local_peer_id and result == StatusRules.Bite.KNOCKED_DOWN:
		banner.emit(tr("Knockdown!"))


func _on_spit(attacker: int, victim: int, aim: Vector3, stunned: bool) -> void:
	var a := session.get_body(attacker)
	if a == null:
		return
	var mouth := a.global_position + Vector3.UP * a.role_data.height * 0.6 + aim * 0.2
	var v := session.get_body(victim)
	var to := v.global_position + Vector3.UP * v.role_data.height * 0.85 if v != null \
		else _spit_landing(a, mouth, aim)
	Sfx.play_at(self, "spit", mouth)
	var flight := Vfx.spit(self, mouth, to)
	get_tree().create_timer(flight).timeout.connect(func() -> void:
		Sfx.play_at(self, "splat", to)
		_add_puddle(to - aim * 0.05)  # (a hair back from a wall it hit, so the ray down misses the wall)
		if victim != 0 and victim == session.local_peer_id:
			_splat_layer.add_child(SpitSplat.new())
			Vfx.shake(0.2)
			if stunned:
				banner.emit(tr("PTOOEY! Rat spit in the eye: you're stunned"))
		elif stunned and attacker == session.local_peer_id:
			banner.emit(tr("Bullseye! The supervisor is stunned")))


## A puddle on the floor under `pos` (on the supervisor's feet too: it drips off).
func _add_puddle(pos: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.DOWN * 4.0,
		PhysicsLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var puddle := Vfx.spit_puddle(self, hit["position"])
	if puddle == null:
		return
	_puddles.append(puddle)
	while _puddles.size() > MAX_PUDDLES:
		var oldest: Decal = _puddles.pop_front()
		if is_instance_valid(oldest):
			oldest.create_tween().tween_property(oldest, "scale", Vector3(0.01, 1.0, 0.01), 0.4)
			oldest.get_tree().create_timer(0.45).timeout.connect(oldest.queue_free)


func _clear_puddles() -> void:
	for puddle in _puddles:
		if is_instance_valid(puddle):
			puddle.queue_free()
	_puddles.clear()


## Where a spit that hit nobody lands: the first wall along `aim` (the bars don't count), or the
## floor at the end of its range.
func _spit_landing(rat: Player, mouth: Vector3, aim: Vector3) -> Vector3:
	var data := rat.role_data.ability(&"spit")
	var end := mouth + aim * (data.range if data != null else 5.0) + Vector3.DOWN * 0.4
	var ignore: Array[RID] = [rat.get_rid()]
	var cage := Cage.of_occupant(get_tree(), rat.peer_id)
	if cage != null:
		ignore.append(cage.bars.get_rid())
	var query := PhysicsRayQueryParameters3D.create(mouth, end, PhysicsLayers.WORLD, ignore)
	var hit := rat.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]
	query = PhysicsRayQueryParameters3D.create(end, end + Vector3.DOWN * 3.0, PhysicsLayers.WORLD, ignore)
	hit = rat.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else end


func _on_snap(pos: Vector3) -> void:
	Sfx.play(self, "snap", 4.0)  # loud for every supervisor, wherever they are
	Sfx.play_at(self, "snap", pos)
	Vfx.puff(self, pos + Vector3.UP * 0.1, Vfx.DUST, 10, 0.5)
	Vfx.sparks(self, pos + Vector3.UP * 0.1, 10, Color.WHITE)
	banner.emit(tr("SNAP! A trap caught a rat"))
