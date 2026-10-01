class_name JoinRules
extends RefCounted
## Pure join-handshake rules (no nodes), so they can be unit-tested.

const MAX_NAME_LENGTH := 16
const DEFAULT_NAME := "Player"


## Returns "" if the join is allowed, otherwise a reason to show the player.
static func check(client_version: String, server_version: String, player_count: int, max_players: int) -> String:
	if client_version != server_version:
		return "Version mismatch: server is %s, you have %s" % [server_version, client_version]
	if player_count >= max_players:
		return "Server full"
	return ""


## Trims, drops control characters and BBCode brackets, collapses spaces, caps the length.
static func sanitize_name(raw: String) -> String:
	var kept := ""
	for c in raw:
		if c.unicode_at(0) >= 32 and c != "[" and c != "]":
			kept += c
	var words := kept.split(" ", false)
	var result := " ".join(words).substr(0, MAX_NAME_LENGTH).strip_edges()
	return result if not result.is_empty() else DEFAULT_NAME


## Appends " (2)", " (3)"… until the name is not in `taken` (case-insensitive).
static func unique_name(wanted: String, taken: Array[String]) -> String:
	var lower: Array[String] = []
	for t in taken:
		lower.append(t.to_lower())
	if not lower.has(wanted.to_lower()):
		return wanted
	var n := 2
	while lower.has(("%s (%d)" % [wanted, n]).to_lower()):
		n += 1
	return "%s (%d)" % [wanted, n]
