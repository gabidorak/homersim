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
var _lens_material := StandardMaterial3D.new()
var _lens_mesh: MeshInstance3D


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
	_lens_mesh = MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.22, 0.18, 0.4)
	_lens_mesh.mesh = body
	_lens_mesh.material_override = _lens_material
	lens.add_child(_lens_mesh)


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


# Cosmetic: a working camera is dark with a red light, a broken one droops and turns grey.
func _process(delta: float) -> void:
	if _lens_mesh == null:
		return
	var droop := 0.7 if broken else 0.0
	_lens_mesh.rotation.x = lerpf(_lens_mesh.rotation.x, -droop, 1.0 - exp(-6.0 * delta))
	_lens_material.albedo_color = Color(0.45, 0.45, 0.45) if broken else Color(0.12, 0.12, 0.14)
	_lens_material.emission_enabled = not broken
	_lens_material.emission = Color(1, 0.1, 0.1) * (0.6 if Time.get_ticks_msec() % 1000 < 500 else 0.1)
