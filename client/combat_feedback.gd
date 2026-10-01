class_name CombatFeedback
extends Node3D
## Client-only cosmetics for PvP events (placeholders until M7): broom whoosh and BONK, bite
## chomp, and the SNAP of a trap (only supervisors are sent that one). Also forwards short lines
## to the HUD banner through `banner`.

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
		Sfx.play_at(self, "bonk", v.global_position + Vector3.UP * 0.3)
		if victim == session.local_peer_id:
			banner.emit("BONK! You're stunned")


func _on_bite(attacker: int, victim: int, result: int) -> void:
	var v := session.get_body(victim)
	if v == null:
		return
	Sfx.play_at(self, "chomp", v.global_position + Vector3.UP * 1.0)
	if victim == session.local_peer_id and result == StatusRules.Bite.KNOCKED_DOWN:
		banner.emit("The rats knocked you down!")
	elif attacker == session.local_peer_id and result == StatusRules.Bite.KNOCKED_DOWN:
		banner.emit("Knockdown!")


func _on_snap(pos: Vector3) -> void:
	Sfx.play(self, "snap", 4.0)  # loud for every supervisor, wherever they are
	Sfx.play_at(self, "snap", pos)
	banner.emit("SNAP! A trap caught a rat")
