class_name Hints
extends CanvasLayer
## First-time hints (M8, ClientOnly): a short tip the first time something happens (the lobby, each
## role's first match, getting caged, carrying a rat, a stolen keycard, the CCTV chair, the alarm,
## being out, the map…). Each one shows once, ever: Config.seen_hints remembers it (Settings → Gameplay brings
## them back). One at a time; the others wait their turn. Texts name the player's own keys.

const CHECK_S := 0.25
const MIN_SHOW_S := 7.0
const MAX_SHOW_S := 16.0
const SECONDS_PER_CHAR := 0.055
## Where the tip sits: top left in the lobby (the chat is docked lower), and in a match below the
## countdown banner and above the chat box.
const LOBBY_Y := 76.0
const MATCH_Y := 345.0

var _panel: PanelContainer
var _title: Label
var _body: Label
var _queue: Array[String] = []
var _showing := ""
var _hide_at := 0.0
var _next_check := 0.0


func _ready() -> void:
	layer = 7
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"CardPanel"
	_panel.position = Vector2(16, LOBBY_Y)
	_panel.custom_minimum_size = Vector2(0, 0)  # (narrow enough to clear the meltdown panel at 1280 px)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/third_party/kenney_game-icons/information.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.modulate = Color("ffc93c")
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"SubheaderLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(340, 0)
	_body.add_theme_font_size_override("font_size", 17)
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_body)
	var footer := Label.new()
	footer.theme_type_variation = &"MutedLabel"
	footer.text = tr("Tips show once. Settings > Gameplay brings them back.")
	footer.add_theme_font_size_override("font_size", 13)
	col.add_child(footer)
	_panel.visible = false


func _process(_delta: float) -> void:
	var now := Net.local_time()
	if _showing != "" and (now >= _hide_at or not _still_relevant(_showing)):
		_hide()
	if now < _next_check:
		return
	_next_check = now + CHECK_S
	var id := _current_situation()
	if id != "" and not Config.hint_seen(id) and id != _showing and not _queue.has(id):
		_queue.append(id)
	_queue = _queue.filter(_still_relevant)  # (a tip whose moment passed while it waited is dropped)
	if _showing == "" and not _queue.is_empty():
		show_hint(_queue.pop_front())


## The hint the situation calls for right now, or "".
func _current_situation() -> String:
	var session := Session.current
	var mm := session.match_manager
	var body := session.get_body(session.local_peer_id)
	var role := mm.local_role()
	if mm.in_match() and mm.is_ghost(session.local_peer_id):
		return "eliminated" if mm.entry(session.local_peer_id).get("eliminated", false) else "spectator"
	match mm.state:
		MatchManager.State.LOBBY:
			return "lobby" if body != null else ""
		MatchManager.State.COUNTDOWN:
			return "role_rat" if role == Role.Kind.RAT else "role_supervisor" if role == Role.Kind.SUPERVISOR else ""
		MatchManager.State.PLAYING:
			if body == null:
				return ""
			if body.status.has(StatusComponent.Status.CAGED):
				return "caged"
			if body.status.has(StatusComponent.Status.KNOCKED_DOWN):
				return "knocked_down"
			if role == Role.Kind.SUPERVISOR:
				if body.status.carrying != 0:
					return "carrying"
				if not body.inventory.keycard:
					return "keycard_stolen"
				if body.watching_cctv():
					return "cctv"
				if session.plant.alarm == PlantModel.Alarm.CRITICAL:
					return "alarm_supervisor"
			elif role == Role.Kind.RAT:
				if session.plant.alarm == PlantModel.Alarm.CRITICAL:
					return "alarm_rat"
			if MapInfo.plan_in(get_tree()) != null:
				return "map"
	return ""


## False once the moment a tip is about has passed (the lobby tip after the match started…).
func _still_relevant(id: String) -> bool:
	var session := Session.current
	var mm := session.match_manager
	var body := session.get_body(session.local_peer_id)
	match id:
		"lobby":
			return mm.state == MatchManager.State.LOBBY
		"role_supervisor", "role_rat":
			return mm.state in [MatchManager.State.COUNTDOWN, MatchManager.State.PLAYING]
		"caged":
			return body != null and body.status.has(StatusComponent.Status.CAGED)
		"knocked_down":
			return body != null and body.status.has(StatusComponent.Status.KNOCKED_DOWN)
		"carrying":
			return body != null and body.status.carrying != 0
		"cctv":
			return body != null and body.watching_cctv()
		"eliminated", "spectator":
			return mm.in_match()
		"map":
			var overlay := session.client_only.get_node_or_null("MapOverlay") as MapOverlay
			return mm.state == MatchManager.State.PLAYING and not (overlay != null and overlay.is_open())
	return mm.state == MatchManager.State.PLAYING


