class_name ToastPath
extends RefCounted
## One slice of bread through an end-of-match cinematic (client/outro/outro.gd), as a pure function of
## the clock: transform_at(t) is where it is at any time (its centre, the slice standing face to +Z
## when not turned), state_at(t) what it's doing. The physics tests (tests/unit/test_outro.gd) sample
## both at 1/120 s: a slice must rest on what it rests on, fly like a thrown thing, and never go
## through anything.
##
## A path is a list of phases, each from its start time to the next one's:
##   hold      still (in a slot, on the plate): REST on `support`, or SLOT
##   move      eased from one transform to another (the toaster's carriage): SLOT
##   flight    thrown: p(t) = p0 + v0 τ + ½ g τ² with g = G down, where τ is the flight's own clock. τ
##             runs with the real one, except near the top, where it slows down for a cartoon hang
##             (`hang`: the slowest, 0..1, and how long): the physics tests only check gravity outside
##             that window. Straight up while still in the slot, then a flick at the rim sends it
##             sideways and sets it turning (rim_s after the launch): FLIGHT
##   squash    landed: squashed flat on `support`, then a little bounce (itself a flight) and a
##             smaller squash: LANDING, then REST
##   follow    held: wherever `follow` (a Callable(t) -> Transform3D) says: HELD
##   gone      eaten: GONE

enum State { SLOT, FLIGHT, LANDING, REST, HELD, DRAPED, GONE }

const G := 9.8  ## m/s², every flight
const BOUNCE := 0.011  ## m: how high a landed slice bounces
const SQUASH := 0.28  ## how flat it squashes on landing (its thickness shrinks by this, its face grows)

var size := Vector3(0.104, 0.118, 0.014)  ## the slice: width, height, thickness (tools/blender/kitchen.py)
var _phases: Array[Dictionary] = []


func _init(p_size: Vector3) -> void:
	size = p_size


func hold(t0: float, xform: Transform3D, state := State.REST, support := "") -> ToastPath:
	_phases.append({"t0": t0, "kind": "hold", "xform": xform, "state": state, "support": support})
	return self


func move(t0: float, t1: float, from: Transform3D, to: Transform3D, trans := Tween.TRANS_SINE,
		ease_ := Tween.EASE_IN_OUT, state := State.SLOT) -> ToastPath:
	_phases.append({"t0": t0, "kind": "move", "t1": t1, "from": from, "to": to, "trans": trans, "ease": ease_,
		"state": state})
	hold(t1, to, state)
	return self


func gone(t0: float) -> ToastPath:
	_phases.append({"t0": t0, "kind": "gone", "state": State.GONE})
	return self


func follow(t0: float, fn: Callable, state := State.HELD) -> ToastPath:
	_phases.append({"t0": t0, "kind": "follow", "fn": fn, "state": state})
	return self


## A throw from `from` (the slice standing in its slot) that lands it flat on top of `support_top`
## (a world height) at `land_at` (x, z), turned `flip` radians about X on the way (a multiple of TAU
## plus or minus a quarter turn, so it lands flat). It leaves at `t0` going up at `v_up`; the flick
## at the rim comes `rim_s` later. Then the squash and the bounce, and it rests on `support`.
## Returns the time it lands.
func throw(t0: float, from: Transform3D, v_up: float, land_at: Vector2, support_top: float, support: String,
		flip: float, rim_s: float, hang := Vector2(0.35, 0.16)) -> float:
	var p0 := from.origin
	var rim_y := p0.y + v_up * rim_s - 0.5 * G * rim_s * rim_s
	var v_rim := v_up - G * rim_s
	# Lands flat: its centre half a thickness over the support.
	var land_y := support_top + size.z * 0.5
	var fall := rim_y - land_y
	var tau_land := rim_s + (v_rim + sqrt(v_rim * v_rim + 2.0 * G * fall)) / G  # flight clock at touchdown
	var v_side := Vector2(land_at.x - p0.x, land_at.y - p0.z) / (tau_land - rim_s)
	var tau_top := v_up / G
	var flight := {"t0": t0, "kind": "flight", "p0": p0, "basis": from.basis, "v_up": v_up, "v_side": v_side,
		"rim": rim_s, "tau_land": tau_land, "flip": flip, "hang_k": hang.x, "hang_w": hang.y, "tau_top": tau_top,
		"state": State.FLIGHT}
	# The hang's window is centred on the top of the arc (real time); over the whole window the clock
	# loses k w / 2, a quarter of it by the middle.
	flight["t_top"] = t0 + tau_top + hang.x * hang.y * 0.25
	var t_land := t0 + tau_land + hang.x * hang.y * 0.5
	flight["t_land"] = t_land
	_phases.append(flight)
	var landed := Transform3D(Basis(Vector3.RIGHT, flip) * from.basis,
		Vector3(land_at.x, land_y, land_at.y))
	_squash(t_land, landed, support_top, support)
	return t_land


