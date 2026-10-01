extends GutTest


func test_clean_strips_bbcode_brackets_and_control_chars() -> void:
	assert_eq(ChatService.clean("  [color=red]hi[/color]\n "), "color=redhi/color")
	assert_eq(ChatService.clean("a\tb"), "ab")


func test_clean_empty() -> void:
	assert_eq(ChatService.clean(" [] "), "")


func test_rate_limit_one_message_per_second() -> void:
	assert_false(ChatService.rate_ok(1000, 1999))
	assert_true(ChatService.rate_ok(1000, 2000))
