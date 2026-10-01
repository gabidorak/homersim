class_name CctvView
extends CanvasLayer
## Client: the view of a supervisor sitting at the CCTV chair (CctvConsole). While our peer is the
## chair's synced `user`, the screen shows the selected camera (Q / E: previous / next; Space: stand
## up), with static and "NO SIGNAL" for a broken one. No extra viewport: our main view simply
## switches to a camera placed at the lens, so nothing renders for anyone else.
## The camera node only exists while we watch: Godot makes a leftover camera current on its own
## when the current one goes away.

const STATIC_SHADER: Shader = preload("res://shaders/tv_static.gdshader")

var selected := 0  ## index into CctvCamera.all_in()

var _camera: Camera3D
var _root: Control
var _title: Label
var _no_signal: Label
var _static: ColorRect


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_static = ColorRect.new()
	_static.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = STATIC_SHADER
	_static.material = mat
	_root.add_child(_static)
	_title = _label(28, Control.PRESET_TOP_LEFT, Vector2(24, 16))
	_no_signal = _label(64, Control.PRESET_CENTER, Vector2.ZERO)
	_no_signal.text = "NO SIGNAL"
	_no_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_signal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_no_signal.grow_vertical = Control.GROW_DIRECTION_BOTH
	var hint := _label(20, Control.PRESET_CENTER_BOTTOM, Vector2(0, -40))
	hint.text = "Q / E: previous / next camera  ·  Space: stand up  ·  you can still be bitten!"
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _label(font_size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.set_anchors_and_offsets_preset(preset)
	label.position += offset
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


## The console we sit at, or null.
func _console() -> CctvConsole:
	var session := Session.current
	if session.get_body(session.local_peer_id) == null:
		return null
	return CctvConsole.of_peer(get_tree(), session.local_peer_id)


func _process(_delta: float) -> void:
	var console := _console()
	var cameras := CctvCamera.all_in(get_tree())
	var active := console != null and not cameras.is_empty()
	if active != (_camera != null):
		_set_active(active)
	if not active:
		return
	selected = posmod(selected, cameras.size())
	var cam := cameras[selected]
	_camera.global_transform = cam.lens.global_transform
	_title.text = "CAM %d  ·  %s%s" % [cam.number, cam.label, "  ·  BROKEN" if cam.broken else ""]
	_static.visible = cam.broken
	_no_signal.visible = cam.broken


func _set_active(active: bool) -> void:
	_root.visible = active
	if active:
		_camera = Camera3D.new()
		_camera.name = "CctvViewCamera"
		_camera.fov = 70.0
		add_child(_camera)
		_camera.make_current()
		Log.info("cctv", "watching the cameras")
		return
	var body := Session.current.get_body(Session.current.local_peer_id)
	if body != null and body.rig.camera != null:
		body.rig.camera.make_current()
	_camera.queue_free()
	_camera = null


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event.is_action_pressed("next_trap"):
		selected -= 1
	elif event.is_action_pressed("interact"):
		selected += 1
	elif event.is_action_pressed("jump"):
		var console := _console()
		if console != null:
			console.request_stand_up.rpc_id(1)
	else:
		return
	get_viewport().set_input_as_handled()
