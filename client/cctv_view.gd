class_name CctvView
extends CanvasLayer
## Client: what a supervisor sees of the CCTV cameras, at the chair (CctvConsole) or on the tablet
## (Player.using_tablet). Q / E: previous / next camera; a broken one shows static and "NO SIGNAL".
##   Chair:  while our peer is the chair's synced `user`, the whole screen shows the camera (Space
##           stands up). No extra viewport: our main view simply switches to a camera placed at the
##           lens, so nothing renders for anyone else. That camera node only exists while we watch:
##           Godot makes a leftover camera current on its own when the current one goes away.
##   Tablet: C takes it out (the server agrees) and puts it away. Our FirstPersonRig plays the arms'
##           tablet clips (the left hand brings it up) and its screen shows the rig's tablet_feed;
##           we keep walking and looking around, but our hands are full (no broom, items or E).

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
	_no_signal.text = tr("NO SIGNAL")
	_no_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_signal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_no_signal.grow_vertical = Control.GROW_DIRECTION_BOTH
	var hint := _label(20, Control.PRESET_CENTER_BOTTOM, Vector2(0, -40))
	hint.text = tr("%s / %s: previous / next camera  ·  %s: stand up  ·  you can still be bitten!") % [
		Keys.label(&"next_trap"), Keys.label(&"interact"), Keys.label(&"jump")]
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


## Our body, or null.
func _body() -> Player:
	var session := Session.current
	return session.get_body(session.local_peer_id) if session != null else null


func _process(_delta: float) -> void:
	var body := _body()
	var cameras := CctvCamera.all_in(get_tree())
	var seated := body != null and body.seated_console() != null and not cameras.is_empty()
	var tablet := body != null and body.using_tablet and not cameras.is_empty()
	if seated != (_camera != null):
		_set_seated(seated)
	var rig := body.rig as FirstPersonRig if body != null else null
	if rig != null and rig.tablet_feed != null:
		if tablet and not rig.tablet_out():
			Log.info("cctv", "watching the cameras on the tablet")
		rig.set_tablet(tablet)
	if not seated and not tablet:
		return
	selected = posmod(selected, cameras.size())
	var cam := cameras[selected]
	if tablet:
		if rig != null and rig.tablet_feed != null:
			rig.tablet_feed.show_feed(cam, tr("%s / %s: previous / next camera  ·  %s: put the tablet away") % [
				Keys.label(&"next_trap"), Keys.label(&"interact"), Keys.label(&"cctv_tablet")])
		return
	_camera.global_transform = cam.lens.global_transform
	_title.text = "%s  ·  %s%s" % [tr("CAM %d") % cam.number, tr(cam.label), "  ·  " + tr("BROKEN") if cam.broken else ""]
	_static.visible = cam.broken
	_no_signal.visible = cam.broken


func _set_seated(seated: bool) -> void:
	_root.visible = seated
	if seated:
		_camera = Camera3D.new()
		_camera.name = "CctvViewCamera"
		_camera.fov = 70.0
		add_child(_camera)
		_camera.make_current()
		Log.info("cctv", "watching the cameras at the chair")
		return
	var body := _body()
	if body != null and body.rig.camera != null:
		body.rig.camera.make_current()
	_camera.queue_free()
	_camera = null


func _unhandled_input(event: InputEvent) -> void:
	var body := _body()
	if body == null or not body.watching_cctv():
		# C takes the tablet out (the server checks the rest: playing, not stunned, no rat in hand…).
		if event.is_action_pressed("cctv_tablet") and body != null and body.role == Role.Kind.SUPERVISOR \
				and PlayerInput.has_control() and body.tablet_blocker() == "":
			body.request_tablet.rpc_id(1, true)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next_trap"):
		selected -= 1
	elif event.is_action_pressed("interact"):
		selected += 1
	elif body.using_tablet and event.is_action_pressed("cctv_tablet"):
		body.request_tablet.rpc_id(1, false)
	elif body.seated_console() != null and event.is_action_pressed("jump"):
		body.seated_console().request_stand_up.rpc_id(1)
	else:
		return  # (on the tablet, Space still jumps)
	get_viewport().set_input_as_handled()
