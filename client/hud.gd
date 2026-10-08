extends Control
## In-game HUD. Only reads synced state (MatchManager, PlantSim) and the local player:
## timer, meltdown bar, core temperature gauge (coloured by alarm), one icon per subsystem
## (health fill + cooldown overlay), interaction prompt + progress ring, stamina bar.
## Alarm feedback: a screen-edge tint, and a placeholder beep when the alarm goes up.
## PvP (M4): the local player's statuses, abilities with cooldowns, keycard / traps / stolen item,
## a banner for big moments (BONK, SNAP, caged), and what a ghost or spectator can do.
## M6: hazard hits and plant-wide events (SCRAM, coolant) in the banner, the SCRAM countdown and the
## time it added under the timer, and a short flash of the edge tint whenever the alarm gets worse.
## M8: every text is translated and names the player's own keys (Keys.label); the long key list moved
## to How to play and the first-time hints, so the corner only keeps a short reminder.
## The inventory (keycard, traps, donut, a rat's loot) is the HotbarView at the bottom during a match,
## with the stamina bar and the statuses lifted above it; the corner text keeps the alerts.

const ALARM_COLORS := {
	PlantModel.Alarm.NORMAL: Color(0.35, 0.8, 0.4),
	PlantModel.Alarm.WARNING: Color(1, 0.7, 0.15),
	PlantModel.Alarm.CRITICAL: Color(1, 0.2, 0.15),
}
const BEEP_RATE := 22050
const BANNER_S := 2.5
const ALARM_FLASH_S := 0.6
const ABOVE_HOTBAR := 10.0  ## px between the hotbar and the stamina bar

var _player: Player
var _icons: Array[SubsystemIcon] = []
var _temp_fill := StyleBoxFlat.new()
var _meltdown_fill := StyleBoxFlat.new()
var _beep: AudioStreamPlayer
var _last_alarm := PlantModel.Alarm.NORMAL
var _banner_until_ms := 0
var _flash_until_ms := 0
var _hotbar: HotbarView
var _lifted := false
var _stamina_offsets := Vector2.ZERO  # the scene's offset_top / offset_bottom (no hotbar)
var _status_offsets := Vector2.ZERO

@onready var info_label: Label = %InfoLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var crosshair: Control = %Crosshair
@onready var plant_panel: Control = %PlantPanel
@onready var timer_label: Label = %TimerLabel
@onready var meltdown_label: Label = %MeltdownLabel
@onready var meltdown_bar: ProgressBar = %MeltdownBar
@onready var temp_label: Label = %TempLabel
@onready var temp_bar: ProgressBar = %TempBar
@onready var subsystems_box: HBoxContainer = %Subsystems
@onready var ring: ProgressRing = %Ring
@onready var prompt_label: Label = %PromptLabel
@onready var alarm_tint: ColorRect = %AlarmTint
@onready var status_label: RichTextLabel = %StatusLabel
@onready var ability_label: Label = %AbilityLabel
@onready var banner_label: Label = %BannerLabel


func _ready() -> void:
	Events.local_player_spawned.connect(func(player: Node3D) -> void: _player = player as Player)
	Events.plant_alarm_changed.connect(_on_alarm_changed)
	Events.local_hazard_hit.connect(show_banner)
	Events.plant_announcement.connect(show_banner)
	var feedback := Session.current.client_only.get_node_or_null("CombatFeedback") as CombatFeedback
	if feedback != null:
		feedback.banner.connect(show_banner)
	var plant := Session.current.plant
	for i in plant.count():
		var icon := SubsystemIcon.new()
		icon.custom_minimum_size = Vector2(52, 52)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.label = tr(plant.data(i).short_name)
		icon.critical = plant.data(i).critical
		icon.tooltip_text = tr(plant.data(i).display_name)
		subsystems_box.add_child(icon)
		_icons.append(icon)
	_meltdown_fill.bg_color = Color(0.85, 0.15, 0.6)
	meltdown_bar.add_theme_stylebox_override("fill", _meltdown_fill)
	temp_bar.add_theme_stylebox_override("fill", _temp_fill)
	_beep = AudioStreamPlayer.new()
	_beep.stream = _make_beep()
	add_child(_beep)
	_hotbar = HotbarView.new()
	_hotbar.name = "Hotbar"
	_hotbar.visible = false
	add_child(_hotbar)
	_stamina_offsets = Vector2(stamina_bar.offset_top, stamina_bar.offset_bottom)
	_status_offsets = Vector2(status_label.offset_top, status_label.offset_bottom)


func _process(_delta: float) -> void:
	_update_plant()
	_update_player()


