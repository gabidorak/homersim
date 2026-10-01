class_name RateLimiter
extends RefCounted
## Server: at most `max_per_s` requests per peer per wall-clock second (ARCHITECTURE §12).

var max_per_s := 20
var _counts: Dictionary[int, Vector2i] = {}  # peer → (second, requests in that second)


func _init(p_max_per_s: int = 20) -> void:
	max_per_s = p_max_per_s


func allow(peer: int) -> bool:
	var second := floori(Time.get_ticks_msec() / 1000.0)
	var entry: Vector2i = _counts.get(peer, Vector2i(second, 0))
	if entry.x != second:
		entry = Vector2i(second, 0)
	entry.y += 1
	_counts[peer] = entry
	return entry.y <= max_per_s


func forget(peer: int) -> void:
	_counts.erase(peer)
