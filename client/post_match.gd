extends Control
## Post-match screen: winner banner, reason, and a stats table (MatchManager.result), shown
## during POST_MATCH until everyone is back in the lobby.

const COLUMNS: Array[String] = ["Player", "Role", "Sabotages", "Repairs"]

var _shown_result: Dictionary = {}

@onready var panel: Control = %Panel
@onready var banner: Label = %Banner
@onready var reason: Label = %Reason
@onready var stats: GridContainer = %Stats
@onready var footer: Label = %Footer


func _process(_delta: float) -> void:
	var mm := Session.current.match_manager
	visible = mm.state == MatchManager.State.POST_MATCH and not mm.result.is_empty()
	if not visible:
		return
	if mm.result != _shown_result:  # result and state can arrive in either order: rebuild on change
		_show(mm.result)
	footer.text = "Back to the lobby in %d s" % mm.countdown_left


func _show(result: Dictionary) -> void:
	_shown_result = result
	var winner: MatchRulesModel.Team = result.get("winner", MatchRulesModel.Team.NONE)
	var mine := Session.current.match_manager.local_role()
	var won := (winner == MatchRulesModel.Team.SUPERVISORS and mine == Role.Kind.SUPERVISOR) \
		or (winner == MatchRulesModel.Team.RATS and mine == Role.Kind.RAT)
	banner.text = "%s WIN!" % MatchRulesModel.team_name(winner).to_upper()
	banner.modulate = Color(0.5, 1, 0.5) if won else (Color(1, 0.55, 0.5) if mine in [Role.Kind.SUPERVISOR,
		Role.Kind.RAT] else Color.WHITE)
	reason.text = str(result.get("reason", ""))
	for child in stats.get_children():
		child.queue_free()
	for title in COLUMNS:
		stats.add_child(_cell(title, true))
	for row: Dictionary in result.get("stats", []):
		stats.add_child(_cell(str(row["name"]), false))
		stats.add_child(_cell(Role.display_name(row["role"]), false))
		stats.add_child(_cell(str(row["sabotages"]), false))
		stats.add_child(_cell(str(row["repairs"]), false))


func _cell(text: String, header: bool) -> Label:
	var label := Label.new()
	label.text = text
	if header:
		label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	return label
