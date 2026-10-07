class_name AnimationController
extends Node
## Drives a player body's character model (ARCHITECTURE §4, M7) with an AnimationTree built here:
##
##   loco      BlendSpace1D on horizontal speed: idle → walk → run (rats: idle → run)
##   loco_rate TimeScale, so feet keep up with the body at any speed
##   state     Transition: ground (loco), jump, fall, interact, climb, crawl, sit, stunned,
##             knocked, dangle, caged
##   carry     Blend2 with a filter on the arms: a supervisor carrying a rat holds it up while
##             the legs keep walking
##   action    OneShot for short clips fired by events: swing, bite, place, eat, get_up, emote
##
## Everything comes from data every peer already has (ARCHITECTURE §3): the speed is measured from
## how the body moves (remote bodies glide toward their synced position), statuses from
## StatusComponent, and what the player is doing from Player.sync_anim (BodySync), which the owner
## fills in local_flags(). One-shots come from the cosmetic RPCs (broom swing, bite) and from
## changes in synced state (a donut eaten, an emote). Client only: the headless server never
## creates this node.
##
## Clip names are the ones exported by tools/blender/supervisor.py and rat.py; a missing clip is
## skipped (the placeholder visuals have none, so nothing breaks before the models exist).

signal one_shot(clip: String)  ## a short clip started (BodyFx plays its sound)
signal state_changed(state: String)
signal landed(fall_speed: float)

## Player.sync_anim bits (written by the owner, read by everyone).
const FLAG_AIRBORNE := 1
const FLAG_INTERACT := 2
const FLAG_EMOTE := 4
const FLAG_CLIMB := 8
const FLAG_IN_VENT := 16
const FLAG_RISING := 32
const STATES: Array[String] = ["ground", "jump", "fall", "interact", "climb", "crawl", "sit", "stunned", "knocked",
	"dangle", "caged"]
const EMOTE_S := 1.6
const SPEED_SMOOTHING := 12.0
const VENT_CHECK_S := 0.2

## Per role: which clip each state uses ("" = stay on the ground state), the arms for the carry
## blend, and the run clip's natural speed (m/s) for the time scale.
const HUMAN_CLIPS := {
	"idle": "idle", "walk": "walk", "run": "run", "jump": "jump", "fall": "fall", "interact": "interact",
	"climb": "walk", "crawl": "", "sit": "sit", "stunned": "", "knocked": "knocked", "dangle": "", "caged": "",
	"carry": "carry_idle", "emote": "emote", "arms": ["arm-left", "arm-right"],
}
const ROLE_CLIPS := {
	Role.Kind.NONE: HUMAN_CLIPS,  # lobby bodies wear the supervisor model
	Role.Kind.SUPERVISOR: HUMAN_CLIPS,
	Role.Kind.RAT: {
		"idle": "idle", "run": "run", "jump": "jump", "fall": "fall", "interact": "gnaw", "climb": "run",
		"crawl": "crawl", "sit": "", "stunned": "stunned", "knocked": "stunned", "dangle": "dangle", "caged": "caged",
		"carry": "", "emote": "squeak", "arms": [],
	},
}

var body: Player
var model: Node3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var clips: Dictionary = {}
var state := "ground"
var speed := 0.0  ## m/s, horizontal, smoothed
var vertical_speed := 0.0

var _last_pos := Vector3.ZERO
var _was_airborne := false
var _air_time := 0.0
var _min_vy := 0.0
var _emote_until := 0.0  # owner: Time in seconds
var _last_flags := 0
var _last_donuts := 0
var _vent_check := 0.0
var _in_vent := false
var _walk_speed := 1.0
var _run_speed := 1.0


## `model_root` is the role visual (its AnimationPlayer is found below it).
func setup(p_body: Player, model_root: Node3D) -> void:
	body = p_body
	model = model_root
	clips = ROLE_CLIPS.get(body.role, {})
	var found := model.find_children("*", "AnimationPlayer", true, false) if model != null else []
	anim_player = found[0] as AnimationPlayer if not found.is_empty() else null
	_walk_speed = body.role_data.walk_speed
	_run_speed = body.role_data.sprint_speed


