extends GutTest
## StatusComponent outside a network: tests drive apply/clear and the expiry directly.

var status: StatusComponent


func before_each() -> void:
	status = autofree(StatusComponent.new())


func test_apply_and_clear() -> void:
	assert_true(status.can_act())
	status.apply(StatusComponent.Status.LOCKED)
	assert_true(status.has(StatusComponent.Status.LOCKED))
	assert_false(status.can_act())
	status.clear(StatusComponent.Status.LOCKED)
	assert_false(status.has(StatusComponent.Status.LOCKED))
	assert_true(status.can_act())


func test_timed_status_expires() -> void:
	status.apply(StatusComponent.Status.LOCKED, -1.0)  # already in the past
	assert_true(status.has(StatusComponent.Status.LOCKED), "active until the next tick")
	status._physics_process(0.0)
	assert_false(status.has(StatusComponent.Status.LOCKED))


func test_non_blocking_status_allows_actions() -> void:
	status.apply(StatusComponent.Status.REVEALED, 10.0)
	assert_true(status.has(StatusComponent.Status.REVEALED))
	assert_true(status.can_act())


func test_changed_signal_on_flag_change_only() -> void:
	watch_signals(status)
	status.apply(StatusComponent.Status.LOCKED)
	status.apply(StatusComponent.Status.LOCKED)
	assert_signal_emit_count(status, "changed", 1)
