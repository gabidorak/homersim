class_name AiHazards
extends RefCounted
## The plant's hazards as the AI bots see them (M10 phase E, GDD §6). Players see every hazard (the
## steam, the sparks on a puddle, the radiation glow, the debris warning circle), so bots may read
## them. AiDriver uses this for every goal:
##   cyclic     steam jets and electrified puddles: a moving bot waits at the edge of one that is live,
##              or goes live before it could get through (BotTuning.hazard_cross_s), and never starts a
##              hold inside one that is live or about to be
##   debris     a pending impact (the warning circle) near the bot: it steps away
##   radiation  exposure builds inside the active zone: a bot that isn't just passing through leaves
##              before it glows (BotTuning.radiation_limit_s)
## Hazard clocks are on Net.server_time() (synced cooldowns), never the AI's own clock.
## The pure checks (inside, should_wait) are unit tested in tests/unit/test_ai_hazards.gd.

enum Shape { BOX, JET }

const Y_BELOW := 0.5  ## m: a body's feet this far under a hazard's box still count as inside

var tuning := HazardTuning.load_default()
var cyclic: Array[Hazard] = []
var debris: Array[DebrisZone] = []
var radiation: Array[RadiationZone] = []


func collect(level: Node3D) -> void:
	for node in level.get_tree().get_nodes_in_group(Hazard.ALL_GROUP):
		if not level.is_ancestor_of(node):
			continue
		if node is SteamJet or node is ElectricPuddle:
			cyclic.append(node)
		elif node is DebrisZone:
			debris.append(node)
		elif node is RadiationZone:
			radiation.append(node)


# --- Pure checks (unit tested) ---------------------------------------------------------------

## `local` (a point in the hazard's own space) is inside a hazard of `size`, grown by `margin` metres.
## BOX: centred on the origin in X and Z, from the floor up (puddles, the radiation zone). JET: from
## the nozzle (the origin) along +Z for size.z, size.x wide (the frustum's far end, so it errs wide).
static func inside(shape: Shape, local: Vector3, size: Vector3, margin: float = 0.0) -> bool:
	if local.y < -Y_BELOW or local.y > size.y + margin + 0.6:
		return false
	if absf(local.x) > size.x * 0.5 + margin:
		return false
	if shape == Shape.JET:
		return local.z >= -margin and local.z <= size.z + margin
	return absf(local.z) <= size.z * 0.5 + margin


## A cyclic hazard in the way: wait if it is live now, or if it switches on sooner than `cross_s`
## (the time we need to get through or to finish what we start there).
static func should_wait(live: bool, to_switch: float, cross_s: float) -> bool:
	return live or to_switch < cross_s


# --- The level's hazards -------------------------------------------------------------------------

static func shape_of(hazard: Hazard) -> Shape:
	return Shape.JET if hazard is SteamJet else Shape.BOX


## The active cyclic hazard at `pos` (grown by `margin`) that is live or switches on within `cross_s`,
## or null.
func blocking(pos: Vector3, cross_s: float, margin: float = 0.0) -> Hazard:
	var t := Net.server_time()
	for h in cyclic:
		if not h.active or not inside(shape_of(h), h.to_local(pos), h.size, margin):
			continue
		var live := h.is_live(t)
		if should_wait(live, HazardRules.time_to_switch(h.elapsed(t), h.on_s, h.off_s, h.phase), cross_s):
			return h
	return null


## The pending debris impact closest to `pos` that lands within `radius` of it, as {"pos", "at"}
## (server time), or {} if none.
func impact_near(pos: Vector3, radius: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for zone in debris:
		if not zone.active:
			continue
		for impact: Dictionary in zone.pending_impacts():
			var at: Vector3 = impact["pos"]
			var d := Vector2(at.x - pos.x, at.z - pos.z).length()
			if d <= radius and absf(at.y - pos.y) < 1.5 and d < best_d:
				best_d = d
				best = impact
	return best


## The active radiation zone `pos` is in, or null.
func radiation_at(pos: Vector3) -> RadiationZone:
	for zone in radiation:
		if zone.is_live(Net.server_time()) and inside(Shape.BOX, zone.to_local(pos), zone.size):
			return zone
	return null


## A point just outside `zone`, the nearest way out from `pos`.
static func way_out(zone: RadiationZone, pos: Vector3, margin: float = 1.0) -> Vector3:
	var local := zone.to_local(pos)
	var half := Vector2(zone.size.x, zone.size.z) * 0.5
	var to_x := half.x - absf(local.x)
	var to_z := half.y - absf(local.z)
	if to_x < to_z:
		local.x = signf(local.x if local.x != 0.0 else 1.0) * (half.x + margin)
	else:
		local.z = signf(local.z if local.z != 0.0 else 1.0) * (half.y + margin)
	return zone.to_global(local)
