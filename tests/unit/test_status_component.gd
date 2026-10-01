extends GutTest
## StatusComponent outside a network: it publishes StatusRules' result as flags and speed_factor.
## The rules themselves are in test_status_rules.gd.

const S := StatusComponent.Status

var status: StatusComponent


func before_each() -> void:
	status = autofree(StatusComponent.new())


func test_apply_and_clear() -> void:
	assert_true(status.can_act())
	assert_true(status.apply(S.LOCKED))
	assert_true(status.has(S.LOCKED))
	assert_false(status.can_act())
	status.clear(S.LOCKED)
	assert_false(status.has(S.LOCKED))
	assert_true(status.can_act())


func test_non_blocking_status_allows_actions() -> void:
	status.apply(S.REVEALED, 10.0)
	assert_true(status.has(S.REVEALED))
	assert_true(status.can_act())


func test_refused_status_returns_false() -> void:
	status.apply(S.INVULNERABLE, 10.0)
	watch_signals(status)
	assert_false(status.apply(S.STUNNED, 2.0))
	assert_false(status.has(S.STUNNED))
	assert_signal_not_emitted(status, "applied")


func test_speed_factor_is_published() -> void:
	status.set_speed_factor(&"bite", 0.7, 10.0)
	assert_almost_eq(status.speed_multiplier(), 0.7, 0.001)
	assert_true(status.has(S.SLOWED))


func test_role_immunity_from_role_data() -> void:
	status.setup(Role.data(Role.Kind.RAT))
	assert_eq(status.rules.stun_immunity_s, 1.5)
	status.setup(Role.data(Role.Kind.SUPERVISOR))
	assert_eq(status.rules.knockdown_immunity_s, 3.0)


func test_bite_uses_ability_numbers() -> void:
	var bite: AbilityData = load("res://data/abilities/bite.tres")
	assert_eq(status.bite(bite), StatusRules.Bite.SLOWED)
	assert_almost_eq(status.speed_multiplier(), 0.7, 0.001)
	status.bite(bite)
	watch_signals(status)
	assert_eq(status.bite(bite), StatusRules.Bite.KNOCKED_DOWN)
	assert_true(status.has(S.KNOCKED_DOWN))
	assert_signal_emitted_with_parameters(status, "applied", [S.KNOCKED_DOWN])


func test_changed_signal_on_flag_change_only() -> void:
	watch_signals(status)
	status.apply(S.LOCKED)
	status.apply(S.LOCKED)
	assert_signal_emit_count(status, "changed", 1)