func _update_plant() -> void:
	var mm := Session.current.match_manager
	plant_panel.visible = mm.state in [MatchManager.State.COUNTDOWN, MatchManager.State.PLAYING,
		MatchManager.State.POST_MATCH]
	if not plant_panel.visible:
		alarm_tint.visible = false
		return
	var plant := Session.current.plant
	var seconds := mm.time_left if mm.state != MatchManager.State.COUNTDOWN else 0
	timer_label.text = "%d:%02d" % [floori(seconds / 60.0), seconds % 60] if mm.state == MatchManager.State.PLAYING else ""
	if mm.state == MatchManager.State.PLAYING:
		if plant.scram_left > 0.0:
			timer_label.text += "\n" + tr("SCRAM %d s") % ceili(plant.scram_left)
		if mm.time_added > 0:
			timer_label.text += "\n" + tr("(+%d s SCRAM)") % mm.time_added
	timer_label.modulate = Color(1, 0.5, 0.4) if mm.state == MatchManager.State.PLAYING and seconds <= 30 else Color.WHITE
	meltdown_bar.value = plant.meltdown
	meltdown_label.text = tr("Meltdown %d%%") % floori(plant.meltdown)
	temp_bar.value = plant.core_temp
	temp_label.text = tr("Core %d°") % roundi(plant.core_temp)
	_temp_fill.bg_color = ALARM_COLORS[plant.alarm]
	for i in _icons.size():
		_icons[i].set_state(plant.health(i), plant.cooldown_left(i), plant.needs_reboot(i))

	# Edge tint: steady for WARNING, pulsing for CRITICAL.
	var strength := 0.0
	if mm.state == MatchManager.State.PLAYING:
		match plant.alarm:
			PlantModel.Alarm.WARNING:
				alarm_tint.material.set_shader_parameter("tint", Color(1, 0.6, 0.1))
				strength = 0.25
			PlantModel.Alarm.CRITICAL:
				alarm_tint.material.set_shader_parameter("tint", Color(1, 0.08, 0.05))
				strength = 0.4 + 0.2 * sin(Time.get_ticks_msec() / 200.0)
	if Time.get_ticks_msec() < _flash_until_ms:
		strength = maxf(strength, 0.9 * (_flash_until_ms - Time.get_ticks_msec()) / (ALARM_FLASH_S * 1000.0))
	alarm_tint.visible = strength > 0.0
	alarm_tint.material.set_shader_parameter("strength", strength)


## A big line in the middle of the screen for a few seconds.
func show_banner(text: String) -> void:
	banner_label.text = text
	_banner_until_ms = Time.get_ticks_msec() + int(BANNER_S * 1000.0)


func _update_player() -> void:
	var alive := is_instance_valid(_player) and _player.is_inside_tree()
	stamina_bar.visible = alive
	var in_match := Session.current.match_manager.state in [MatchManager.State.COUNTDOWN, MatchManager.State.PLAYING]
	_hotbar.player = _player if alive and in_match else null
	_hotbar.visible = _hotbar.wanted()
	_lift_above_hotbar(_hotbar.visible)
	crosshair.visible = alive and _player.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON \
		and _player.seated_console() == null
	if Time.get_ticks_msec() > _banner_until_ms:
		banner_label.text = ""
	if not alive:
		_update_ghost()
		return
	var stamina := _player.movement.stamina
	stamina_bar.value = stamina.fraction() * 100.0
	stamina_bar.modulate = Color(1, 0.45, 0.4) if stamina.exhausted else Color.WHITE
	var role := tr(Role.display_name(_player.role))
	var frozen := "  ·  " + tr("frozen") if not _player.movement.can_move() else ""
	var keys := [tr("%s chat") % Keys.label(&"chat")]
	if _player.role in [Role.Kind.SUPERVISOR, Role.Kind.RAT]:
		keys.append(tr("%s team chat") % Keys.label(&"team_chat"))
	keys.append(tr("%s scores and map") % Keys.label(&"scoreboard"))
	keys.append(tr("Esc menu"))
	info_label.text = "%s%s\n%s" % [role, frozen, " · ".join(keys)]
	var playing := Session.current.match_manager.state == MatchManager.State.PLAYING
	prompt_label.text = _player.interactor.prompt_text() if playing else ""  # (translated by the interactable)
	ring.value = _player.interactor.hold_progress() if playing else 0.0
	_update_statuses()
	ability_label.text = _ability_text() if playing else ""


