class_name StatusBoard
extends Node3D
## The plant status board on the Control Room wall (GDD §4.5). Client only: a StatusBoardPanel is
## drawn into a SubViewport that textures a quad facing this node's +Z, redrawn REFRESH_S apart
## and only while the board is in view.

const PANEL_SIZE := Vector2i(640, 360)
const REFRESH_S := 0.2

@export var size := Vector2(4.8, 2.7)  ## m

var _viewport: SubViewport
var _panel: StatusBoardPanel
var _notifier: VisibleOnScreenNotifier3D
var _since_refresh := INF


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.size = PANEL_SIZE
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_panel = StatusBoardPanel.new()
	_panel.size = Vector2(PANEL_SIZE)
	_viewport.add_child(_panel)
	var board := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	board.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	board.material_override = mat
	board.position.z = 0.03
	add_child(board)
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.15, size.y + 0.15, 0.05)
	frame.mesh = box
	add_child(frame)
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-size.x / 2, -size.y / 2, -0.05), Vector3(size.x, size.y, 0.1))
	add_child(_notifier)


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH_S or not _notifier.is_on_screen():
		return
	_since_refresh = 0.0
	_panel.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
