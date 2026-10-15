extends Node
## Visual check of a rat's tail spin, windowed: loads the plant offline, puts a rat model between a
## snap trap and a cheese lure in the Control Room, spins it in slow motion (the model's whirl, the
## speed streaks, the floor swirl, the dust ring, the traps smashing) and saves a screenshot at each
## moment of SHOTS.
##   godot tests/helpers/TailSpinShots.tscn -- [--out DIR]

const SPOT := Vector3(-1, 0, 8.5)
const SLOW := 0.1  ## Engine.time_scale while spinning, so each shot lands where it should
const SMASH_AT := 0.05  ## s into the spin: the server's answer comes back about now
## [name, seconds into the spin]
const SHOTS := [["0_start", 0.02], ["1_whirl", 0.1], ["2_smash", 0.18], ["3_fast", 0.28], ["4_slowing", 0.42],
	["5_end", 0.58]]
const TRAPS := [["snap_trap", Vector3(0.9, 0, 0.5)], ["cheese_lure", Vector3(-0.9, 0, 0.5)]]

var _out := ""


func _ready() -> void:
	_out = Cli.get_str("out", "user://tail_spin_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	var session: Session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(session)
	await get_tree().create_timer(1.0).timeout
	for node in session.client_only.get_children():
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = false
	var world := session.get_node("World") as Node3D
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		SPOT + Vector3.UP * 3.0, SPOT + Vector3.DOWN * 3.0, PhysicsLayers.WORLD))
	var floor_at: Vector3 = hit["position"] if not hit.is_empty() else SPOT
	var rat := Role.data(Role.Kind.RAT)
	var body := Node3D.new()
	world.add_child(body)
	body.global_position = floor_at
	var visual := Node3D.new()
	body.add_child(visual)
	visual.add_child(rat.visual_scene.instantiate())
	var traps: Array[Node3D] = []
	for spec: Array in TRAPS:
		var trap := Node3D.new()
		world.add_child(trap)
		trap.global_position = floor_at + (spec[1] as Vector3)
		Art.add(trap, spec[0], Transform3D.IDENTITY)
		traps.append(trap)
	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.look_at_from_position(floor_at + Vector3(0.4, 1.5, 2.8), floor_at + Vector3(0, 0.25, 0))
	camera.make_current()
	await get_tree().create_timer(0.5).timeout
	await _shot("before")
	# The spin, as BodyFx and CombatFeedback play it.
	Engine.time_scale = SLOW
	var spin := rat.ability(&"tail_spin")
	var duration := float(spin.extra["spin_s"])
	var tween := body.create_tween()
	tween.tween_method(func(u: float) -> void:
		visual.rotation.y = -TAU * BodyFx.SPIN_TURNS * (1.0 - (1.0 - u) * (1.0 - u))
		visual.position.y = sin(u * PI) * BodyFx.SPIN_HOP, 0.0, 1.0, duration)
	Vfx.tail_spin(body, spin.range, duration)
	get_tree().create_timer(SMASH_AT).timeout.connect(func() -> void:
		for trap in traps:
			Vfx.smash(world, trap.global_position)
			trap.queue_free())
	var elapsed := 0.0
	for shot: Array in SHOTS:
		await get_tree().create_timer(float(shot[1]) - elapsed).timeout
		elapsed = shot[1]
		await _shot(shot[0])
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.5).timeout
	await _shot("after")
	Log.info("tail_spin_shots", "saved in %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("%s.png" % shot_name)
	get_viewport().get_texture().get_image().save_png(path)