func _squash(t0: float, landed: Transform3D, support_top: float, support: String) -> void:
	var v := sqrt(2.0 * G * BOUNCE)
	var up := 2.0 * v / G
	_phases.append({"t0": t0, "kind": "squash", "xform": landed, "top": support_top, "dur": 0.07, "amount": SQUASH,
		"state": State.LANDING, "support": support})
	_phases.append({"t0": t0 + 0.07, "kind": "bounce", "xform": landed, "top": support_top, "v": v, "dur": up,
		"state": State.FLIGHT})
	_phases.append({"t0": t0 + 0.07 + up, "kind": "squash", "xform": landed, "top": support_top, "dur": 0.05,
		"amount": SQUASH * 0.45, "state": State.LANDING, "support": support})
	hold(t0 + 0.12 + up, landed, State.REST, support)


func _phase(t: float) -> Dictionary:
	var at: Dictionary = _phases[0]
	for phase in _phases:
		if t >= phase["t0"]:
			at = phase
	return at


func state_at(t: float) -> Dictionary:
	var phase := _phase(t)
	return {"state": phase["state"], "support": phase.get("support", "")}


## Where the slice is at `t`, and its squash (scale), as a transform of its centre.
func transform_at(t: float) -> Transform3D:
	var phase := _phase(t)
	match phase["kind"]:
		"hold":
			return phase["xform"]
		"move":
			var u := clampf((t - phase["t0"]) / (phase["t1"] - phase["t0"]), 0.0, 1.0)
			u = Tween.interpolate_value(0.0, 1.0, u, 1.0, phase["trans"], phase["ease"])
			return (phase["from"] as Transform3D).interpolate_with(phase["to"], u)
		"flight":
			return _flight(phase, t)
		"squash":
			var u := clampf((t - phase["t0"]) / phase["dur"], 0.0, 1.0)
			var k: float = phase["amount"] * sin(u * PI)
			return _flat_on(phase["xform"], phase["top"], k, 0.0)
		"bounce":
			var s := t - float(phase["t0"])
			var h: float = phase["v"] * s - 0.5 * G * s * s
			return _flat_on(phase["xform"], phase["top"], 0.0, maxf(h, 0.0))
		"follow":
			return (phase["fn"] as Callable).call(t)
		"gone":
			return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3(0, -100, 0))
	return Transform3D.IDENTITY


## The flight's own clock at real time `t`: the real one, slowed near the top of the arc (dτ/dt dips
## to 1 - hang_k, in a cos² window hang_w long, centred where τ reaches the top): the cartoon hang.
static func flight_clock(phase: Dictionary, t: float) -> float:
	var s := t - float(phase["t0"])
	var k: float = phase["hang_k"]
	var w: float = phase["hang_w"]
	var centre := float(phase["tau_top"]) + k * w * 0.25  # (real seconds after the launch)
	var a := clampf((s - (centre - w * 0.5)) / w, 0.0, 1.0)
	# What the window has taken so far: k ∫ cos² = k w/2 (a - sin(2πa) / 2π).
	return s - k * w * 0.5 * (a - sin(TAU * a) / TAU)


func _flight(phase: Dictionary, t: float) -> Transform3D:
	var tau := flight_clock(phase, t)
	var p0: Vector3 = phase["p0"]
	var rim: float = phase["rim"]
	var y := p0.y + float(phase["v_up"]) * tau - 0.5 * G * tau * tau
	var side := maxf(tau - rim, 0.0)
	var v_side: Vector2 = phase["v_side"]
	var pos := Vector3(p0.x + v_side.x * side, y, p0.z + v_side.y * side)
	var turn := float(phase["flip"]) * clampf(side / (float(phase["tau_land"]) - rim), 0.0, 1.0)
	return Transform3D(Basis(Vector3.RIGHT, turn) * (phase["basis"] as Basis), pos)


## A slice lying flat (`xform`) on the surface at `top`, squashed by `k` (thinner, wider), `lift` m up.
func _flat_on(xform: Transform3D, top: float, k: float, lift: float) -> Transform3D:
	var thick := size.z * (1.0 - k)
	var grow := 1.0 + k * 0.45
	var basis := xform.basis.scaled_local(Vector3(grow, grow, 1.0 - k))
	return Transform3D(basis, Vector3(xform.origin.x, top + thick * 0.5 + lift, xform.origin.z))


## Every throw of the path: [{t0 (launch), t_rim (the flick), t_top, hang (its window, real time),
## t_land}], for the physics tests.
func flights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for phase in _phases:
		if phase["kind"] == "flight":
			var w: float = phase["hang_w"]
			var centre: float = phase["t0"] + phase["tau_top"] + phase["hang_k"] * w * 0.25
			out.append({"t0": phase["t0"], "t_rim": phase["t0"] + phase["rim"], "t_top": phase["t_top"],
				"hang": Vector2(centre - w * 0.5, centre + w * 0.5), "t_land": phase["t_land"]})
		elif phase["kind"] == "bounce":
			out.append({"t0": phase["t0"], "t_rim": phase["t0"], "t_top": phase["t0"] + phase["v"] / G,
				"hang": Vector2(-1, -1), "t_land": phase["t0"] + phase["dur"]})
	return out
