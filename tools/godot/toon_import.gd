@tool
extends EditorScenePostImport
## Import script for every glTF scene (project.godot sets it as the scene importer's default, so new
## .glb files pick it up on their own). It gives imported models the cartoon look (ASSETS §1):
##   - the materials named by tools/blender/common.py become the shared toon materials
##     ("palette", "palette_emissive", "glass" → shaders/materials/*.tres), so every prop draws with
##     the same few materials;
##   - any other material becomes a toon ShaderMaterial keeping its albedo texture and colour (and
##     emission), with the outline as next_pass;
##   - animations listed in LOOPING (or named "*_loop") loop.
## Re-import a model (or delete .godot/imported) after changing this script.

const PALETTE: Material = preload("res://shaders/materials/toon_palette.tres")
const EMISSIVE: Material = preload("res://shaders/materials/toon_emissive.tres")
const GLASS: Material = preload("res://shaders/materials/toon_glass.tres")
const OUTLINE: Material = preload("res://shaders/materials/outline.tres")
const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const NAMED := {"palette": PALETTE, "palette_emissive": EMISSIVE, "glass": GLASS}
## Character clips that repeat (the rest play once). The second line: the intro's supervisor and
## hamster clips (client/intro/).
const LOOPING: Array[String] = ["idle", "walk", "run", "carry_idle", "carry", "interact", "gnaw", "stunned",
	"dangle", "caged", "crawl", "sit", "fall", "tablet",
	"carry_walk", "faceplant", "cheer", "cower", "ouch", "chase", "nibble", "beg", "shiver", "wash", "look_up"]

var _converted: Dictionary = {}  # source material -> toon material


func _post_import(scene: Node) -> Object:
	_converted.clear()
	_walk(scene)
	return scene


func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				mesh.surface_set_material(i, _toon(mesh.surface_get_material(i)))
	elif node is AnimationPlayer:
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			var base := String(anim_name).get_slice("/", 1) if String(anim_name).contains("/") else String(anim_name)
			if base in LOOPING or base.ends_with("_loop"):
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for child in node.get_children():
		_walk(child)


func _toon(source: Material) -> Material:
	if source == null:
		return PALETTE
	var key := source.resource_name.get_slice(".", 0)  # Godot may add ".001"-style suffixes
	if NAMED.has(key):
		return NAMED[key]
	if _converted.has(source):
		return _converted[source]
	var toon := ShaderMaterial.new()
	toon.shader = TOON_SHADER
	toon.resource_name = source.resource_name
	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		if base.albedo_texture != null:
			toon.set_shader_parameter("albedo_texture", base.albedo_texture)
		toon.set_shader_parameter("albedo", base.albedo_color)
		if base.emission_enabled:
			toon.set_shader_parameter("emission", base.emission)
			toon.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
			if base.emission_texture != null:
				toon.set_shader_parameter("emission_texture", base.emission_texture)
	toon.next_pass = OUTLINE
	_converted[source] = toon
	return toon
