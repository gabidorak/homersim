extends GutTest
## StatusRules (GDD §5.4, M4): stacking, immunity windows, expiry, bite → knockdown counting.

const S := StatusComponent.Status

var rules: StatusRules


func before_each() -> void:
	rules = StatusRules.new()


func _bite(now: float) -> StatusRules.Bite:
	return rules.bite(now, 0.7, 3.0, 3, 6.0, 4.0)


func test_status_expires() -> void:
	assert_true(rules.apply(S.STUNNED, 2.0, 10.0))
	assert_true(rules.has(S.STUNNED, 11.9))
	assert_false(rules.has(S.STUNNED, 12.0))
	assert_eq(rules.tick(12.0), [S.STUNNED] as Array[StatusComponent.Status])
	assert_eq(rules.flags(12.0), 0)


func test_reapply_extends_non_blocking_status() -> void:
	rules.apply(S.REVEALED, 10.0, 0.0)
	rules.apply(S.REVEALED, 5.0, 8.0)
	assert_true(rules.has(S.REVEALED, 12.5), "extended to 13")
	rules.apply(S.REVEALED, 1.0, 9.0)
	assert_true(rules.has(S.REVEALED, 12.5), "a shorter one never shortens it")


func test_stun_cannot_be_chained_while_active() -> void:
	assert_true(rules.apply(S.STUNNED, 2.0, 0.0))
	assert_false(rules.apply(S.STUNNED, 2.0, 1.0), "already stunned")
	assert_false(rules.has(S.STUNNED, 2.5), "not extended")


func test_invulnerable_blocks_stun_knockdown_and_bites() -> void:
	rules.apply(S.INVULNERABLE, 3.0, 0.0)
	assert_false(rules.apply(S.STUNNED, 2.0, 1.0))
	assert_false(rules.apply(S.KNOCKED_DOWN, 4.0, 1.0))
	assert_eq(_bite(1.0), StatusRules.Bite.IGNORED)
	assert_almost_eq(rules.speed_factor(1.0), 1.0, 0.001, "an ignored bite doesn't slow")
	assert_true(rules.apply(S.STUNNED, 2.0, 3.0), "invulnerability is over")


func test_rat_stun_immunity_window() -> void:
	rules.stun_immunity_s = 1.5
	rules.apply(S.STUNNED, 2.0, 0.0)
	rules.tick(2.0)
	assert_true(rules.is_immune(S.STUNNED, 2.0))
	assert_false(rules.apply(S.STUNNED, 2.0, 3.4), "immune until 3.5")
	assert_true(rules.apply(S.STUNNED, 2.0, 3.5))


func test_immunity_starts_at_expiry_even_if_ticked_late() -> void:
	rules.stun_immunity_s = 1.5
	rules.apply(S.STUNNED, 2.0, 0.0)
	rules.tick(3.0)  # a late tick: the stun really ended at 2.0
	assert_true(rules.apply(S.STUNNED, 2.0, 3.5))


func test_clearing_a_stun_starts_the_immunity_too() -> void:
	rules.stun_immunity_s = 1.5
	rules.apply(S.STUNNED, 2.0, 0.0)
	rules.clear(S.STUNNED, 1.0)
	assert_false(rules.has(S.STUNNED, 1.0))
	assert_false(rules.apply(S.STUNNED, 2.0, 2.0))
	assert_true(rules.apply(S.STUNNED, 2.0, 2.5))


func test_no_immunity_without_a_window() -> void:
	rules.apply(S.STUNNED, 2.0, 0.0)
	rules.tick(2.0)
	assert_true(rules.apply(S.STUNNED, 2.0, 2.0), "supervisors have no stun immunity")


func test_slows_multiply_with_a_floor() -> void:
	rules.set_speed_factor(&"bite", 0.7, 3.0, 0.0)
	assert_almost_eq(rules.speed_factor(0.0), 0.7, 0.001)
	rules.set_speed_factor(&"radiation", 0.8, 3.0, 0.0)
	assert_almost_eq(rules.speed_factor(0.0), 0.56, 0.001)
	rules.set_speed_factor(&"puddle", 0.5, 3.0, 0.0)
	assert_almost_eq(rules.speed_factor(0.0), StatusRules.SLOW_FLOOR, 0.001, "0.28 floored at 0.4")
	assert_true(rules.flags(0.0) & (1 << S.SLOWED) != 0)


