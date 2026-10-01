extends Control
## Lobby panel (role preference, Ready) plus the centre banner for the countdown and "GO!".
## It only shows the replicated MatchManager state and sends requests; the server decides.

const GO_BANNER_MS := 1500

var _go_until_ms := 0

@onready var panel: Control = %Panel
@onready var status_label: Label = %StatusLabel
@onready var roster_label: RichTextLabel = %RosterLabel
@onready var any_button: Button = %AnyButton
@onready var supervisor_button: Button = %SupervisorButton
@onready var rat_button: Button = %RatButton
@onready var ready_button: Button = %ReadyButton
@onready var banner: Label = %Banner


func _ready() -> void:
	var group := ButtonGroup.new()
	for button: Button in [any_button, supervisor_button, rat_button]:
		button.button_group = group
	any_button.pressed.connect(_request_pref.bind(Role.Kind.NONE))
	supervisor_button.pressed.connect(_request_pref.bind(Role.Kind.SUPERVISOR))
	rat_button.pressed.connect(_request_pref.bind(Role.Kind.RAT))
	ready_button.toggled.connect(func(on: bool) -> void: _match().request_set_ready.rpc_id(1, on))
	_match().state_changed.connect(_on_state_changed)
	_match().roster_changed.connect(_refresh)
	_refresh()


func _match() -> MatchManager:
	return Session.current.match_manager


func _request_pref(pref: Role.Kind) -> void:
	_match().request_set_pref.rpc_id(1, pref)


func _on_state_changed(state: MatchManager.State) -> void:
	if state == MatchManager.State.PLAYING:
		_go_until_ms = Time.get_ticks_msec() + GO_BANNER_MS
	_refresh()


func _process(_delta: float) -> void:
	_update_banner()  # countdown_left changes every second without a signal


func _refresh() -> void:
	var mm := _match()
	panel.visible = mm.state == MatchManager.State.LOBBY
	var me := mm.entry(Session.current.local_peer_id)
	var lines: Array[String] = []
	for peer: int in mm.roster:
		var e: Dictionary = mm.roster[peer]
		lines.append("%s%s  [color=#9ab]%s[/color]%s" % [
			e["name"], " (you)" if peer == Session.current.local_peer_id else "",
			Role.pref_name(e["pref"]), "  [color=#6e6]READY[/color]" if e["ready"] else ""])
	roster_label.text = "\n".join(lines)
	var count := mm.roster.size()
	if count < mm.min_players:
		status_label.text = "Waiting for players: %d / %d" % [count, mm.min_players]
	else:
		status_label.text = "%d / %d ready. The match starts when more than half are ready." % [mm.ready_count(), count]
	if not me.is_empty():
		match int(me["pref"]):
			Role.Kind.SUPERVISOR:
				supervisor_button.set_pressed_no_signal(true)
			Role.Kind.RAT:
				rat_button.set_pressed_no_signal(true)
			_:
				any_button.set_pressed_no_signal(true)
		ready_button.set_pressed_no_signal(me["ready"])
		ready_button.text = "Ready!" if me["ready"] else "Ready?"
	_update_banner()


func _update_banner() -> void:
	var mm := _match()
	var role := mm.local_role()
	match mm.state:
		MatchManager.State.ROLE_ASSIGN, MatchManager.State.COUNTDOWN:
			if role == Role.Kind.SPECTATOR:
				banner.text = "Spectating until the next match"
			else:
				banner.text = "You are a %s!\nStarting in %d" % [Role.display_name(role), mm.countdown_left]
		MatchManager.State.PLAYING:
			if role == Role.Kind.SPECTATOR:
				banner.text = "Spectating until the next match"
			else:
				banner.text = "GO!" if Time.get_ticks_msec() < _go_until_ms else ""
		_:
			banner.text = ""
