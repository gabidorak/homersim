class_name AiSenses
extends RefCounted
## What one AI bot knows about its enemies (M10, GDD §5.5 Fair play). This is the ONLY AI code that
## reads an enemy body's position or state: a review of server/ai/ should find it nowhere else. (The
## server's own rule checks, like the broom's hit test, still read positions, as they do for players.)
##   sight    within the skill's view range (smoke_view_range in active smoke), inside the field of
##            view (supervisors fov_supervisor_deg around the body's facing; rats fov_rat_deg, their
##            third-person camera sees around them), with a clear line of sight on WORLD from the
##            eyes. An enemy only counts after the skill's reaction_s of continuous sight.
##   hearing  moving enemies within a radius (a walking rat, a sprinting rat, a supervisor), and the
##            sounds AiDirector passes on (bites, broom swings, squeaks, SNAPs): a position with
##            ±hear_noise of error
##   always   Revealed enemies (the outline through walls); what the HUD and the map show anyone
##            (machines, cages) is read by the goals from the level directly
##   CCTV     supervisors seated in the chair: rats within cctv_range of an unbroken camera's lens,
##            inside its view (cctv_fov_deg), with a clear line from the lens
##   memory   a last known position is kept memory_s, then becomes a search area for search_s.
##            Teammate bots share sightings through the blackboard, after share_delay_s.
##   out of play  carried, caged and eliminated enemies are forgotten at once, with their callouts
## Things, checked twice a second:
##   traps    rats notice a trap within trap_notice_radius, in sight, with the skill's trap_notice
##            chance (one roll per trap); teammate bots hear about it like a sighting
##   cameras  supervisors see whether a camera is broken from camera_seen_radius in sight, on the
##            Control Room's wall screens, or from the chair
##   keycards supervisors see a dropped keycard in sight; a rat seen (or heard about) stealing one is
##            a known thief until a stun or a cage makes it drop it
##   keycard  rats see whether a supervisor still has its keycard from close up (the steal prompt)
## The pure checks (can_notice, hearing_radius, seen_long_enough) are unit tested
## (tests/unit/test_ai_senses.gd).

const THINGS_EVERY_S := 0.5  ## traps, cameras and dropped keycards are looked for this often
const KEYCARD_SEEN_M := 4.0  ## m: whether a supervisor has its keycard is seen this close (the steal prompt)
const CONTROL_ROOM_SCREENS_M := 10.0  ## m from the CCTV chair: the Control Room's wall screens show the cameras


## What the bot knows about one enemy.
class Known:
	var peer := 0
	var role := Role.Kind.NONE
	var pos := Vector3.ZERO  ## last known position
	var velocity := Vector3.ZERO  ## while seen
	var at := 0.0  ## when it was last seen or heard
	var visible := false  ## in sight right now (after the reaction time)
	var heard := false  ## the position came from a sound or a callout (±noise)
	var revealed := false
	var stunned := false
	var knocked := false
	var carrying := 0  ## supervisors: the rat they carry
	var busy := false  ## standing at something: repairing, sabotaging, seated at the CCTV
	var seated := false
	var facing := 0.0  ## body yaw, while seen
	var cctv := false  ## the position came from a CCTV camera (a seated supervisor)
	var keycard := true  ## supervisors: still has its keycard (seen from close up; assumed until then)
	var invulnerable := false

	func age(now: float) -> float:
		return now - at


var ctx: AiContext
var known: Dictionary[int, Known] = {}
var searches: Array[Dictionary] = []  ## {"pos": Vector3, "until": float}
var bitten_by := 0  ## the last enemy that bit us (we know where it is: it just bit us)
var bitten_at := -INF
var traps_noticed: Dictionary = {}  ## rats: Trap instance id -> Trap, noticed and still armed
var broken_cameras: Dictionary = {}  ## supervisors: CctvCamera -> broken, as last seen
var keycards_seen: Array[Pickup] = []  ## supervisors: dropped keycards in sight
var thieves: Dictionary = {}  ## supervisors: rat peer -> when it was seen stealing (it still has the keycard)
var cctv_spotted_at := -INF  ## supervisors: the last time the CCTV showed a rat

