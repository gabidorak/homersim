class_name OutroPhysics
extends RefCounted
## The physics consistency checks of the end-of-match cinematics (client/outro/outro.gd), for
## tests/unit/test_outro.gd. Everything there that moves is a function of the clock, so this seeks a
## whole timeline every STEP (1/120 s) and measures, at every step:
##   - nothing goes through anything: the slices against the toaster (its walls and base; a slice is
##     inside a slot only while it's in the toaster), the plate (its real profile: a flat centre and
##     a sloping rim), the counter and the things on it, grandma and each other; grandma against the
##     toaster, the counter, the plate, her cup and the butter dish;
##   - what rests, rests: a slice on the plate or on the other slice, the limp one on the toaster's
##     top, grandma's slippers on the floor (unless she hops), the toaster, plate, cup and butter dish
##     on the counter: no deeper than PENETRATION, no higher than CONTACT;
##   - the lever goes down only under grandma's hand, which touches its knob (and it comes back up
##     only when the toaster pops it);
##   - the slices fly like thrown things: gravity is G all along their flights but in their
##     deliberate hang at the top, and they never jump from one place to another;
##   - the camera is never inside anything (nor so close its near plane cuts into it).
## Shapes. A slice is the box of its mesh (in the slice's frame: it turns and squashes with it), so
## is what the slices meet on the counter; the toaster is its body's box minus its two slots, the
## plate its real profile. Grandma, and what she meets, are cut in cells: each piece of the mesh
## (a sphere, a rounded box, a lathed dress...), split in smaller cells when it's big, each cell the
## roundest box that still holds its part of the surface: as round as she is, never smaller, and
## following its bone. A slice meets her with points all over its real surface (its rounded
## outline, not its box). Her slippers and her hand on the lever are checked with their vertices.
##
## The rats. In the dark (RATS) each rat sits on what its spot says (Outro.spots(): the counter, the
## fridge, the windowsill, her plate) while it's there, no deeper than PENETRATION and no higher than
## CONTACT, and never goes into a prop; its eyes, when they open, are seen from the camera (no mesh and
## no piece of grandma on the way), and so is the last pair, by her face. The caged rat (SUPERVISORS)
## stays inside its cage, sits on its floor (but for its hop) and never goes into the bars, the
## wheel or the bowl; the cage stands on the sink counter, in nothing. A rat is checked with its
## vertices (rigid skin, like grandma's: each follows its bone), against the props' cells.
##
## run() returns the problems, one line each with its worst moment (empty: all good). A test passes
## a `tweak` to break a timeline on purpose (a slice pushed into the plate...): the checks must
## catch it.

const STEP := 1.0 / 120.0
const PENETRATION := 0.001  ## m: deeper than this, two things are inside each other
const CONTACT := 0.002  ## m: a resting thing is at most this far from what it rests on
const CAMERA_MARGIN := 0.03  ## m: the camera's near plane (0.02) and the corners of its view
const MAX_SPEED := 4.0  ## m/s: no slice moves faster (the launch is 3.3 m/s): faster is a jump
const SURFACE_SPACING := 0.005  ## m between the points sampled over a slice's surface
## The toaster's body rounds its edges at least this much (kitchen.py: 0.02 along the top, 0.06 up
## the corners): her hands meet it as a box rounded this much.
const TOASTER_RADIUS := 0.02
## The toaster's body depth (kitchen.py TOASTER_D): its mesh's AABB also holds the chrome trim on its
## front, which stands out below the slots (where nothing goes).
const TOASTER_D := 0.17
## The toaster's slots (tools/blender/kitchen.py SLOT_L, SLOT_W, SLOT_FLOOR): their length (x),
## width (z) and the height of their floor over the toaster's base. Where they are comes from the
## model (its Slot1 and Slot2 empties), and the body's size from its mesh.
const SLOT_L := 0.15
const SLOT_W := 0.026
const SLOT_FLOOR := 0.035
## The lever's knob (kitchen.py KNOB, in Godot axes; the Lever part's pivot is its centre) and the
## rounding of its edges.
const KNOB := Vector3(0.03, 0.022, 0.05)
const KNOB_RADIUS := 0.008
## The plate's top (kitchen.py build_plate): its height over the plate's foot, out from its centre.
const PLATE_PROFILE: Array[Vector2] = [Vector2(0.0, 0.01), Vector2(0.085, 0.01), Vector2(0.1, 0.014),
	Vector2(0.12, 0.02), Vector2(0.123, 0.017)]
## Grandma's bones whose pieces the slices and the camera meet. Her face's shapes (eyes, brows,
## mouths, cheeks) lie on the front of her head and scale in place.
const BODY_BONES: Array[String] = ["hips", "torso", "head", "bun", "glasses", "arm_l", "arm_r", "forearm_l",
	"forearm_r", "hand_l", "hand_r", "thumb_l", "thumb_r", "leg_l", "leg_r"]
## The slice she holds is in her left hand: that hand and its thumb grip it.
const GRIP_BONES: Array[String] = ["hand_l", "thumb_l"]
## At the bite her lips close over a corner of the slice: it may go this deep into her head then
## (s around Outro.A_BITE), and it must reach her mouth (tools/blender/grandma.py MOUTH, in the head
## bone's space) to within BITE_REACH.
const BITE_DEPTH := 0.02
const BITE_WINDOW := Vector2(-0.1, 0.05)
const MOUTH := Vector3(0.0, 0.072, 0.195)
const BITE_REACH := 0.015
## The hang may slow a slice harder than gravity (it stops in mid-air), never push it up.
const HANG_PULL := 1.5  ## x G
## Pieces bigger than this (m) are cut in cells: grandma's, and the props' (the counter is boxes; the
## round things are cut finer). Smaller cells fit round and hollow things closer, at a cost. A piece
## a rounded box already fits (every vertex within TIGHT of its surface: a sphere, a rounded box) stays
## whole, whatever its size.
const CELL := 0.1
const TIGHT := 0.004
const PROP_CELLS := {"the toaster": 0.06, "the lever": 0.05, "the counter": 0.3, "the plate": 0.06, "her cup": 0.05,
	"the butter dish": 0.08, "the cage": 0.05, "the fridge": 0.3, "the window": 0.1, "the sink counter": 0.15}
## The rats are checked every RAT_STEP (they sit and nibble: slower than the slices).
const RAT_STEP := 1.0 / 30.0
const FRIDGE_TOP := 1.45  ## kitchen.py build_fridge H
## The cage (tools/blender/intro_props.py, in its own space, unscaled): its floor (the tray's top: the
## bedding is under it), and the room inside its bars and under its roof.
const CAGE_FLOOR := 0.08
const CAGE_INSIDE := AABB(Vector3(-0.305, 0.075, -0.195), Vector3(0.61, 0.403, 0.39))
## A hit on the way to an eye this close to it is what it sits on (an eye on the cat clock's face).
const EYE_CLEARANCE := 0.03
## The last pair of eyes is right by her face: within this of her head's middle.
const BUTTON_REACH := 0.42

# Cut once per process (the cells take a moment): mesh id -> ...
static var _surfaces: Dictionary[int, PackedVector3Array] = {}  # points over its surface (its space)
static var _mesh_cells: Dictionary[int, Array] = {}  # its cells [Piece] (its space)
static var _grandmas: Dictionary[int, Dictionary] = {}  # {pieces: bone -> [Piece], points: bone -> vertices, reach}
static var _actors: Dictionary[int, Dictionary] = {}  # a rat's mesh -> {bone -> its vertices (bone space)}
static var _triangles: Dictionary[int, TriangleMesh] = {}  # a mesh -> its triangles (for the eyes' sight lines)

var outro: Outro
var _problems: Dictionary[String, Dictionary] = {}  # key -> {text, worst, at, from, to, count}
var _skeleton: Skeleton3D
var _pieces: Dictionary[String, Array] = {}  # bone -> [Piece]
var _bone_points: Dictionary[String, PackedVector3Array] = {}  # bone -> its vertices (its space)
var _bone_reach: Dictionary[String, Vector4] = {}  # bone -> sphere holding its pieces (its space): centre, radius
var _bone_now: Dictionary[String, Transform3D] = {}  # this step's bone transforms
var _boxes_now: Dictionary[String, Array] = {}  # this step's cells of a bone [Box]
var _toaster_solid: Array[AABB] = []  # in the toaster's frame
## What grandma meets: the toaster (its body and lever), the counter, the plate, her cup, the butter.
## Each {name, mesh, cells (its space), boxes (now), centre, reach}.
var _furniture: Array[Dictionary] = []
var _slots: Array[AABB] = []
var _samples: Array[Dictionary] = []  # per step: {t, toasts (positions), states, lever, contact}
var _rat_props: Array[Dictionary] = []  # what the rats mustn't go into: like _furniture, and the fridge, window...
var _cage_boxes: Array[Box] = []  # the cage's cells (SUPERVISORS)
var _tweak := Callable()
var _next_rat_check := 0.0


