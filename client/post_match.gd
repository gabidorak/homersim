extends Control
## The post-match screen (M8), from POST_MATCH: the winning team's banner pops in with confetti,
## "You win!" or "You lose...", the reason, each team's stats and scores (MatchManager.result, best
## first), and the fun awards (Awards). AI bots (M10) get a BOT badge after their name.
## First comes the end-of-match cinematic (client/outro/, OutroScreen: the winners' ending, 9.5 or 11.8 s,
## a click skips it), for every client that saw the match being played: players and spectators alike (a
## client that joins during POST_MATCH gets the result straight away). After a meltdown it waits for
## the boom (MusicDirector) to land first.
## After MIN_SHOW_S the buttons appear: "Back to the lobby" closes it, and in solo "Quit to menu" too.
## The server goes back to the lobby on its own after post_match_s, but the screen stays until closed,
## for whoever wants to study it (it also shows when the cinematic ends after the server went back);
## it closes by itself when the next match starts (and stops the cinematic). Only reads replicated
## state. post_match_s leaves the result about as long on screen as before the cinematic came in:
## see data/match_rules.gd.

const SUPERVISOR_COLOR := Color("ffc93c")
const RAT_COLOR := Color("7bd389")
const ICONS := "res://assets/third_party/kenney_game-icons/%s.png"
## [stat, short column title] (short: both tables side by side must fit 1280 px in every language).
const SUPERVISOR_COLUMNS := [["score", "Score"], ["repairs", "Repairs"], ["catches", "Catches"], ["bonks", "Bonks"],
	["donuts", "Donuts"], ["hazard_hits", "Hazards"]]
const RAT_COLUMNS := [["score", "Score"], ["sabotages", "Sabotages"], ["bites", "Bites"], ["knockdowns", "Knockdowns"],
	["frees", "Frees"], ["steals", "Steals"], ["caught", "Caught"]]
const DENSE_FROM := 9  ## players in a team from which the tables' rows get smaller (big bot matches)
const MIN_SHOW_S := 5.0  ## the result stays at least this long before the buttons appear (counted from when it shows)
const MELTDOWN_BOOM_S := 1.0  ## after a meltdown the cinematic waits for the boom
const SCORE_COLOR := Color("7fb7e6")
const CONFETTI := [Color("ffc93c"), Color("e84a5f"), Color("7bd389"), Color("7fb7e6"), Color("ff8fb8"), Color("ffffff")]

var _shown_result: Dictionary = {}  # empty while closed
var _shown_at_ms := 0
var _dismissed: Dictionary = {}  # the result closed with "Back to the lobby", not to show again
var _dense := false  # this result's tables use small rows
var _confetti: CPUParticles2D
var _outro: OutroScreen  # the end-of-match cinematic, playing before the result shows
var _outro_for: Dictionary = {}  # the result it plays for
var _saw_play := false  # this client saw the match being played (it gets the cinematic)

@onready var banner: Label = %Banner
@onready var you_line: Label = %YouLine
@onready var reason: Label = %Reason
@onready var tables: HBoxContainer = %Tables
@onready var awards_row: HBoxContainer = %Awards
@onready var buttons: HBoxContainer = %Buttons
@onready var lobby_button: Button = %LobbyButton
@onready var quit_button: Button = %QuitButton
@onready var footer: Label = %Footer


func _ready() -> void:
	visible = false
	lobby_button.pressed.connect(_close)
	quit_button.pressed.connect(func() -> void: Session.current.leave())
	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 160
	_confetti.lifetime = 3.5
	_confetti.explosiveness = 0.85
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 60.0
	_confetti.gravity = Vector2(0, 260)
	_confetti.initial_velocity_min = 80.0
	_confetti.initial_velocity_max = 320.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.scale_amount_min = 5.0
	_confetti.scale_amount_max = 9.0
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	ramp.colors = PackedColorArray(CONFETTI)
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT  # one solid colour per bit of confetti
	_confetti.color_initial_ramp = ramp
	add_child(_confetti)


func _process(_delta: float) -> void:
	var mm := Session.current.match_manager
	if mm.state == MatchManager.State.PLAYING:
		_saw_play = true
	if mm.state == MatchManager.State.POST_MATCH and not mm.result.is_empty():
		# The result and the state can arrive in either order: rebuild on change.
		if mm.result != _shown_result and mm.result != _dismissed and mm.result != _outro_for:
			if _saw_play and OutroScreen.wanted():
				_play_outro(mm.result)
			else:
				_show(mm.result)
	elif mm.state != MatchManager.State.LOBBY:
		_dismissed = {}
		_outro_for = {}
		if _outro != null:
			_outro.stop()  # the next match is starting
		if visible:
			_close()
	if not visible:
		return
	var buttons_due := Time.get_ticks_msec() - _shown_at_ms >= MIN_SHOW_S * 1000.0
	if buttons_due and not buttons.visible:
		buttons.visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP  # a click here must not grab the mouse for the game
		lobby_button.grab_focus()
	if buttons_due and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # the buttons need the mouse
	var local := LocalServer.for_session()
	if mm.state == MatchManager.State.LOBBY and (local == null or local.mode != LocalServer.Mode.SOLO):
		footer.text = tr("The others are in the lobby: %d / %d ready") % [mm.ready_count(), mm.roster.size()]
	else:
		footer.text = ""


