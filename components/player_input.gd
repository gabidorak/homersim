class_name PlayerInput
extends RefCounted
## Whether gameplay input (moving, looking) should reach the local player right now.

## Set by UI that takes the keyboard, like the open chat box.
static var blocked := false


static func has_control() -> bool:
	return not blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