## A box in the world: a frame (orthonormal), half sizes, and an all-round rounding (0: sharp).
class Box:
	var name := ""
	var origin := Vector3.ZERO
	var basis := Basis.IDENTITY
	var half := Vector3.ZERO  ## the inner box: the shape is this grown by `radius` all round
	var radius := 0.0
	var reach := 0.0  ## the radius of a sphere holding it (from its centre)
	var extent := Vector3.ZERO  ## the half size of a world box holding it (for quick rejection)
	var empty := false  ## scaled to nothing (a hidden piece): meets nothing

	## The box of `aabb` (in the frame `xform`, which may be scaled), rounded by `radius_` (in that frame).
	static func make(name_: String, xform: Transform3D, aabb: AABB, radius_ := 0.0) -> Box:
		var box := Box.new()
		box.name = name_
		var scale := xform.basis.get_scale().abs()
		box.empty = scale.x < 1e-4 or scale.y < 1e-4 or scale.z < 1e-4
		box.basis = xform.basis.orthonormalized() if not box.empty else Basis.IDENTITY
		box.origin = xform * aabb.get_center()
		box.half = aabb.size * 0.5 * scale
		box.radius = radius_ * (scale.x + scale.y + scale.z) / 3.0
		box.reach = box.half.length() + box.radius
		box.extent = box.basis.x.abs() * box.half.x + box.basis.y.abs() * box.half.y + box.basis.z.abs() * box.half.z 			+ Vector3.ONE * box.radius
		return box

	## Whether the world boxes holding `self` and `other` overlap (with `slack`): if not, they can't meet.
	func near(other: Box, slack := 0.0) -> bool:
		var d := (other.origin - origin).abs()
		var e := extent + other.extent + Vector3.ONE * slack
		return d.x <= e.x and d.y <= e.y and d.z <= e.z

	func to_local(p: Vector3) -> Vector3:
		return (p - origin) * basis

	## The point of the inner box nearest to `p`.
	func closest(p: Vector3) -> Vector3:
		return origin + basis * to_local(p).clamp(-half, half)

	## How far `p` is outside the shape (negative: inside, that deep).
	func sdf(p: Vector3) -> float:
		if empty:
			return INF
		var q := to_local(p).abs() - half
		var out := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
		return out + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - radius

	func bound() -> float:
		return reach

	func corners() -> Array[Vector3]:
		var out: Array[Vector3] = []
		for i in 8:
			var s := Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1)
			out.append(origin + basis * (half * s))
		return out

	## Points over its edges, about `spacing` m apart, and its corners.
	func edge_points(spacing: float) -> Array[Vector3]:
		var out: Array[Vector3] = corners()
		for axis in 3:
			var n := maxi(int(half[axis] * 2.0 / spacing), 1)
			for j in range(1, n):
				var u := -1.0 + 2.0 * j / n
				for s1: float in [-1.0, 1.0]:
					for s2: float in [-1.0, 1.0]:
						var l := Vector3.ZERO
						l[axis] = u * half[axis]
						l[(axis + 1) % 3] = s1 * half[(axis + 1) % 3]
						l[(axis + 2) % 3] = s2 * half[(axis + 2) % 3]
						out.append(origin + basis * l)
		return out

	func lowest() -> float:
		return origin.y - (absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z) - radius

	func highest() -> float:
		return origin.y + (absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z) + radius


## A piece of a surface (a cell of grandma, of a prop) as the roundest box holding it, in a frame of
## its own (`basis`, in its mesh's or bone's space: the points' own axes, or the space's when they
## fit closer, so a tilted rounded box is fitted exactly).
class Piece:
	var basis := Basis.IDENTITY
	var aabb := AABB()  ## the inner box, in `basis` (the shape is this grown by radius)
	var radius := 0.0

	static func fit(points: PackedVector3Array) -> Piece:
		var best: Piece = null
		for frame: Basis in [Basis.IDENTITY, OutroPhysics.principal_axes(points)]:
			var piece := Piece.new()
			piece.basis = frame
			var local := PackedVector3Array()
			local.resize(points.size())
			for i in points.size():
				local[i] = points[i] * frame  # (orthonormal: the transpose takes points into it)
			piece._fit_local(local)
			if best == null or piece.volume() < best.volume() - 1e-9:
				best = piece
		return best

	func _fit_local(points: PackedVector3Array) -> void:
		var box := AABB(points[0], Vector3.ZERO)
		for p in points:
			box = box.expand(p)
		var centre := box.get_center()
		var half := box.size * 0.5
		var lo := 0.0
		var hi := minf(half.x, minf(half.y, half.z))
		for i in 18:
			var r := (lo + hi) * 0.5
			if _deepest_outside(points, centre, half - Vector3.ONE * r, r) <= 1e-5:
				lo = r
			else:
				hi = r
		radius = lo
		aabb = AABB(centre - half + Vector3.ONE * lo, (half - Vector3.ONE * lo) * 2.0)

	func volume() -> float:
		var s := aabb.size + Vector3.ONE * radius * 2.0
		return s.x * s.y * s.z

	## Whether every one of `points` is within TIGHT of its surface: it's their shape, not a box around it.
	func holds_tightly(points: PackedVector3Array) -> bool:
		var centre := aabb.get_center()
		var inner := aabb.size * 0.5
		for p in points:
			var q := (p * basis - centre).abs() - inner
			var d := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() \
				+ minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - radius
			if d < -TIGHT:
				return false
		return true

	static func _deepest_outside(points: PackedVector3Array, centre: Vector3, inner: Vector3, r: float) -> float:
		var worst := -INF
		for p in points:
			var q := (p - centre).abs() - inner
			var d := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() \
				+ minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r
			if d > 1e-5:
				return d
			worst = maxf(worst, d)
		return worst


## The axes of `points`: their covariance's eigenvectors (Jacobi rotations), as an orthonormal basis.
static func principal_axes(points: PackedVector3Array) -> Basis:
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= points.size()
	var m: Array[PackedFloat64Array] = [PackedFloat64Array([0, 0, 0]), PackedFloat64Array([0, 0, 0]),
		PackedFloat64Array([0, 0, 0])]
	var rows: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for p in points:
		var d := p - c
		rows[0] += d * d.x
		rows[1] += d * d.y
		rows[2] += d * d.z
	for i in 3:
		m[i] = PackedFloat64Array([rows[i].x, rows[i].y, rows[i].z])
	var v: Array[PackedFloat64Array] = [PackedFloat64Array([1, 0, 0]), PackedFloat64Array([0, 1, 0]),
		PackedFloat64Array([0, 0, 1])]
	for sweep in 16:
		for pq: Vector2i in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
			var p := pq.x
			var q := pq.y
			if absf(m[p][q]) < 1e-14:
				continue
			var theta := (m[q][q] - m[p][p]) / (2.0 * m[p][q])
			var t := (1.0 if theta >= 0.0 else -1.0) / (absf(theta) + sqrt(theta * theta + 1.0))
			var cs := 1.0 / sqrt(t * t + 1.0)
			var sn := t * cs
			for k in 3:  # m = Jᵀ m J, column then row
				var mkp := m[k][p]
				var mkq := m[k][q]
				m[k][p] = cs * mkp - sn * mkq
				m[k][q] = sn * mkp + cs * mkq
			for k in 3:
				var mpk := m[p][k]
				var mqk := m[q][k]
				m[p][k] = cs * mpk - sn * mqk
				m[q][k] = sn * mpk + cs * mqk
			for k in 3:  # v = v J
				var vkp := v[k][p]
				var vkq := v[k][q]
				v[k][p] = cs * vkp - sn * vkq
				v[k][q] = sn * vkp + cs * vkq
	# The axis that stands out (its spread furthest from the other two: a rod's length, a slab's
	# thickness)...
	var axes: Array[Vector3] = []
	for k in 3:
		axes.append(Vector3(v[0][k], v[1][k], v[2][k]).normalized())
	var spread := Vector3(m[0][0], m[1][1], m[2][2])
	var lone := 0
	var apart := -1.0
	for k in 3:
		var gap := minf(absf(spread[k] - spread[(k + 1) % 3]), absf(spread[k] - spread[(k + 2) % 3]))
		if gap > apart:
			apart = gap
			lone = k
	var n := axes[lone]
	if not n.is_finite() or n.length_squared() < 0.5:
		return Basis.IDENTITY
	# ...and across it, the turn that boxes the points tightest (rotating calipers on their outline:
	# PCA alone can't choose for a square).
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := n.cross(u)
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.dot(u), p.dot(w)))
	var hull := Geometry2D.convex_hull(flat)
	var best := INF
	var turn := 0.0
	for i in range(hull.size() - 1):
		var e := (hull[i + 1] - hull[i])
		if e.length_squared() < 1e-12:
			continue
		var a := e.angle()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in hull:
			var r := q.rotated(-a)
			lo = lo.min(r)
			hi = hi.max(r)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best:
			best = area
			turn = a
	var x := u * cos(turn) + w * sin(turn)
	var y := n.cross(x)
	return Basis(x, y, n)


