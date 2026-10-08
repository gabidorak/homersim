class_name IntroActor
extends Node3D
## A character of the intro (client/intro/intro.gd): a generated model (supervisor, hamster, rat)
## driven by an AnimationTree built here:
##
##   base   Transition between every clip of the model: play() crossfades to a full-body clip
##   layer  Blend2 filtered to the upper body (supervisors: torso, arms, head): play_upper() lays a
##          clip over the base one (eating or cheering while seated), "" lifts it
##   speed  TimeScale: the playback rate of both
##
## The node itself is moved by the intro's tweens (the clips animate the body in place, models face
## +Z). Client only: nothing here runs in a headless process (the intro never starts there).

const XFADE := 0.18
## Bones the upper-body layer drives, per model (others have none).
const UPPER_BONES := {"supervisor": ["torso", "arm-left", "arm-right", "head"]}

var model_name := ""
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var tree: AnimationTree
var clip := ""  ## the base clip playing
var upper_clip := ""

var _layer_tween: Tween


## A new actor showing `p_model_name` (assets/generated/<name>.glb), playing `start_clip`.
static func create(parent: Node, p_model_name: String, pos: Vector3, yaw: float, start_clip := "idle") -> IntroActor:
	var actor := IntroActor.new()
	actor.name = p_model_name.capitalize().replace(" ", "")
	actor.model_name = p_model_name
	actor.position = pos
	actor.rotation.y = yaw
	parent.add_child(actor)
	actor.play(start_clip, 0.0)
	return actor


func _enter_tree() -> void:
	if model != null:
		return
	model = Art.add(self, model_name)
	if model == null:
		push_warning("IntroActor: model '%s' is missing (run tools/build_assets.sh)" % model_name)
		return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	var players := model.find_children("*", "AnimationPlayer", true, false)
	anim = players[0] as AnimationPlayer if not players.is_empty() else null
	if anim != null:
		_build_tree()


func has_clip(name_: String) -> bool:
	return anim != null and anim.has_animation(name_)


## Crossfades the whole body to `name_` (a clip that is already playing keeps going, unless
## `restart`). `speed` is the playback rate from now on.
func play(name_: String, xfade := XFADE, speed := 1.0, restart := false) -> void:
	if tree == null or not has_clip(name_):
		return
	tree.set(&"parameters/speed/scale", speed)
	if name_ == clip and not restart:
		return
	clip = name_
	((tree.tree_root as AnimationNodeBlendTree).get_node(&"base") as AnimationNodeTransition).xfade_time = xfade
	tree.set(&"parameters/base/transition_request", name_)


## Lays `name_` over the upper body ("" fades the layer out).
func play_upper(name_: String, fade := 0.25) -> void:
	if tree == null or (name_ != "" and not has_clip(name_)):
		return
	if name_ != "":
		if name_ != upper_clip:
			((tree.tree_root as AnimationNodeBlendTree).get_node(&"upper") as AnimationNodeTransition).xfade_time = \
				fade if upper_clip != "" else 0.0
			tree.set(&"parameters/upper/transition_request", name_)
	upper_clip = name_
	if _layer_tween != null:
		_layer_tween.kill()
	_layer_tween = create_tween()
	_layer_tween.tween_property(tree, ^"parameters/layer/blend_amount", 1.0 if name_ != "" else 0.0, fade)


func set_speed(speed: float) -> void:
	if tree != null:
		tree.set(&"parameters/speed/scale", speed)


## Hangs `node` on `bone` (it follows the animated bone), at `xform` in the bone's space.
## (Without that bone, it hangs on the actor itself.)
func attach(node: Node3D, bone: String, xform := Transform3D.IDENTITY) -> BoneAttachment3D:
	var hold: BoneAttachment3D = null
	if skeleton != null and skeleton.find_bone(bone) >= 0:
		hold = skeleton.get_node_or_null(NodePath(bone)) as BoneAttachment3D
		if hold == null:
			hold = BoneAttachment3D.new()
			hold.name = bone
			hold.bone_name = bone
			skeleton.add_child(hold)
	var parent: Node = hold if hold != null else self
	if node.get_parent() != null:
		node.reparent(parent, false)
	else:
		parent.add_child(node)
	node.transform = xform
	return hold


