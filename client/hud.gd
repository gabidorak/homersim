extends Control
## In-game HUD. Only reads synced state (MatchManager, PlantSim) and the local player:
## timer, meltdown bar, core temperature gauge (coloured by alarm), one icon per subsystem
## (health fill + cooldown overlay), interaction prompt + progress ring, stamina bar.
## Alarm feedback: a screen-edge tint, and a placeholder beep when the alarm goes up.

const ALARM_COLORS := {
	PlantModel.Alarm.NORMAL: Color(0.35, 0.8, 0.4),
	PlantModel.Alarm.WARNING: Color(1, 0.7, 0.15),
	PlantModel.Alarm.CRITICAL: Color(1, 0.2, 0.15),
}
const BEEP_RATE := 22050

var _player: Player
var _icons: Array[SubsystemIcon] = []
var _temp_fill := StyleBoxFlat.new()
var _meltdown_fill := StyleBoxFlat.new()
var _beep: AudioStreamPlayer
var _last_alarm := PlantModel.Alarm.NORMAL

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


func _ready() -> void:
	Events.local_player_spawned.connect(func(player: Node3D) -> void: _player = player as Player)
	Events.plant_alarm_changed.connect(_on_alarm_changed)
	var plant := Session.current.plant
	for i in plant.count():
		var icon := SubsystemIcon.new()
		icon.custom_minimum_size = Vector2(52, 52)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.label = plant.data(i).short_name
		icon.critical = plant.data(i).critical
		icon.tooltip_text = plant.data(i).display_name
		subsystems_box.add_child(icon)
		_icons.append(icon)
	_meltdown_fill.bg_color = Color(0.85, 0.15, 0.6)
	meltdown_bar.add_theme_stylebox_override("fill", _meltdown_fill)
	temp_bar.add_theme_stylebox_override("fill", _temp_fill)
	_beep = AudioStreamPlayer.new()
	_beep.stream = _make_beep()
	add_child(_beep)


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
	timer_label.modulate = Color(1, 0.5, 0.4) if mm.state == MatchManager.State.PLAYING and seconds <= 30 else Color.WHITE
	meltdown_bar.value = plant.meltdown
	meltdown_label.text = "Meltdown %d%%" % floori(plant.meltdown)
	temp_bar.value = plant.core_temp
	temp_label.text = "Core %d°" % roundi(plant.core_temp)
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
	alarm_tint.visible = strength > 0.0
	alarm_tint.material.set_shader_parameter("strength", strength)


func _update_player() -> void:
	var alive := is_instance_valid(_player) and _player.is_inside_tree()
	stamina_bar.visible = alive
	crosshair.visible = alive and _player.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON
	if not alive:
		info_label.text = "Enter: chat"
		prompt_label.text = ""
		ring.value = 0.0
		return
	var stamina := _player.movement.stamina
	stamina_bar.value = stamina.fraction() * 100.0
	stamina_bar.modulate = Color(1, 0.45, 0.4) if stamina.exhausted else Color.WHITE
	var role := Role.display_name(_player.role)
	var frozen := "  ·  frozen" if not _player.movement.can_move() else ""
	var hint := "WASD move · Shift sprint · Space jump · E (hold) interact · Enter chat · Esc free the mouse"
	info_label.text = "%s%s\n%s" % [role, frozen, hint]
	var playing := Session.current.match_manager.state == MatchManager.State.PLAYING
	prompt_label.text = _player.interactor.prompt_text() if playing else ""
	ring.value = _player.interactor.hold_progress() if playing else 0.0


func _on_alarm_changed(alarm: int) -> void:
	var worse := alarm > _last_alarm
	_last_alarm = alarm as PlantModel.Alarm
	if not worse or Session.current.match_manager.state != MatchManager.State.PLAYING:
		return
	# Only when it gets worse: WARNING beeps once, CRITICAL twice.
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