func _update_statuses() -> void:
	var parts: Array[String] = []
	for entry: Array in StatusComponent.describe(_player.status.flags):
		parts.append("[color=#%s]%s[/color]" % [(entry[1] as Color).to_html(false), tr(entry[0])])
	status_label.text = "  ".join(parts)
	if _player.status.has(StatusComponent.Status.CAGED):
		banner_label.text = tr("You're caged! A free rat can let you out (hold %s at the cage). Meanwhile, %s spits at supervisors") \
			% [Keys.label(&"interact"), Keys.label(&"primary")]
		_banner_until_ms = Time.get_ticks_msec() + 200


func _ability_text() -> String:
	var lines: Array[String] = []
	var abilities := _player.abilities
	var primary := abilities.primary()
	if primary != null:
		lines.append("%s %s: %s" % [Keys.label(&"primary"), tr(primary.display_name), _cooldown_text(primary.id)])
	var inv := _player.inventory
	if _player.role == Role.Kind.SUPERVISOR:
		if not inv.keycard:  # (the hotbar shows the keycard; this says where to get a spare)
			lines.append(tr("Keycard: STOLEN · spare in Storage in %d s") % inv.spare_wait_left if inv.spare_wait_left > 0
				else tr("Keycard: STOLEN · a spare is waiting in Storage"))
		if _player.status.carrying != 0:
			lines.append(tr("Carrying %s: get to a cage!") % Session.current.name_of(_player.status.carrying))
	elif inv.stolen_item != &"":
		lines.append(tr("You carry a %s (a bit slower; a stun drops it)") % tr(String(inv.stolen_item)))
	return "\n".join(lines)


## The stamina bar and the statuses sit above the hotbar while it shows, at the bottom otherwise.
func _lift_above_hotbar(lifted: bool) -> void:
	if lifted == _lifted:
		return
	_lifted = lifted
	var lift := HotbarView.height() + ABOVE_HOTBAR + _stamina_offsets.y if lifted else 0.0
	stamina_bar.offset_top = _stamina_offsets.x - lift
	stamina_bar.offset_bottom = _stamina_offsets.y - lift
	status_label.offset_top = _status_offsets.x - lift
	status_label.offset_bottom = _status_offsets.y - lift
	# The item caption goes above the statuses.
	_hotbar.caption_lift = ABOVE_HOTBAR + (_stamina_offsets.y - _status_offsets.x) + 6.0


func _cooldown_text(id: StringName) -> String:
	var left := _player.abilities.cooldown_left(id)
	return tr("ready") if left <= 0.0 else "%.1f s" % left


## No body: in the lobby gap, eliminated, or a late joiner.
func _update_ghost() -> void:
	prompt_label.text = ""
	ring.value = 0.0
	status_label.text = ""
	ability_label.text = ""
	var mm := Session.current.match_manager
	if not mm.in_match():
		info_label.text = tr("%s chat") % Keys.label(&"chat") + " · " + tr("Esc menu")
		return
	var me := mm.entry(Session.current.local_peer_id)
	var why := tr("You were eliminated") if me.get("eliminated", false) else tr("Spectating until the next match")
	info_label.text = "%s · %s\n%s" % [why, tr("ghost chat only (%s)") % Keys.label(&"chat"),
		tr("%s / %s: watch the next / previous player · %s + %s / %s: fly") % [Keys.label(&"primary"),
		Keys.label(&"secondary"), Keys.move_label(), Keys.label(&"spectate_up"), Keys.label(&"spectate_down")]]


func _on_alarm_changed(alarm: int) -> void:
	var worse := alarm > _last_alarm
	_last_alarm = alarm as PlantModel.Alarm
	if not worse or Session.current.match_manager.state != MatchManager.State.PLAYING:
		return
	# Only when it gets worse: a flash, then WARNING beeps once, CRITICAL twice.
	_flash_until_ms = Time.get_ticks_msec() + int(ALARM_FLASH_S * 1000.0)
	alarm_tint.material.set_shader_parameter("tint", ALARM_COLORS[alarm])
	_beep.pitch_scale = 1.0 if alarm == PlantModel.Alarm.WARNING else 1.4
	_beep.play()
	if alarm == PlantModel.Alarm.CRITICAL:
		await get_tree().create_timer(0.3).timeout
		_beep.play()


## Placeholder alarm sound (until M7): a 0.2 s 880 Hz square-ish tone, generated in code.
static func _make_beep() -> AudioStreamWAV:
	var samples := int(BEEP_RATE * 0.2)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / BEEP_RATE
		var envelope := minf(1.0, (samples - i) / 600.0)  # short fade-out, no click
		var value := clampf(sin(TAU * 880.0 * t) * 2.0, -1.0, 1.0) * 0.35 * envelope
		data.encode_s16(i * 2, int(value * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = BEEP_RATE
	wav.data = data
	return wav
