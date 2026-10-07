class_name AiDirector
extends Node
## The AI bots (M10, GDD §5.5, ARCHITECTURE §6 AI bots), server only: Session adds it under
## ServerOnly. It
##   - bakes the navigation meshes (AiNav) once the level's shapes exist, then tells MatchManager
##     the bots can play (Session.ai_ready, recheck_start);
##   - names the bots MatchManager adds to the roster (bot_name);
##   - runs one AiBot per bot body from COUNTDOWN on, with a blackboard per team, and stops them
##     when the match ends. Teammate bots don't collide with each other: the ducts and the shaft are one
##     rat wide, and two bots meeting there head-on would block each other for good (humans still bump
##     into everyone);
##   - keeps what each bot did for the test result file (report(), the "ai" section).
## Nothing is baked on a server without bots (bot_fill_to 0).
##
## Test-only server flags (debug builds): --ai-seed S (the bots' random numbers), --ai-log (one log
## line per decision), --ai-scenario NAME, --ai-goals role:Goal,… (bots only use these goals, e.g.
## rat:Sabotage; rat:none = no goals, the bot stands still). Scenarios:
##   tour      every bot walks to its share of its role's targets, then the match ends (ai_nav_tour.sh)
##   capture   when PLAYING starts, the rat bots stand in the Cage Room and the supervisor bots 6 m
##             away, facing them (ai_capture.sh)
##   path:X,Y,Z:X,Y,Z[:…]   the first bot starts at the first point and walks to the others in order;
##             the others stand still. For debugging a spot, with --ai-trace.
##   hot       when PLAYING starts the core is at HOT_CORE (ai_control.sh: coolant, then SCRAM)
##   steal     when PLAYING starts the pumps are at 55 and the rat bots wait 5 m behind the pumps'
##             repair spot (ai_steal.sh: the repairing supervisor faces away from them)
##   cctv      when PLAYING starts the rat bots stand at camera 8's junction box (ai_cctv.sh)
## --ai-trace NAME|all: a log line 4 times a second per bot (position, intent, path, link, floor, wall).
## --ai-labels: each bot's current goal goes to every client twice a second (MatchManager.on_ai_labels),
## shown under its name tag: for a spectating debug client.
## Every SUMMARY_S of a match the log gets a summary line per bot (AiBot.summary) and the AI's total
## cost per physics frame (the budget is BUDGET_MS per bot).

const FIRST_ID := -1001  ## bots get -1001, -1002…: ENet ids are always positive
const SUMMARY_S := 30.0
const BUDGET_MS := 0.3  ## per bot per physics tick
const LABELS_EVERY_S := 0.5
const STUCK_CSV := "user://ai_stuck.csv"
const HOT_CORE := 950.0  ## --ai-scenario hot
const LURE_NEAR_TARGET := 12.0  ## m: a vent exit this close to a machine gets a cheese lure spot…
const LURE_NEAR_CAGE := 10.0  ## …or this close to a cage
const LURE_INTO_ROOM := 1.0  ## m from the vent exit into the room (rats that notice it can pass)
const TRAP_REACH := 1.8  ## m (flat): a trap spot needs supervisor floor this close
const HIDEOUT_DEPTH := 1.2  ## m from a vent exit into its duct: a rats' bolt-hole


