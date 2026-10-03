extends GutTest
## M10: AiPathFollower (waypoints, links, steps) and its Stuck escalation, fed made-up positions.

const K := AiPathFollower.LinkKind
const U := AiPathFollower.Unstick


func _follower(points: Array, kinds: Array = [], ups: Array = [], feet: Array = []) -> AiPathFollower:
	var f := AiPathFollower.new()
	f.arrive_radius = 0.4
	f.slow_radius = 1.5
	f.set_path(PackedVector3Array(points), PackedInt32Array(kinds), PackedVector3Array(ups), PackedVector3Array(feet))
	return f


func test_waypoints_are_reached_in_order() -> void:
	var f := _follower([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 5)])
	var s := f.steer(Vector3(0.1, 0, 0), 0.0, true)
	assert_almost_eq((s["dir"] as Vector3).x, 1.0, 0.01, "heads for the second point")
	s = f.steer(Vector3(4.8, 0, 0), 0.1, true)
	assert_eq(f.index, 2, "within 0.4 m: the corner is reached")
	assert_almost_eq((s["dir"] as Vector3).z, 1.0, 0.05, "then on to the last point")
	f.steer(Vector3(5, 0, 4.9), 0.2, true)
	assert_true(f.is_done())
	assert_eq(f.steer(Vector3(5, 0, 5), 0.3, true)["dir"], Vector3.ZERO, "done: stand still")


func test_a_corner_we_went_past_counts() -> void:
	var f := _follower([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 5)])
	f.steer(Vector3(0.2, 0, 0), 0.0, true)
	f.steer(Vector3(5.3, 0, 0.6), 0.1, true)
	assert_eq(f.index, 2, "past the corner along the next segment, 0.7 m away")
	var g := _follower([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 5)])
	g.steer(Vector3(0.2, 0, 0), 0.0, true)
	g.steer(Vector3(4.4, 0, -0.5), 0.1, true)
	assert_eq(g.index, 1, "short of the corner: not reached")


func test_height_matters() -> void:
	var f := _follower([Vector3.ZERO, Vector3(0, 3, 0)])
	f.steer(Vector3.ZERO, 0.0, true)
	f.steer(Vector3(0, 0, 0.1), 0.1, true)
	assert_eq(f.index, 1, "a point right above us isn't reached from below")


func test_no_sprint_near_the_end_and_a_gentle_stop() -> void:
	var f := _follower([Vector3.ZERO, Vector3(10, 0, 0)])
	assert_true(f.steer(Vector3(0.5, 0, 0), 0.0, true)["sprint_ok"], "far from the end")
	assert_false(f.steer(Vector3(9.0, 0, 0), 0.1, true)["sprint_ok"], "the last 1.5 m: walk")
	var near: Vector3 = f.steer(Vector3(9.55, 0, 0), 0.2, true)["dir"]
	assert_true(near.length() < 1.0 and near.length() > 0.0, "slows down at the very end")


func test_ladder_up_lines_up_then_climbs_then_steps_off() -> void:
	var up := Vector3(1, 0, 0)
	var foot := Vector3(0.8, 0, 0)
	var f := _follower([Vector3(0.3, 0, 0), Vector3(2, 6, 0)], [K.LADDER], [up], [foot])
	var s := f.steer(Vector3(0.3, 0, 0), 0.0, true)
	assert_eq(s["link"], K.LADDER)
	assert_almost_eq((s["dir"] as Vector3).x, 1.0, 0.01, "on the ladder's line: push up into it")
	s = f.steer(Vector3(0.3, 0, 0.6), 0.1, true)
	assert_true((s["dir"] as Vector3).z < -0.5, "off the line: walk to the foot first")
	s = f.steer(Vector3(0.6, 3, 0.2), 0.2, false)
	assert_true((s["dir"] as Vector3).z < 0.0 and (s["dir"] as Vector3).x > 0.5, "climbing: pushes up, back onto the line")
	s = f.steer(Vector3(1.0, 5.8, 0), 0.3, false)
	assert_almost_eq((s["dir"] as Vector3).x, 1.0, 0.01, "at the top: on to the end")
	assert_false(s["jump"], "no step-up jumps on a ladder")
	f.steer(Vector3(1.8, 6, 0), 0.4, true)
	assert_true(f.is_done(), "the top counts within 0.6 m")


func test_ladder_down_walks_off_the_top_along_the_ladder() -> void:
	var up := Vector3(1, 0, 0)
	var f := _follower([Vector3(2, 6, 0), Vector3(0.3, 0, 0.5)], [K.LADDER], [up], [Vector3(0.8, 0, 0)])
	var s := f.steer(Vector3(2, 6, 0), 0.0, true)
	assert_almost_eq((s["dir"] as Vector3).x, -1.0, 0.01, "away from the wall, straight along the ladder (not toward the bottom point)")
	s = f.steer(Vector3(0.8, 0.3, 0), 0.1, false)
	assert_almost_eq((s["dir"] as Vector3).x, -1.0, 0.01, "still on the ladder in the air: keep climbing down")
	s = f.steer(Vector3(0.8, 0.0, 0), 0.2, true)
	assert_true((s["dir"] as Vector3).z > 0.5, "on the floor at the bottom: on to the end")


