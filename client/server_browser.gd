extends Control
## The server browser (M8): servers found on the LAN (LanBrowser: name, players, state, ping), the
## saved favourites (Config.favourites: join, rename, remove), and a field to type any address.
## It never connects itself: it emits join_requested and the main menu does the joining.

signal closed
signal join_requested(address: String, server_name: String, locked: bool)

const ICONS := "res://assets/third_party/kenney_game-icons/%s.png"
const STATE_TEXT := {
	"lobby": "In the lobby",
	"starting": "Starting",
	"playing": "Match on",
	"results": "Results",
}

var _lan: LanBrowser
var _lan_rows: Dictionary = {}  # server id -> row Control

@onready var tabs: TabContainer = %Tabs
@onready var lan_list: VBoxContainer = %LanList
@onready var fav_list: VBoxContainer = %FavList
@onready var address_edit: LineEdit = %AddressEdit


func _ready() -> void:
	tabs.set_tab_title(0, tr("On your network"))
	tabs.set_tab_title(1, tr("Favourites"))
	%BackButton.pressed.connect(func() -> void: closed.emit())
	%JoinButton.pressed.connect(_join_typed)
	%SaveButton.pressed.connect(_save_typed)
	address_edit.text = Config.last_address
	address_edit.text_submitted.connect(func(_t: String) -> void: _join_typed())
	address_edit.text_changed.connect(func(t: String) -> void: Config.set_value("last_address", t))
	Config.changed.connect(_on_config_changed)
	_lan = LanBrowser.new()
	_lan.name = "LanBrowser"
	add_child(_lan)
	_lan.changed.connect(_refresh_lan)
	_refresh_lan()
	_refresh_favourites()
	if Config.favourites.size() > 0 and _lan.list.servers.is_empty():
		tabs.current_tab = 0
	tabs.get_tab_bar().grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		closed.emit()
		accept_event()


func _on_config_changed(key: String) -> void:
	if key == "favourites":
		_refresh_favourites()


# --- Direct connect --------------------------------------------------------------

func _join_typed() -> void:
	var text := address_edit.text.strip_edges()
	if text == "":
		address_edit.grab_focus()
		return
	join_requested.emit(text, "", false)


func _save_typed() -> void:
	var text := address_edit.text.strip_edges()
	if Net.parse_address(text).is_empty():
		Ui.play("ui_error")
		MessageDialog.inform(self, LeaveReason.title(LeaveReason.Code.BAD_ADDRESS),
			LeaveReason.message(LeaveReason.Code.BAD_ADDRESS, text))
		return
	Config.add_favourite(text, text)
	tabs.current_tab = 1


# --- LAN -----------------------------------------------------------------------

func _refresh_lan() -> void:
	var status: Label = %LanStatus
	if not _lan.is_listening():
		status.text = tr("LAN search is off: another copy of the game is using UDP ports 7778-7781. Close it, or type the server's address below.")
	elif _lan.list.servers.is_empty():
		status.text = tr("Looking for servers on your network... Nothing yet? The server may be on another network (type its address below), or a firewall blocks it: on Windows, allow HomerSim on private networks.")
	else:
		status.text = tr("Servers on your network. They refresh by themselves.")
	var entries := _lan.list.sorted()
	var ids: Array = []
	for entry in entries:
		ids.append(entry["id"])
	for id: int in _lan_rows.keys():
		if not ids.has(id):
			(_lan_rows[id] as Control).queue_free()
			_lan_rows.erase(id)
	for i in entries.size():
		var entry := entries[i]
		var row: Control = _lan_rows.get(entry["id"])
		if row == null:
			row = _make_lan_row(entry)
			lan_list.add_child(row)
			_lan_rows[entry["id"]] = row
		lan_list.move_child(row, i)
		_update_lan_row(row, entry)
	_refresh_favourites_status()


func _make_lan_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(_icon("locked", "Lock", Color(1, 0.79, 0.24)))
	row.add_child(_label("Name", "", true))
	row.add_child(_label("Players", "", false, 70))
	row.add_child(_label("State", "", false, 150))
	var ping := HBoxContainer.new()
	ping.name = "Ping"
	ping.custom_minimum_size = Vector2(96, 0)
	ping.add_child(_icon("signal3", "Bars", Color.WHITE))
	ping.add_child(_label("Ms", "", false))
	row.add_child(ping)
	var star := _icon_button("star", tr("Save to favourites"))
	star.name = "Star"
	star.pressed.connect(func() -> void:
		Config.add_favourite(entry["name"], LanDiscovery.address_of(_lan.list.servers.get(entry["id"], entry)))
		Ui.play("ui_confirm"))
	row.add_child(star)
	var join := Button.new()
	join.name = "Join"
	join.text = tr("Join")
	join.theme_type_variation = &"AccentButton"
	join.custom_minimum_size = Vector2(110, 0)
	join.pressed.connect(func() -> void:
		var current: Dictionary = _lan.list.servers.get(entry["id"], entry)
		join_requested.emit(LanDiscovery.address_of(current), current["name"], current["locked"]))
	row.add_child(join)
	return card