## The level's targets, collected when a match starts (goals read them).
class World:
	var sabotage_points: Array[SabotagePoint] = []
	var levers: Array[CriticalLever] = []
	var repair_points: Array[RepairPoint] = []
	var cages: Array[Cage] = []
	var cameras: Array[CctvCamera] = []
	var consoles: Array[CctvConsole] = []
	var actions: Array[ConsoleAction] = []
	var pickups: Array[Pickup] = []
	var readers: Array[KeycardReader] = []
	var doors: Array[Door] = []
	var vent_exits: Array[Vector3] = []
	var vent_spots: Array[Vector3] = []  ## the floor in the middle of each vent volume
	var vent_boxes: Array = []  ## [global Transform3D, size] of each vent volume's box
	var smokes: Array[Smoke] = []
	var hazards := AiHazards.new()
	var console: CctvConsole  ## the CCTV chair
	var coolant: ConsoleAction
	var scram: ConsoleAction
	var refills: Dictionary[StringName, Pickup] = {}  ## Storage: trap id → the box that refills it
	var spare: Pickup  ## Storage: the spare keycard
	var donuts: Pickup  ## Break Room
	var dynamic: Node3D  ## World/Dynamic: traps and dropped keycards
	var _trap_spots: Array[Dictionary] = []
	var _nav_for_spots: AiNav
	var _hideouts: Array[Vector3] = []
	var _hideouts_done := false

	func collect(level: Node3D, dynamic_root: Node3D) -> void:
		dynamic = dynamic_root
		for node in level.get_tree().get_nodes_in_group(Interactable.GROUP):
			if not level.is_ancestor_of(node):
				continue
			if node is SabotagePoint:
				sabotage_points.append(node)
			elif node is CriticalLever:
				levers.append(node)
			elif node is RepairPoint:
				repair_points.append(node)
			elif node is Cage:
				cages.append(node)
			elif node is CctvCamera:
				cameras.append(node)
			elif node is CctvConsole:
				consoles.append(node)
			elif node is ConsoleAction:
				actions.append(node)
			elif node is Pickup:
				pickups.append(node)
			elif node is KeycardReader:
				readers.append(node)
		for node in level.find_children("*", "Node3D", true, false):
			if node is Door:
				doors.append(node)
		for node in level.get_tree().get_nodes_in_group(Hazard.ALL_GROUP):
			if node is Smoke and level.is_ancestor_of(node):
				smokes.append(node)
		for node in level.get_tree().get_nodes_in_group("vent_exits"):
			if level.is_ancestor_of(node):
				vent_exits.append((node as Node3D).global_position)
		for node in level.get_tree().get_nodes_in_group(VentVolume.GROUP):
			var shape := (node as Node).get_node_or_null("Shape") as CollisionShape3D
			if shape != null and shape.shape is BoxShape3D and level.is_ancestor_of(node):
				var size := (shape.shape as BoxShape3D).size
				vent_spots.append(shape.global_transform * Vector3(0, -size.y / 2.0 + 0.05, 0))
				vent_boxes.append([shape.global_transform, size])
		hazards.collect(level)
		console = consoles[0] if not consoles.is_empty() else null
		for action in actions:
			if action.action == "coolant":
				coolant = action
			elif action.action == "scram":
				scram = action
		for pickup in pickups:
			match pickup.item:
				"trap_refill", "lure_refill":
					refills[Pickup.REFILLS[pickup.item]] = pickup
				"spare_keycard":
					spare = pickup
				"donut":
					donuts = pickup

	var _stands := {}

	## Where `role` stands to use `node` (cached: it casts a ray).
	func stand(node: Interactable, role: Role.Kind) -> Vector3:
		var key := "%d:%d" % [node.get_instance_id(), role]
		if not _stands.has(key):
			_stands[key] = node.stand_position(role)
		return _stands[key]

	## The repair point of subsystem `id`, or null.
	func repair_point(id: StringName) -> RepairPoint:
		for point in repair_points:
			if point.subsystem_id == id:
				return point
		return null

	## The traps on the floor right now (every peer sees them; rats only know those AiSenses noticed).
	func traps() -> Array[Trap]:
		var out: Array[Trap] = []
		if dynamic != null:
			for child in dynamic.get_children():
				if child is Trap and not child.is_queued_for_deletion():
					out.append(child)
		return out

	## Keycards on the floor (a stunned or caught thief dropped them).
	func dropped_keycards() -> Array[Pickup]:
		var out: Array[Pickup] = []
		if dynamic != null:
			for child in dynamic.get_children():
				if child is Pickup and (child as Pickup).item == "keycard" and not child.is_queued_for_deletion():
					out.append(child)
		return out

	## Where supervisors lay traps (GDD §5.1, M10 phase E), worked out once per match:
	## {"pos", "kind" (&"snap_trap" | &"cheese_lure"), "value" 0..1, "key"}. Snap traps go on the
	## rats' stand spots at machines and levers (value: the heat weight); cheese lures a metre into
	## the room from the vent exits near those targets and near the cages.
	func trap_spots(nav: AiNav, plant: PlantSim) -> Array[Dictionary]:
		if not _trap_spots.is_empty():
			return _trap_spots
		_nav_for_spots = nav
		var targets: Array[Interactable] = []
		targets.append_array(sabotage_points)
		targets.append_array(levers)
		for node in targets:
			var index: int = node.get("index")
			if index == -1:
				continue
			var spot := stand(node, Role.Kind.RAT)
			_add_trap_spot(spot, &"snap_trap", plant.data(index).heat_weight / AiScoring.MAX_HEAT_WEIGHT)
		for exit in vent_exits:
			var value := 0.0
			for node in targets:
				if Vector2(exit.x - node.global_position.x, exit.z - node.global_position.z).length() < LURE_NEAR_TARGET:
					value = maxf(value, 0.5)
			for cage in cages:
				if Vector2(exit.x - cage.global_position.x, exit.z - cage.global_position.z).length() < LURE_NEAR_CAGE:
					value = maxf(value, 0.6)
			if value <= 0.0:
				continue
			var inward := _into_room(nav, exit)
			if inward == Vector3.ZERO:
				continue  # (no supervisor floor at that exit: the roof's shaft, the Control Room drop)
			_add_trap_spot(exit + inward * LURE_INTO_ROOM, &"cheese_lure", value)
		return _trap_spots

	## Rats' bolt-holes (M10 phase F): a point just inside each vent opening, in the duct, where no
	## supervisor can follow (a vent exit itself is on the room's floor, within a broom's reach).
	func hideouts(nav: AiNav) -> Array[Vector3]:
		if _hideouts_done:
			return _hideouts
		_hideouts_done = true
		for exit in vent_exits:
			var inward := _into_room(nav, exit)
			if inward == Vector3.ZERO:
				continue  # (the roof's shaft, the Control Room drop)
			for depth: float in [HIDEOUT_DEPTH, HIDEOUT_DEPTH + 0.6]:
				var want := exit - inward * depth
				var spot := nav.closest_point(Role.Kind.RAT, want)
				if Vector2(spot.x - want.x, spot.z - want.z).length() < 0.4 and absf(spot.y - exit.y) < 0.8 and in_vent(spot):
					_hideouts.append(spot)
					break
		return _hideouts

	## `pos` is inside a vent volume (rat-only space).
	func in_vent(pos: Vector3) -> bool:
		for box: Array in vent_boxes:
			var local: Vector3 = (box[0] as Transform3D).affine_inverse() * (pos + Vector3.UP * 0.2)
			var half: Vector3 = (box[1] as Vector3) * 0.5 + Vector3.ONE * 0.1
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				return true
		return false

	## The way from a vent exit into its room: a metre that way is supervisor floor, a metre the
	## other way isn't (the wall and the duct behind it). ZERO if no direction fits.
	static func _into_room(nav: AiNav, exit: Vector3) -> Vector3:
		var best := Vector3.ZERO
		var best_off := 0.3
		for i in 8:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 8.0)
			var front := exit + dir * LURE_INTO_ROOM
			var back := exit - dir * LURE_INTO_ROOM
			var on_front := nav.closest_point(Role.Kind.SUPERVISOR, front)
			if Vector2(on_front.x - front.x, on_front.z - front.z).length() > 0.15 or absf(on_front.y - front.y) > 0.5:
				continue
			var on_back := nav.closest_point(Role.Kind.SUPERVISOR, back)
			var off := Vector2(on_back.x - back.x, on_back.z - back.z).length() + absf(on_back.y - back.y)
			if off > best_off:
				best_off = off
				best = dir
		return best

	func _add_trap_spot(pos: Vector3, kind: StringName, value: float) -> void:
		if _nav_for_spots != null:
			var stand := _nav_for_spots.closest_point(Role.Kind.SUPERVISOR, pos)
			if Vector2(stand.x - pos.x, stand.z - pos.z).length() > TRAP_REACH or absf(stand.y - pos.y) > 0.5:
				return  # no supervisor floor next to it (on a crate, in a duct)
		var key := "trap_spot:%d:%d" % [roundi(pos.x * 2.0), roundi(pos.z * 2.0)]
		_trap_spots.append({"pos": pos, "kind": kind, "value": value, "key": key})


