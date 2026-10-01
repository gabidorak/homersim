class_name Role
extends RefCounted
## Player roles. NONE doubles as "no preference" (Any) in the lobby and as the lobby body's role.

enum Kind { NONE, SUPERVISOR, RAT, SPECTATOR }

const _DATA_PATHS := {
	Kind.NONE: "res://data/roles/lobby.tres",
	Kind.SUPERVISOR: "res://data/roles/supervisor.tres",
	Kind.RAT: "res://data/roles/rat.tres",
}

static var _cache: Dictionary[int, RoleData] = {}


## The stats of a role that has a body (NONE = lobby body). Null for SPECTATOR.
## Loaded lazily (not preloaded) to avoid a Role → .tres → RoleData → Role preload cycle.
static func data(kind: Kind) -> RoleData:
	if not _cache.has(kind):
		if not _DATA_PATHS.has(kind):
			return null
		_cache[kind] = load(_DATA_PATHS[kind])
	return _cache[kind]


static func display_name(kind: Kind) -> String:
	match kind:
		Kind.SUPERVISOR:
			return "Supervisor"
		Kind.RAT:
			return "Rat"
		Kind.SPECTATOR:
			return "Spectator"
	return "Lobby"


## How a lobby preference reads: NONE means "Any".
static func pref_name(kind: Kind) -> String:
	return "Any" if kind == Kind.NONE else display_name(kind)


## Parses "rat", "supervisor", "any" (used by test CLI args). Unknown text gives NONE.
static func from_text(text: String) -> Kind:
	match text.to_lower():
		"supervisor", "sup":
			return Kind.SUPERVISOR
		"rat":
			return Kind.RAT
	return Kind.NONE