func _ready() -> void:
	_last_pos = body.global_position
	if anim_player != null and not clips.is_empty() and not Art.headless():
		_build_tree()
	var abilities := Session.current.abilities if Session.current != null else null
	if abilities != null:
		abilities.broom_swung.connect(func(attacker: int, _victim: int, _stunned: bool) -> void:
			if attacker == body.peer_id and not body.is_local():  # the owner fired it already
				play_one_shot("swing"))
		abilities.bitten.connect(func(attacker: int, _victim: int, _result: int) -> void:
			if attacker == body.peer_id and not body.is_local():
				play_one_shot("bite"))
	_last_donuts = body.inventory.donuts


func has_clip(clip: String) -> bool:
	return anim_player != null and clip != "" and anim_player.has_animation(clip)


## Starts a short clip on top of whatever the body does (no-op without that clip).
func play_one_shot(clip: String) -> void:
	one_shot.emit(clip)
	if tree == null or not has_clip(clip):
		return
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node("action_clip") as AnimationNodeAnimation
	node.animation = clip
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Freezes the pose for `seconds` (hit-stop on a BONK).
func hit_stop(seconds: float) -> void:
	if tree == null:
		return
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(tree):
			tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)


## Owner: start an emote (Z): synced to everyone through FLAG_EMOTE.
func start_emote() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _emote_until + 0.4:
		return
	_emote_until = now + EMOTE_S


## Owner: what this body is doing, packed into Player.sync_anim.
func local_flags() -> int:
	return flags_for(body, body.interactor.holding != null or _minigame_open(),
		Time.get_ticks_msec() / 1000.0 < _emote_until, _in_vent)


## The Player.sync_anim bits for `body` (it must be simulated here: the owner, or the server for an
## AI bot, whose driver fills sync_anim with this, M10).
static func flags_for(body: Player, interacting: bool, emoting: bool, in_vent: bool) -> int:
	var flags := 0
	if not body.is_on_floor() and not body.movement.climbing:
		flags |= FLAG_AIRBORNE
		if body.velocity.y > 0.5:
			flags |= FLAG_RISING
	if interacting:
		flags |= FLAG_INTERACT
	if emoting:
		flags |= FLAG_EMOTE
	if body.movement.climbing:
		flags |= FLAG_CLIMB
	if in_vent:
		flags |= FLAG_IN_VENT
	return flags


func _process(delta: float) -> void:
	# Speed from movement (works the same for the owner and for interpolated remote bodies).
	var pos := body.global_position
	var moved := pos - _last_pos
	_last_pos = pos
	if delta > 0.0:
		var flat := Vector2(moved.x, moved.z).length() / delta
		if flat > 30.0:  # a teleport, not a run
			flat = 0.0
		var w := 1.0 - exp(-SPEED_SMOOTHING * delta)
		speed = lerpf(speed, flat, w)
		vertical_speed = lerpf(vertical_speed, moved.y / delta, w)
	if body.is_local():
		_vent_check -= delta
		if _vent_check <= 0.0:
			_vent_check = VENT_CHECK_S
			_in_vent = body.role == Role.Kind.RAT and VentVolume.contains(body)
	var flags := body.sync_anim
	_check_flag_edges(flags)
	var airborne := flags & FLAG_AIRBORNE != 0
	if airborne:
		_air_time += delta
		_min_vy = minf(_min_vy, vertical_speed)
	elif _was_airborne:
		if _air_time > 0.35:
			landed.emit(-_min_vy)
		_air_time = 0.0
		_min_vy = 0.0
	_was_airborne = airborne
	_set_state(_pick_state(flags))
	_check_donut()
	if tree != null:
		tree.set("parameters/loco/blend_position", speed)
		var rate := 1.0
		if speed > _walk_speed * 1.05:
			rate = clampf(speed / _run_speed, 0.7, 1.5)
		elif speed > 0.2:
			rate = clampf(speed / _walk_speed, 0.6, 1.3)
		tree.set("parameters/loco_rate/scale", rate)
		var carrying := body.status.carrying != 0
		tree.set("parameters/carry/blend_amount", 1.0 if carrying else 0.0)


