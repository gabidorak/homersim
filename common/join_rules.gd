class_name JoinRules
extends RefCounted
## Pure join-handshake rules (no nodes), so they can be unit-tested.

const MAX_NAME_LENGTH := 16
const DEFAULT_NAME := "Player"


## Whether a join is allowed: LeaveReason.Code.NONE, or why not (VERSION, FULL, PASSWORD_REQUIRED,
## WRONG_PASSWORD). The version comes first (an old client can't do anything else right), then the
## room, then the password (nobody types a password only to hear the server is full).
static func check(client_version: String, server_version: String, player_count: int, max_players: int,
		password: String = "", server_password: String = "") -> LeaveReason.Code:
	if client_version != server_version:
		return LeaveReason.Code.VERSION
	if player_count >= max_players:
		return LeaveReason.Code.FULL
	if server_password != "" and password != server_password:
		return LeaveReason.Code.PASSWORD_REQUIRED if password == "" else LeaveReason.Code.WRONG_PASSWORD
	return LeaveReason.Code.NONE


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