func _init(p_outro: Outro) -> void:
	outro = p_outro


## Seeks the whole timeline (or from `from` to `to` s) and returns the problems (empty: all good).
## `tweak` (outro, time) runs after each seek: a test breaks the timeline with it.
func run(tweak := Callable(), from := 0.0, to := INF) -> Array[String]:
	_problems.clear()
	_samples.clear()
	outro.playing = false
	_tweak = tweak
	_build_grandma()
	_build_toaster()
	_check_props_rest()
	_build_furniture()
	_build_rat_props()
	_next_rat_check = from
	var end := minf(to, outro.length())
	var steps := int(ceil((end - from) / STEP))
	for i in steps + 1:
		var time := minf(from + i * STEP, end)
		outro.seek(time)
		if tweak.is_valid():
			tweak.call(outro, time)
		_check_moment(time)
	_check_flights()
	_check_lever(from <= 0.0 and end >= outro.length())
	if outro.ending == Outro.Ending.SUPERVISORS and from <= Outro.A_GRAB and end >= Outro.A_GRAB:
		_check_grab()
	if outro.ending == Outro.Ending.SUPERVISORS and from <= Outro.A_BITE and end >= Outro.A_BITE:
		_check_bite()
	if outro.ending == Outro.Ending.RATS:
		_check_eyes(from, end)
	var lines: Array[String] = []
	for key: String in _problems:
		var p := _problems[key]
		lines.append("%s: worst %.1f mm at %.3f s (%d steps, %.3f..%.3f s)" % [p["text"], p["worst"] * 1000.0,
			p["at"], p["count"], p["from"], p["to"]])
	return lines


## A problem at `time`, `amount` m bad (the report keeps the worst, and when it happens).
func _problem(key: String, text: String, time: float, amount: float) -> void:
	if not _problems.has(key):
		_problems[key] = {"text": text, "worst": amount, "at": time, "from": time, "to": time, "count": 0}
	var p := _problems[key]
	p["count"] += 1
	p["to"] = time
	if amount > p["worst"]:
		p["worst"] = amount
		p["at"] = time


# --- The shapes ---------------------------------------------------------------------------------------

## Grandma's cells, by bone (from the cache: the same model, the same cells).
func _build_grandma() -> void:
	if not _pieces.is_empty():
		return
	_skeleton = outro.grandma.skeleton
	var mesh_instance: MeshInstance3D = null
	for node in outro.grandma.model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh_instance = node
	var id := mesh_instance.mesh.get_instance_id()
	if not _grandmas.has(id):
		_grandmas[id] = _cut_grandma(mesh_instance, _skeleton)
	var cut_: Dictionary = _grandmas[id]
	_pieces = cut_["pieces"]
	_bone_points = cut_["points"]
	_bone_reach = cut_["reach"]


