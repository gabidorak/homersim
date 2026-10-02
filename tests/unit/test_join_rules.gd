extends GutTest


func test_check_accepts_matching_version_with_room() -> void:
	assert_eq(JoinRules.check("0.1.0", "0.1.0", 2, 6), LeaveReason.Code.NONE)


func test_check_rejects_version_mismatch() -> void:
	assert_eq(JoinRules.check("0.0.9", "0.1.0", 0, 6), LeaveReason.Code.VERSION)


func test_check_rejects_when_full() -> void:
	assert_eq(JoinRules.check("0.1.0", "0.1.0", 6, 6), LeaveReason.Code.FULL)


func test_version_is_checked_before_capacity() -> void:
	assert_eq(JoinRules.check("x", "0.1.0", 6, 6), LeaveReason.Code.VERSION)


func test_password() -> void:
	assert_eq(JoinRules.check("1", "1", 0, 6, "", ""), LeaveReason.Code.NONE, "no password set: anyone joins")
	assert_eq(JoinRules.check("1", "1", 0, 6, "whatever", ""), LeaveReason.Code.NONE, "a password sent to an open server is ignored")
	assert_eq(JoinRules.check("1", "1", 0, 6, "", "cheese"), LeaveReason.Code.PASSWORD_REQUIRED)
	assert_eq(JoinRules.check("1", "1", 0, 6, "chese", "cheese"), LeaveReason.Code.WRONG_PASSWORD)
	assert_eq(JoinRules.check("1", "1", 0, 6, "cheese", "cheese"), LeaveReason.Code.NONE)


func test_full_is_checked_before_the_password() -> void:
	assert_eq(JoinRules.check("1", "1", 6, 6, "", "cheese"), LeaveReason.Code.FULL)


func test_leave_reason_log_texts_keep_the_test_wording() -> void:
	# tests/integration/*.sh grep these lines in the client logs.
	assert_eq(LeaveReason.log_text(LeaveReason.Code.FULL), "Server full")
	assert_string_starts_with(LeaveReason.log_text(LeaveReason.Code.VERSION, "0.2.0|0.1.0"), "Version mismatch")
	assert_string_contains(LeaveReason.log_text(LeaveReason.Code.VERSION, "0.2.0|0.1.0"), "server is 0.2.0, you have 0.1.0")
	for code: int in LeaveReason.Code.values():
		if code != LeaveReason.Code.NONE:
			assert_ne(LeaveReason.title(code), "", "every failure has a title")
			assert_ne(LeaveReason.message(code, "a|b"), "", "every failure has a message")


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
