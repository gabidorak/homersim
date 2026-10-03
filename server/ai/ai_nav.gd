class_name AiNav
extends RefCounted
## Navigation for the AI bots (M10, ARCHITECTURE §6 AI bots): one navigation mesh per role, baked
## from the level's static colliders (layer WORLD) into its own NavigationServer map, plus the links
## a body of that role can take. tests/helpers/map_check.gd bakes with this same code, so the map
## check validates exactly the meshes the bots walk on.
##
##   - Auto doors are left out of the bake (anyone opens them by walking up). Keycard doors stay
##     closed: each gets a link through it on navigation layer KEYCARD_LAYER, which supervisors
##     query only while they hold a keycard (path(..., keycard = true)).
##   - The level's NavigationLink3Ds are copied per role (navigation layer 1 = supervisors,
##     2 = rats): the yard ladder, the rats' vent shaft, the one-way drop into the Control Room.
##   - Paths come with what each link is (Link: a ladder, a drop, a keycard door), so the path
##     follower knows how to cross it.
## Every RID is freed by release() (the Session's exit), or the tests flag the leaks.

const KEYCARD_LAYER := 4
const CELL_HEIGHT := 0.05
const MAX_SLOPE := 45.0
const EDGE_MAX_LENGTH := 4.0  ## long thin vent polygons otherwise come out broken
const KEYCARD_LINK_OFFSET := 1.2  ## m from a keycard door's centre to each end of its link
const LADDER_SEARCH := 3.0  ## m: a link with a Ladder volume this close is a ladder

## What a body of one role can walk on.
class Agent:
	var label: String
	var role: Role.Kind
	var radius: float
	var height: float
	var climb: float
	var cell: float
	var link_layer: int  ## which of the level's NavigationLink3Ds it may take
	var speed: float  ## walking speed (path times)
	var map: RID

	func _init(p_label: String, p_role: Role.Kind, p_radius: float, p_height: float, p_climb: float,
			p_cell: float, p_link_layer: int) -> void:
		label = p_label
		role = p_role
		radius = p_radius
		height = p_height
		climb = p_climb
		cell = p_cell
		link_layer = p_link_layer
		speed = Role.data(p_role).walk_speed


## A link on a path and how to cross it.
class Link:
	var kind := AiPathFollower.LinkKind.NONE
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var up := Vector3.ZERO  ## ladders: Ladder.up_direction()
	var foot := Vector3.ZERO  ## ladders: the Ladder node's position (the bottom of its line)
	var door: Door  ## keycard doors
	var rid: RID


## A path: its points and, for each segment i (points[i] → points[i + 1]), the Link it crosses or null.
class Path:
	var points := PackedVector3Array()
	var links: Array = []
	var length := 0.0

	func is_empty() -> bool:
		return points.is_empty()

	func end() -> Vector3:
		return points[points.size() - 1] if not points.is_empty() else Vector3.INF


var agents: Dictionary = {}  ## Role.Kind (or a custom key) -> Agent
var bake_seconds := 0.0

var _links: Dictionary = {}  # link RID -> Link
var _rids: Array[RID] = []


## The agent specs (the same as the map check always used).
static func supervisor_agent() -> Agent:
	return Agent.new("Supervisor", Role.Kind.SUPERVISOR, 0.35, 1.8, 0.3, 0.175, 1)


static func rat_agent() -> Agent:
	return Agent.new("Rat", Role.Kind.RAT, 0.2, 0.5, 0.6, 0.1, 2)


## Bakes both roles' meshes (awaitable). Wait at least 2 physics frames after the level enters the
## tree first: the stand positions and the parse need its shapes.
func bake(level: Node3D) -> void:
	var started := Time.get_ticks_msec()
	for agent: Agent in [supervisor_agent(), rat_agent()]:
		await bake_agent(agent, level)
		agents[agent.role] = agent
	bake_seconds = (Time.get_ticks_msec() - started) / 1000.0


