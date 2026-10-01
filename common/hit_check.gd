class_name HitCheck
extends RefCounted
## Melee hit checks (broom, bite) as pure geometry, so GUT can test them. The server calls them
## with its latest known positions; line of sight is checked separately (it needs physics).
## Generous on purpose (M4 pitfalls): the cone is measured flat (yaw only), so looking straight
## ahead still hits a rat at your feet, and the caller adds a lag tolerance to the range.

const MAX_HEIGHT_DIFF := 1.5  ## m between the two body centres
const POINT_BLANK := 0.3  ## m: closer than this, any direction counts


## True if `target` is within `reach` (horizontal metres) of `origin` and inside the flat cone of
## `cone_deg` (full width) around `aim`. cone_deg >= 360 means any direction.
static func in_reach(origin: Vector3, aim: Vector3, target: Vector3, reach: float, cone_deg: float) -> bool:
	var to := target - origin
	if absf(to.y) > MAX_HEIGHT_DIFF:
		return false
	to.y = 0.0
	var distance := to.length()
	if distance > reach:
		return false
	if cone_deg >= 360.0 or distance < POINT_BLANK:
		return true
	var flat_aim := Vector3(aim.x, 0.0, aim.z)
	if flat_aim.length_squared() < 0.0001:
		return true
	return flat_aim.angle_to(to) <= deg_to_rad(cone_deg * 0.5)


## The peers of `candidates` (peer -> body centre) that are in reach, nearest first.
static func targets_in_reach(origin: Vector3, aim: Vector3, candidates: Dictionary, reach: float,
		cone_deg: float) -> Array[int]:
	var hits: Array[int] = []
	for peer: int in candidates:
		if in_reach(origin, aim, candidates[peer], reach, cone_deg):
			hits.append(peer)
	hits.sort_custom(func(a: int, b: int) -> bool:
		return _flat_distance(origin, candidates[a]) < _flat_distance(origin, candidates[b]))
	return hits


## `wanted` if it is within `max_angle_deg` of `reference` (both flattened), otherwise `reference`.
## The server trusts the client's aim only that far from the synced look direction.
static func clamp_aim(wanted: Vector3, reference: Vector3, max_angle_deg: float) -> Vector3:
	var w := Vector3(wanted.x, 0.0, wanted.z)
	var r := Vector3(reference.x, 0.0, reference.z)
	if w.length_squared() < 0.0001 or not w.is_finite():
		return r.normalized()
	if r.length_squared() < 0.0001 or w.angle_to(r) <= deg_to_rad(max_angle_deg):
		return w.normalized()
	return r.normalized()


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True if nothing in the level (layer WORLD) is between `from` and `to`. Bodies in `exclude`
## and `attacker` itself are ignored. Needs physics, so it isn't covered by the unit tests.
static func has_line_of_sight(attacker: Player, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var ignore: Array[RID] = [attacker.get_rid()]
	ignore.append_array(exclude)
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD, ignore)
	return attacker.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
