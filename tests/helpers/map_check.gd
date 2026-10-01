extends Node
## Map check (M5): bakes a navigation mesh per role from the level's collision geometry and checks
## the layout against the GDD §7 design rules. Paths, not straight lines: walls, doors and floors
## all count. Ladders, the rats' shaft and the one-way vent drop come from the level's
## NavigationLink3D nodes (navigation layer 1 = supervisors, 2 = rats).
##   godot --headless tests/helpers/MapCheck.tscn [-- --level test] [--report PATH]
## Checks (exit code 1 if one fails):
##   - supervisors reach every repair point, cage, pickup, camera and the CCTV chair from the
##     Control Room, and every repair point is at most MAX_SUPERVISOR_S away at walking speed
##   - rats reach every sabotage point / lever, cage and camera from the Rat Nest
##   - the Cage Room is at most MAX_RAT_TO_CAGES_S from the nest at rat walking speed
##   - every sabotage point / lever has two rat routes: one on foot without any vent (from the
##     South Corridor, where the nest's vent comes out), and a vent exit at most MAX_VENT_EXIT_M
##     away
##   - supervisors can't reach the Rat Nest, and have no walkable floor inside any vent
## The report (a Markdown table) goes to stdout and, with --report, to a file (docs/map/README.md
## quotes it).

const MAX_SUPERVISOR_S := 25.0
const MAX_RAT_TO_CAGES_S := 30.0
const MAX_VENT_EXIT_M := 25.0  ## path from a sabotage point to the nearest vent exit
const REACHED := 0.6  ## m: a path ending closer than this to its target reached it

class Agent:
	var label: String
	var radius: float
	var height: float
	var climb: float
	var speed: float
	var cell: float
	var layer: int
	var map: RID

	func _init(p_label: String, p_radius: float, p_height: float, p_climb: float, p_speed: float, p_cell: float, p_layer: int) -> void:
		label = p_label
		radius = p_radius
		height = p_height
		climb = p_climb
		speed = p_speed
		cell = p_cell
		layer = p_layer


var _session: Session
var _lines: Array[String] = []
var _failures := 0
var _rids: Array[RID] = []


func _ready() -> void:
	_session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_session)
	for i in 5:
		await get_tree().physics_frame
	var supervisor := Agent.new("Supervisor", 0.35, 1.8, 0.3, 4.0, 0.175, 1)
	var rat := Agent.new("Rat", 0.2, 0.5, 0.6, 5.0, 0.1, 2)
	var rat_on_foot := Agent.new("Rat without vents", 0.2, 0.5, 0.6, 5.0, 0.1, 2)
	var started := Time.get_ticks_msec()
	await _bake(supervisor, true)
	await _bake(rat, false)
	await _bake(rat_on_foot, false, true)
	_out("Navigation meshes baked in %.1f s (level: %s)." % [(Time.get_ticks_msec() - started) / 1000.0, Session.level_id()])
	_out("")
	_check_supervisors(supervisor)
	_check_rats(rat, rat_on_foot)
	_check_vents(supervisor)
	_out("")
	_out("**%s**" % ("All checks passed." if _failures == 0 else "%d check(s) FAILED." % _failures))
	if Cli.has_arg("report"):
		var file := FileAccess.open(Cli.get_str("report"), FileAccess.WRITE)
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	for rid in _rids:
		NavigationServer3D.free_rid(rid)
	get_tree().quit(1 if _failures > 0 else 0)


func _out(line: String) -> void:
	_lines.append(line)
	print(line)


# --- Baking ---------------------------------------------------------------------------------

