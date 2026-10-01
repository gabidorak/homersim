extends GutTest
## ChatService.route: TEAM and GHOST channels (M4). Peers: 1x = supervisors, 2x = rats,
## 29 = an eliminated rat, 30 = a late-joining spectator.

const C := ChatService.Channel

var members := {
	11: {"role": Role.Kind.SUPERVISOR, "ghost": false},
	21: {"role": Role.Kind.RAT, "ghost": false},
	22: {"role": Role.Kind.RAT, "ghost": false},
	29: {"role": Role.Kind.RAT, "ghost": true},
	30: {"role": Role.Kind.SPECTATOR, "ghost": true},
}


func _to(channel: int, sender: int, in_match: bool = true) -> Array:
	var r := ChatService.route(channel, sender, members, in_match)
	var to: Array = r["to"]
	to.sort()
	return to


func test_all_reaches_everyone() -> void:
	assert_eq(_to(C.ALL, 11), [11, 21, 22, 29, 30])


func test_team_reaches_the_team_only() -> void:
	assert_eq(_to(C.TEAM, 21), [21, 22, 29], "rats, including the eliminated one (read only)")
	assert_eq(_to(C.TEAM, 11), [11])


func test_ghost_never_reaches_the_living() -> void:
	var r := ChatService.route(C.GHOST, 29, members, true)
	assert_eq(r["error"], "")
	assert_eq(_to(C.GHOST, 29), [29, 30])


func test_ghosts_cannot_talk_to_the_living() -> void:
	for channel in [C.ALL, C.TEAM]:
		var r := ChatService.route(channel, 29, members, true)
		assert_eq(r["channel"], C.GHOST, "forced to ghost")
		assert_eq(_to(channel, 29), [29, 30])


func test_living_cannot_use_ghost() -> void:
	assert_ne(ChatService.route(C.GHOST, 21, members, true)["error"], "")


func test_no_team_or_ghost_rules_outside_a_match() -> void:
	assert_ne(ChatService.route(C.TEAM, 21, members, false)["error"], "", "no team chat in the lobby")
	assert_eq(_to(C.ALL, 29, false), [11, 21, 22, 29, 30], "everyone talks in the lobby")


func test_unknown_sender_or_channel_refused() -> void:
	assert_ne(ChatService.route(C.ALL, 99, members, true)["error"], "")
	assert_ne(ChatService.route(C.SYSTEM, 11, members, true)["error"], "", "clients can't fake system messages")
	assert_ne(ChatService.route(42, 11, members, true)["error"], "")
