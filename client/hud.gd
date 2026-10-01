extends Control
## Temporary in-game HUD (M2): role line, controls hint, crosshair and stamina bar.
## The full HUD (timer, meltdown, subsystems) arrives in M3.

var _player: Player

@onready var info_label: Label = %InfoLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var crosshair: Control = %Crosshair


func _ready() -> void:
	Events.local_player_spawned.connect(func(player: Node3D) -> void: _player = player as Player)


func _process(_delta: float) -> void:
	var alive := is_instance_valid(_player) and _player.is_inside_tree()
	stamina_bar.visible = alive
	crosshair.visible = alive and _player.role_data.camera_kind == RoleData.CameraKind.FIRST_PERSON
	if not alive:
		info_label.text = "Enter: chat"
		return
	var stamina := _player.movement.stamina
	stamina_bar.value = stamina.fraction() * 100.0
	stamina_bar.modulate = Color(1, 0.45, 0.4) if stamina.exhausted else Color.WHITE
	var role := Role.display_name(_player.role)
	var frozen := "  ·  frozen" if not _player.movement.can_move() else ""
	info_label.text = "%s%s\nWASD move · Shift sprint · Space jump · Enter chat · Esc free the mouse" % [role, frozen]
