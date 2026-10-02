extends Control
## Chat box: the log is always visible; Enter opens the input (everyone), T opens it for the team,
## Enter sends, Esc cancels. Ghosts (eliminated, spectating) always talk in the ghost chat: the
## server reroutes them. While the input is open, gameplay input is blocked (PlayerInput.blocked).
## M8: docked tall on the left side in the lobby, a compact box bottom left during matches; rude
## words masked when Config.chat_filter is on (ChatFilter). System messages arrive translated.

const MAX_LINES := 50
const LOBBY_TOP := 300.0  ## px: in the lobby the box runs from here to the bottom (the hints sit above)
const MATCH_HEIGHT := 170.0
const WIDTH := 430.0

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
	log_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	Session.current.chat.message_received.connect(_on_message)
	Session.current.match_manager.state_changed.connect(func(_s: MatchManager.State) -> void: _dock())
	_dock()


## Tall on the left in the lobby (it is the main thing to do there), compact during a match.
func _dock() -> void:
	var box := $Box as Control
	var lobby := Session.current.match_manager.state == MatchManager.State.LOBBY
	box.anchor_top = 0.0 if lobby else 1.0
	box.offset_top = LOBBY_TOP if lobby else -16.0 - MATCH_HEIGHT
	box.offset_bottom = -16.0
	box.offset_left = 16.0
	box.offset_right = 16.0 + WIDTH
	(log_label.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a = 0.45 if lobby else 0.2


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
			input.placeholder_text = tr("(team) Say something to your team")
		ChatService.Channel.GHOST:
			input.placeholder_text = tr("(ghost) Only other ghosts will read this")
		_:
			input.placeholder_text = tr("Say something (Enter sends, Esc cancels)")
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
			tag = "[color=%s](%s)[/color] " % [CHANNEL_COLORS[channel], tr("team") if channel == ChatService.Channel.TEAM else tr("ghost")]
		if Config.chat_filter:
			text = ChatFilter.clean(text)
		_lines.append("%s[color=#%s]%s[/color]: %s" % [tag, color.to_html(false), from_name, text])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	log_label.text = "\n".join(_lines)