## The winners' ending first, then the result.
func _play_outro(result: Dictionary) -> void:
	_saw_play = false
	_outro_for = result
	var meltdown := str(result.get("reason", "")).begins_with("Meltdown")
	var delay := MELTDOWN_BOOM_S if meltdown else 0.0
	_outro = OutroScreen.play(self, result.get("winner", MatchRulesModel.Team.NONE), delay, OutroScreen.rats_in(result))
	_outro.finished.connect(func() -> void:
		_outro = null
		var mm := Session.current.match_manager
		if mm.state in [MatchManager.State.POST_MATCH, MatchManager.State.LOBBY] and mm.result == result:
			_show(result))


func _close() -> void:
	_dismissed = _shown_result
	_shown_result = {}
	visible = false
	_confetti.emitting = false


func _show(result: Dictionary) -> void:
	_shown_result = result
	_shown_at_ms = Time.get_ticks_msec()
	visible = true
	Events.post_match_shown.emit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.visible = false
	var local := LocalServer.for_session()
	quit_button.visible = local != null and local.mode == LocalServer.Mode.SOLO
	var winner: MatchRulesModel.Team = result.get("winner", MatchRulesModel.Team.NONE)
	var mine := Session.current.match_manager.local_role()
	var team_color := SUPERVISOR_COLOR if winner == MatchRulesModel.Team.SUPERVISORS else RAT_COLOR
	banner.text = tr("SUPERVISORS WIN!") if winner == MatchRulesModel.Team.SUPERVISORS else tr("RATS WIN!")
	banner.add_theme_color_override("font_color", team_color)
	var played := mine in [Role.Kind.SUPERVISOR, Role.Kind.RAT]
	var won := (winner == MatchRulesModel.Team.SUPERVISORS and mine == Role.Kind.SUPERVISOR) \
		or (winner == MatchRulesModel.Team.RATS and mine == Role.Kind.RAT)
	you_line.text = (tr("You win!") if won else tr("You lose...")) if played else ""
	you_line.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if won else Color(1, 0.6, 0.55))
	reason.text = tr(str(result.get("reason", "")))
	for child in tables.get_children() + awards_row.get_children():
		child.queue_free()
	var stats: Array = result.get("stats", [])
	var team_sizes := {}
	for row: Dictionary in stats:
		team_sizes[row.get("role")] = team_sizes.get(row.get("role"), 0) + 1
	_dense = team_sizes.values().any(func(n: int) -> bool: return n >= DENSE_FROM)
	tables.add_child(_table(tr("Supervisors"), Role.Kind.SUPERVISOR, SUPERVISOR_COLOR, SUPERVISOR_COLUMNS, stats))
	tables.add_child(_table(tr("Rats"), Role.Kind.RAT, RAT_COLOR, RAT_COLUMNS, stats))
	for award in Awards.compute(stats):
		awards_row.add_child(_award_card(award))
	_celebrate()


## The banner pops in and wobbles; confetti rains from the top.
func _celebrate() -> void:
	banner.pivot_offset = banner.size / 2.0
	banner.scale = Vector2(0.2, 0.2)
	banner.rotation = -0.12
	var tween := create_tween().set_parallel()
	tween.tween_property(banner, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner, "rotation", 0.0, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var view := get_viewport_rect().size
	_confetti.position = Vector2(view.x / 2.0, -20.0)
	_confetti.emission_rect_extents = Vector2(view.x / 2.0, 10.0)
	_confetti.restart()


func _table(title: String, role: Role.Kind, color: Color, columns: Array, stats: Array) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid := GridContainer.new()
	grid.columns = 1 + columns.size()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 0 if _dense else 4)
	card.add_child(grid)
	var heading := _cell(title, color)
	heading.add_theme_font_size_override("font_size", 22)
	grid.add_child(heading)
	for column: Array in columns:
		var header := _cell(tr(column[1]), Color(0.64, 0.65, 0.68), true)
		header.add_theme_font_size_override("font_size", 16)
		grid.add_child(header)
	for row: Dictionary in stats:
		if row.get("role") != role:
			continue
		var me: bool = row.get("peer", 0) == Session.current.local_peer_id
		var name_cell := _cell(str(row["name"]), color if me else Color.WHITE)
		_shrink(name_cell)
		if row.get("bot", false):
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(name_cell)
			line.add_child(Ui.bot_badge())
			grid.add_child(line)
		else:
			grid.add_child(name_cell)
		for column: Array in columns:
			var count := int(row.get(column[0], 0))
			var tint := SCORE_COLOR if column[0] == "score" else Color.WHITE
			grid.add_child(_shrink(_cell(str(count), tint if count > 0 else Color(0.5, 0.52, 0.56), true)))
	return card


## A row's cell in small type when the tables are dense.
func _shrink(label: Label) -> Label:
	if _dense:
		label.add_theme_font_size_override("font_size", 15)
	return label


func _award_card(award: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(190, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	var icon := TextureRect.new()
	icon.texture = load(ICONS % "trophy")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(0, 34)
	icon.modulate = SUPERVISOR_COLOR
	col.add_child(icon)
	var title := _cell(tr(award["title"]), SUPERVISOR_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var who := _cell(award["name"], RAT_COLOR if award["role"] == Role.Kind.RAT else Color.WHITE)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 20)
	col.add_child(who)
	var detail := _cell(tr(award["detail"]) % award["count"], Color(0.7, 0.72, 0.76))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 15)
	col.add_child(detail)
	return card


func _cell(text: String, color: Color, right: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label
