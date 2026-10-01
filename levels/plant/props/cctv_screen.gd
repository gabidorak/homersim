class_name CctvScreen
extends Node3D
## A Control Room wall screen showing CCTV feeds, switching between `cameras` (numbers) every
## CYCLE_S. Client only. The feed is a small SubViewport (FEED_SIZE) that renders on demand, about
## 10 times a second and only while the screen is in view, so it costs little. Broken cameras show
## static. The quad faces this node's +Z.

const FEED_SIZE := Vector2i(256, 144)
const REFRESH_S := 0.1
const CYCLE_S := 5.0
const STATIC_SHADER: Shader = preload("res://shaders/tv_static.gdshader")

@export var cameras: Array[int] = []
@export var size := Vector2(2.4, 1.35)  ## m

var _viewport: SubViewport
var _camera: Camera3D
var _label: Label
var _static: ColorRect
var _notifier: VisibleOnScreenNotifier3D
var _since_refresh := 0.0
var _since_cycle := 0.0
var _index := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.size = FEED_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_viewport.add_child(_camera)
	_static = ColorRect.new()
	_static.size = Vector2(FEED_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = STATIC_SHADER
	mat.set_shader_parameter("cells", Vector2(128, 72))
	_static.material = mat
	_viewport.add_child(_static)
	_label = Label.new()
	_label.position = Vector2(6, 4)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_viewport.add_child(_label)

	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	screen.mesh = quad
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_texture = _viewport.get_texture()
	screen.material_override = screen_mat
	screen.position.z = 0.03
	add_child(screen)
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.12, size.y + 0.12, 0.05)
	frame.mesh = box
	add_child(frame)
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-size.x / 2, -size.y / 2, -0.05), Vector3(size.x, size.y, 0.1))
	add_child(_notifier)


func _process(delta: float) -> void:
	_since_cycle += delta
	if _since_cycle >= CYCLE_S:
		_since_cycle = 0.0
		_index += 1
	_since_refresh += delta
	if _since_refresh < REFRESH_S or not _notifier.is_on_screen():
		return
	_since_refresh = 0.0
	var cam := _current_camera()
	if cam == null:
		return
	_camera.global_transform = cam.lens.global_transform
	_static.visible = cam.broken
	_label.text = "CAM %d %s%s" % [cam.number, cam.label, " - NO SIGNAL" if cam.broken else ""]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _current_camera() -> CctvCamera:
	if cameras.is_empty():
		return null
	var wanted := cameras[_index % cameras.size()]
	for cam in CctvCamera.all_in(get_tree()):
		if cam.number == wanted:
			return cam
	return null
