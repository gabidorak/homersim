@tool
extends Node3D
## Side-by-side preview of the supervisor skins: the plant supervisor (tools/blender/supervisor.py)
## and the Soviet general (tools/blender/supervisor_general.py, not in the game yet). Open the scene in
## the editor: both models play `clip` in the 3D view (pick another one in the inspector). Run it (F6)
## to watch them turn round, or from a terminal:
##   godot tests/helpers/SkinPreview.tscn -- [--clip NAME] [--out PATH]
## --out saves a screenshot (models facing the camera) and quits.

## The clip both models play: idle, walk, run, jump, fall, swing, carry_idle, place, interact,
## knocked, get_up, eat, sit, emote, emote_no, or one of the intro's (cheer, chase, point, ...).
@export var clip := "idle":
	set(value):
		clip = value
		if is_inside_tree():
			_play()
## How fast the models turn when the scene runs (degrees per second).
@export var turn_speed := 25.0

var _shot := ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		var args := OS.get_cmdline_user_args()
		for i in args.size() - 1:
			if args[i] == "--clip":
				clip = args[i + 1]
			elif args[i] == "--out":
				_shot = args[i + 1]
	_play()
	if _shot != "":
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(_shot)
		print("skin preview: ", _shot)
		get_tree().quit()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _shot != "":
		return
	for model: Node3D in [$Supervisor, $General]:
		model.rotate_y(deg_to_rad(turn_speed) * delta)


func _play() -> void:
	for player: AnimationPlayer in find_children("*", "AnimationPlayer", true, false):
		if player.has_animation(clip):
			player.play(clip)