func _pick_state(flags: int) -> String:
	var st := body.status
	if st.has(StatusComponent.Status.CARRIED):
		return "dangle"
	if st.has(StatusComponent.Status.CAGED):
		return "caged"
	if st.has(StatusComponent.Status.KNOCKED_DOWN):
		return "knocked"
	if st.has(StatusComponent.Status.STUNNED):
		return "stunned"
	if body.seated_console() != null:
		return "sit"
	if flags & FLAG_CLIMB:
		return "climb"
	if flags & FLAG_AIRBORNE:
		return "jump" if flags & FLAG_RISING else ("fall" if _air_time > 0.5 else "jump")
	if flags & FLAG_INTERACT:
		return "interact"
	if flags & FLAG_IN_VENT:
		return "crawl"
	return "ground"


func _set_state(new_state: String) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(state)
	if tree != null:
		var clip: String = clips.get(state, "")
		var target := state if state != "ground" and has_clip(clip) else "ground"
		tree.set("parameters/state/transition_request", target)
	if old == "knocked":
		play_one_shot("get_up")


func _check_flag_edges(flags: int) -> void:
	var started := flags & ~_last_flags
	_last_flags = flags
	if started & FLAG_EMOTE:
		play_one_shot(clips.get("emote", "emote"))


## A supervisor that just ate a donut (one fewer carried: eating is the only way to lose one).
func _check_donut() -> void:
	var donuts := body.inventory.donuts
	if donuts < _last_donuts:
		play_one_shot("eat")
	_last_donuts = donuts


func _minigame_open() -> bool:
	var host := Session.current.client_only.get_node_or_null("MinigameHost") as MinigameHost \
		if Session.current != null else null
	return host != null and host.is_open()


# --- The tree ------------------------------------------------------------------------------------

func _clip_node(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_clip_node(clips["idle"]), 0.0, -1, &"idle")
	if clips.has("walk") and has_clip(clips["walk"]):
		loco.add_blend_point(_clip_node(clips["walk"]), _walk_speed, -1, &"walk")
	loco.add_blend_point(_clip_node(clips["run"]), _run_speed, -1, &"run")
	loco.min_space = 0.0
	loco.max_space = _run_speed * 1.5
	root.add_node("loco", loco)
	root.add_node("loco_rate", AnimationNodeTimeScale.new())
	root.connect_node("loco_rate", 0, "loco")
	var transition := AnimationNodeTransition.new()
	transition.xfade_time = 0.15
	transition.input_count = STATES.size()
	for i in STATES.size():
		transition.set_input_name(i, STATES[i])
	root.add_node("state", transition)
	root.connect_node("state", 0, "loco_rate")
	for i in range(1, STATES.size()):
		var clip: String = clips.get(STATES[i], "")
		var node_name := "clip_" + STATES[i]
		root.add_node(node_name, _clip_node(clip if has_clip(clip) else clips["idle"]))
		root.connect_node("state", i, node_name)
	var carry := AnimationNodeBlend2.new()
	root.add_node("carry", carry)
	root.connect_node("carry", 0, "state")
	var carry_clip: String = clips.get("carry", "")
	root.add_node("carry_clip", _clip_node(carry_clip if has_clip(carry_clip) else clips["idle"]))
	root.connect_node("carry", 1, "carry_clip")
	var skeleton := model.find_children("*", "Skeleton3D", true, false)
	if not skeleton.is_empty():
		carry.filter_enabled = true
		var skel_path := String(model.get_path_to(skeleton[0]))
		for bone: String in clips.get("arms", []):
			carry.set_filter_path(NodePath("%s:%s" % [skel_path, bone]), true)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.08
	action.fadeout_time = 0.15
	root.add_node("action", action)
	root.connect_node("action", 0, "carry")
	root.add_node("action_clip", _clip_node(clips["idle"]))
	root.connect_node("action", 1, "action_clip")
	root.connect_node("output", 0, "action")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = root
	anim_player.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