func _update_lan_row(card: Control, entry: Dictionary) -> void:
	var row := card.get_child(0)
	(row.get_node("Lock") as Control).modulate.a = 1.0 if entry["locked"] else 0.0
	(row.get_node("Lock") as Control).tooltip_text = tr("Needs a password") if entry["locked"] else ""
	(row.get_node("Name") as Label).text = entry["name"]
	var full: bool = entry["players"] >= entry["max"]
	var players := row.get_node("Players") as Label
	players.text = "%d/%d" % [entry["players"], entry["max"]]
	players.modulate = Color(1, 0.55, 0.5) if full else Color.WHITE
	var state := row.get_node("State") as Label
	var same_version: bool = entry["version"] == Session.game_version()
	if not same_version:
		state.text = tr("Other version")
		state.tooltip_text = tr("The server runs %s, you have %s") % [entry["version"], Session.game_version()]
		state.modulate = Color(1, 0.55, 0.5)
	else:
		state.text = tr(STATE_TEXT.get(entry["state"], "In the lobby"))
		state.tooltip_text = tr("You can join during a match: you watch until the next one.") if entry["state"] != "lobby" else ""
		state.modulate = Color(0.6, 1, 0.65) if entry["state"] == "lobby" else Color(1, 0.85, 0.5)
	var ping_ms: int = entry["ping_ms"]
	var bars := row.get_node("Ping/Bars") as TextureRect
	bars.texture = load(ICONS % ("signal3" if ping_ms < 60 else "signal2" if ping_ms < 150 else "signal1"))
	bars.modulate = Color(0.6, 1, 0.65) if ping_ms < 60 else Color(1, 0.85, 0.5) if ping_ms < 150 else Color(1, 0.55, 0.5)
	bars.modulate.a = 1.0 if ping_ms >= 0 else 0.25
	(row.get_node("Ping/Ms") as Label).text = tr("%d ms") % ping_ms if ping_ms >= 0 else "..."
	var join := row.get_node("Join") as Button
	join.disabled = not same_version or full
	join.tooltip_text = tr("Server full") if full else ""


# --- Favourites ----------------------------------------------------------------

func _refresh_favourites() -> void:
	for child in fav_list.get_children():
		child.queue_free()
	(%FavStatus as Label).text = tr("No favourites yet. Type an address below and press Save, or press the star next to a server on your network.") \
		if Config.favourites.is_empty() else tr("Your saved servers.")
	for i in Config.favourites.size():
		fav_list.add_child(_make_fav_row(i, Config.favourites[i]))
	_refresh_favourites_status()
	if get_viewport().gui_get_focus_owner() == null or tabs.current_tab == 1:
		_focus_favourites.call_deferred()


## After a change to the list (or a dialog closing), put the keyboard focus back on it.
func _focus_favourites() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_instance_valid(focused) and not focused.is_queued_for_deletion():
		return
	for card in fav_list.get_children():
		if not card.is_queued_for_deletion():
			(card.get_child(0).get_child(-1) as Control).grab_focus()
			return
	address_edit.grab_focus()


func _make_fav_row(index: int, fav: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.set_meta(&"address", fav["address"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(_label("Name", fav["name"], true))
	var address := _label("Address", fav["address"], false, 200)
	address.theme_type_variation = &"MutedLabel"
	address.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(address)
	row.add_child(_label("Status", "", false, 150))
	var rename := Button.new()
	rename.text = tr("Rename")
	rename.pressed.connect(func() -> void:
		var box := MessageDialog.ask(self, tr("Rename"), tr("A name for %s") % fav["address"], fav["name"], false, "", 40)
		box.closed.connect(func(ok: bool, text: String) -> void:
			if ok:
				Config.rename_favourite(index, text)))
	row.add_child(rename)
	var remove := _icon_button("trashcan", tr("Remove"))
	remove.theme_type_variation = &"DangerButton"
	remove.pressed.connect(func() -> void:
		var box := MessageDialog.confirm(self, tr("Remove"), tr("Remove %s from your favourites?") % fav["name"],
			tr("Remove"), "", true)
		box.closed.connect(func(ok: bool, _t: String) -> void:
			if ok:
				Config.remove_favourite(index)))
	row.add_child(remove)
	var join := Button.new()
	join.text = tr("Join")
	join.theme_type_variation = &"AccentButton"
	join.custom_minimum_size = Vector2(110, 0)
	join.pressed.connect(func() -> void:
		var lan := _lan_entry_for(fav["address"])
		join_requested.emit(fav["address"], fav["name"], lan.get("locked", false)))
	row.add_child(join)
	return card


## A favourite that is also on the LAN shows its live numbers.
func _refresh_favourites_status() -> void:
	for card in fav_list.get_children():
		if card.is_queued_for_deletion():
			continue
		var status := card.get_child(0).get_node("Status") as Label
		var lan := _lan_entry_for(card.get_meta(&"address"))
		if lan.is_empty():
			status.text = ""
		else:
			status.text = "%d/%d  ·  %s" % [lan["players"], lan["max"],
				tr("%d ms") % lan["ping_ms"] if lan["ping_ms"] >= 0 else "..."]


## The LAN entry with the same address as `address` (same host and port), or {}.
func _lan_entry_for(address: String) -> Dictionary:
	var wanted := Net.parse_address(address)
	if wanted.is_empty():
		return {}
	for entry: Dictionary in _lan.list.servers.values():
		if entry["port"] == wanted["port"] and (entry["address"] == wanted["host"]
				or (wanted["host"] in ["localhost", "127.0.0.1"] and entry["address"] == "127.0.0.1")):
			return entry
	return {}


# --- Little builders -----------------------------------------------------------

func _label(node_name: String, text: String, expand: bool, min_width: int = 0) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_PASS  # (tooltips)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
	if min_width > 0:
		label.custom_minimum_size = Vector2(min_width, 0)
	return label


func _icon(file: String, node_name: String, color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.texture = load(ICONS % file)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(26, 26)
	icon.modulate = color
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	return icon


func _icon_button(file: String, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = load(ICONS % file)
	button.add_theme_constant_override("icon_max_width", 26)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(56, 0)
	button.tooltip_text = tooltip
	return button