## Where a bone is right now (world space), e.g. to aim an effect at a head.
func bone_position(bone: String, offset := Vector3.ZERO) -> Vector3:
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return global_position + offset
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
	return pose * offset


## Moves to `target` in `duration` s facing the way it goes (a tween the caller may chain on).
func move_to(target: Vector3, duration: float, face := true, trans := Tween.TRANS_LINEAR,
		ease_ := Tween.EASE_IN_OUT) -> Tween:
	if face:
		face_towards(target, minf(0.2, duration))
	var tween := create_tween()
	tween.tween_property(self, ^"position", target, duration).set_trans(trans).set_ease(ease_)
	return tween


## Turns (about Y) to face `target` in `duration` s.
func face_towards(target: Vector3, duration := 0.2) -> void:
	var flat := target - position
	flat.y = 0.0
	if flat.length() < 0.001:
		return
	turn_to(atan2(flat.x, flat.z), duration)


## Turns to the yaw `yaw` (radians, 0 = facing +Z) the short way round.
func turn_to(yaw: float, duration := 0.2) -> void:
	var target := rotation.y + wrapf(yaw - rotation.y, -PI, PI)
	if duration <= 0.0:
		rotation.y = target
		return
	create_tween().tween_property(self, ^"rotation:y", target, duration).set_trans(Tween.TRANS_SINE)


## Hops along an arc to `target` (`height` m above the straight line) in `duration` s.
func hop_to(target: Vector3, height: float, duration: float) -> Tween:
	face_towards(target, minf(0.12, duration))
	var from := position
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		position = from.lerp(target, t) + Vector3.UP * height * 4.0 * t * (1.0 - t), 0.0, 1.0, duration)
	return tween


func _build_tree() -> void:
	var clips := anim.get_animation_list()
	var root := AnimationNodeBlendTree.new()
	var base := _transition(clips)
	root.add_node(&"base", base)
	var upper := _transition(clips)
	root.add_node(&"upper", upper)
	for c in clips:
		root.add_node(StringName("b_" + c), _clip_node(c))
		root.connect_node(&"base", clips.find(c), StringName("b_" + c))
		root.add_node(StringName("u_" + c), _clip_node(c))
		root.connect_node(&"upper", clips.find(c), StringName("u_" + c))
	var layer := AnimationNodeBlend2.new()
	root.add_node(&"layer", layer)
	root.connect_node(&"layer", 0, &"base")
	root.connect_node(&"layer", 1, &"upper")
	if skeleton != null and UPPER_BONES.has(model_name):
		layer.filter_enabled = true
		var skel_path := String(model.get_path_to(skeleton))
		for bone: String in UPPER_BONES[model_name]:
			layer.set_filter_path(NodePath("%s:%s" % [skel_path, bone]), true)
	root.add_node(&"speed", AnimationNodeTimeScale.new())
	root.connect_node(&"speed", 0, &"layer")
	root.connect_node(&"output", 0, &"speed")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = root
	anim.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.anim_player = tree.get_path_to(anim)
	tree.set(&"parameters/layer/blend_amount", 0.0)
	tree.set(&"parameters/speed/scale", 1.0)
	tree.active = true


static func _transition(clips: PackedStringArray) -> AnimationNodeTransition:
	var node := AnimationNodeTransition.new()
	node.xfade_time = XFADE
	node.allow_transition_to_self = true
	node.input_count = clips.size()
	for i in clips.size():
		node.set_input_name(i, clips[i])
	return node


static func _clip_node(name_: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name_
	return node
