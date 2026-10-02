class_name CombatFeedback
extends Node3D
## Client-only cosmetics for PvP events: broom whoosh and BONK (stars, a puff, a camera shake for
## the two involved), bite chomp, and the SNAP of a trap (only supervisors are sent that one). Also
## forwards short lines to the HUD banner through `banner`.

signal banner(text: String)

@onready var session: Session = Session.current


func _ready() -> void:
	session.abilities.broom_swung.connect(_on_broom)
	session.abilities.bitten.connect(_on_bite)
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


func _on_snap(pos: Vector3) -> void:
	Sfx.play(self, "snap", 4.0)  # loud for every supervisor, wherever they are
	Sfx.play_at(self, "snap", pos)
	Vfx.puff(self, pos + Vector3.UP * 0.1, Vfx.DUST, 10, 0.5)
	Vfx.sparks(self, pos + Vector3.UP * 0.1, 10, Color.WHITE)
	banner.emit(tr("SNAP! A trap caught a rat"))