## [title, text] of a hint, in the player's language and with their keys.
func text_of(id: String) -> Array[String]:
	var interact := Keys.label(&"interact")
	match id:
		"lobby":
			return [tr("Welcome to the lobby!"), tr("Pick the role you'd like with %s / %s / %s (any, supervisor, rat) and press %s when you're ready. The match starts once more than half of the players are ready. %s opens the menu.")
				% [Keys.label(&"lobby_pref_any"), Keys.label(&"lobby_pref_supervisor"), Keys.label(&"lobby_pref_rat"),
				Keys.label(&"lobby_ready"), Keys.pause_label()]]
		"role_supervisor":
			return [tr("You're a supervisor"), tr("Keep the plant alive until the shift ends. Repair damaged machines (%s at their repair panel), bonk rats with your broom (%s) and carry them to a cage (%s).")
				% [interact, Keys.label(&"primary"), interact]]
		"role_rat":
			return [tr("You're a rat"), tr("Sabotage the machines (hold %s at their red junction boxes) until the meltdown meter hits 100%%. Use the vents, bite supervisors (%s) and free your caged friends.")
				% [interact, Keys.label(&"primary")]]
		"caged":
			return [tr("Caged!"), tr("Another rat can free you by holding %s at the cage. Get caught a second time and you're out of the match.") % interact]
		"knocked_down":
			return [tr("Knocked down"), tr("The rats bit you three times in a row. You get up in a few seconds, and nobody can knock you down again right away.")]
		"carrying":
			return [tr("Got one!"), tr("Carry the rat to the nearest cage (Cage Room or Reactor Hall) and press %s there. Hurry: it wriggles free after a few seconds, and a bite from another rat makes you drop it.") % interact]
		"keycard_stolen":
			return [tr("Keycard stolen"), tr("Without it, the keycard doors stay shut. Stun the thief to drop it, or pick up the spare in Storage when it's ready.")]
		"cctv":
			var body := Session.current.get_body(Session.current.local_peer_id)
			if body != null and body.using_tablet:
				return [tr("CCTV"), tr("%s / %s switch cameras, %s puts the tablet away. You can walk while you watch, but your hands are full. Rats can break cameras: repair them where they hang.")
					% [Keys.label(&"next_trap"), interact, Keys.label(&"cctv_tablet")]]
			return [tr("CCTV"), tr("%s / %s switch cameras, %s stands up. Rats can break cameras: repair them where they hang.")
				% [Keys.label(&"next_trap"), interact, Keys.label(&"jump")]]
		"alarm_supervisor":
			return [tr("Critical alarm!"), tr("The core is overheating. Fix the broken machines fast, or use the Control Room: emergency coolant cools it down, and SCRAM buys time.")]
		"alarm_rat":
			return [tr("Critical alarm!"), tr("The core is overheating: keep the machines broken and the meltdown meter climbs faster.")]
		"map":
			return [tr("Lost?"), tr("Hold %s to see the map of the plant under the scoreboard, with every machine and your team (%s opens a bigger one with a legend). The minimap in the corner turns with you and names the room you're in.")
				% [Keys.label(&"scoreboard"), Keys.label(&"map")]]
		"eliminated":
			return [tr("You're out"), tr("You were caught twice. Watch the rest of the match: %s / %s follow players, %s flies. Only other ghosts can read your messages.")
				% [Keys.label(&"primary"), Keys.label(&"secondary"), Keys.move_label()]]
		"spectator":
			return [tr("Watching"), tr("A match is under way: you join in at the next one. %s / %s follow players, %s flies.")
				% [Keys.label(&"primary"), Keys.label(&"secondary"), Keys.move_label()]]
	return ["", ""]


## Shows `id` now (and marks it seen).
func show_hint(id: String) -> void:
	var texts := text_of(id)
	if texts[0] == "":
		return
	Config.mark_hint_seen(id)
	_showing = id
	_title.text = texts[0]
	_body.text = texts[1]
	_hide_at = Net.local_time() + clampf(MIN_SHOW_S + texts[1].length() * SECONDS_PER_CHAR, MIN_SHOW_S, MAX_SHOW_S)
	_panel.visible = true
	_panel.modulate.a = 0.0
	_panel.position.x = -40
	_panel.position.y = LOBBY_Y if Session.current.match_manager.state == MatchManager.State.LOBBY else MATCH_Y
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "position:x", 16.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Ui.play("ui_open")
	Log.info("hints", "showing '%s'" % id)


func _hide() -> void:
	_showing = ""
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: _panel.visible = _showing != "")