var _sight_since: Dictionary[int, float] = {}  # peer -> when continuous sight began
var _last: Dictionary[int, Array] = {}  # peer -> [position, time] at the last update (velocity, hearing)
var _emoting: Dictionary[int, bool] = {}  # rats' FLAG_EMOTE at the last update (squeaks)
var _next_update := 0.0
var _next_things := 0.0  # traps, cameras and keycards: twice a second
var _events_read := 0.0  # AiDirector sound events up to this time are already heard
var _traps_rolled: Dictionary = {}  # trap instance id -> true: the notice roll was made
var _enemies: Array[Known] = []  # enemies(), sorted, for this tick
var _enemies_at := -1.0
var _traps: Array[Trap] = []  # traps(), for this tick
var _traps_at := -1.0


func _init(p_ctx: AiContext) -> void:
	ctx = p_ctx


# --- Pure checks (unit tested) ---------------------------------------------------------------

## True if `target` is within `view_range` of `eye` and inside the flat field of view of `fov_deg`
## (full angle) around `facing_yaw`. (The line of sight is checked separately: it needs physics.)
static func can_notice(eye: Vector3, facing_yaw: float, fov_deg: float, view_range: float, target: Vector3) -> bool:
	var to := target - eye
	if to.length() > view_range:
		return false
	if fov_deg >= 360.0:
		return true
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.3:
		return true
	var forward := Vector2(-sin(facing_yaw), -cos(facing_yaw))
	return absf(forward.angle_to(flat)) <= deg_to_rad(fov_deg * 0.5)


## How far a body of `role` moving at `speed` is heard (0 = silent).
static func hearing_radius(role: Role.Kind, speed: float, walk_speed: float, tuning: BotTuning) -> float:
	if speed < 0.5:
		return 0.0
	if role == Role.Kind.RAT:
		return tuning.hear_rat_sprint if speed > walk_speed * 1.15 else tuning.hear_rat_walk
	return tuning.hear_supervisor


## An enemy in sight since `since` counts as seen at `now` after `reaction_s`.
static func seen_long_enough(since: float, now: float, reaction_s: float) -> bool:
	return since >= 0.0 and now - since >= reaction_s


## An enemy nobody can act on: eliminated, caged, or carried (it hangs from a supervisor's hand,
## the carrier's business; no broom reaches it and nothing is left to chase until it is dropped).
static func _out_of_play(enemy: Player) -> bool:
	var st := enemy.status
	return st.has(StatusComponent.Status.ELIMINATED) or st.has(StatusComponent.Status.CAGED) \
		or st.has(StatusComponent.Status.CARRIED)


# --- Every tick ----------------------------------------------------------------------------------