func test_same_source_replaces_its_factor() -> void:
	rules.set_speed_factor(&"bite", 0.7, 3.0, 0.0)
	rules.set_speed_factor(&"bite", 0.7, 3.0, 2.0)
	assert_almost_eq(rules.speed_factor(2.0), 0.7, 0.001, "not 0.49")
	assert_almost_eq(rules.speed_factor(4.5), 0.7, 0.001, "refreshed until 5")
	assert_almost_eq(rules.speed_factor(5.0), 1.0, 0.001)


func test_boost_applies_on_top_of_the_floor() -> void:
	rules.set_speed_factor(&"donut", 1.2, 20.0, 0.0)
	assert_almost_eq(rules.speed_factor(0.0), 1.2, 0.001)
	assert_true(rules.flags(0.0) & (1 << S.BOOSTED) != 0)
	assert_false(rules.flags(0.0) & (1 << S.SLOWED) != 0)
	rules.set_speed_factor(&"a", 0.5, 5.0, 0.0)
	rules.set_speed_factor(&"b", 0.5, 5.0, 0.0)
	assert_almost_eq(rules.speed_factor(0.0), 0.48, 0.001, "floor 0.4 × boost 1.2")


func test_slows_expire() -> void:
	rules.set_speed_factor(&"bite", 0.7, 3.0, 0.0)
	rules.tick(3.0)
	assert_almost_eq(rules.speed_factor(3.0), 1.0, 0.001)
	assert_eq(rules.flags(3.0), 0)


func test_three_bites_within_six_seconds_knock_down() -> void:
	assert_eq(_bite(0.0), StatusRules.Bite.SLOWED)
	assert_eq(_bite(2.0), StatusRules.Bite.SLOWED)
	assert_eq(_bite(4.0), StatusRules.Bite.KNOCKED_DOWN)
	assert_true(rules.has(S.KNOCKED_DOWN, 7.9))
	assert_false(rules.has(S.KNOCKED_DOWN, 8.0), "4 s knockdown")


func test_bites_spread_out_do_not_knock_down() -> void:
	assert_eq(_bite(0.0), StatusRules.Bite.SLOWED)
	assert_eq(_bite(3.0), StatusRules.Bite.SLOWED)
	assert_eq(_bite(6.5), StatusRules.Bite.SLOWED, "the first bite fell out of the 6 s window")
	assert_eq(_bite(8.0), StatusRules.Bite.KNOCKED_DOWN, "bites at 3, 6.5 and 8")


func test_bites_on_a_knocked_down_body_are_ignored() -> void:
	_bite(0.0)
	_bite(0.5)
	_bite(1.0)
	assert_eq(_bite(2.0), StatusRules.Bite.IGNORED)


func test_knockdown_immunity_prevents_perma_knockdown() -> void:
	rules.knockdown_immunity_s = 3.0
	_bite(0.0)
	_bite(0.5)
	assert_eq(_bite(1.0), StatusRules.Bite.KNOCKED_DOWN)
	rules.tick(5.0)  # knocked down 1..5, immune 5..8
	assert_eq(_bite(5.5), StatusRules.Bite.SLOWED)
	assert_eq(_bite(6.0), StatusRules.Bite.SLOWED)
	assert_eq(_bite(6.5), StatusRules.Bite.SLOWED, "immune: bites slow but don't count")
	assert_false(rules.has(S.KNOCKED_DOWN, 6.5))
	assert_almost_eq(rules.speed_factor(6.5), 0.7, 0.001)
	_bite(8.0)
	_bite(8.5)
	assert_eq(_bite(9.0), StatusRules.Bite.KNOCKED_DOWN, "the count restarted after the immunity")


func test_blocking_statuses() -> void:
	for status: StatusComponent.Status in [S.LOCKED, S.STUNNED, S.KNOCKED_DOWN, S.CARRIED, S.CAGED, S.ELIMINATED]:
		assert_true(StatusRules.blocks_actions(1 << status), S.keys()[status])
	for status: StatusComponent.Status in [S.SLOWED, S.INVULNERABLE, S.REVEALED, S.BOOSTED]:
		assert_false(StatusRules.blocks_actions(1 << status), S.keys()[status])


func test_reset_forgets_everything() -> void:
	rules.stun_immunity_s = 1.5
	rules.apply(S.STUNNED, 2.0, 0.0)
	rules.tick(2.0)
	rules.set_speed_factor(&"bite", 0.7, 3.0, 2.0)
	rules.reset()
	assert_eq(rules.flags(2.0), 0)
	assert_true(rules.apply(S.STUNNED, 2.0, 2.0))
