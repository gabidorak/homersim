extends GutTest
## M8 pure logic: key binding text, LAN discovery packets and the server list, awards, the chat
## filter, system message formatting, the credits converter. Runs in English whatever the
## machine's language.

var _locale := ""


func before_all() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_locale)


# --- Keys ----------------------------------------------------------------------

func test_keys_encode_decode() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	assert_eq(Keys.encode(key), "key:%d" % KEY_E)
	var back := Keys.decode("key:%d" % KEY_E) as InputEventKey
	assert_eq(back.physical_keycode, KEY_E)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(Keys.encode(mouse), "mouse:2")
	assert_eq((Keys.decode("mouse:2") as InputEventMouseButton).button_index, MOUSE_BUTTON_RIGHT)
	for junk in ["", "key", "key:", "key:abc", "key:-3", "pad:1", "mouse:0"]:
		assert_null(Keys.decode(junk), "'%s' is refused" % junk)


func test_keys_labels() -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_eq(Keys.event_label(mouse), "LMB")
	var digit := InputEventKey.new()
	digit.physical_keycode = KEY_2
	assert_eq(Keys.event_label(digit), "2", "the digit, whatever the layout")
	assert_eq(Keys.label(&"no_such_action"), "?")
	assert_eq(Keys.move_label().length(), 4, "WASD (or ZQSD) in one word")


func test_keys_conflicts() -> void:
	var bindings := {&"jump": "key:32", &"spectate_up": "key:32", &"interact": "key:69", &"emote": "key:69"}
	assert_eq(Keys.conflicts(&"jump", "key:32", bindings), [] as Array[StringName],
		"jump and fly up never apply at the same time")
	assert_eq(Keys.conflicts(&"interact", "key:69", bindings), [&"emote"] as Array[StringName])
	assert_eq(Keys.conflicts(&"interact", "", bindings), [] as Array[StringName], "unbound conflicts with nothing")


# --- LAN discovery -------------------------------------------------------------

func _announce(id: int, players: int = 2, state: String = "lobby") -> Dictionary:
	return LanDiscovery.decode(LanDiscovery.encode_announce({"id": id, "name": "Plant %d" % id, "players": players,
		"max": 6, "port": 7777, "version": "0.1.0", "state": state, "locked": false}))


func test_lan_announce_round_trip() -> void:
	var packet := _announce(42, 3)
	assert_eq(packet["kind"], "announce")
	assert_eq(packet["id"], 42)
	assert_eq(packet["name"], "Plant 42")
	assert_eq(packet["players"], 3)
	assert_eq(packet["port"], 7777)
	assert_false(packet["locked"])


func test_lan_ping_pong() -> void:
	assert_eq(LanDiscovery.decode(LanDiscovery.encode_ping(7)), {"kind": "ping", "token": 7})
	assert_eq(LanDiscovery.decode(LanDiscovery.encode_pong(7)), {"kind": "pong", "token": 7})


func test_lan_refuses_garbage() -> void:
	for bytes: PackedByteArray in ["".to_utf8_buffer(), "hello".to_utf8_buffer(), "[1,2]".to_utf8_buffer(),
			JSON.stringify({"game": "othergame", "id": 1, "players": 1, "max": 2, "port": 7777}).to_utf8_buffer(),
			JSON.stringify({"game": "homersim", "id": "x", "players": 1, "max": 2, "port": 7777}).to_utf8_buffer(),
			JSON.stringify({"game": "homersim", "id": 1, "players": 1, "max": 2, "port": 99999}).to_utf8_buffer(),
			"x".repeat(LanDiscovery.MAX_PACKET + 1).to_utf8_buffer()]:
		assert_eq(LanDiscovery.decode(bytes), {}, "refused: %s" % bytes.get_string_from_utf8().left(40))


func test_lan_cleans_what_it_shows() -> void:
	var packet := LanDiscovery.decode(LanDiscovery.encode_announce({"id": 1, "name": "[b]Evil[/b]\n" + "x".repeat(80),
		"players": 500, "max": 0, "port": 7777, "version": "1", "state": "dancing"}))
	assert_false(packet["name"].contains("["), "no BBCode")
	assert_true(packet["name"].length() <= LanDiscovery.MAX_NAME)
	assert_eq(packet["players"], 99)
	assert_eq(packet["max"], 1)
	assert_eq(packet["state"], "lobby", "an unknown state reads as lobby")