func update(now: float) -> void:
	if now < _next_update:
		return
	_next_update = now + 1.0 / ctx.tuning.senses_hz
	_enemies_at = -1.0
	var me := ctx.body
	var eye := _eye_of(me)
	var enemy_role := Role.Kind.RAT if ctx.role == Role.Kind.SUPERVISOR else Role.Kind.SUPERVISOR
	var fov := ctx.tuning.fov_supervisor_deg if ctx.role == Role.Kind.SUPERVISOR else ctx.tuning.fov_rat_deg
	var cameras := _cctv_lenses() if ctx.role == Role.Kind.SUPERVISOR and me.seated_console() != null else []
	var present := {}
	for node in ctx.session.players_root.get_children():
		var enemy := node as Player
		if enemy == null or enemy.role != enemy_role or enemy.is_queued_for_deletion() or _out_of_play(enemy):
			continue
		present[enemy.peer_id] = true
		var pos := enemy.global_position
		var center := Interactable.origin_of(enemy)
		var speed := 0.0
		if _last.has(enemy.peer_id):
			var dt := now - float(_last[enemy.peer_id][1])
			if dt > 0.0:
				speed = _flat(pos - (_last[enemy.peer_id][0] as Vector3)).length() / dt
		var previous_pos: Vector3 = _last[enemy.peer_id][0] if _last.has(enemy.peer_id) else pos
		var previous_time: float = _last[enemy.peer_id][1] if _last.has(enemy.peer_id) else now
		_last[enemy.peer_id] = [pos, now]
		var range_now := ctx.skill.view_range
		if _in_smoke(eye) or _in_smoke(center):
			range_now = minf(range_now, ctx.tuning.smoke_view_range)
		var in_view := can_notice(eye, me.rotation.y, fov, range_now, center) and _line_of_sight(eye, center, enemy)
		if in_view:
			if not _sight_since.has(enemy.peer_id):
				_sight_since[enemy.peer_id] = now
		else:
			_sight_since.erase(enemy.peer_id)
		var revealed := enemy.status.has(StatusComponent.Status.REVEALED)
		var seen := in_view and seen_long_enough(_sight_since.get(enemy.peer_id, -1.0), now, ctx.skill.reaction_s)
		var on_cctv := not seen and not cameras.is_empty() and _on_camera(cameras, center, enemy)
		if seen or revealed or on_cctv or (enemy.peer_id == bitten_by and now - bitten_at < 1.0):
			var k := _entry(enemy)
			k.velocity = (pos - previous_pos) / maxf(now - previous_time, 0.05) if k.visible else Vector3.ZERO
			k.pos = pos
			k.at = now
			k.visible = seen
			k.heard = false
			k.cctv = on_cctv
			k.revealed = revealed
			k.stunned = enemy.status.has(StatusComponent.Status.STUNNED)
			k.knocked = enemy.status.has(StatusComponent.Status.KNOCKED_DOWN)
			k.invulnerable = enemy.status.has(StatusComponent.Status.INVULNERABLE)
			k.carrying = enemy.status.carrying
			k.seated = enemy.seated_console() != null
			k.facing = enemy.rotation.y
			k.busy = k.seated or enemy.sync_anim & AnimationController.FLAG_INTERACT != 0
			if seen and enemy_role == Role.Kind.SUPERVISOR and pos.distance_to(me.global_position) <= KEYCARD_SEEN_M:
				k.keycard = enemy.inventory.keycard  # (the steal prompt says so)
			if seen and k.stunned:
				_not_a_thief(enemy.peer_id)  # a stun makes it drop what it stole
			if on_cctv:
				cctv_spotted_at = now
			ctx.board.report_sighting(enemy.peer_id, pos, now, ctx.peer, k.seated)
		else:
			if known.has(enemy.peer_id):
				known[enemy.peer_id].visible = false
			var radius := hearing_radius(enemy.role, speed, enemy.role_data.walk_speed, ctx.tuning)
			if radius > 0.0 and pos.distance_to(me.global_position) <= radius:
				_hear(enemy.peer_id, enemy.role, pos, now)
		if enemy_role == Role.Kind.RAT:
			var emoting := enemy.sync_anim & AnimationController.FLAG_EMOTE != 0
			if emoting and not _emoting.get(enemy.peer_id, false) \
					and pos.distance_to(me.global_position) <= ctx.tuning.hear_squeak:
				_hear(enemy.peer_id, enemy.role, pos, now)
			_emoting[enemy.peer_id] = emoting
	for peer: int in known.keys():
		if not present.has(peer):
			known.erase(peer)  # carried, caged, eliminated or gone
			_sight_since.erase(peer)
	for peer: int in thieves.keys():
		if not present.has(peer):
			_not_a_thief(peer)  # caught (a cage takes the keycard off it) or gone
	_read_events(now)
	_read_callouts(now, present)
	_forget(now)
	if now >= _next_things:
		_next_things = now + THINGS_EVERY_S
		if ctx.role == Role.Kind.RAT:
			_look_for_traps(eye, now)
		else:
			_look_at_cameras(eye)
			_look_for_keycards(eye)