## Her mesh's vertices by bone (rigid skin: each has one), in their bone's space, cut in cells.
static func _cut_grandma(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var skin := mesh_instance.skin
	var pieces: Dictionary[String, Array] = {}
	var points_of: Dictionary[String, PackedVector3Array] = {}
	var reach: Dictionary[String, Vector4] = {}
	for s in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var bind_of := PackedInt32Array()
		var local := PackedVector3Array()
		bind_of.resize(verts.size())
		local.resize(verts.size())
		var by_bind := {}  # (Arrays: a packed array in a dictionary would be copied on write)
		for v in verts.size():
			var best := 0
			for j in per:  # (rigid: one bone has it all)
				if weights[v * per + j] > weights[v * per + best]:
					best = j
			bind_of[v] = bones[v * per + best]
			local[v] = skin.get_bind_pose(bind_of[v]) * verts[v]
			if not by_bind.has(bind_of[v]):
				by_bind[bind_of[v]] = []
			by_bind[bind_of[v]].append(local[v])
		var cells := cells_of(local, _indices(arrays, verts.size()), bind_of, CELL)
		for bind: int in cells:
			var bone := skin.get_bind_name(bind)
			if skeleton.find_bone(bone) < 0:
				continue
			if not pieces.has(bone):
				pieces[bone] = []
			pieces[bone].append_array(cells[bind])
			points_of[bone] = points_of.get(bone, PackedVector3Array()) + PackedVector3Array(by_bind[bind])
	for bone: String in pieces:
		var box := AABB(points_of[bone][0], Vector3.ZERO)
		for p in points_of[bone]:
			box = box.expand(p)
		var c := box.get_center()
		reach[bone] = Vector4(c.x, c.y, c.z, box.size.length() * 0.5 + 0.01)
	return {"pieces": pieces, "points": points_of, "reach": reach}


static func _indices(arrays: Array, count: int) -> PackedInt32Array:
	if arrays[Mesh.ARRAY_INDEX] != null:
		return arrays[Mesh.ARRAY_INDEX]
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = i
	return out


## A surface (triangles over `points`; `groups` of vertices kept apart: grandma's bones) cut in
## cells: its connected pieces (welded where vertices meet), each split in halves (along its
## longest side, every triangle clipped at the cut, so the cells still cover all of it) until no
## bigger than `size`, then fitted. {group: [Piece]}.
static func cells_of(points: PackedVector3Array, indices: PackedInt32Array, groups: PackedInt32Array,
		size: float) -> Dictionary:
	# Connected pieces: union-find over the welded vertices (an Array: passed by reference).
	var root: Array[int] = []
	root.resize(points.size())
	var welded := {}
	for v in points.size():
		var key := Vector4i(roundi(points[v].x * 1e5), roundi(points[v].y * 1e5), roundi(points[v].z * 1e5),
			groups[v] if not groups.is_empty() else 0)
		root[v] = welded.get(key, v)
		welded[key] = root[v]
	for i in indices.size() / 3:
		var a := _root_of(root, indices[i * 3])
		for j in range(1, 3):
			var b := _root_of(root, indices[i * 3 + j])
			if a != b:
				root[b] = a
	var polygons := {}  # piece -> its triangles
	var group_of := {}
	for i in indices.size() / 3:
		var r := _root_of(root, indices[i * 3])
		if not polygons.has(r):
			polygons[r] = []
			group_of[r] = groups[indices[i * 3]] if not groups.is_empty() else 0
		polygons[r].append(PackedVector3Array([points[indices[i * 3]], points[indices[i * 3 + 1]],
			points[indices[i * 3 + 2]]]))
	var out := {}
	for r: int in polygons:
		var g: int = group_of[r]
		if not out.has(g):
			out[g] = []
		_split(polygons[r], out[g], size, 0)
	return out


static func _root_of(root: Array[int], v: int) -> int:
	var r := v
	while root[r] != r:
		r = root[r]
	while root[v] != r:  # (path compression)
		var next := root[v]
		root[v] = r
		v = next
	return r


static func _split(polygons: Array, cells: Array, size: float, level: int) -> void:
	var box := AABB()
	var any := false
	for poly: PackedVector3Array in polygons:
		for p in poly:
			box = box.expand(p) if any else AABB(p, Vector3.ZERO)
			any = true
	if not any:
		return
	var axis := box.get_longest_axis_index()
	var points := PackedVector3Array()
	for poly: PackedVector3Array in polygons:
		points.append_array(poly)
	var piece := Piece.fit(points)
	if box.size[axis] <= size or level >= 12 or piece.holds_tightly(points):
		cells.append(piece)
		return
	var at := box.position[axis] + box.size[axis] * 0.5
	var below := []
	var above := []
	for poly: PackedVector3Array in polygons:
		var lo := PackedVector3Array()
		var hi := PackedVector3Array()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var da := a[axis] - at
			var db := b[axis] - at
			if da <= 0.0:
				lo.append(a)
			if da >= 0.0:
				hi.append(a)
			if da * db < 0.0:
				var x := a.lerp(b, da / (da - db))
				lo.append(x)
				hi.append(x)
		if lo.size() >= 3:
			below.append(lo)
		if hi.size() >= 3:
			above.append(hi)
	_split(below, cells, size, level + 1)
	_split(above, cells, size, level + 1)


## A static mesh's cells (no bigger than `size`), in its space.
static func mesh_cells(mesh: Mesh, size: float) -> Array:
	var id := mesh.get_instance_id()
	if not _mesh_cells.has(id):
		var all := []
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			all.append_array(cells_of(verts, _indices(arrays, verts.size()), PackedInt32Array(), size).get(0, []))
		_mesh_cells[id] = all
	return _mesh_cells[id]


func _bone(bone: String) -> Transform3D:
	if not _bone_now.has(bone):
		_bone_now[bone] = _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
	return _bone_now[bone]


## A bone's cells now, if they may reach within `reach` m of `centre` (and only those).
func _pieces_near(bone: String, centre: Vector3, reach: float) -> Array[Box]:
	var out: Array[Box] = []
	if not _pieces.has(bone):
		return out
	var xform := _bone(bone)
	var sphere: Vector4 = _bone_reach[bone]
	var scale := xform.basis.get_scale().abs()
	if (xform * Vector3(sphere.x, sphere.y, sphere.z)).distance_to(centre) > sphere.w * maxf(scale.x, maxf(scale.y, scale.z)) + reach:
		return out
	if not _boxes_now.has(bone):
		var boxes := []
		for piece: Piece in _pieces[bone]:
			boxes.append(Box.make("grandma's " + bone, xform * Transform3D(piece.basis, Vector3.ZERO), piece.aabb,
				piece.radius))
		_boxes_now[bone] = boxes
	for box: Box in _boxes_now[bone]:
		if box.origin.distance_to(centre) <= box.bound() + reach:
			out.append(box)
	return out


## Where a bone's vertices are now (exact, whatever the bone does).
func _points_of(bone: String) -> PackedVector3Array:
	var xform := _bone(bone)
	var local := _bone_points[bone]
	var out := PackedVector3Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = xform * local[i]
	return out


## The toaster's solid insides around its two slots, and the slots, in its frame.
func _build_toaster() -> void:
	_toaster_solid.clear()
	_slots.clear()
	var toaster := outro.set_.toaster
	var inv := toaster.global_transform.affine_inverse()
	var body := AABB()
	for mesh in Art.meshes(Art.part(toaster, "Body")):
		var local := inv * mesh.global_transform * mesh.mesh.get_aabb()
		body = local if body.size == Vector3.ZERO else body.merge(local)
	body.position.z = body.get_center().z - TOASTER_D * 0.5
	body.size.z = TOASTER_D
	var top := body.end.y
	var x0 := INF
	var x1 := -INF
	for k in 2:
		var at := inv * Art.part(toaster, "Slot%d" % (k + 1)).global_position
		_slots.append(AABB(Vector3(at.x - SLOT_L * 0.5, SLOT_FLOOR, at.z - SLOT_W * 0.5),
			Vector3(SLOT_L, top - SLOT_FLOOR, SLOT_W)))
		x0 = minf(x0, at.x - SLOT_L * 0.5)
		x1 = maxf(x1, at.x + SLOT_L * 0.5)
	var p := body.position
	var e := body.end
	_toaster_solid.append(AABB(p, Vector3(e.x - p.x, SLOT_FLOOR - p.y, e.z - p.z)))  # the base
	_toaster_solid.append(AABB(Vector3(p.x, SLOT_FLOOR, p.z), Vector3(x0 - p.x, top - SLOT_FLOOR, e.z - p.z)))
	_toaster_solid.append(AABB(Vector3(x1, SLOT_FLOOR, p.z), Vector3(e.x - x1, top - SLOT_FLOOR, e.z - p.z)))
	# Between the ends: the walls behind, between and in front of the slots.
	var cuts: Array[float] = [p.z]
	var sorted := _slots.duplicate()
	sorted.sort_custom(func(a: AABB, b: AABB) -> bool: return a.position.z < b.position.z)
	for slot: AABB in sorted:
		cuts.append(slot.position.z)
		cuts.append(slot.end.z)
	cuts.append(e.z)
	for i in range(0, cuts.size(), 2):
		_toaster_solid.append(AABB(Vector3(x0, SLOT_FLOOR, cuts[i]), Vector3(x1 - x0, top - SLOT_FLOOR, cuts[i + 1] - cuts[i])))


## The boxes of every visible mesh under `node` (in their own frames).
static func boxes_of(node: Node, label: String) -> Array[Box]:
	var out: Array[Box] = []
	for mesh in Art.meshes(node):
		if mesh.is_visible_in_tree() and mesh.mesh != null:
			out.append(Box.make("%s (%s)" % [label, mesh.name], mesh.global_transform, mesh.mesh.get_aabb()))
	return out


## The world AABB of every mesh under `node`.
static func world_aabb(node: Node) -> AABB:
	var out := AABB()
	for mesh in Art.meshes(node):
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		out = box if out.size == Vector3.ZERO else out.merge(box)
	return out


## Points all over a mesh's surface, about SURFACE_SPACING apart, in its own space (once per mesh).
static func surface_points(mesh: Mesh) -> PackedVector3Array:
	var id := mesh.get_instance_id()
	if _surfaces.has(id):
		return _surfaces[id]
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tris := indices.size() / 3 if not indices.is_empty() else verts.size() / 3
		for i in tris:
			var a := verts[indices[i * 3] if not indices.is_empty() else i * 3]
			var b := verts[indices[i * 3 + 1] if not indices.is_empty() else i * 3 + 1]
			var c := verts[indices[i * 3 + 2] if not indices.is_empty() else i * 3 + 2]
			for edge: Array in [[a, b], [b, c], [c, a]]:  # along its edges...
				var from: Vector3 = edge[0]
				var to: Vector3 = edge[1]
				var n := maxi(ceili(from.distance_to(to) / SURFACE_SPACING), 1)
				for j in n:
					out.append(from.lerp(to, float(j) / n))
			var normal := (b - a).cross(c - a)  # ...and a lattice inside it (as many points as its area)
			if normal.length_squared() < 1e-14:
				continue
			var e1 := (b - a).normalized()
			var e2 := normal.normalized().cross(e1)
			var tb := Vector2((b - a).dot(e1), 0.0)
			var tc := Vector2((c - a).dot(e1), (c - a).dot(e2))
			var lo := Vector2(minf(0.0, minf(tb.x, tc.x)), minf(0.0, tc.y))
			var hi := Vector2(maxf(0.0, maxf(tb.x, tc.x)), maxf(0.0, tc.y))
			var x := lo.x + SURFACE_SPACING * 0.5
			while x < hi.x:
				var y := lo.y + SURFACE_SPACING * 0.5
				while y < hi.y:
					var w := Geometry2D.point_is_inside_triangle(Vector2(x, y), Vector2.ZERO, tb, tc)
					if w:
						out.append(a + e1 * x + e2 * y)
					y += SURFACE_SPACING
				x += SURFACE_SPACING
	_surfaces[id] = out
	return out


# --- Overlaps -------------------------------------------------------------------------------------------

## How deep `a` and `b` are in each other (m; negative: apart). Separating axes for sharp boxes;
## for rounded ones, the distance between the inner boxes (alternating projections: exact for two
## convex shapes) against their roundings.
static func depth(a: Box, b: Box) -> float:
	if a.empty or b.empty or not a.near(b, 0.01):
		return -0.01
	var sat := _sat(a, b)
	var r := a.radius + b.radius
	if r == 0.0 or sat > 0.0 or sat < -r:
		return sat + r
	return r - _distance(a, b)


static func _sat(a: Box, b: Box) -> float:
	var axes: Array[Vector3] = [a.basis.x, a.basis.y, a.basis.z, b.basis.x, b.basis.y, b.basis.z]
	for u: Vector3 in [a.basis.x, a.basis.y, a.basis.z]:
		for v: Vector3 in [b.basis.x, b.basis.y, b.basis.z]:
			var c := u.cross(v)
			if c.length_squared() > 1e-8:
				axes.append(c.normalized())
	var d := b.origin - a.origin
	var least := INF
	for axis in axes:
		var ra := a.half.x * absf(a.basis.x.dot(axis)) + a.half.y * absf(a.basis.y.dot(axis)) \
			+ a.half.z * absf(a.basis.z.dot(axis))
		var rb := b.half.x * absf(b.basis.x.dot(axis)) + b.half.y * absf(b.basis.y.dot(axis)) \
			+ b.half.z * absf(b.basis.z.dot(axis))
		least = minf(least, ra + rb - absf(d.dot(axis)))
	return least


static func _distance(a: Box, b: Box) -> float:
	var p := a.closest(b.origin)
	var q := b.closest(p)
	for i in 96:
		var p2 := a.closest(q)
		var q2 := b.closest(p2)
		var moved := p2.distance_squared_to(p) + q2.distance_squared_to(q)
		p = p2
		q = q2
		if moved < 1e-14:
			break
	return p.distance_to(q)


## A box against one in the toaster's frame (`local`): how deep.
func _depth_in_toaster(box: Box, local: AABB) -> float:
	return depth(box, Box.make("", outro.set_.toaster.global_transform, local))


## How deep `box` is in the plate (its real profile; the counter is under it).
func _depth_in_plate(box: Box) -> float:
	var plate := outro.set_.plate.global_transform
	var inv := plate.affine_inverse()
	var reach := PLATE_PROFILE[-1].x
	if box.lowest() > plate.origin.y + 0.03 \
			or Vector2(box.origin.x - plate.origin.x, box.origin.z - plate.origin.z).length() > reach + box.bound():
		return -0.01
	var deepest := -0.01
	for p in box.edge_points(0.01):
		var l := inv * p
		var r := Vector2(l.x, l.z).length()
		if r <= reach:
			deepest = maxf(deepest, _plate_top(r) - l.y)
	return deepest


static func _plate_top(r: float) -> float:
	for i in range(1, PLATE_PROFILE.size()):
		if r <= PLATE_PROFILE[i].x:
			var a := PLATE_PROFILE[i - 1]
			var b := PLATE_PROFILE[i]
			return lerpf(a.y, b.y, (r - a.x) / (b.x - a.x))
	return 0.0


# --- Each moment ---------------------------------------------------------------------------------------

func _check_moment(time: float) -> void:
	_bone_now.clear()
	_boxes_now.clear()
	var toasts: Array[Array] = []  # per slice: its boxes
	var states: Array[Dictionary] = []
	var positions: Array[Vector3] = []
	for k in outro.toasts.size():
		var state := outro.paths[k].state_at(time)
		states.append(state)
		toasts.append(boxes_of(outro.toasts[k], "Toast%d" % (k + 1)) if outro.toasts[k].visible else [])
		positions.append(outro.toasts[k].global_position)
	_samples.append({"t": time, "toasts": positions, "states": states,
		"lever": outro.set_.lever.position.y, "contact": _hand_on_knob()})
	for k in toasts.size():
		_check_toast(time, k, toasts[k], states[k])
	for k in toasts.size():  # each other
		for j in range(k + 1, toasts.size()):
			for a: Box in toasts[k]:
				for b: Box in toasts[j]:
					var d := depth(a, b)
					if d > PENETRATION:
						_problem("toast-toast", "the slices go through each other", time, d)
	_check_feet(time)
	_check_grandma(time)
	_check_camera(time)
	if time >= _next_rat_check - 1e-6:
		_next_rat_check += RAT_STEP
		if outro.ending == Outro.Ending.RATS:
			_check_gang(time)
		else:
			_check_cage_rat(time)


func _check_toast(time: float, k: int, boxes: Array, state: Dictionary) -> void:
	var label := "Toast%d" % (k + 1)
	var what: ToastPath.State = state["state"]
	# In the toaster: in its slot, or still rising out of it before the flick at the rim.
	var leaving_slot := false
	for f in outro.paths[k].flights():
		if time >= f["t0"] and time < f["t_rim"]:
			leaving_slot = true
	var in_toaster := what == ToastPath.State.SLOT or leaving_slot
	var meshes := Art.meshes(outro.toasts[k]).filter(func(m: MeshInstance3D) -> bool: return m.is_visible_in_tree())
	for i in boxes.size():
		var box: Box = boxes[i]
		var part := box.name
		for j in _toaster_solid.size():
			var d := _depth_in_toaster(box, _toaster_solid[j])
			if d > PENETRATION:
				_problem("%s-toaster-%d" % [label, j], "%s is inside the toaster's body (%s)" % [part, ["base", "left end",
					"right end", "back wall", "middle wall", "front wall"][j]], time, d)
		# A slot holds a slice only while it's in the toaster (the limp one's bottom stays in its slot).
		var draped_bottom := what == ToastPath.State.DRAPED and not (part.contains("Middle") or part.contains("Top"))
		if not in_toaster and not draped_bottom:
			for j in _slots.size():
				var d := _depth_in_toaster(box, _slots[j])
				if d > PENETRATION:
					_problem("%s-slot-%d" % [label, j], "%s is in slot %d out of the toaster's hands" % [part, j + 1], time, d)
		var plate := _depth_in_plate(box)
		if plate > PENETRATION:
			_problem(label + "-plate", "%s is inside the plate" % part, time, plate)
		for prop: Node3D in [outro.set_.island, outro.set_.teacup, outro.set_.butter.get_parent()]:
			for other in boxes_of(prop, prop.name):
				var d := depth(box, other)
				if d > PENETRATION:
					_problem(label + "-" + prop.name, "%s is inside %s" % [part, other.name], time, d)
		_check_toast_grandma(time, label, box, meshes[i], what)
	_check_rest(time, k, boxes, state)


## A slice against grandma (every piece of her but the hand holding it): the points over its
## surface must stay out of her. At the bite her lips close on a corner of it.
func _check_toast_grandma(time: float, label: String, box: Box, mesh: MeshInstance3D, what: ToastPath.State) -> void:
	var held := what == ToastPath.State.HELD
	var biting := held and outro.ending == Outro.Ending.SUPERVISORS and time >= Outro.A_BITE + BITE_WINDOW.x \
		and time <= Outro.A_BITE + BITE_WINDOW.y
	var points := PackedVector3Array()
	for bone in BODY_BONES:
		if held and bone in GRIP_BONES:
			continue
		var allowed := BITE_DEPTH if biting and bone == "head" else PENETRATION
		for piece in _pieces_near(bone, box.origin, box.bound()):
			if depth(box, piece) <= allowed:
				continue  # (its box isn't in that deep: the slice can't be)
			if points.is_empty():
				var xform := mesh.global_transform
				for p in surface_points(mesh.mesh):
					points.append(xform * p)
			var deepest := 0.0
			for p in points:
				deepest = maxf(deepest, -piece.sdf(p))
			if deepest > allowed:
				_problem("%s-grandma-%s" % [label, bone], "%s goes into %s" % [box.name, piece.name], time, deepest)


## What rests on something is on it: no deeper than PENETRATION, no higher than CONTACT.
func _check_rest(time: float, k: int, boxes: Array, state: Dictionary) -> void:
	var what: ToastPath.State = state["state"]
	var support: String = state["support"]
	if boxes.is_empty() or not what in [ToastPath.State.REST, ToastPath.State.LANDING, ToastPath.State.DRAPED]:
		return
	var label := "Toast%d" % (k + 1)
	var box: Box = boxes[0]
	if support == "Plate":
		var surface := Art.part(outro.set_.plate, "Surface").global_position
		_gap(time, label + " on the plate", box.lowest() - surface.y)
		var off := Vector2(box.origin.x - surface.x, box.origin.z - surface.z).length()
		if off > 0.02:
			_problem(label + "-off-plate", label + " lies off the plate's middle", time, off)
	elif support == "Toast1":
		var under: Array[Box] = boxes_of(outro.toasts[0], "Toast1")
		if not under.is_empty():
			_gap(time, label + " on Toast1", box.lowest() - under[0].highest())
			var l := under[0].to_local(box.origin)
			if absf(l.x) > under[0].half.x or absf(l.y) > under[0].half.y:
				_problem(label + "-off-toast", label + " isn't over Toast1", time, Vector2(l.x, l.y).length())
	elif support == "Toaster" and time >= Outro.B_FOLDED + 0.3:
		# The limp slice lies folded over the front of its slot: its middle on the toaster's top.
		for b: Box in boxes:
			if b.name.contains("Middle"):
				var top := outro.set_.toaster.global_position.y + _slots[0].end.y
				_gap(time, label + "'s middle on the toaster", b.lowest() - top)


func _gap(time: float, what: String, gap: float) -> void:
	if gap < -PENETRATION:
		_problem(what + "-in", what + ": sunk in", time, -gap)
	elif gap > CONTACT:
		_problem(what + "-float", what + ": floating", time, gap)


## The props stand on the counter (they don't move: once); the cage on the sink counter, in nothing.
func _check_props_rest() -> void:
	outro.seek(0.0)
	var counter := world_aabb(outro.set_.island).end.y
	for prop: Node3D in [outro.set_.toaster, outro.set_.plate, outro.set_.teacup, outro.set_.butter.get_parent()]:
		_gap(0.0, "the %s on the counter" % prop.name, world_aabb(prop).position.y - counter)
	var cage := outro.set_.cage
	if cage != null:
		_gap(0.0, "the cage on the sink counter", world_aabb(cage).position.y - OutroKitchen.COUNTER_TOP)
		var counter_cells := _cells_of(outro.set_.sink_counter, "the sink counter")
		for mesh in Art.meshes(cage):
			for cell in mesh_cells(mesh.mesh, PROP_CELLS["the cage"]):
				var box := Box.make("the cage", mesh.global_transform * Transform3D(cell.basis, Vector3.ZERO), cell.aabb,
					cell.radius)
				for other: Box in counter_cells:
					var d := depth(box, other)
					if d > PENETRATION and box.lowest() > OutroKitchen.COUNTER_TOP - 0.01:  # (its tray on the top is the gap above)
						_problem("cage-counter", "the cage goes into the sink counter (its sink, tap or canisters)", 0.0, d)


## Her slippers are on the floor, unless she hops; never through it.
func _check_feet(time: float) -> void:
	var lowest := INF
	for side: String in ["leg_l", "leg_r"]:
		for p in _points_of(side):
			lowest = minf(lowest, p.y)
	var lift := _bone("root").origin.y
	if lowest < -PENETRATION:
		_problem("feet-in", "grandma's slippers are in the floor", time, -lowest)
	elif lift < 0.0005 and lowest > CONTACT:
		_problem("feet-float", "grandma's slippers float over the floor (she isn't hopping)", time, lowest)


## What grandma meets, cut in cells (the lever moves: its cells are placed again each step).
func _build_furniture() -> void:
	_furniture.clear()
	var things := {"the toaster": Art.part(outro.set_.toaster, "Body"), "the lever": outro.set_.lever,
		"the counter": outro.set_.island, "the plate": outro.set_.plate, "her cup": outro.set_.teacup,
		"the butter dish": outro.set_.butter.get_parent()}
	for thing: String in things:
		for mesh in Art.meshes(things[thing]):
			if mesh.mesh != null:
				_furniture.append({"name": thing, "mesh": mesh, "cells": mesh_cells(mesh.mesh, PROP_CELLS[thing]),
					"moves": thing == "the lever"})
	for item in _furniture:
		_place(item)


func _place(item: Dictionary) -> void:
	var mesh: MeshInstance3D = item["mesh"]
	var boxes := []
	for piece: Piece in item["cells"]:
		boxes.append(Box.make(item["name"], mesh.global_transform * Transform3D(piece.basis, Vector3.ZERO), piece.aabb,
			piece.radius))
	item["boxes"] = boxes
	var box := mesh.global_transform * mesh.mesh.get_aabb()
	item["centre"] = box.get_center()
	item["reach"] = box.size.length() * 0.5 + 0.01


## Grandma doesn't go into the furniture (her hands may touch it: they rest, tap and press there).
func _check_grandma(time: float) -> void:
	for item in _furniture:
		if item["moves"]:  # (the lever: placed again each step)
			_place(item)
		var centre: Vector3 = item["centre"]
		var reach: float = item["reach"]
		for bone in BODY_BONES:
			var sphere := _bone_sphere(bone)
			if sphere.w < 0.0 or Vector3(sphere.x, sphere.y, sphere.z).distance_to(centre) > sphere.w + reach:
				continue
			# Its boxes around this bone, then this bone's cells against them.
			var near: Array[Box] = []
			for thing: Box in item["boxes"]:
				if Vector3(sphere.x, sphere.y, sphere.z).distance_to(thing.origin) <= sphere.w + thing.reach:
					near.append(thing)
			if near.is_empty():
				continue
			for piece in _pieces_near(bone, Vector3(sphere.x, sphere.y, sphere.z), sphere.w):
				for thing in near:
					_meet(time, bone, piece, thing)


## A bone's sphere now (its pieces are all in it): centre, radius (-1: no pieces).
func _bone_sphere(bone: String) -> Vector4:
	if not _pieces.has(bone):
		return Vector4(0, 0, 0, -1)
	var xform := _bone(bone)
	var sphere: Vector4 = _bone_reach[bone]
	var scale := xform.basis.get_scale().abs()
	var c := xform * Vector3(sphere.x, sphere.y, sphere.z)
	return Vector4(c.x, c.y, c.z, sphere.w * maxf(scale.x, maxf(scale.y, scale.z)))


func _meet(time: float, bone: String, piece: Box, thing: Box) -> void:
	if not piece.near(thing):
		return
	var d := depth(piece, thing)
	if d > PENETRATION:
		_problem("grandma-%s-%s" % [bone, thing.name], "%s goes into %s" % [piece.name, thing.name], time, d)


## The camera stays out of everything (the set's meshes, and grandma).
func _check_camera(time: float) -> void:
	var eye := outro.camera.global_position
	var viewport := outro.get_viewport()
	for mesh: MeshInstance3D in outro.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.get_viewport() != viewport \
				or outro.grandma.is_ancestor_of(mesh):
			continue
		var d := Box.make(mesh.name, mesh.global_transform, mesh.mesh.get_aabb()).sdf(eye)
		if d < CAMERA_MARGIN:
			_problem("camera-" + str(mesh.get_path()), "the camera is in (or too close to) %s" % mesh.get_path(), time,
				CAMERA_MARGIN - d)
	for bone in BODY_BONES:
		for piece in _pieces_near(bone, eye, CAMERA_MARGIN):
			var d := piece.sdf(eye)
			if d < CAMERA_MARGIN:
				_problem("camera-grandma-" + bone, "the camera is in %s" % piece.name, time, CAMERA_MARGIN - d)


## The grab: her left hand is on the top slice when she takes it (it doesn't float under her hand).
func _check_grab() -> void:
	outro.seek(Outro.A_GRAB)
	_bone_now.clear()
	var slice: Box = boxes_of(outro.toasts[1], "Toast2")[0]
	var nearest := INF
	for bone: String in GRIP_BONES:
		for p in _points_of(bone):
			nearest = minf(nearest, slice.sdf(p))
	if nearest > CONTACT:
		_problem("grab", "her hand isn't on the slice she takes", Outro.A_GRAB, nearest)
	elif nearest < -PENETRATION * 4.0:
		_problem("grab-in", "her hand is in the slice she takes", Outro.A_GRAB, -nearest)


## The bite: as it comes (the moment before the bitten slice shows), the slice in her hand is at her
## mouth.
func _check_bite() -> void:
	outro.seek(Outro.A_BITE - 0.01)
	_bone_now.clear()
	var mouth := _bone("head") * MOUTH
	var nearest := INF
	for mesh in Art.meshes(outro.toasts[1]):
		if mesh.is_visible_in_tree():
			for p in surface_points(mesh.mesh):
				nearest = minf(nearest, (mesh.global_transform * p).distance_to(mouth))
	if nearest > BITE_REACH:
		_problem("bite", "the slice doesn't reach her mouth at the bite", Outro.A_BITE, nearest)


# --- Over the whole timeline ------------------------------------------------------------------------------

## How far grandma's right hand is from the lever's knob (m; negative: in it), from its vertices.
func _hand_on_knob() -> float:
	var lever := outro.set_.lever
	var knob := Box.make("knob", lever.global_transform, AABB(-KNOB * 0.5 + Vector3.ONE * KNOB_RADIUS,
		KNOB - Vector3.ONE * KNOB_RADIUS * 2.0), KNOB_RADIUS)
	var nearest := INF
	for bone: String in ["hand_r", "thumb_r"]:
		for p in _points_of(bone):
			nearest = minf(nearest, knob.sdf(p))
	return nearest


## The lever goes down only under her hand (touching the knob, never sinking in it); it comes back
## up only when the toaster pops it (DING, or the pale slices' "pwomp").
func _check_lever(whole: bool) -> void:
	var pops := Vector2(Outro.A_DING, Outro.A_DING + 0.1) if outro.ending == Outro.Ending.SUPERVISORS \
		else Vector2(Outro.B_PWOMP, Outro.B_UP + 0.01)
	var pressed := false
	for i in _samples.size():
		var s := _samples[i]
		var contact: float = s["contact"]
		if contact < -PENETRATION:
			_problem("hand-in-knob", "grandma's hand is inside the lever's knob", s["t"], -contact)
		if i == 0:
			continue
		var before := _samples[i - 1]
		var moved: float = s["lever"] - before["lever"]
		if moved < -1e-6:
			pressed = true
			for c: float in [contact, before["contact"]]:
				if c > CONTACT:
					_problem("lever-alone", "the lever goes down without grandma's hand on it", s["t"], c)
		elif moved > 1e-6 and (s["t"] < pops.x or s["t"] > pops.y):
			_problem("lever-up", "the lever goes up when the toaster doesn't pop", s["t"], moved)
	if whole and not pressed:
		_problem("lever-never", "the lever never goes down", 0.0, 0.0)


## Every flight (a throw, a bounce): gravity G but in the hang at the top (which never pushes it
## up); straight up out of the slot, then a steady drift; and no slice ever jumps.
func _check_flights() -> void:
	var g := ToastPath.G
	for k in outro.toasts.size():
		var label := "Toast%d" % (k + 1)
		for f in outro.paths[k].flights():
			var hang: Vector2 = f["hang"]
			if hang.x >= 0.0:
				if not (f["t_top"] > hang.x and f["t_top"] < hang.y):
					_problem(label + "-hang-top", label + "'s hang isn't at the top of its arc", f["t_top"], 0.0)
				if hang.y - hang.x > 0.3:
					_problem(label + "-hang-long", label + "'s hang is too long", hang.x, hang.y - hang.x)
			for i in range(1, _samples.size() - 1):
				var t: float = _samples[i]["t"]
				if t - STEP < f["t0"] + 1e-6 or t + STEP > f["t_land"] - 1e-6:
					continue
				var p0: Vector3 = _samples[i - 1]["toasts"][k]
				var p1: Vector3 = _samples[i]["toasts"][k]
				var p2: Vector3 = _samples[i + 1]["toasts"][k]
				var accel := (p2 - 2.0 * p1 + p0) / (STEP * STEP)
				var side := Vector2(accel.x, accel.z).length()
				var rim: float = f["t_rim"]
				var at_rim := t - STEP < rim and t + STEP > rim
				if t + STEP > hang.x and t - STEP < hang.y:
					if accel.y > 0.05 * g or accel.y < -HANG_PULL * g:
						_problem(label + "-hang", label + "'s hang pushes it up or yanks it down (accel, mm = cm/s²)", t,
							absf(accel.y) * 0.001)
				else:
					if absf(accel.y + g) > 0.02 * g:
						_problem(label + "-gravity", label + " doesn't fall with gravity (accel, mm = cm/s²)", t,
							absf(accel.y + g) * 0.001)
					if not at_rim and side > 0.02 * g:
						_problem(label + "-drift", label + " swerves in the air (accel, mm = cm/s²)", t, side * 0.001)
				if t + STEP < rim and Vector2(p2.x - p1.x, p2.z - p1.z).length() > 1e-6:
					_problem(label + "-slot-drift", label + " leaves its slot sideways", t, Vector2(p2.x - p1.x, p2.z - p1.z).length())
		for i in range(1, _samples.size()):
			var states: Array = _samples[i]["states"]
			var before: Array = _samples[i - 1]["states"]
			if states[k]["state"] == ToastPath.State.GONE or before[k]["state"] == ToastPath.State.GONE:
				continue
			var step: float = (_samples[i]["toasts"][k] as Vector3).distance_to(_samples[i - 1]["toasts"][k])
			if step > MAX_SPEED * STEP:
				_problem(label + "-jump", label + " jumps", _samples[i]["t"], step)


# --- The rats -----------------------------------------------------------------------------------------

## What the rats mustn't go into, cut in cells: the counter, the toaster and its lever, the plate, her
## cup, the butter dish, the fridge, the window (its sill and geraniums), the sink counter.
func _build_rat_props() -> void:
	_rat_props.clear()
	var set_ := outro.set_
	var things := {"the counter": set_.island, "the toaster": Art.part(set_.toaster, "Body"), "the lever": set_.lever,
		"the plate": set_.plate, "her cup": set_.teacup, "the butter dish": set_.butter.get_parent(),
		"the fridge": set_.fridge, "the window": set_.window, "the sink counter": set_.sink_counter}
	for thing: String in things:
		var node: Node3D = things[thing]
		if node == null:
			continue
		for mesh in Art.meshes(node):
			if mesh.mesh != null and mesh.is_visible_in_tree():
				var item := {"name": thing, "mesh": mesh, "cells": mesh_cells(mesh.mesh, PROP_CELLS[thing]),
					"moves": thing == "the lever"}
				_place(item)
				_rat_props.append(item)


## A node's meshes cut in cells, placed (they don't move).
func _cells_of(node: Node3D, label: String) -> Array[Box]:
	var out: Array[Box] = []
	if node == null:
		return out
	for mesh in Art.meshes(node):
		for cell in mesh_cells(mesh.mesh, PROP_CELLS.get(label, CELL)):
			out.append(Box.make(label, mesh.global_transform * Transform3D(cell.basis, Vector3.ZERO), cell.aabb, cell.radius))
	return out


## A rat's vertices now, in the world (every other one: enough to find a rat in a prop), from its
## skeleton's pose.
func _rat_points(actor: IntroActor) -> PackedVector3Array:
	var out := PackedVector3Array()
	if actor == null or actor.skeleton == null:
		return out
	var mesh_instance: MeshInstance3D = null
	for node in actor.model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh_instance = node
	var id := mesh_instance.mesh.get_instance_id()
	if not _actors.has(id):
		_actors[id] = bone_vertices(mesh_instance, 2)
	var skel := actor.skeleton
	var by_bone: Dictionary = _actors[id]
	for bone: String in by_bone:
		var xform := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))
		for p: Vector3 in by_bone[bone]:
			out.append(xform * p)
	return out