func test_lan_list_dedups_keeps_first_address_and_expires() -> void:
	var list := LanDiscovery.new()
	assert_true(list.heard(_announce(1), "192.168.1.5", 50000, 10.0), "new server")
	assert_false(list.heard(_announce(1, 4), "127.0.0.1", 50000, 11.0), "same server through loopback")
	assert_eq(list.servers.size(), 1)
	assert_eq(list.servers[1]["address"], "192.168.1.5", "the first address is kept")
	assert_eq(list.servers[1]["players"], 4, "but the numbers update")
	list.got_pong(1, 0.023)
	assert_eq(list.servers[1]["ping_ms"], 23)
	list.heard(_announce(2), "192.168.1.6", 50001, 14.0)
	assert_false(list.expire(16.9), "nothing older than 6 s yet")
	assert_true(list.expire(17.5), "server 1 was last heard at 11 s")
	assert_eq(list.servers.keys(), [2])
	assert_eq(LanDiscovery.address_of(list.servers[2]), "192.168.1.6:7777")


func test_lan_sorted_puts_open_lobbies_first() -> void:
	var list := LanDiscovery.new()
	list.heard(_announce(1, 2, "playing"), "a", 1, 0.0)
	list.heard(_announce(2, 6, "lobby"), "b", 1, 0.0)  # full
	list.heard(_announce(3, 1, "lobby"), "c", 1, 0.0)
	assert_eq(list.sorted()[0]["id"], 3)


# --- Awards --------------------------------------------------------------------

func _row(name: String, role: Role.Kind, counts: Dictionary) -> Dictionary:
	var row := {"name": name, "role": role}
	for key in MatchManager.STAT_KEYS:
		row[key] = counts.get(key, 0)
	return row


func test_awards_pick_the_best_and_spread_them() -> void:
	var stats := [
		_row("Ana", Role.Kind.SUPERVISOR, {"bonks": 5, "donuts": 3, "repairs": 2}),
		_row("Ben", Role.Kind.SUPERVISOR, {"bonks": 2, "repairs": 6}),
		_row("Cat", Role.Kind.RAT, {"sabotages": 4, "bites": 3}),
		_row("Dan", Role.Kind.RAT, {"sabotages": 6, "caught": 1, "frees": 2}),
	]
	var awards := Awards.compute(stats)
	var by_id := {}
	for a in awards:
		by_id[a["id"]] = a
	assert_eq(awards.size(), Awards.MAX)
	assert_eq(by_id["bonks"]["name"], "Ana")
	assert_eq(by_id["sneaky"]["name"], "Cat", "Dan sabotaged more but got caught")
	assert_eq(by_id["sneaky"]["count"], 4)
	var names := awards.map(func(a: Dictionary) -> String: return a["name"])
	assert_true(names.has("Ben") and names.has("Dan"), "everyone who earned one gets one before anyone gets two")


func test_awards_ties_and_minimums() -> void:
	var stats := [
		_row("Zoe", Role.Kind.SUPERVISOR, {"bonks": 2}),
		_row("Abe", Role.Kind.SUPERVISOR, {"bonks": 2}),
		_row("Rat", Role.Kind.RAT, {"bites": 1}),
	]
	var awards := Awards.compute(stats)
	assert_eq(awards[0]["name"], "Abe", "a tie goes to the first name")
	for a in awards:
		assert_ne(a["id"], "biter", "1 bite is below the award's minimum")


func test_awards_empty_match() -> void:
	assert_eq(Awards.compute([]), [] as Array[Dictionary])
	assert_eq(Awards.compute([_row("Idle", Role.Kind.RAT, {})]), [] as Array[Dictionary])


# --- Chat ----------------------------------------------------------------------

func test_chat_filter() -> void:
	assert_eq(ChatFilter.clean("well shit happens"), "well s*** happens")
	assert_eq(ChatFilter.clean("SHIT"), "S***", "any case")
	assert_eq(ChatFilter.clean("putain de merde"), "p***** de m****")
	assert_eq(ChatFilter.clean("enculé"), "e*****", "accents count as letters")
	assert_eq(ChatFilter.clean("Scunthorpe, shitake, constant"), "Scunthorpe, shitake, constant", "whole words only")
	assert_eq(ChatFilter.clean("bite the supervisor"), "bite the supervisor", "game words stay")


func test_system_message_format() -> void:
	assert_eq(ChatService.format("%s joined", ["Bob"], false), "Bob joined")
	assert_eq(ChatService.format("Plain text", [], false), "Plain text")
	assert_eq(ChatService.format("%s and %s", ["one"], false), "%s and %s", "a mismatch shows the text instead of failing")


func test_credits_markdown() -> void:
	var credits: GDScript = load("res://client/credits.gd")
	var bb: String = credits.call("to_bbcode", "# Title\nSome **bold** and a [link](https://x.y).\n| A | B |\n|---|---|\n| one | https://kenney.nl |\n- item")
	assert_string_contains(bb, "[b]bold[/b]")
	assert_string_contains(bb, "[url=https://x.y]link[/url]")
	assert_string_contains(bb, "[b]one[/b]")
	assert_string_contains(bb, "[url=https://kenney.nl]kenney.nl[/url]")
	assert_string_contains(bb, "•  item")
	assert_false(bb.contains("|---"), "no table separator")