var nav := AiNav.new()
var tuning := BotTuning.load_default()
var world: World
var boards: Dictionary = {}  ## Role.Kind -> AiBlackboard
var seed_base := 0
var log_decisions := false
var scenario := ""
var trace := ""  ## --ai-trace: a bot's name, or "all"
var labels := false  ## --ai-labels
var playing_since := 0.0  ## AI clock: when this match's PLAYING began
var only_goals: Dictionary = {}  ## Role.Kind -> Array[String] (--ai-goals)
## Sounds bots may hear (AiSenses.record_sound): {"kind": "bite"|"broom", "pos", "at", "peer"}.
var sound_events: Array[Dictionary] = []

var _bots: Dictionary[int, AiBot] = {}
var _stats: Dictionary[int, Dictionary] = {}  # bot peer -> AiBot.stats, kept until the next match
var _tour := {"targets": 0, "reached": 0, "failed": []}
var _tour_left := 0  # bots still touring
var _names := PackedStringArray()
var _path_start := Vector3.ZERO
var _next_summary := 0.0
var _next_labels := 0.0
var _worst_frame_ms := 0.0
var _spawns: Dictionary = {}  # Role.Kind -> spawn positions (spawn_spots)  # the AI's highest cost per physics frame over the match's summaries

@onready var session: Session = Session.current


