// The toon model shader with per-instance `tint` and `glow` (see toon_model.gdshaderinc): used by
// toon_emissive.tres, so lamps and screens can change colour and switch off without a material copy.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#define TINTABLE
#include "res://shaders/toon_model.gdshaderinc"
