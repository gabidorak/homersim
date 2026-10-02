extends Node
## Visual check of the characters (M7), windowed: loads the plant offline, spawns remote-looking
## bodies (through Session's own spawn function) in every animation state, and saves screenshots.
##   godot tests/helpers/CharacterTour.tscn -- [--out DIR] [--shot NAME]
## Shots: supervisors, rats, close (one of each, up close). Each body is "remote" (authority 100+),
## so it is drawn and animated from sync_anim / its status like any other player's body.

const SETTLE_S := 1.4


const Z0 := 10.0  # the Control Room's open floor

# name, role, position, yaw (deg), status bits, sync_anim flags, one-shot to fire, moving speed
const CAST := [
	["idle", Role.Kind.SUPERVISOR, Vector3(-8, 0, Z0), 0, 0, 0, "", 0.0],
	["walk", Role.Kind.SUPERVISOR, Vector3(-6, 0, Z0), 0, 0, 0, "", 4.0],
	["run", Role.Kind.SUPERVISOR, Vector3(-4, 0, Z0), 0, 0, 0, "", 7.0],
	["swing", Role.Kind.SUPERVISOR, Vector3(-2, 0, Z0), 0, 0, 0, "swing", 0.0],
	["interact", Role.Kind.SUPERVISOR, Vector3(0, 0, Z0), 0, 0, AnimationController.FLAG_INTERACT, "", 0.0],
	["carry", Role.Kind.SUPERVISOR, Vector3(2, 0, Z0), 0, 0, 0, "", 0.0],
	["knocked", Role.Kind.SUPERVISOR, Vector3(4, 0, Z0 + 0.5), 0, 1 << StatusComponent.Status.KNOCKED_DOWN, 0, "", 0.0],
	["stunned", Role.Kind.SUPERVISOR, Vector3(6, 0, Z0), 0, 1 << StatusComponent.Status.STUNNED, 0, "", 0.0],
	["lobby", Role.Kind.NONE, Vector3(8, 0, Z0), 0, 0, 0, "", 0.0],
	["r_idle", Role.Kind.RAT, Vector3(-7, 0, Z0 + 3), 0, 0, 0, "", 0.0],
	["r_run", Role.Kind.RAT, Vector3(-5.5, 0, Z0 + 3), 0, 0, 0, "", 6.0],
	["r_gnaw", Role.Kind.RAT, Vector3(-4, 0, Z0 + 3), 0, 0, AnimationController.FLAG_INTERACT, "", 0.0],
	["r_stunned", Role.Kind.RAT, Vector3(-2.5, 0, Z0 + 3), 0, 1 << StatusComponent.Status.STUNNED, 0, "", 0.0],
	["r_caged", Role.Kind.RAT, Vector3(-1, 0, Z0 + 3), 0, 1 << StatusComponent.Status.CAGED, 0, "", 0.0],
	["r_dangle", Role.Kind.RAT, Vector3(0.5, 0.9, Z0 + 3), 0, 1 << StatusComponent.Status.CARRIED, 0, "", 0.0],
	["r_crawl", Role.Kind.RAT, Vector3(2, 0, Z0 + 3), 0, 0, AnimationController.FLAG_IN_VENT, "", 2.0],
	["r_bite", Role.Kind.RAT, Vector3(3.5, 0, Z0 + 3), 0, 0, 0, "bite", 0.0],
	["r_squeak", Role.Kind.RAT, Vector3(5, 0, Z0 + 3), 0, 0, AnimationController.FLAG_EMOTE, "", 0.0],
	["r_jump", Role.Kind.RAT, Vector3(6.5, 0.4, Z0 + 3), 0, 0, AnimationController.FLAG_AIRBORNE | AnimationController.FLAG_RISING, "", 0.0],
]
# name, eye, look at
const SHOTS := [
	["supervisors", Vector3(0, 2.6, Z0 + 7.5), Vector3(0, 0.9, Z0)],
	["rats", Vector3(-0.5, 1.3, Z0 + 6.2), Vector3(-0.5, 0.2, Z0 + 3)],
	["close", Vector3(-5.2, 1.2, Z0 + 5.2), Vector3(-6.3, 0.6, Z0 + 1.5)],
]

var _session: Session
var _bodies: Array[Player] = []
var _movers: Array = []  # [body, centre, speed]


func _ready() -> void:
	var out := Cli.get_str("out", "user://character_tour")
	DirAccess.make_dir_recursive_absolute(out)
	_session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_session)
	await get_tree().create_timer(0.8).timeout
	for node in _session.client_only.get_children():
		if node is CanvasItem or (node is CanvasLayer and not node is DebugOverlay):
			node.set("visible", false)
	var id := 100
	for c: Array in CAST:
		id += 1
		_session.players[id] = PlayerInfo.new()
		_session.players[id].name = c[0]
		var body := _session._spawn_player({"peer": id, "name": c[0], "role": c[1], "pos": c[2],
			"yaw": deg_to_rad(c[3] + 180.0), "locked": false}) as Player
		_session.players_root.add_child(body)
		body.status.flags = c[4]
		body.sync_anim = c[5]
		body.sync_position = c[2]
		if c[0] == "carry":
			body.status.carrying = 999
		if c[7] > 0.0:
			_movers.append([body, c[2], c[7]])
		_bodies.append(body)
	await get_tree().create_timer(0.6).timeout
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.make_current()
	for shot: Array in SHOTS:
		if Cli.has_arg("shot") and shot[0] != Cli.get_str("shot"):
			continue
		camera.look_at_from_position(shot[1], shot[2])
		for i in CAST.size():
			if CAST[i][6] != "":
				_bodies[i].anim.play_one_shot(CAST[i][6])
		await get_tree().create_timer(SETTLE_S if CAST.any(func(c: Array) -> bool: return c[6] == "") else 0.2).timeout
		if shot[0] == "supervisors" or shot[0] == "rats":
			for i in CAST.size():  # re-fire one-shots so the picture catches them mid-motion
				if CAST[i][6] != "":
					_bodies[i].anim.play_one_shot(CAST[i][6])
			await get_tree().create_timer(0.15).timeout
		var path := "%s/%s.png" % [out, shot[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("character tour: ", path)
	get_tree().quit()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for m: Array in _movers:
		var body: Player = m[0]
		# Walk back and forth on the spot (speed m/s): the animation reads the motion.
		var x := sin(t * m[2] / 0.6) * 0.6
		body.sync_position = (m[1] as Vector3) + Vector3(0, 0, x)
		body.sync_yaw = PI if cos(t * m[2] / 0.6) > 0.0 else 0.0