## Sounds AiDirector recorded (bites, broom swings, SNAPs) since our last look.
func _read_events(now: float) -> void:
	var me := ctx.body.global_position
	for e: Dictionary in ctx.director.sound_events:
		if float(e["at"]) <= _events_read:
			continue
		var radius: float = {"bite": ctx.tuning.hear_bite, "broom": ctx.tuning.hear_broom}.get(e["kind"], 0.0)
		var source: int = e["peer"]
		if radius > 0.0 and source != ctx.peer and (e["pos"] as Vector3).distance_to(me) <= radius \
				and ctx.director.role_of(source) != ctx.role:
			_hear(source, ctx.director.role_of(source), e["pos"], now)
	_events_read = now


## Teammate bots' sightings, traps and thieves, once share_delay_s old: like hearing a callout.
## A sighting of an enemy out of play (not in `present`) is dropped: an old callout of a rat that got
## carried to a cage would otherwise bring it back as a trace to search, next to the cage, forever.
func _read_callouts(now: float, present: Dictionary) -> void:
	for id: int in ctx.board.traps:
		var t: Dictionary = ctx.board.traps[id]
		if not traps_noticed.has(id) and now - float(t["at"]) >= ctx.tuning.share_delay_s and is_instance_valid(t["trap"]):
			traps_noticed[id] = t["trap"]
	for rat: int in ctx.board.thieves:
		if not thieves.has(rat) and now - float(ctx.board.thieves[rat]) >= ctx.tuning.share_delay_s:
			thieves[rat] = ctx.board.thieves[rat]
	for enemy: int in ctx.board.sightings.keys():
		if not present.has(enemy):
			ctx.board.sightings.erase(enemy)
			continue
		var s: Dictionary = ctx.board.sightings[enemy]
		if s["by"] == ctx.peer or now - float(s["at"]) < ctx.tuning.share_delay_s:
			continue
		var k: Known = known.get(enemy)
		if k != null and k.at >= float(s["at"]):
			continue
		if k == null:
			k = Known.new()
			k.peer = enemy
			k.role = ctx.director.role_of(enemy)
			known[enemy] = k
		k.pos = s["pos"]
		k.at = s["at"]
		k.visible = false
		k.heard = true


func _forget(now: float) -> void:
	# Rats keep a supervisor's last spot as long as it makes that area dangerous (AiContext.danger_at).
	var keep := maxf(ctx.tuning.memory_s, ctx.tuning.danger_memory_s) if ctx.role == Role.Kind.RAT else ctx.tuning.memory_s
	for peer: int in known.keys():
		var k: Known = known[peer]
		if not k.visible and k.age(now) > keep:
			searches.append({"pos": k.pos, "until": now + ctx.tuning.search_s})
			known.erase(peer)
	searches = searches.filter(func(s: Dictionary) -> bool: return now < float(s["until"]))


func _hear(peer: int, role: Role.Kind, pos: Vector3, now: float) -> void:
	var k: Known = known.get(peer)
	if k != null and k.visible:
		return  # we see it: better than hearing
	if k == null:
		k = Known.new()
		k.peer = peer
		k.role = role
		known[peer] = k
	var noise := ctx.tuning.hear_noise
	k.pos = pos + Vector3(ctx.rng.randf_range(-noise, noise), 0.0, ctx.rng.randf_range(-noise, noise))
	k.at = now
	k.heard = true
	k.visible = false


func _entry(enemy: Player) -> Known:
	var k: Known = known.get(enemy.peer_id)
	if k == null:
		k = Known.new()
		k.peer = enemy.peer_id
		k.role = enemy.role
		known[enemy.peer_id] = k
	return k


## AbilityService: `attacker` bit us. We know where it is.
func on_bitten(attacker: int) -> void:
	bitten_by = attacker
	bitten_at = ctx.now
	_next_update = 0.0


# --- For goals --------------------------------------------------------------------------------

