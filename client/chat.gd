extends Control
## Chat box: the log is always visible; Enter opens the input (everyone), T opens it for the team,
## Enter sends, Esc cancels. Ghosts (eliminated, spectating) always talk in the ghost chat: the
## server reroutes them. While the input is open, gameplay input is blocked (PlayerInput.blocked).

const MAX_LINES := 50

const CHANNEL_COLORS := {
	ChatService.Channel.TEAM: "#7fd4ff",
	ChatService.Channel.GHOST: "#c9a0ff",
}

var _lines: Array[String] = []
var _channel := ChatService.Channel.ALL

@onready var log_label: RichTextLabel = %Log
@onready var input: LineEdit = %Input


func _ready() -> void:
	input.visible = false
	input.max_length = ChatService.MAX_LENGTH
	input.text_submitted.connect(_on_submitted)
	Session.current.chat.message_received.connect(_on_message)


func _exit_tree() -> void:
	PlayerInput.blocked = false


func _unhandled_input(event: InputEvent) -> void:
	if input.visible:
		return
	if event.is_action_pressed("chat"):
		_open(ChatService.Channel.ALL)
		accept_event()
	elif event.is_action_pressed("team_chat") and Session.current.match_manager.in_match():
		_open(ChatService.Channel.TEAM)
		accept_event()


func _input(event: InputEvent) -> void:
	# _input runs before the GUI and _unhandled_input: Esc closes the chat instead of freeing the mouse.
	if input.visible and event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _open(channel: ChatService.Channel) -> void:
	var mm := Session.current.match_manager
	_channel = ChatService.Channel.GHOST if mm.is_ghost(Session.current.local_peer_id) else channel
	match _channel:
		ChatService.Channel.TEAM:
			input.placeholder_text = "(team) Say something to your team"
		ChatService.Channel.GHOST:
			input.placeholder_text = "(ghost) Only other ghosts will read this"
		_:
			input.placeholder_text = "Say something (Enter sends, Esc cancels)"
	input.visible = true
	input.grab_focus()
	PlayerInput.blocked = true


func _close() -> void:
	input.clear()
	input.release_focus()
	input.visible = false
	PlayerInput.blocked = false


func _on_submitted(text: String) -> void:
	if not text.strip_edges().is_empty():
		Session.current.chat.send(text, _channel)
	_close()


func _on_message(from_name: String, text: String, channel: ChatService.Channel) -> void:
	# Safe as BBCode: the server strips [ and ] from messages and names.
	if from_name.is_empty():
		_lines.append("[color=#b8b8b8][i]%s[/i][/color]" % text)
	else:
		var color := Color.from_hsv(fmod(absi(from_name.hash()) * 0.618034, 1.0), 0.5, 1.0)
		var tag := ""
		if CHANNEL_COLORS.has(channel):
			tag = "[color=%s](%s)[/color] " % [CHANNEL_COLORS[channel], "team" if channel == ChatService.Channel.TEAM else "ghost"]
		_lines.append("%s[color=#%s]%s[/color]: %s" % [tag, color.to_html(false), from_name, text])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	log_label.text = "\n".join(_lines)