## Bakes `agent`'s navigation mesh with doors open (all of them for supervisors, who have keycards;
## only the normal ones for rats) into its own navigation map, with the links it may use.
func _bake(agent: Agent, keycards: bool, without_vents: bool = false) -> void:
	for door in _session.level.find_children("*", "Node3D", true, false):
		if door is Door:
			var d := door as Door
			d.set_physics_process(false)  # offline, the server logic would close them again
			var open := d.auto_open or keycards
			d.panel.position = Vector3(d.panel.position.x, 1.3, d.panel.position.z) + (d.open_offset if open else Vector3.ZERO)
	await get_tree().physics_frame
	var mesh := NavigationMesh.new()
	mesh.cell_size = agent.cell
	mesh.cell_height = 0.05
	mesh.agent_radius = agent.radius
	mesh.agent_height = agent.height
	mesh.agent_max_climb = agent.climb
	mesh.agent_max_slope = 45.0
	mesh.edge_max_length = 4.0  # long thin vent polygons otherwise come out broken
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = PhysicsLayers.WORLD
	var source := NavigationMeshSourceGeometryData3D.new()
	var vents := _session.level.get_node_or_null("POIs/VentNetwork") as Node3D
	var vents_parent := vents.get_parent() if vents != null else null
	if without_vents and vents != null:
		vents_parent.remove_child(vents)
	NavigationServer3D.parse_source_geometry_data(mesh, source, _session.level)
	if without_vents and vents != null:
		vents_parent.add_child(vents)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	agent.map = NavigationServer3D.map_create()
	_rids.append(agent.map)
	NavigationServer3D.map_set_cell_size(agent.map, agent.cell)
	NavigationServer3D.map_set_cell_height(agent.map, 0.05)
	NavigationServer3D.map_set_active(agent.map, true)
	var region := NavigationServer3D.region_create()
	_rids.append(region)
	NavigationServer3D.region_set_map(region, agent.map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	for node in _session.level.find_children("*", "NavigationLink3D", true, false):
		var link_node := node as NavigationLink3D
		if link_node.navigation_layers & agent.layer == 0 or (without_vents and vents.is_ancestor_of(link_node)):
			continue
		var link := NavigationServer3D.link_create()
		_rids.append(link)
		NavigationServer3D.link_set_map(link, agent.map)
		NavigationServer3D.link_set_bidirectional(link, link_node.bidirectional)
		NavigationServer3D.link_set_start_position(link, link_node.global_transform * link_node.start_position)
		NavigationServer3D.link_set_end_position(link, link_node.global_transform * link_node.end_position)
	while NavigationServer3D.map_get_iteration_id(agent.map) == 0 \
			or NavigationServer3D.map_get_closest_point(agent.map, Vector3.ZERO) == Vector3.ZERO:
		await get_tree().physics_frame
	await get_tree().physics_frame


## [length, reached] of the path from `from` to `to` on `agent`'s map.
func _path(agent: Agent, from: Vector3, to: Vector3) -> Array:
	var points := NavigationServer3D.map_get_path(agent.map, from, to, true)
	if points.is_empty():
		return [INF, false]
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
	var start_gap := points[0].distance_to(from)
	var end_gap := points[points.size() - 1].distance_to(to)
	return [length, start_gap < REACHED and end_gap < REACHED]


# --- Checks ---------------------------------------------------------------------------------

func _targets(kinds: Array[String], role: Role.Kind) -> Array[Array]:
	var out: Array[Array] = []
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		var kind: String = it.get_script().get_global_name()
		if kind in kinds and _session.level.is_ancestor_of(it):
			out.append([_describe(it), it.stand_position(role), kind])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func _describe(it: Interactable) -> String:
	if it is CctvCamera:
		return "Camera %d (%s)" % [(it as CctvCamera).number, (it as CctvCamera).label]
	if it.get("subsystem_id") != null:
		return "%s %s" % [it.get("subsystem_id"), it.name]
	return "%s %s" % [it.get_parent().name, it.name] if it.get_parent() != _session.level else str(it.name)


func _spawn(role: Role.Kind) -> Vector3:
	var points := _session.spawn_points_for(role)
	return points[0].global_position if not points.is_empty() else Vector3.ZERO


func _control_room() -> Vector3:
	for node in get_tree().get_nodes_in_group(CctvConsole.CONSOLE_GROUP):
		return (node as Node3D).global_position + Vector3(0, 0, -3)  # in front of the chair
	return _spawn(Role.Kind.SUPERVISOR)


func _check_supervisors(agent: Agent) -> void:
	var from := _control_room()
	_out("### Supervisors (from the Control Room, walking at %.0f m/s)" % agent.speed)
	_out("")
	_out("| Target | Path | Time | Rule |")
	_out("|---|---|---|---|")
	for t in _targets(["RepairPoint", "Cage", "Pickup", "CctvCamera", "CctvConsole", "KeycardReader"], Role.Kind.SUPERVISOR):
		var result := _path(agent, from, t[1])
		var rule := ""
		var ok: bool = result[1]
		if t[2] == "RepairPoint":
			var fast: bool = result[0] / agent.speed <= MAX_SUPERVISOR_S
			rule = "≤ %d s %s" % [MAX_SUPERVISOR_S, "ok" if fast and ok else "**FAIL**"]
			ok = ok and fast
		_row(t[0], result, agent, rule, ok)
	var nest := _path(agent, from, _spawn(Role.Kind.RAT))
	_out("| Rat Nest | %s | | must be unreachable %s |" % ["unreachable" if not nest[1] else "%.0f m" % nest[0],
		"ok" if not nest[1] else "**FAIL**"])
	if nest[1]:
		_failures += 1
	_out("")


func _check_rats(agent: Agent, on_foot: Agent) -> void:
	var from := _spawn(Role.Kind.RAT)
	_out("### Rats (from the Rat Nest, walking at %.0f m/s)" % agent.speed)
	_out("")
	_out("Second route: on foot from the South Corridor with every vent sealed, and the nearest vent exit.")
	_out("")
	_out("| Target | Path | Time | Rule | On foot | Nearest vent exit |")
	_out("|---|---|---|---|---|---|")
	var corridor := _nest_exit()
	for t in _targets(["SabotagePoint", "CriticalLever", "Cage", "CctvCamera"], Role.Kind.RAT):
		var result := _path(agent, from, t[1])
		var rule := ""
		var ok: bool = result[1]
		var extra := "  |  |"
		if t[2] == "Cage":
			var fast: bool = result[0] / agent.speed <= MAX_RAT_TO_CAGES_S
			rule = "≤ %d s %s" % [MAX_RAT_TO_CAGES_S, "ok" if fast and ok else "**FAIL**"]
			ok = ok and fast
		elif t[2] in ["SabotagePoint", "CriticalLever"]:
			var foot := _path(on_foot, corridor, t[1])
			var vent := _nearest_vent_exit(agent, t[1])
			var foot_ok: bool = foot[1]
			var vent_ok: bool = vent < MAX_VENT_EXIT_M
			extra = " %s | %s |" % ["%.0f m" % foot[0] if foot_ok else "**none**",
				"%.0f m%s" % [vent, "" if vent_ok else " **> %d m**" % MAX_VENT_EXIT_M] if vent < INF else "**none**"]
			ok = ok and foot_ok and vent_ok
		_row(t[0], result, agent, rule, ok, extra)
	var control := _path(agent, from, _control_room())
	_row("Control Room", control, agent, "", control[1], "  |  |")
	_out("")


func _row(target: String, result: Array, agent: Agent, rule: String, ok: bool, extra: String = "") -> void:
	var reached: bool = result[1]
	var path := "%.0f m" % result[0] if reached else "**unreachable**"
	var time := "%.1f s" % (result[0] / agent.speed) if reached else ""
	if not ok:
		_failures += 1
		if rule == "":
			rule = "**FAIL**"
	_out("| %s | %s | %s | %s |%s" % [target, path, time, rule, extra])


## Where the nest's vent comes out in the South Corridor: the nearest vent exit to the nest.
func _nest_exit() -> Vector3:
	var nest := _spawn(Role.Kind.RAT)
	var best := nest
	var best_d := INF
	for node in get_tree().get_nodes_in_group("vent_exits"):
		var p := (node as Node3D).global_position
		if p.distance_to(nest) < best_d:
			best_d = p.distance_to(nest)
			best = p
	return best


## Path length from `target` to the closest vent exit (INF if none is reachable).
func _nearest_vent_exit(agent: Agent, target: Vector3) -> float:
	var best := INF
	for node in get_tree().get_nodes_in_group("vent_exits"):
		var result := _path(agent, target, (node as Node3D).global_position)
		if result[1]:
			best = minf(best, result[0])
	return best


## No supervisor floor inside a vent: sample every vent volume and look for supervisor navmesh there.
func _check_vents(agent: Agent) -> void:
	var bad: Array[String] = []
	var samples := 0
	for node in get_tree().get_nodes_in_group(VentVolume.GROUP):
		var vent := node as VentVolume
		var shape := vent.get_node_or_null("Shape") as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D:
			continue
		var size := (shape.shape as BoxShape3D).size
		var steps := maxi(1, ceili(maxf(size.x, size.z) / 2.0))
		for i in steps + 1:
			var local := Vector3(lerpf(-size.x / 2, size.x / 2, float(i) / steps) if size.x > size.z else 0.0,
				-size.y / 2 + 0.05, lerpf(-size.z / 2, size.z / 2, float(i) / steps) if size.z >= size.x else 0.0)
			var point := shape.global_transform * local
			samples += 1
			var closest := NavigationServer3D.map_get_closest_point(agent.map, point)
			var inside := (shape.global_transform.affine_inverse() * closest).abs()
			if inside.x < size.x / 2 - 0.05 and inside.y < size.y / 2 and inside.z < size.z / 2 - 0.05:
				bad.append("%s at %s" % [vent.name, point])
	var ok := bad.is_empty()
	_out("Supervisor floor inside vents: %s (%d samples)%s" % ["none, ok" if ok else "**FOUND**", samples,
		"" if ok else ": " + ", ".join(bad)])
	if not ok:
		_failures += 1