## The enemies we know of, nearest (last known position) first. Sorted once per tick (goals ask often).
func enemies() -> Array[Known]:
	if _enemies_at == ctx.now:
		return _enemies
	_enemies_at = ctx.now
	_enemies.assign(known.values())
	var here := ctx.body.global_position
	_enemies.sort_custom(func(a: Known, b: Known) -> bool: return a.pos.distance_to(here) < b.pos.distance_to(here))
	return _enemies


## The nearest known enemy within `max_distance` (visible ones only if `visible_only`), or null.
func nearest(max_distance: float = INF, visible_only: bool = false) -> Known:
	for k in enemies():
		if visible_only and not k.visible:
			continue
		if k.pos.distance_to(ctx.body.global_position) <= max_distance:
			return k
		return null
	return null


func get_known(peer: int) -> Known:
	return known.get(peer)


## A known enemy within `radius` of `pos`.
func enemy_near(pos: Vector3, radius: float) -> bool:
	for k: Known in known.values():
		if k.pos.distance_to(pos) <= radius:
			return true
	return false


## A rat's GrabHandle, only while we see that rat (Capture presses it).
func grab_handle_of(peer: int) -> GrabHandle:
	var k: Known = known.get(peer)
	if k == null or not k.visible:
		return null
	var body := ctx.session.get_body(peer)
	return body.get_node_or_null("GrabHandle") as GrabHandle if body != null else null


## A supervisor's StealHandle, only while we see it.
func steal_handle_of(peer: int) -> StealHandle:
	var k: Known = known.get(peer)
	if k == null or not k.visible:
		return null
	var body := ctx.session.get_body(peer)
	return body.get_node_or_null("StealHandle") as StealHandle if body != null else null


## True when a sound-making event (a bite, a broom swing, a SNAP) happened at `pos` within `radius`
## in the last `seconds` (for Flee: "a broom swing heard").
func heard_recently(kind: String, radius: float, seconds: float) -> bool:
	var me := ctx.body.global_position
	for e: Dictionary in ctx.director.sound_events:
		if e["kind"] == kind and ctx.now - float(e["at"]) <= seconds and e["peer"] != ctx.peer \
				and (e["pos"] as Vector3).distance_to(me) <= radius:
			return true
	return false


## The traps this rat knows of (noticed itself or called out), still armed (gathered once per tick).
func traps() -> Array[Trap]:
	if _traps_at == ctx.now:
		return _traps
	_traps_at = ctx.now
	var out := _traps
	out.clear()
	for id: int in traps_noticed.keys():
		var trap: Variant = traps_noticed[id]  # (untyped: it may have been freed, sprung)
		if is_instance_valid(trap) and not (trap as Trap).is_queued_for_deletion():
			out.append(trap)
		else:
			traps_noticed.erase(id)
	return out


## A trap this rat knows of within `radius` (flat) of `pos`.
func trap_near(pos: Vector3, radius: float) -> bool:
	for trap in traps():
		var at := trap.global_position
		if Vector2(at.x - pos.x, at.z - pos.z).length() <= radius and absf(at.y - pos.y) < 1.0:
			return true
	return false


func is_thief(peer: int) -> bool:
	return thieves.has(peer)


func _not_a_thief(peer: int) -> void:
	thieves.erase(peer)
	ctx.board.thieves.erase(peer)


## A seen keycard steal (AiDirector): a rat we know of right now stole one. The team hears of it.
func on_theft(rat: int) -> void:
	var k: Known = known.get(rat)
	if k != null and (k.visible or k.cctv) and k.age(ctx.now) < 1.0:
		thieves[rat] = ctx.now
		ctx.board.thieves[rat] = ctx.now
		ctx.log_line("saw %s steal a keycard" % ctx.session.name_of(rat))