func test_drop_and_keycard_links() -> void:
	var f := _follower([Vector3(0, 2.8, 0), Vector3(0, 2.8, 2), Vector3(0, 0, 4)], [K.NONE, K.DROP])
	f.steer(Vector3(0, 2.8, 0.1), 0.0, true)  # (a path starts where the bot stands)
	f.steer(Vector3(0, 2.8, 1.8), 0.0, true)
	assert_eq(f.current_link(), K.DROP)
	assert_almost_eq((f.steer(Vector3(0, 2.8, 2.2), 0.1, true)["dir"] as Vector3).z, 1.0, 0.01, "walk off the edge")
	f.steer(Vector3(0, 0, 3.5), 0.2, true)
	assert_true(f.is_done(), "the bottom of a drop counts within 0.6 m")
	var door := _follower([Vector3.ZERO, Vector3(0, 0, 1.2), Vector3(0, 0, 3.6), Vector3(0, 0, 6)], [K.NONE, K.KEYCARD, K.NONE])
	door.steer(Vector3(0, 0, 0.1), 0.0, true)
	assert_eq(door.next_link(), K.KEYCARD, "heading for a keycard door's link")
	door.steer(Vector3(0, 0, 1.0), 0.1, true)
	assert_eq(door.current_link(), K.KEYCARD, "at the door: the driver presses the reader")
	assert_false(door.steer(Vector3(0, 0, 1.0), 0.2, true)["sprint_ok"], "no sprinting through links")


func test_step_jumps() -> void:
	var f := _follower([Vector3.ZERO, Vector3(1, 0.6, 0), Vector3(5, 0.6, 0)])
	var s := f.steer(Vector3(0.2, 0, 0), 0.0, true)
	assert_true(s["jump"], "a 0.6 m step 0.8 m ahead: jump")
	assert_false(f.steer(Vector3(0.25, 0, 0), 0.2, true)["jump"], "not again right away")
	assert_false(f.steer(Vector3(0.25, 0.3, 0), 1.0, false)["jump"], "not in the air")
	var low := _follower([Vector3.ZERO, Vector3(1, 0.2, 0)])
	assert_false(low.steer(Vector3(0.2, 0, 0), 0.0, true)["jump"], "a low step: try it on foot")
	assert_true(low.steer(Vector3(0.2, 0, 0), 1.0, true, true)["jump"], "…and jump when blocked")
	var high := _follower([Vector3.ZERO, Vector3(1, 2.0, 0)])
	assert_false(high.steer(Vector3(0.2, 0, 0), 0.0, true)["jump"], "too high to jump onto")


func test_stuck_escalates_then_fails() -> void:
	var st := AiPathFollower.Stuck.new()
	st.reset(0.0)
	var pos := Vector3.ZERO
	assert_eq(st.sample(pos, 0.0), U.NONE, "first sample")
	assert_eq(st.sample(pos, 0.3), U.NONE, "between checks")
	assert_eq(st.sample(pos + Vector3(0.05, 0, 0), 0.5), U.JUMP, "1st check without progress: jump")
	assert_eq(st.sample(pos, 1.0), U.SIDESTEP, "2nd: sidestep and jump")
	assert_eq(st.sample(pos, 1.5), U.REPATH, "3rd: repath")
	assert_eq(st.sample(pos, 2.0), U.JUMP, "then again from the start")
	assert_almost_eq(st.stalled_for(2.0), 2.0, 0.01)
	var t := 2.5
	var last := U.NONE
	while t < 7.0:
		last = st.sample(pos, t)
		if last == U.FAIL:
			break
		t += 0.5
	assert_eq(last, U.FAIL, "6 s without progress: give up")
	assert_almost_eq(t, 6.0, 0.01)


func test_stuck_resets_on_progress_and_waits_out_a_grace() -> void:
	var st := AiPathFollower.Stuck.new()
	st.reset(0.0)
	st.sample(Vector3.ZERO, 0.0)
	assert_eq(st.sample(Vector3.ZERO, 0.5), U.JUMP)
	assert_eq(st.sample(Vector3(1, 0, 0), 1.0), U.NONE, "moved 1 m: fine again")
	assert_eq(st.level, 0)
	assert_eq(st.sample(Vector3(1, 0, 0), 1.5), U.JUMP, "the escalation starts over")
	st.grace(3.0)
	assert_eq(st.sample(Vector3(1, 0, 0), 2.0), U.NONE, "a door is opening")
	assert_eq(st.sample(Vector3(1, 0, 0), 2.5), U.NONE)
	assert_eq(st.sample(Vector3(1, 0, 0), 3.5), U.JUMP, "after the grace")
