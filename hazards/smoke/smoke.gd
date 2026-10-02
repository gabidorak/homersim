class_name Smoke
extends Hazard
## Thick smoke in the vent network and the Control Room (ventilation; GDD §6): visibility drops to
## about 6 m. Purely cosmetic, so the server never looks at it: it only syncs `active`.
## Each Smoke node is a FogVolume of `size` (centred on the node). Volumetric fog must be on in the
## environment for fog volumes to show: the first active smoke turns it on (with no global fog),
## the last one turns it off again. Volumetric fog needs the Forward+ renderer.

static var _active_count := 0

var _fog: FogVolume
var _shown := false


func _checks_overlaps() -> bool:
	return false


func _make_shape() -> CollisionShape3D:
	return null


func _ready() -> void:
	super()
	set_physics_process(false)


func _exit_tree() -> void:
	if _shown:
		_set_shown(false)


func _build_look() -> void:
	_fog = FogVolume.new()
	_fog.size = size
	_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var mat := FogMaterial.new()
	# Transmittance exp(-density * d) is about 5% at d = smoke_visibility.
	mat.density = 3.0 / maxf(tuning.smoke_visibility, 0.5)
	mat.albedo = Color(0.55, 0.55, 0.52)
	mat.edge_fade = 0.3
	_fog.material = mat
	_fog.visible = false
	add_child(_fog)


func _update_look(_live: bool, _delta: float) -> void:
	if active != _shown:
		_set_shown(active)


func _set_shown(value: bool) -> void:
	_shown = value
	_fog.visible = value
	_active_count += 1 if value else -1
	var env := get_world_3d().environment if is_inside_tree() else null
	if env == null:
		var world_env := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		env = world_env.environment if world_env != null else null
	if env != null:
		env.volumetric_fog_enabled = _active_count > 0
		env.volumetric_fog_density = 0.0
