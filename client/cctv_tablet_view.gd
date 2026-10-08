class_name CctvTabletView
extends SubViewport
## Client: what the supervisor's CCTV tablet shows (FirstPersonRig owns it and puts its texture on
## the TabletScreen of the fp_arms model; CctvView picks the camera). It renders the main world from
## the selected CCTV camera, only while the tablet is in hand, with the title, the key hint and static
## and "NO SIGNAL" for a broken camera drawn over it. The arms themselves are on LAYER, which its
## camera leaves out, so the screen never draws itself.

const FEED_SIZE := Vector2i(960, 704)  ## close to the screen's aspect
const LAYER := 1 << 19  ## render layer 20: the first-person arms and the tablet

var _camera: Camera3D
var _static: ColorRect
var _title: Label
var _no_signal: Label
var _hint: Label


func _ready() -> void:
	size = FEED_SIZE
	audio_listener_enable_3d = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.name = "TabletCamera"
	_camera.fov = 70.0
	_camera.cull_mask &= ~LAYER
	_camera.current = true  # (this viewport's own camera: the main view keeps the player's)
	add_child(_camera)
	_static = ColorRect.new()
	_static.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/tv_static.gdshader")
	_static.material = mat
	add_child(_static)
	_title = _label(40, Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_LEFT)
	_title.offset_left = 28
	_title.offset_top = 18
	_title.offset_bottom = 78
	_no_signal = _label(84, Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER)
	_no_signal.text = tr("NO SIGNAL")
	_no_signal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint = _label(30, Control.PRESET_BOTTOM_WIDE, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.offset_top = -64
	_hint.offset_bottom = -18


func _label(font_size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = align
	label.clip_text = true
	label.set_anchors_and_offsets_preset(preset)
	add_child(label)
	return label


## Render (while the tablet is in hand) or not.
func set_live(live: bool) -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED


## Show `cam` on the screen; `hint` is the key help along its bottom edge.
func show_feed(cam: CctvCamera, hint: String) -> void:
	_camera.global_transform = cam.lens.global_transform
	_title.text = "%s  ·  %s%s" % [tr("CAM %d") % cam.number, tr(cam.label), "  ·  " + tr("BROKEN") if cam.broken else ""]
	_static.visible = cam.broken
	_no_signal.visible = cam.broken
	_hint.text = hint