## Bakes `agent`'s mesh into its own map, with the links it may use (awaitable). `skip` (map check):
## a subtree left out of the bake, along with its links.
func bake_agent(agent: Agent, level: Node3D, skip: Node3D = null) -> void:
	var mesh := NavigationMesh.new()
	mesh.cell_size = agent.cell
	mesh.cell_height = CELL_HEIGHT
	mesh.agent_radius = agent.radius
	mesh.agent_height = agent.height
	mesh.agent_max_climb = agent.climb
	mesh.agent_max_slope = MAX_SLOPE
	mesh.edge_max_length = EDGE_MAX_LENGTH
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = PhysicsLayers.WORLD
	var source := NavigationMeshSourceGeometryData3D.new()
	# Auto doors open for anyone: leave their panels out (their layer off during the parse only).
	var doors := _doors(level)
	var layers := {}
	for door in doors:
		if door.auto_open:
			layers[door] = door.panel.collision_layer
			door.panel.collision_layer = 0
	var skip_parent := skip.get_parent() if skip != null else null
	if skip != null:
		skip_parent.remove_child(skip)
	NavigationServer3D.parse_source_geometry_data(mesh, source, level)
	if skip != null:
		skip_parent.add_child(skip)
	for door: Door in layers:
		door.panel.collision_layer = layers[door]
	var done := [false]
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func() -> void: done[0] = true)
	while not done[0]:
		await level.get_tree().process_frame

	agent.map = _keep(NavigationServer3D.map_create())
	NavigationServer3D.map_set_cell_size(agent.map, agent.cell)
	NavigationServer3D.map_set_cell_height(agent.map, CELL_HEIGHT)
	NavigationServer3D.map_set_active(agent.map, true)
	var region := _keep(NavigationServer3D.region_create())
	NavigationServer3D.region_set_map(region, agent.map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	var ladders := level.find_children("*", "Area3D", true, false).filter(func(n: Node) -> bool: return n is Ladder)
	for node in level.find_children("*", "NavigationLink3D", true, false):
		var link_node := node as NavigationLink3D
		if link_node.navigation_layers & agent.link_layer == 0 or (skip != null and skip.is_ancestor_of(link_node)):
			continue
		var link := Link.new()
		link.start = link_node.global_transform * link_node.start_position
		link.end = link_node.global_transform * link_node.end_position
		var ladder := _ladder_near(ladders, link)
		if ladder != null:
			link.kind = AiPathFollower.LinkKind.LADDER
			link.up = ladder.up_direction()
			link.foot = ladder.global_position
		elif link.end.y < link.start.y - 1.0:
			link.kind = AiPathFollower.LinkKind.DROP
		else:
			link.kind = AiPathFollower.LinkKind.WALK
		_add_link(agent.map, link, link_node.bidirectional, 1)
	if agent.role == Role.Kind.SUPERVISOR:
		for door in doors:
			if door.auto_open:
				continue
			var link := Link.new()
			link.kind = AiPathFollower.LinkKind.KEYCARD
			link.door = door
			link.start = door.global_transform * Vector3(0, 0, KEYCARD_LINK_OFFSET)
			link.end = door.global_transform * Vector3(0, 0, -KEYCARD_LINK_OFFSET)
			_add_link(agent.map, link, true, KEYCARD_LAYER)
	# The map syncs on the next physics frames: wait until it answers queries.
	while NavigationServer3D.map_get_iteration_id(agent.map) == 0 \
			or NavigationServer3D.map_get_closest_point(agent.map, Vector3.ZERO) == Vector3.ZERO:
		await level.get_tree().physics_frame
	await level.get_tree().physics_frame


func _add_link(map: RID, link: Link, bidirectional: bool, layers: int) -> void:
	link.rid = _keep(NavigationServer3D.link_create())
	NavigationServer3D.link_set_map(link.rid, map)
	NavigationServer3D.link_set_bidirectional(link.rid, bidirectional)
	NavigationServer3D.link_set_navigation_layers(link.rid, layers)
	NavigationServer3D.link_set_start_position(link.rid, link.start)
	NavigationServer3D.link_set_end_position(link.rid, link.end)
	_links[link.rid] = link


func _ladder_near(ladders: Array, link: Link) -> Ladder:
	var mid := (link.start + link.end) * 0.5
	for node in ladders:
		var ladder := node as Ladder
		var offset := ladder.global_position - mid
		if absf(link.end.y - link.start.y) > 1.0 and Vector2(offset.x, offset.z).length() < LADDER_SEARCH:
			return ladder
	return null


func _doors(level: Node3D) -> Array[Door]:
	var out: Array[Door] = []
	for node in level.find_children("*", "Node3D", true, false):
		if node is Door:
			out.append(node)
	return out


func _keep(rid: RID) -> RID:
	_rids.append(rid)
	return rid


func agent_for(role: Variant) -> Agent:
	return agents.get(role)


func is_ready() -> bool:
	return agents.has(Role.Kind.SUPERVISOR) and agents.has(Role.Kind.RAT)


## The path for `agent` from `from` to `to`, with what each segment crosses. `keycard` (supervisors):
## keycard doors are open to it.
func path_for(agent: Agent, from: Vector3, to: Vector3, keycard: bool = false) -> Path:
	var params := NavigationPathQueryParameters3D.new()
	params.map = agent.map
	params.start_position = from
	params.target_position = to
	params.navigation_layers = 1 | (KEYCARD_LAYER if keycard else 0)
	params.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES \
		| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_RIDS
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(params, result)
	var out := Path.new()
	out.points = result.path
	out.links.resize(maxi(out.points.size() - 1, 0))
	var types := result.path_types
	var rids := result.path_rids
	for i in range(out.points.size() - 1):
		var link: Link = null
		if i < types.size() and types[i] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			link = _links.get(rids[i])
		if link == null and i + 1 < types.size() and types[i + 1] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			link = _links.get(rids[i + 1])
		# A link's segment goes from (near) one of its ends to the other.
		if link != null and not _spans(link, out.points[i], out.points[i + 1]):
			link = null
		out.links[i] = link
		out.length += out.points[i].distance_to(out.points[i + 1])
	return out


## The path for `role` (a Role.Kind or a custom agent key).
func path(role: Variant, from: Vector3, to: Vector3, keycard: bool = false) -> Path:
	var agent := agent_for(role)
	return path_for(agent, from, to, keycard) if agent != null else Path.new()


static func _spans(link: Link, a: Vector3, b: Vector3) -> bool:
	const NEAR := 0.6
	return (a.distance_to(link.start) < NEAR and b.distance_to(link.end) < NEAR) \
		or (a.distance_to(link.end) < NEAR and b.distance_to(link.start) < NEAR)


## The closest point of `role`'s mesh to `point`.
func closest_point(role: Variant, point: Vector3) -> Vector3:
	var agent := agent_for(role)
	return NavigationServer3D.map_get_closest_point(agent.map, point) if agent != null else point


## Frees every RID (call it once, when the session ends).
func release() -> void:
	for rid in _rids:
		NavigationServer3D.free_rid(rid)
	_rids.clear()
	_links.clear()
	agents.clear()
