class_name AiBlackboard
extends RefCounted
## One team's shared memory (M10, ARCHITECTURE §6 AI bots). AiDirector keeps one per team for a
## match. Pure: every time is passed in, so GUT can test it (tests/unit/test_ai_blackboard.gd).
##   claims      one bot per job: "repair:<sub>", "sabotage:<sub>", "lever:<sub>:A|B",
##               "free:<cage>", "chase:<rat>", "camera:<n>", "cctv_chair", "steal:<sup>",
##               "trap_spot:<cell>". A claim lapses after its TTL unless its bot renews it, and
##               goes when its bot is removed (release_all).
##   lever pairs one per critical subsystem: the first bot opens it (side A), the next joins
##               (side B). Human rats need no entry: a lever a human holds alone is a standing
##               request the goal sees on the lever itself.
##   gang        the supervisor the team's rats bite together, until gang_until
##   sightings   enemy peer → where a teammate bot last saw it; AiSenses picks them up after
##               share_delay_s, like a callout
##   events      sounds the team heard: {"kind", "pos", "at", "peer"} (SNAPs, bites…)

const EVENT_KEEP_S := 15.0

var claims: Dictionary = {}  ## key -> {"owner": int, "until": float}
var pairs: Dictionary = {}  ## subsystem -> {"A": int, "B": int, "opened": float}
var sightings: Dictionary = {}  ## enemy peer -> {"pos": Vector3, "at": float, "by": int}
var events: Array[Dictionary] = []
var gang_target := 0
var gang_until := 0.0
var visited: Dictionary = {}  ## supervisors' patrol: subsystem -> when a bot last looked at it


func clear() -> void:
	claims.clear()
	pairs.clear()
	sightings.clear()
	events.clear()
	visited.clear()
	gang_target = 0


# --- Claims ----------------------------------------------------------------------------------

## Takes (or renews) `key` for `owner` until now + ttl. False if another bot holds it.
func claim(key: String, owner: int, now: float, ttl: float) -> bool:
	if claimed_by_other(key, owner, now):
		return false
	claims[key] = {"owner": owner, "until": now + ttl}
	return true


## Who holds `key` now (0 = nobody: never claimed, released or lapsed).
func owner_of(key: String, now: float) -> int:
	var c: Dictionary = claims.get(key, {})
	return c.get("owner", 0) if not c.is_empty() and now < float(c["until"]) else 0


func claimed_by_other(key: String, owner: int, now: float) -> bool:
	var holder := owner_of(key, now)
	return holder != 0 and holder != owner


func release(key: String, owner: int) -> void:
	if claims.has(key) and claims[key]["owner"] == owner:
		claims.erase(key)


## Everything `owner` held: its claims and its lever sides (a bot left the match).
func release_all(owner: int) -> void:
	for key: String in claims.keys():
		if claims[key]["owner"] == owner:
			claims.erase(key)
	for sub: StringName in pairs.keys():
		lever_leave(sub, owner)
	if gang_target == owner:
		gang_target = 0


# --- Lever pairs ------------------------------------------------------------------------------

## `peer` takes a side of `sub`'s lever pair: "A" when it opens the pair, "B" when it joins one
## that is waiting (or the side it already has). "" if both sides are taken. A pair whose opener
## has waited `stale_s` with nobody joining is dropped first.
func lever_join(sub: StringName, peer: int, now: float, stale_s: float) -> String:
	var side := lever_side(sub, peer)
	if side != "":
		return side
	var pair: Dictionary = pairs.get(sub, {})
	if not pair.is_empty() and (pair["A"] == 0 or pair["B"] == 0) and now - float(pair["opened"]) > stale_s:
		pairs.erase(sub)
		pair = {}
	if pair.is_empty():
		pairs[sub] = {"A": peer, "B": 0, "opened": now}
		return "A"
	for s: String in ["A", "B"]:
		if pair[s] == 0:
			pair[s] = peer
			return s
	return ""


## `peer` takes `side` ("A" or "B") of `sub`'s pair if it is free (opening the pair if needed; a
## stale pair is dropped first, as in lever_join). False if another bot has that side.
func lever_take(sub: StringName, peer: int, side: String, now: float, stale_s: float) -> bool:
	var mine := lever_side(sub, peer)
	if mine == side:
		return true
	var pair: Dictionary = pairs.get(sub, {})
	if not pair.is_empty() and (pair["A"] == 0 or pair["B"] == 0) and now - float(pair["opened"]) > stale_s \
			and mine == "":
		pairs.erase(sub)
		pair = {}
	if pair.is_empty():
		pairs[sub] = {"A": 0, "B": 0, "opened": now}
		pair = pairs[sub]
	if pair[side] != 0:
		return false
	if mine != "":
		pair[mine] = 0
	pair[side] = peer
	return true


func lever_side(sub: StringName, peer: int) -> String:
	var pair: Dictionary = pairs.get(sub, {})
	for s: String in ["A", "B"]:
		if not pair.is_empty() and pair[s] == peer:
			return s
	return ""


## The bot on the other side of `peer`'s pair (0 = nobody yet).
func lever_partner(sub: StringName, peer: int) -> int:
	var side := lever_side(sub, peer)
	if side == "":
		return 0
	return pairs[sub]["B" if side == "A" else "A"]


## The side a pair of `sub` is waiting for ("" when there is no pair, or it is full).
func lever_waiting_side(sub: StringName) -> String:
	var pair: Dictionary = pairs.get(sub, {})
	if pair.is_empty():
		return ""
	if pair["A"] != 0 and pair["B"] == 0:
		return "B"
	if pair["B"] != 0 and pair["A"] == 0:
		return "A"
	return ""


func lever_leave(sub: StringName, peer: int) -> void:
	var pair: Dictionary = pairs.get(sub, {})
	if pair.is_empty():
		return
	for s: String in ["A", "B"]:
		if pair[s] == peer:
			pair[s] = 0
	if pair["A"] == 0 and pair["B"] == 0:
		pairs.erase(sub)


# --- Sightings and events -------------------------------------------------------------------------

func report_sighting(enemy: int, pos: Vector3, now: float, by: int) -> void:
	sightings[enemy] = {"pos": pos, "at": now, "by": by}


func add_event(kind: String, pos: Vector3, now: float, peer: int = 0) -> void:
	events.append({"kind": kind, "pos": pos, "at": now, "peer": peer})
	while not events.is_empty() and now - float(events[0]["at"]) > EVENT_KEEP_S:
		events.pop_front()
