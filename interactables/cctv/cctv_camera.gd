class_name CctvCamera
extends Interactable
## A CCTV camera (GDD §4.5, §5.2). This node is the camera's junction box at the foot of a wall,
## the part players reach with E; the lens sits `lens_height` above it and looks into the room
## (this node's +Z), turned by `lens_yaw_deg` and tilted down by `lens_pitch_deg`.
## Rats hold E to break it (2 s), supervisors hold E to repair it (3 s). `broken` is synced; the
## CCTV chair and the Control Room wall screens show static instead of a broken camera's feed.
## Cameras are numbered 1..8; the CCTV views list them in that order.

const CAMERA_GROUP := "cctv_cameras"

@export var number := 1
@export var label := "Camera"
@export var lens_height := 3.0  ## m above the junction box
@export var lens_pitch_deg := 25.0  ## looking down
@export var lens_yaw_deg := 0.0  ## turned from straight into the room (+ = toward local +X)

# --- Replicated by the Sync child --------------------------------------------------------
var broken := false

var lens: Marker3D  ## where the view is from (its -Z looks along the view)
var tuning: PvpTuning = PvpTuning.load_default()
var _head: Node3D  # the camera head (models: cctv_head, cctv_head_broken), under the lens
var _head_broken: Node3D
var _lamp: Node3D
var _shown_broken := false


func _init() -> void:
	allowed_roles = [Role.Kind.RAT, Role.Kind.SUPERVISOR]
	prompt = "Camera"
	reach = 1.4


func _enter_tree() -> void:
	super()
	add_to_group(CAMERA_GROUP)
	add_to_group(MatchManager.RESET_GROUP)


func _ready() -> void:
	super()
	lens = Marker3D.new()
	lens.name = "Lens"
	lens.position = Vector3(0, lens_height, 0.15)
	lens.rotation = Vector3(-deg_to_rad(lens_pitch_deg), PI + deg_to_rad(lens_yaw_deg), 0.0)
	add_child(lens)
	# The conduit from the box up to the head, and the head itself (models face +Z, the lens -Z).
	Art.add(self, "cctv_conduit", Transform3D(Basis.from_scale(Vector3(1, lens_height - 0.25, 1)),
		Vector3(0, 0.25, -0.13)))
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 0.1))
	_head = Art.add(lens, "cctv_head", turn)
	_head_broken = Art.add(lens, "cctv_head_broken", turn)
	if _head_broken != null:
		_head_broken.visible = false
	_lamp = Art.part(_head, "Lamp")


## The cameras of the level, in number order.
static func all_in(tree: SceneTree) -> Array[CctvCamera]:
	var out: Array[CctvCamera] = []
	for node in tree.get_nodes_in_group(CAMERA_GROUP):
		out.append(node as CctvCamera)
	out.sort_custom(func(a: CctvCamera, b: CctvCamera) -> bool: return a.number < b.number)
	return out


func _synced_properties() -> Array[String]:
	var list := super()
	list.append("broken")
	return list


## Server (MatchManager, at every match start): working again.
func reset_for_match() -> void:
	broken = false


func hold_duration() -> float:
	return tuning.cctv_repair_hold_s if broken else tuning.cctv_break_hold_s


func is_available(player: Player) -> bool:
	return broken if player.role == Role.Kind.SUPERVISOR else not broken


func prompt_for(player: Player) -> String:
	if player.role == Role.Kind.SUPERVISOR:
		return "Repair camera %d" % number if broken else "Camera %d works" % number
	return "Camera %d is broken" % number if broken else "Break camera %d" % number


func _complete(player: Player) -> void:
	broken = player.role == Role.Kind.RAT
	Log.info("cctv", "%s %s camera %d (%s)" % [player.display_name, "broke" if broken else "repaired", number, label])
	super(player)


# Cosmetic: a working camera blinks its red record lamp; a broken one hangs smashed (with a crash of
# glass and sparks when it breaks).
func _process(_delta: float) -> void:
	if _lamp != null:
		Art.set_glow(_lamp, 2.0 if Time.get_ticks_msec() % 1000 < 500 else 0.2)
	if broken == _shown_broken or _head == null:
		return
	_shown_broken = broken
	_head.visible = not broken
	if _head_broken != null:
		_head_broken.visible = broken
	if broken and Session.current != null and Session.current.match_manager.state == MatchManager.State.PLAYING:
		Sfx.play_at(self, "glass_break", lens.global_position)
		Vfx.sparks(self, lens.global_position, 18)