## A rigid-skinned mesh's vertices by bone, in their bone's space (every `every`-th).
static func bone_vertices(mesh_instance: MeshInstance3D, every := 1) -> Dictionary:
	var skin := mesh_instance.skin
	var out := {}
	for s in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for v in range(0, verts.size(), every):
			var best := 0
			for j in per:
				if weights[v * per + j] > weights[v * per + best]:
					best = j
			var bind := bones[v * per + best]
			var bone := skin.get_bind_name(bind)
			if not out.has(bone):
				out[bone] = PackedVector3Array()
			out[bone].append(skin.get_bind_pose(bind) * verts[v])
	return out


## The rats in the dark: each, while it's there, on what it sits on and in no prop.
func _check_gang(time: float) -> void:
	for i in outro.gang.size():
		var member: Dictionary = outro.gang[i]
		var actor: IntroActor = member["actor"]
		if actor == null or not actor.visible:
			continue  # (eyes alone; not there yet)
		if i == 0 and time >= Outro.B_LEAP:
			if time >= Outro.B_LEAP + 0.13 and time < Outro.B_SLIP + 0.2:
				_check_hang(time, actor)
			continue
		var spot: Dictionary = member["spot"]
		var label: String = actor.name
		var points := _rat_points(actor)
		var lowest := INF
		var centre := Vector3.ZERO
		for p in points:
			lowest = minf(lowest, p.y)
			centre += p
		centre /= points.size()
		_gap(time, "%s on %s" % [label, spot["on"]], lowest - _surface(spot["on"]))
		var reach := AABB(points[0], Vector3.ZERO)
		for p in points:
			reach = reach.expand(p)
		reach = reach.grow(0.01)
		for item in _rat_props:
			if item["moves"]:
				_place(item)
			if (item["centre"] as Vector3).distance_to(centre) > float(item["reach"]) + 0.5:
				continue
			for thing: Box in item["boxes"]:
				if not reach.intersects(AABB(thing.origin - thing.extent, thing.extent * 2.0)):
					continue
				var deepest := 0.0
				for p in points:
					deepest = maxf(deepest, -thing.sdf(p))
				if deepest > PENETRATION:
					_problem("%s-%s" % [label, item["name"]], "%s goes into %s" % [label, item["name"]], time, deepest)


