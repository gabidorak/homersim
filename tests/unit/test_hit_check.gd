extends GutTest
## HitCheck: the broom/bite reach and cone (flat, generous), and the aim clamp.

const ORIGIN := Vector3(0, 1, 0)
const AHEAD := Vector3(0, 0, -1)  # Godot's forward


func test_target_ahead_in_range() -> void:
	assert_true(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0, 1, -2), 2.5, 70.0))


func test_out_of_range() -> void:
	assert_false(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0, 1, -2.6), 2.5, 70.0))


func test_cone_edges() -> void:
	var inside := Vector3(0, 0, -2).rotated(Vector3.UP, deg_to_rad(34.0)) + ORIGIN
	var outside := Vector3(0, 0, -2).rotated(Vector3.UP, deg_to_rad(36.0)) + ORIGIN
	assert_true(HitCheck.in_reach(ORIGIN, AHEAD, inside, 2.5, 70.0))
	assert_false(HitCheck.in_reach(ORIGIN, AHEAD, outside, 2.5, 70.0))


func test_behind_is_missed_unless_any_direction() -> void:
	assert_false(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0, 1, 1), 2.5, 70.0))
	assert_true(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0, 1, 1), 2.5, 360.0))


func test_cone_is_flat_so_a_rat_at_your_feet_counts() -> void:
	# A supervisor looking slightly down at a rat 1.2 m ahead, 0.75 m lower.
	var aim := Vector3(0, -0.2, -1).normalized()
	assert_true(HitCheck.in_reach(Vector3(0, 0.9, 0), aim, Vector3(0, 0.25, -1.2), 2.5, 70.0))


func test_height_limit() -> void:
	assert_false(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0, 2.6, -1), 2.5, 70.0), "on a high shelf")


func test_point_blank_counts_from_any_direction() -> void:
	assert_true(HitCheck.in_reach(ORIGIN, AHEAD, Vector3(0.1, 1, 0.1), 2.5, 70.0))


func test_targets_sorted_nearest_first() -> void:
	var candidates := {11: Vector3(0, 1, -2.2), 12: Vector3(0, 1, -1), 13: Vector3(0, 1, 2), 14: Vector3(0.5, 1, -1.5)}
	assert_eq(HitCheck.targets_in_reach(ORIGIN, AHEAD, candidates, 2.5, 70.0), [12, 14, 11] as Array[int])


func test_clamp_aim() -> void:
	var near := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(20.0))
	var far := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(90.0))
	assert_almost_eq(HitCheck.clamp_aim(near, AHEAD, 45.0).angle_to(near), 0.0, 0.001, "trusted")
	assert_almost_eq(HitCheck.clamp_aim(far, AHEAD, 45.0).angle_to(AHEAD), 0.0, 0.001, "too far: synced look")
	assert_almost_eq(HitCheck.clamp_aim(Vector3(NAN, 0, 0), AHEAD, 45.0).angle_to(AHEAD), 0.0, 0.001, "garbage")
