extends GutTest
## M10: a team's AiBlackboard: claims with a TTL, their release, the lever pair handshake.

var board: AiBlackboard


func before_each() -> void:
	board = AiBlackboard.new()


func test_claims_are_one_bot_each() -> void:
	assert_true(board.claim("repair:pumps", -1001, 0.0, 3.0))
	assert_false(board.claim("repair:pumps", -1002, 1.0, 3.0), "taken")
	assert_true(board.claimed_by_other("repair:pumps", -1002, 1.0))
	assert_false(board.claimed_by_other("repair:pumps", -1001, 1.0), "not by someone else for its owner")
	assert_true(board.claim("repair:pumps", -1001, 2.0, 3.0), "the owner renews")
	assert_eq(board.owner_of("repair:pumps", 4.9), -1001, "renewed until 5")
	assert_true(board.claim("repair:grid", -1002, 1.0, 3.0), "another job")


func test_claims_lapse_after_their_ttl() -> void:
	board.claim("sabotage:grid", -1003, 0.0, 3.0)
	assert_eq(board.owner_of("sabotage:grid", 2.9), -1003)
	assert_eq(board.owner_of("sabotage:grid", 3.0), 0, "lapsed")
	assert_true(board.claim("sabotage:grid", -1004, 3.1, 3.0), "free for another bot")


func test_release() -> void:
	board.claim("free:CageA", -1003, 0.0, 3.0)
	board.release("free:CageA", -1004)
	assert_eq(board.owner_of("free:CageA", 1.0), -1003, "only the owner releases")
	board.release("free:CageA", -1003)
	assert_eq(board.owner_of("free:CageA", 1.0), 0)
	board.claim("a", -1003, 0.0, 3.0)
	board.claim("b", -1003, 0.0, 3.0)
	board.claim("c", -1004, 0.0, 3.0)
	board.lever_join(&"rods", -1003, 0.0, 15.0)
	board.release_all(-1003)
	assert_eq([board.owner_of("a", 1.0), board.owner_of("b", 1.0), board.owner_of("c", 1.0)], [0, 0, -1004],
		"a bot that leaves frees what it held")
	assert_eq(board.lever_side(&"rods", -1003), "", "its lever side too")


func test_lever_pair_handshake() -> void:
	assert_eq(board.lever_waiting_side(&"rods"), "", "no pair yet")
	assert_eq(board.lever_join(&"rods", -1003, 0.0, 15.0), "A", "the first opens the pair")
	assert_eq(board.lever_waiting_side(&"rods"), "B", "it waits for a partner on B")
	assert_eq(board.lever_partner(&"rods", -1003), 0)
	assert_eq(board.lever_join(&"rods", -1004, 1.0, 15.0), "B", "the next joins")
	assert_eq(board.lever_partner(&"rods", -1003), -1004)
	assert_eq(board.lever_partner(&"rods", -1004), -1003)
	assert_eq(board.lever_waiting_side(&"rods"), "", "full")
	assert_eq(board.lever_join(&"rods", -1005, 2.0, 15.0), "", "no third")
	assert_eq(board.lever_join(&"rods", -1003, 2.0, 15.0), "A", "joining again keeps the side")
	board.lever_leave(&"rods", -1004)
	assert_eq(board.lever_waiting_side(&"rods"), "B", "the partner left: waiting again")
	board.lever_leave(&"rods", -1003)
	assert_false(board.pairs.has(&"rods"), "empty pairs go")


func test_a_pair_nobody_joins_goes_stale() -> void:
	board.lever_join(&"turbine", -1003, 0.0, 15.0)
	assert_eq(board.lever_join(&"turbine", -1004, 20.0, 15.0), "A", "the opener waited too long: a new pair")
	assert_eq(board.lever_side(&"turbine", -1003), "", "the old opener is out")


func test_lever_take_picks_a_side() -> void:
	assert_true(board.lever_take(&"rods", -1003, "B", 0.0, 15.0), "take B (a human holds A)")
	assert_eq(board.lever_side(&"rods", -1003), "B")
	assert_eq(board.lever_waiting_side(&"rods"), "A")
	assert_false(board.lever_take(&"rods", -1004, "B", 1.0, 15.0), "B is taken")
	assert_true(board.lever_take(&"rods", -1004, "A", 1.0, 15.0))
	assert_eq(board.lever_partner(&"rods", -1004), -1003)


func test_sightings_and_events() -> void:
	board.report_sighting(7, Vector3(1, 0, 2), 3.0, -1003)
	assert_eq(board.sightings[7]["pos"], Vector3(1, 0, 2))
	assert_eq(board.sightings[7]["by"], -1003)
	board.add_event("snap", Vector3.ZERO, 0.0)
	board.add_event("snap", Vector3.ONE, 20.0)
	assert_eq(board.events.size(), 1, "old events are dropped")
	board.clear()
	assert_true(board.claims.is_empty() and board.sightings.is_empty() and board.events.is_empty())