## The rat hanging by its tail from the counter's front edge: in nothing, and (until it slips) its tail
## resting on the counter's top, over the edge.
func _check_hang(time: float, actor: IntroActor) -> void:
	var points := _rat_points(actor)
	for item in _rat_props:
		if item["name"] != "the counter":
			continue
		for thing: Box in item["boxes"]:
			var deepest := 0.0
			for p in points:
				deepest = maxf(deepest, -thing.sdf(p))
			if deepest > PENETRATION:
				_problem("hang-counter", "the hanging rat goes into the counter", time, deepest)
	if time >= Outro.B_SLIP:
		return
	var edge := outro.set_.island.global_position.z + Outro.ISLAND_FRONT
	var lowest := INF
	for p in _rat_bone_points(actor, ["tail_3", "tail_4"]):
		if p.z < edge - 0.004:
			lowest = minf(lowest, p.y)
	if lowest == INF:
		_problem("hang-unhooked", "the hanging rat's tail doesn't reach over the counter's edge", time, 0.0)
	else:
		_gap(time, "the hanging rat's tail on the counter's top", lowest - OutroKitchen.COUNTER_TOP)


## A rat's vertices of `bones` now, in the world.
func _rat_bone_points(actor: IntroActor, bones: Array[String]) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh_instance: MeshInstance3D = null
	for node in actor.model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh_instance = node
	var id := mesh_instance.mesh.get_instance_id()
	if not _actors.has(id):
		_actors[id] = bone_vertices(mesh_instance, 2)
	var skel := actor.skeleton
	for bone in bones:
		var xform := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))
		for p: Vector3 in _actors[id].get(bone, PackedVector3Array()):
			out.append(xform * p)
	return out


