// Toon material for models (shaders/toon_model.gdshaderinc). Pair it with outline.gdshader as
// next_pass. Shared instances live in shaders/materials/ (toon_palette, toon_palette_flat); the glTF
// import script (tools/godot/toon_import.gd) puts them on every imported model. Parts whose colour
// changes at runtime use toon_tintable.gdshader instead (toon_emissive.tres: lamps, screens).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_model.gdshaderinc"
