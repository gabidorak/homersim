class_name Keys
extends RefCounted
## Key bindings as text (M8): what the settings file stores for a rebound action ("key:69",
## "mouse:1"), and what the UI shows for it ("E", "LMB"). Keys are stored by their *physical*
## position (like the project's defaults), so WASD stays where it is on an AZERTY keyboard; the label
## is the key printed at that spot on the player's layout (Z Q S D in France).

## The actions players can rebind, in the order the Controls tab lists them. Esc (pause) is left out
## on purpose: it always opens the menu, so nobody can lock themselves out of the settings.
const REBINDABLE: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch",
	&"primary", &"secondary", &"interact", &"next_trap", &"emote",
	&"chat", &"team_chat", &"scoreboard", &"lobby_ready", &"lobby_pref_any", &"lobby_pref_supervisor",
	&"lobby_pref_rat", &"spectate_up", &"spectate_down", &"debug_overlay", &"debug_stopwatch",
]

## What each action is called in the Controls tab (English source text; the UI translates it).
const ACTION_NAMES := {
	&"move_forward": "Move forward",
	&"move_back": "Move back",
	&"move_left": "Move left",
	&"move_right": "Move right",
	&"jump": "Jump (CCTV: stand up)",
	&"sprint": "Sprint",
	&"crouch": "Crouch / squeeze",
	&"primary": "Broom / bite",
	&"secondary": "Place a trap (hold, release)",
	&"interact": "Interact (hold)",
	&"next_trap": "Switch trap (CCTV: previous camera)",
	&"emote": "Emote",
	&"chat": "Chat",
	&"team_chat": "Team chat",
	&"scoreboard": "Scoreboard (hold)",
	&"lobby_ready": "Lobby: ready",
	&"lobby_pref_any": "Lobby: play any role",
	&"lobby_pref_supervisor": "Lobby: play supervisor",
	&"lobby_pref_rat": "Lobby: play rat",
	&"spectate_up": "Spectator: fly up",
	&"spectate_down": "Spectator: fly down",
	&"debug_overlay": "Debug overlay",
	&"debug_stopwatch": "Route stopwatch",
}

## Actions that are only read in the same situations; a key shared inside a group is a conflict.
## (Space for both "jump" and "fly up" is fine: a spectator has no body to jump with.)
const GROUPS: Array[Array] = [
	[&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch", &"primary",
		&"secondary", &"interact", &"next_trap", &"emote", &"chat", &"team_chat", &"scoreboard",
		&"debug_overlay", &"debug_stopwatch"],
	[&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"emote", &"chat", &"scoreboard",
		&"lobby_ready", &"lobby_pref_any", &"lobby_pref_supervisor", &"lobby_pref_rat"],
	[&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"primary", &"secondary", &"chat",
		&"scoreboard", &"spectate_up", &"spectate_down"],
]

const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4",
	MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}


## "key:<physical keycode>", "mouse:<button index>", or "" for anything else.
static func encode(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return "mouse:%d" % mouse.button_index
	return ""


## The reverse of encode(); null for text it doesn't understand.
static func decode(text: String) -> InputEvent:
	var parts := text.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or parts[1].to_int() <= 0:
		return null
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = parts[1].to_int() as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = parts[1].to_int() as MouseButton
			return mouse
	return null


## What the player presses for `action` ("E", "LMB", "Z"), or "?" when it is unbound.
static func label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events := InputMap.action_get_events(action)
	return event_label(events[0]) if not events.is_empty() else "?"


static func event_label(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code := key.keycode
		if key.physical_keycode >= KEY_0 and key.physical_keycode <= KEY_9:
			return char(key.physical_keycode)  # the digit, also on AZERTY (whose unshifted key is & é " …)
		if key.physical_keycode != KEY_NONE:
			# (the layout lookup is not supported headless: there, the QWERTY name will do)
			code = key.physical_keycode if DisplayServer.get_name() == "headless" \
				else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		var text := OS.get_keycode_string(code)
		return TranslationServer.translate(text) if text != "" else "?"
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return TranslationServer.translate(MOUSE_NAMES.get(mouse.button_index, "Mouse %d" % mouse.button_index))
	return "?"


## The menu key (Esc, never rebound): "Escape", in the player's language.
static func pause_label() -> String:
	var events := InputMap.action_get_events(&"pause") if InputMap.has_action(&"pause") else []
	return event_label(events[0]) if not events.is_empty() else "Esc"


## The four movement keys as one label: "WASD" on QWERTY, "ZQSD" on AZERTY, "W/A/S/D" if any
## of them is longer than one character (rebound to arrows…).
static func move_label() -> String:
	var parts: Array[String] = []
	for action: StringName in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
		parts.append(label(action))
	for part in parts:
		if part.length() != 1:
			return "/".join(parts)
	return "".join(parts)


## The other rebindable actions that share `event` with `action` in one of the GROUPS (with the
## bindings in `bindings`: action -> encoded event, as the settings store them).
static func conflicts(action: StringName, encoded: String, bindings: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if encoded == "":
		return result
	for group: Array in GROUPS:
		if not group.has(action):
			continue
		for other: StringName in group:
			if other != action and bindings.get(other, "") == encoded and not result.has(other):
				result.append(other)
	return result
