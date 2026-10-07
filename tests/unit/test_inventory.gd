extends GutTest
## The inventory rules (GDD §5.1): separate snap trap and cheese lure charges, each refilled by its own
## box in Storage; a supervisor carries one donut from the Break Room counter and
## eats it later from the hotbar; the hotbar's slots per role, their keys and their icons.


func _inventory(role: Role.Kind) -> Inventory:
	var inv := Inventory.new()
	inv.setup(role)
	autofree(inv)
	return inv


func test_start_kit() -> void:
	var sup := _inventory(Role.Kind.SUPERVISOR)
	assert_eq([sup.keycard, sup.snap_charges, sup.lure_charges, sup.donuts], [true, 3, 3, 0])
	var rat := _inventory(Role.Kind.RAT)
	assert_eq([rat.keycard, rat.snap_charges, rat.lure_charges, rat.donuts], [false, 0, 0, 0])


func test_each_trap_kind_has_its_own_charges() -> void:
	var inv := _inventory(Role.Kind.SUPERVISOR)
	inv.set_charges(Inventory.SNAP_TRAP, inv.charges(Inventory.SNAP_TRAP) - 1)
	assert_eq([inv.charges(Inventory.SNAP_TRAP), inv.charges(Inventory.CHEESE_LURE)], [2, 3], "a snap trap costs no lure")
	inv.set_charges(Inventory.CHEESE_LURE, 0)
	assert_eq([inv.snap_charges, inv.lure_charges], [2, 0], "and a lure no snap trap")
	assert_eq([inv.max_charges(Inventory.SNAP_TRAP), inv.max_charges(Inventory.CHEESE_LURE)],
		[inv.tuning.snap_trap_charges, inv.tuning.cheese_lure_charges])
	assert_eq(inv.charges(&"broom"), 0, "not a trap")


func test_every_trap_has_a_refill_box() -> void:
	var traps := Hotbar.slots_for(Role.Kind.SUPERVISOR).filter(func(item: StringName) -> bool: return item != Hotbar.DONUT)
	assert_eq(traps.size(), 2)
	for trap: StringName in traps:
		assert_true(Pickup.REFILLS.values().has(trap), "a Storage box refills %s" % trap)
	for refill: String in Pickup.REFILLS:
		assert_true(Pickup.LOOKS.has(refill), "%s has a look" % refill)


func test_take_then_eat_a_donut() -> void:
	var inv := _inventory(Role.Kind.SUPERVISOR)
	assert_true(inv.can_take_donut(), "the counter has one for us at the start")
	inv.take_donut()
	assert_eq(inv.donuts, 1, "carried")
	assert_false(inv.can_take_donut(), "one at a time (and the counter's wait started)")
	assert_eq(inv.donut_wait_left, roundi(inv.tuning.donut_cooldown_s), "the wait starts when taking it")
	inv.eat_donut()
	assert_eq(inv.donuts, 0)
	assert_false(inv.can_take_donut(), "eating doesn't skip the counter's wait")
	inv.eat_donut()
	assert_eq(inv.donuts, 0, "never below zero")


func test_carry_limit_comes_from_the_tuning() -> void:
	var inv := _inventory(Role.Kind.SUPERVISOR)
	inv.tuning = inv.tuning.duplicate()
	inv.tuning.donut_carry_max = 2
	inv.tuning.donut_cooldown_s = 0.0
	inv.take_donut()
	assert_true(inv.can_take_donut(), "room for a second one")
	inv.take_donut()
	assert_false(inv.can_take_donut(), "full")


func test_hotbar_slots_per_role() -> void:
	assert_eq(Hotbar.slots_for(Role.Kind.SUPERVISOR), [&"snap_trap", &"cheese_lure", Hotbar.DONUT] as Array[StringName])
	assert_eq(Hotbar.slots_for(Role.Kind.RAT), [] as Array[StringName], "rats only carry stolen loot (not selectable)")
	assert_eq(Hotbar.slots_for(Role.Kind.NONE), [] as Array[StringName], "nothing in the lobby")


func test_every_slot_has_a_key_and_an_icon() -> void:
	for role: Role.Kind in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		var slots := Hotbar.slots_for(role)
		assert_true(slots.size() <= Hotbar.SLOT_ACTIONS.size(), "a key for every %s slot" % Role.display_name(role))
		for item in slots:
			assert_true(ResourceLoader.exists(HotbarView.ICONS % item), "an icon for %s" % item)
	assert_true(ResourceLoader.exists(HotbarView.ICONS % "keycard"), "an icon for the keycard (and stolen loot)")
	for action in Hotbar.SLOT_ACTIONS + [&"slot_next", &"slot_prev"]:
		assert_true(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
			"%s has a default key" % action)
		assert_eq(Keys.conflicts(action, Keys.encode(InputMap.action_get_events(action)[0]), Config.all_bindings()),
			[] as Array[StringName], "%s shares its key with nothing in a match" % action)