## How high what a rat sits on is (Outro.spots()'s "on").
func _surface(on: String) -> float:
	match on:
		"the fridge":
			return FRIDGE_TOP
		"the windowsill":
			return OutroKitchen.SILL.y
		"the plate":
			var surface := Art.part(outro.set_.plate, "Surface")
			return surface.global_position.y if surface != null else OutroKitchen.COUNTER_TOP + 0.01
	return OutroKitchen.COUNTER_TOP


## The caged rat: inside its cage (in the cage's own space), on its bedding but for its hop, in none
## of the cage's parts (its bars, wheel, bowl, bottle).
func _check_cage_rat(time: float) -> void:
	var rat := outro.cage_rat
	var cage := outro.set_.cage
	if rat == null or cage == null:
		return
	var points := _rat_points(rat)
	var inv := cage.global_transform.affine_inverse()
	var scale := cage.global_transform.basis.get_scale().x
	var out := 0.0
	var lowest := INF
	for p in points:
		var l := inv * p
		lowest = minf(lowest, l.y)
		var q := (l - CAGE_INSIDE.get_center()).abs() - CAGE_INSIDE.size * 0.5
		out = maxf(out, maxf(q.x, maxf(q.y, q.z)))
	if out > PENETRATION / scale:
		_problem("cage-rat-out", "the caged rat is out of its cage", time, out * scale)
	var hopping := time > Outro.A_HMPH and time < Outro.A_HMPH + 0.26
	var gap := (lowest - CAGE_FLOOR) * scale
	if gap < -PENETRATION or not hopping:
		_gap(time, "the caged rat on its floor", gap)
	var reach := AABB(points[0], Vector3.ZERO)
	for p in points:
		reach = reach.expand(p)
	reach = reach.grow(0.01)
	for box in _cage_cells():
		if not reach.intersects(AABB(box.origin - box.extent, box.extent * 2.0)):
			continue
		var deepest := 0.0
		for p in points:
			deepest = maxf(deepest, -box.sdf(p))
		if deepest > PENETRATION:
			_problem("cage-rat-" + box.name, "the caged rat goes into the cage (%s)" % box.name, time, deepest)


