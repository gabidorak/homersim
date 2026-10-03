class_name ScreenInk
extends MeshInstance3D
## The full-screen ink lines (shaders/screen_ink.gdshader): a quad that the shader stretches over the
## whole screen, so every camera of its 3D world draws them. Config adds one next to each
## WorldEnvironment. Shown only while Config.outline_style() is FULL_SCREEN; the per-object hull
## (shaders/outline.gdshader) is off then.

const SHADER: Shader = preload("res://shaders/screen_ink.gdshader")


func _init() -> void:
	name = "ScreenInk"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = Material.RENDER_PRIORITY_MAX  # after glass and the other see-through things
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16384.0  # placed by the shader, wherever the camera looks: never culled
	ignore_occlusion_culling = true


func _ready() -> void:
	Config.changed.connect(func(key: String) -> void:
		if key == "outlines":
			_update())
	_update()


func _update() -> void:
	visible = Config.outline_style() == Config.Outlines.FULL_SCREEN