## Rats: a trap within trap_notice_radius, in sight, is noticed with the skill's chance (one roll each).
func _look_for_traps(eye: Vector3, now: float) -> void:
	var here := ctx.body.global_position
	for trap in ctx.world.traps():
		var id := trap.get_instance_id()
		if _traps_rolled.has(id) or trap.global_position.distance_to(here) > ctx.tuning.trap_notice_radius:
			continue
		if not _clear_line(eye, trap.global_position + Vector3.UP * 0.15):
			continue
		_traps_rolled[id] = true
		if ctx.rng.randf() < ctx.skill.trap_notice:
			traps_noticed[id] = trap
			ctx.board.traps[id] = {"trap": trap, "at": now}
			ctx.log_line("noticed a %s trap at %s" % [trap.trap_kind, trap.global_position.snapped(Vector3.ONE * 0.1)])


## Supervisors: which cameras are broken, as far as we can see (close up, the wall screens, the chair).
func _look_at_cameras(eye: Vector3) -> void:
	var here := ctx.body.global_position
	var screens := ctx.body.seated_console() != null or (ctx.world.console != null \
		and ctx.world.console.global_position.distance_to(here) <= CONTROL_ROOM_SCREENS_M)
	for camera in ctx.world.cameras:
		if screens or (camera.global_position.distance_to(here) <= ctx.tuning.camera_seen_radius \
				and (_clear_line(eye, camera.lens.global_position) or _clear_line(eye, camera.global_position + Vector3.UP * 0.3))):
			broken_cameras[camera] = camera.broken


## Supervisors: dropped keycards in sight.
func _look_for_keycards(eye: Vector3) -> void:
	keycards_seen.clear()
	var here := ctx.body.global_position
	for pickup in ctx.world.dropped_keycards():
		if pickup.global_position.distance_to(here) <= ctx.skill.view_range \
				and _clear_line(eye, pickup.global_position + Vector3.UP * 0.1):
			keycards_seen.append(pickup)


# --- CCTV ----------------------------------------------------------------------------------------

## The unbroken cameras' lenses: [[position, yaw], …].
func _cctv_lenses() -> Array:
	var out: Array = []
	for camera in ctx.world.cameras:
		if not camera.broken and camera.lens != null:
			var forward := -camera.lens.global_basis.z
			out.append([camera.lens.global_position, atan2(-forward.x, -forward.z)])
	return out


func _on_camera(lenses: Array, center: Vector3, enemy: Player) -> bool:
	for lens: Array in lenses:
		var at: Vector3 = lens[0]
		if can_notice(at, lens[1], ctx.tuning.cctv_fov_deg, ctx.tuning.cctv_range, center) \
				and _clear_line(at, center, [enemy.get_rid()]):
			return true
	return false


# --- Physics -------------------------------------------------------------------------------------

## Where a body looks from: a supervisor's eyes; a rat's third-person camera pivot above it.
static func _eye_of(body: Player) -> Vector3:
	if body.role == Role.Kind.RAT:
		return body.global_position + Vector3.UP * (body.role_data.height + 0.3)
	return body.global_position + Vector3.UP * (body.role_data.height - 0.2)


func _line_of_sight(from: Vector3, to: Vector3, target: Player) -> bool:
	return _clear_line(from, to, [target.get_rid()])


func _clear_line(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var skip: Array[RID] = [ctx.body.get_rid()]
	skip.append_array(exclude)
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD, skip)
	return ctx.body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _in_smoke(pos: Vector3) -> bool:
	for smoke in ctx.world.smokes:
		if smoke.active:
			var local := smoke.to_local(pos).abs()
			if local.x <= smoke.size.x * 0.5 and local.y <= smoke.size.y * 0.5 and local.z <= smoke.size.z * 0.5:
				return true
	return false


# --- Sound events (AiDirector records them; positions are read here, like every enemy position) ---

## Server: a sound everyone nearby hears, made by `peer`'s body ("bite", "broom").
static func record_sound(director: AiDirector, kind: String, peer: int, now: float) -> void:
	var body := director.session.get_body(peer)
	if body == null:
		return
	director.sound_events.append({"kind": kind, "pos": body.global_position, "at": now, "peer": peer})
	while director.sound_events.size() > 64:
		director.sound_events.pop_front()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