## The cage's cells above its bedding (its bars, roof, wheel, bowl, bottle), placed (it doesn't move),
## without the rat in it.
func _cage_cells() -> Array[Box]:
	if not _cage_boxes.is_empty():
		return _cage_boxes
	var cage := outro.set_.cage
	var floor_y := cage.global_position.y + CAGE_FLOOR * cage.global_transform.basis.get_scale().x + 0.002
	for mesh in Art.meshes(cage):
		if outro.cage_rat.is_ancestor_of(mesh):
			continue
		for cell in mesh_cells(mesh.mesh, PROP_CELLS["the cage"]):
			var box := Box.make(mesh.name, mesh.global_transform * Transform3D(cell.basis, Vector3.ZERO), cell.aabb,
				cell.radius)
			if box.highest() >= floor_y:  # (the tray and the bedding under the rat: its _gap)
				_cage_boxes.append(box)
	return _cage_boxes


## The rats' eyes, each pair as it opens (a little after: open), and the last pair by her face: the
## camera sees them, no mesh nor grandma on the way.
func _check_eyes(from: float, to: float) -> void:
	for i in outro.gang.size():
		var at := outro.eyes_at(i) + 0.12
		if at < from or at > to:
			continue
		_seek(at)
		var member: Dictionary = outro.gang[i]
		var label: String = member["spot"]["name"]
		for glint: MeshInstance3D in member["glints"]:
			if not glint.visible:
				_problem("eyes-shut-" + label, "the eyes at the %s aren't open" % label, at, 0.0)
				continue
			_sight(at, "the eyes at the " + label, glint.global_position, member["actor"])
	var at := Outro.B_BUTTON + 0.2
	if at >= from and at <= to:
		_seek(at)
		var head := Outro.bone_xform(outro.grandma, "head") * Vector3(0.0, 0.19, 0.0)
		for glint in outro._button_glints:
			_sight(at, "the last eyes", glint.global_position, null)
			var far := glint.global_position.distance_to(head) - BUTTON_REACH
			if far > 0.0:
				_problem("button-far", "the last eyes aren't by her face", at, far)


## Seeks `time` for a check of its own (the test's tweak too).
func _seek(time: float) -> void:
	outro.seek(time)
	if _tweak.is_valid():
		_tweak.call(outro, time)
	_bone_now.clear()
	_boxes_now.clear()


## Whether the camera sees `eye`: a problem names what's in the way (a mesh of the set, or grandma).
## `owner`'s own meshes don't hide its eyes.
func _sight(time: float, what: String, eye: Vector3, owner: Node) -> void:
	var from := outro.camera.global_position
	var length := from.distance_to(eye)
	var to := from + (eye - from) * (length - EYE_CLEARANCE) / length
	for mesh: MeshInstance3D in outro.set_.find_children("*", "MeshInstance3D", true, false):
		var effect := mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # (glints, crumbs, effects)
		if mesh.mesh == null or not mesh.is_visible_in_tree() or effect or (owner != null and owner.is_ancestor_of(mesh)) \
				or mesh.get_viewport() != outro.get_viewport():
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		if not box.grow(0.01).intersects_segment(from, to):
			continue
		var id := mesh.mesh.get_instance_id()
		if not _triangles.has(id):
			_triangles[id] = mesh.mesh.generate_triangle_mesh()
		var inv := mesh.global_transform.affine_inverse()
		var hit := _triangles[id].intersect_segment(inv * from, inv * to)
		if not hit.is_empty():
			_problem("sight-%s-%s" % [what, mesh.name], "%s are hidden from the camera by %s" % [what, mesh.get_path()], time,
				0.0)
	for bone in BODY_BONES:
		for k in int(length / 0.01):
			var p := from.lerp(to, float(k) / (length / 0.01))
			for piece in _pieces_near(bone, p, 0.0):
				if piece.sdf(p) < 0.0:
					_problem("sight-%s-grandma" % what, "%s are hidden from the camera by %s" % [what, piece.name], time, 0.0)
					return
