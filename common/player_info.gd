class_name PlayerInfo
extends RefCounted
## What the session knows about a joined player. Sent over the network as a Dictionary
## (RPCs can't carry objects), see to_dict()/from_dict().

var peer_id: int
var name: String


func _init(p_peer_id: int = 0, p_name: String = "") -> void:
	peer_id = p_peer_id
	name = p_name


func to_dict() -> Dictionary:
	return {"peer_id": peer_id, "name": name}


static func from_dict(d: Dictionary) -> PlayerInfo:
	return PlayerInfo.new(int(d.get("peer_id", 0)), str(d.get("name", "")))