func _ready() -> void:
	_read_flags()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	_names = tuning.names.duplicate()
	for i in range(_names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := _names[i]
		_names[i] = _names[j]
		_names[j] = tmp
	session.match_manager.state_changed.connect(_on_state_changed)
	if not session.match_manager.bots_enabled():
		return
	session.abilities.broom_swung.connect(func(attacker: int, _victim: int, _stunned: bool) -> void:
		AiSenses.record_sound(self, "broom", attacker, _now()))
	session.abilities.bitten.connect(_on_bitten)
	session.items.keycard_stolen.connect(func(rat: int, _supervisor: int) -> void:
		for ai in bots():
			if ai.body.role == Role.Kind.SUPERVISOR:
				ai.ctx.senses.on_theft(rat))
	session.items.snap_heard.connect(func(pos: Vector3) -> void:
		var board: AiBlackboard = boards.get(Role.Kind.SUPERVISOR)
		if board != null:
			board.add_event("snap", pos, _now()))
	for i in 2:  # the level's shapes must be registered before the parse and the stand positions
		await get_tree().physics_frame
	await nav.bake(session.level)
	if not is_inside_tree():
		return
	var rules := session.match_manager.rules
	Log.info("ai", "navigation meshes baked in %.2f s: bots fill matches up to %d players, %d supervisors + %d rats (%s)"
		% [nav.bake_seconds, MatchRulesModel.bot_target(rules), rules.supervisor_seats(), rules.rat_seats(),
		tuning.skill(rules.bot_difficulty).label])
	session.ai_ready = true
	session.match_manager.recheck_start()


func _exit_tree() -> void:
	nav.release()


func _read_flags() -> void:
	seed_base = randi()
	if not OS.is_debug_build():
		return
	if Cli.has_arg("ai-seed"):
		seed_base = Cli.get_int("ai-seed", 0)
	log_decisions = Cli.has_arg("ai-log")
	scenario = Cli.get_str("ai-scenario")
	trace = Cli.get_str("ai-trace")
	labels = Cli.has_arg("ai-labels")
	for item in Cli.get_str("ai-goals").split(",", false):
		var parts := item.split(":")
		if parts.size() == 2:
			var role := Role.from_text(parts[0].strip_edges())
			if not only_goals.has(role):
				only_goals[role] = []
			(only_goals[role] as Array).append(parts[1].strip_edges())


## A name for the `index`th bot of a match, not in `taken`.
func bot_name(index: int, taken: Array[String]) -> String:
	for i in _names.size():
		var candidate := _names[(index + i) % _names.size()]
		if candidate not in taken:
			return candidate
	return "Bot %d" % (index + 1)


func _on_bitten(attacker: int, victim: int, _result: int) -> void:
	AiSenses.record_sound(self, "bite", attacker, _now())
	var ai := bot(victim)
	if ai != null:
		ai.ctx.senses.on_bitten(attacker)
	var board: AiBlackboard = boards.get(Role.Kind.RAT)
	if board != null and victim != 0:
		board.add_event("bite", Vector3.ZERO, _now(), victim)  # (the last bite on each supervisor: gang bites)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_delta: float) -> void:
	if _bots.is_empty() or session.match_manager.state != MatchManager.State.PLAYING:
		return
	var now := _now()
	if labels and now >= _next_labels:
		_next_labels = now + LABELS_EVERY_S
		var out := {}
		for ai in bots():
			out[ai.peer] = ai.goal_label()
		session.match_manager.on_ai_labels.rpc(out)
	if now >= _next_summary:
		if _next_summary > 0.0:
			_summarize()
		_next_summary = now + SUMMARY_S


## Every bot's summary line, and what the AI costs per physics frame (the bots run one after another).
func _summarize() -> void:
	var frame_us := 0.0
	var list := bots()
	for ai in list:
		frame_us += ai.summary()
	var per_bot := frame_us / maxf(list.size(), 1) / 1000.0
	_worst_frame_ms = maxf(_worst_frame_ms, frame_us / 1000.0)
	Log.info("ai", "summary: the AI took %.3f ms per physics frame for %d bot(s) (%.3f ms per bot, budget %.1f)%s" % [
		frame_us / 1000.0, list.size(), per_bot, BUDGET_MS, "" if per_bot <= BUDGET_MS else " OVER BUDGET"])


## A spot every body of `role` can reach (its spawn point): a path that can't get there starts on a
## scrap of mesh.
func anchor(role: Role.Kind) -> Vector3:
	var points := session.spawn_points_for(role)
	return points[0].global_position if not points.is_empty() else Vector3.ZERO


## Where `role`'s bodies spawn (every player knows: GDD §3).
func spawn_spots(role: Role.Kind) -> Array[Vector3]:
	if not _spawns.has(role):
		var out: Array[Vector3] = []
		for point in session.spawn_points_for(role):
			out.append(point.global_position)
		_spawns[role] = out
	return _spawns[role]


## A match player's role (bots and humans), from the roster.
func role_of(peer: int) -> Role.Kind:
	return session.match_manager.entry(peer).get("role", Role.Kind.NONE)


func difficulty() -> BotSkill:
	return tuning.skill(session.match_manager.rules.bot_difficulty)


func bot(peer: int) -> AiBot:
	return _bots.get(peer)


func bots() -> Array[AiBot]:
	var out: Array[AiBot] = []
	for b: AiBot in _bots.values():
		if is_instance_valid(b):
			out.append(b)
	return out


# --- Match lifecycle -------------------------------------------------------------------------

func _on_state_changed(state: MatchManager.State) -> void:
	match state:
		MatchManager.State.COUNTDOWN:
			_start_bots()
		MatchManager.State.PLAYING:
			playing_since = _now()
			if scenario == "capture":
				_set_up_capture()
			elif scenario.begins_with("path:"):
				_place_path_start()
			elif scenario in ["hot", "steal", "cctv"]:
				_set_up_scenario()
		MatchManager.State.LOBBY:
			_clear_bots()


func _start_bots() -> void:
	_clear_bots()
	_stats.clear()
	sound_events.clear()
	_next_summary = 0.0
	_worst_frame_ms = 0.0
	_tour = {"targets": 0, "reached": 0, "failed": []}
	var mm := session.match_manager
	if not mm.bots_enabled():
		return
	world = World.new()
	world.collect(session.level, session.items.dynamic_root)
	boards = {Role.Kind.SUPERVISOR: AiBlackboard.new(), Role.Kind.RAT: AiBlackboard.new()}
	var peers: Array = mm.roster.keys()
	peers.sort()
	peers.reverse()  # -1001 first
	for peer: int in peers:
		if not mm.is_bot(peer):
			continue
		var body := session.get_body(peer)
		if body == null:
			continue
		var ai := AiBot.new()
		ai.name = "Bot%d" % -peer
		ai.setup(self, body)
		add_child(ai)
		_bots[peer] = ai
		_stats[peer] = ai.stats
	_let_teammates_pass()
	if scenario == "tour":
		_plan_tour()
	elif scenario.begins_with("path:"):
		_plan_path()
	Log.info("ai", "%d bot(s) in this match (%s, seed %d): %d trap spots, %d vent bolt-holes" % [_bots.size(),
		difficulty().label, seed_base, world.trap_spots(nav, session.plant).size(), world.hideouts(nav).size()])


## Bot bodies of the same team pass through each other (see the header).
func _let_teammates_pass() -> void:
	var list := bots()
	for i in list.size():
		for j in range(i + 1, list.size()):
			if list[i].body.role == list[j].body.role:
				list[i].body.add_collision_exception_with(list[j].body)


func _clear_bots() -> void:
	for ai: AiBot in _bots.values():
		if is_instance_valid(ai):
			ai.queue_free()
	_bots.clear()
	for board: AiBlackboard in boards.values():
		board.clear()


## An AiBot whose body is gone (eliminated) removes itself.
func forget(peer: int) -> void:
	_bots.erase(peer)
	for board: AiBlackboard in boards.values():
		board.release_all(peer)


# --- Logging and the report ----------------------------------------------------------------

## A hard-stuck spot: in the log and in user://ai_stuck.csv.
func log_stuck(ai: AiBot, reason: String) -> void:
	var pos := ai.body.global_position
	Log.warn("ai", "%s is hard stuck at %s (%s, goal %s)" % [ai.body.display_name, pos.snapped(Vector3.ONE * 0.01),
		reason, ai.goal_label()])
	var exists := FileAccess.file_exists(STUCK_CSV)
	var file := FileAccess.open(STUCK_CSV, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	if not exists:
		file.store_line("time,name,role,x,y,z,goal,reason")
	file.store_line("%s,%s,%s,%.2f,%.2f,%.2f,%s,%s" % [Time.get_datetime_string_from_system(), ai.body.display_name,
		Role.display_name(ai.body.role).to_lower(), pos.x, pos.y, pos.z, ai.goal_label().replace(",", " "), reason])
	file.close()


## What the bots did this match (the test result file's "ai" section).
func report() -> Dictionary:
	var rows: Array = []
	for peer: int in _stats:
		var s: Dictionary = _stats[peer]
		var goals := {}
		for goal: String in s["goals"]:
			goals[goal] = snappedf(s["goals"][goal], 0.1)
		rows.append({"peer": peer, "name": s["name"], "role": Role.display_name(s["role"]).to_lower(),
			"distance": snappedf(s["distance"], 0.1), "goals": goals, "decisions": s["decisions"],
			"stuck_hard": s["stuck_hard"], "path_failures": s["path_failures"], "hazard_waits": s["hazard_waits"],
			"max_stall_s": snappedf(s["max_stall_s"], 0.1),
			"ms_per_tick": snappedf(float(s["cpu_us"]) / maxf(float(s["ticks"]), 1.0) / 1000.0, 0.001)})
	var out := {"seed": seed_base, "difficulty": difficulty().label, "bake_s": snappedf(nav.bake_seconds, 0.01),
		"bots": rows, "worst_frame_ms": snappedf(_worst_frame_ms, 0.001)}
	if scenario == "tour":
		out["tour"] = _tour
	return out


# --- --ai-scenario path:A:B ----------------------------------------------------------------------

func _plan_path() -> void:
	var parts := scenario.split(":")
	if parts.size() < 3 or _bots.is_empty():
		Log.error("ai", "--ai-scenario path:X,Y,Z:X,Y,Z expected, got %s" % scenario)
		return
	var points: Array[Vector3] = []
	for i in range(1, parts.size()):
		var n := parts[i].split_floats(",")
		points.append(Vector3(n[0], n[1], n[2]) if n.size() == 3 else Vector3.ZERO)
	var first: AiBot = _bots[_bots.keys().max()]  # (-1001)
	var targets: Array = []
	for i in range(1, points.size()):
		targets.append({"name": "point %d %s" % [i, points[i]], "pos": points[i], "node": null})
	_tour["targets"] = targets.size()
	_tour_left = 1
	first.start_tour(targets, true)
	_path_start = points[0]
	for ai: AiBot in _bots.values():
		if ai != first:
			ai.goals.clear()


func _place_path_start() -> void:
	var first: AiBot = _bots.get(_bots.keys().max())
	if first != null:
		first.body.server_force_position(_path_start)
		Log.info("ai", "path scenario: %s starts at %s" % [first.body.display_name, _path_start])


# --- --ai-scenario capture ---------------------------------------------------------------------

## Rats in front of the first cage, supervisors 6 m further out, facing them (a test set-up: the
## bots themselves never teleport).
func _set_up_capture() -> void:
	if world.cages.is_empty():
		return
	var cage := world.cages[0]
	for c in world.cages:
		if c.get_parent().name == "CageRoom":
			cage = c  # (the Cage Room's first cage, whatever the tree order)
			break
	var out := Vector3(cage.global_basis.z.x, 0.0, cage.global_basis.z.z).normalized()
	var rat_spot := nav.closest_point(Role.Kind.RAT, cage.global_position + out * 3.0)
	var sup_spot := nav.closest_point(Role.Kind.SUPERVISOR, rat_spot + out * 6.0)
	for ai: AiBot in _bots.values():
		var spot := rat_spot if ai.body.role == Role.Kind.RAT else sup_spot
		ai.body.server_force_position(spot)
		var to := rat_spot - spot
		if ai.body.role == Role.Kind.SUPERVISOR:
			ai.body.rotation.y = atan2(-to.x, -to.z)
		Log.info("ai", "capture scenario: %s at %s" % [ai.body.display_name, spot.snapped(Vector3.ONE * 0.1)])


# --- --ai-scenario hot | steal | cctv (phase E tests) ------------------------------------------

func _set_up_scenario() -> void:
	var rat_spot := Vector3.INF
	match scenario:
		"hot":
			session.plant.debug_set("core_temp", &"", HOT_CORE)
		"steal":
			session.plant.debug_set("health", &"pumps", 55.0)  # (needs a repair; its steam jets stay off)
			var point := world.repair_point(&"pumps")
			var stand := world.stand(point, Role.Kind.SUPERVISOR)
			var out := Vector3(point.global_basis.z.x, 0.0, point.global_basis.z.z).normalized()
			rat_spot = nav.closest_point(Role.Kind.RAT, stand + out * 5.0)
		"cctv":
			for camera in world.cameras:
				if camera.number == 8:
					rat_spot = nav.closest_point(Role.Kind.RAT, world.stand(camera, Role.Kind.RAT) + Vector3(0, 0, -1.5))
	if rat_spot == Vector3.INF:
		Log.info("ai", "%s scenario: the core is at %.0f" % [scenario, session.plant.core_temp])
		return
	for ai: AiBot in _bots.values():
		if ai.body.role == Role.Kind.RAT:
			ai.body.server_force_position(rat_spot)
			Log.info("ai", "%s scenario: %s at %s" % [scenario, ai.body.display_name, rat_spot.snapped(Vector3.ONE * 0.1)])


# --- --ai-scenario tour ------------------------------------------------------------------------

## Every target of each role, shared out between that role's bots (round robin, shuffled by the seed).
func _plan_tour() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	for role: Role.Kind in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		var targets := _tour_targets(role)
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
		for i in range(targets.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := targets[i]
			targets[i] = targets[j]
			targets[j] = tmp
		var team: Array[AiBot] = []
		for ai: AiBot in _bots.values():
			if ai.body.role == role:
				team.append(ai)
		if team.is_empty():
			continue
		_tour["targets"] += targets.size()
		var shares: Array = []
		for i in team.size():
			shares.append([])
		for i in targets.size():
			(shares[i % team.size()] as Array).append(targets[i])
		for i in team.size():
			team[i].start_tour(shares[i])
			_tour_left += 1


func _tour_targets(role: Role.Kind) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Array = [world.cages, world.cameras]
	if role == Role.Kind.RAT:
		kinds.append_array([world.sabotage_points, world.levers])
		for i in world.vent_exits.size():
			out.append({"name": "Vent exit %d" % (i + 1), "pos": world.vent_exits[i], "node": null})
	else:
		kinds.append_array([world.repair_points, world.consoles, world.actions, world.readers,
			world.pickups.filter(func(p: Pickup) -> bool: return p.item != "keycard")])
	for list: Array in kinds:
		for node: Interactable in list:
			out.append({"name": _describe(node), "pos": node.stand_position(role), "node": node})
	return out


func _describe(node: Interactable) -> String:
	if node is CctvCamera:
		return "Camera %d" % (node as CctvCamera).number
	var parent := node.get_parent()
	if node is KeycardReader:
		return "%s/%s/%s" % [parent.get_parent().name, parent.name, node.name]
	return "%s/%s" % [parent.name, node.name]


## A touring bot reached (or failed to reach) one of its targets.
func tour_result(ai: AiBot, target: String, reached: bool, reason: String = "") -> void:
	if reached:
		_tour["reached"] += 1
		Log.info("ai", "tour: %s reached %s" % [ai.body.display_name, target])
	else:
		(_tour["failed"] as Array).append("%s: %s (%s)" % [ai.body.display_name, target, reason])
		Log.warn("ai", "tour: %s could not reach %s (%s)" % [ai.body.display_name, target, reason])


func tour_finished(ai: AiBot) -> void:
	_tour_left -= 1
	Log.info("ai", "tour: %s is done" % ai.body.display_name)
	if _tour_left <= 0:
		session.match_manager.end_timer_now("every bot finished its tour")
