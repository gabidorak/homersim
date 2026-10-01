extends GutTest


func test_check_accepts_matching_version_with_room() -> void:
	assert_eq(JoinRules.check("0.1.0", "0.1.0", 2, 6), "")


func test_check_rejects_version_mismatch() -> void:
	assert_string_contains(JoinRules.check("0.0.9", "0.1.0", 0, 6), "Version mismatch")


func test_check_rejects_when_full() -> void:
	assert_eq(JoinRules.check("0.1.0", "0.1.0", 6, 6), "Server full")


func test_version_is_checked_before_capacity() -> void:
	assert_string_contains(JoinRules.check("x", "0.1.0", 6, 6), "Version mismatch")


func test_sanitize_trims_and_collapses_spaces() -> void:
	assert_eq(JoinRules.sanitize_name("  Bob   the  Rat "), "Bob the Rat")


func test_sanitize_strips_control_chars_and_bbcode_brackets() -> void:
	assert_eq(JoinRules.sanitize_name("[b]Al\n\tice[/b]"), "bAlice/b")


func test_sanitize_caps_length() -> void:
	assert_eq(JoinRules.sanitize_name("abcdefghijklmnopqrstuvwxyz").length(), JoinRules.MAX_NAME_LENGTH)


func test_sanitize_empty_gives_default() -> void:
	assert_eq(JoinRules.sanitize_name("   "), JoinRules.DEFAULT_NAME)
	assert_eq(JoinRules.sanitize_name("[]"), JoinRules.DEFAULT_NAME)


func test_unique_name_keeps_free_name() -> void:
	assert_eq(JoinRules.unique_name("Bob", ["Al"] as Array[String]), "Bob")


func test_unique_name_adds_suffix_case_insensitively() -> void:
	assert_eq(JoinRules.unique_name("bob", ["Bob"] as Array[String]), "bob (2)")


func test_unique_name_skips_taken_suffixes() -> void:
	assert_eq(JoinRules.unique_name("Bob", ["Bob", "Bob (2)"] as Array[String]), "Bob (3)")


func test_player_info_round_trip() -> void:
	var info := PlayerInfo.from_dict(PlayerInfo.new(42, "Zed").to_dict())
	assert_eq(info.peer_id, 42)
	assert_eq(info.name, "Zed")
