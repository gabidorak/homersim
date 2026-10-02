// The body of the model toon shaders (toon.gdshader, toon_tintable.gdshader): palette (or any
// albedo) texture times a colour, stepped lighting from toon_light.gdshaderinc, an emissive slot.
// With TINTABLE defined, two per-instance uniforms (MeshInstance3D.set_instance_shader_parameter):
// `tint` multiplies the colour and the glow, `glow` scales the emission (a lamp switched off = 0).
// Only the few parts that change colour use them: every instance of a shader with instance
// uniforms takes slots in a global buffer (4096 at most on the Compatibility renderer).

#include "res://shaders/toon_light.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D emission_texture : source_color, filter_nearest_mipmap, hint_default_black;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;
#ifdef TINTABLE
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float glow = 1.0;
#endif

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo;
	vec3 glow_color = texture(emission_texture, UV).rgb + emission.rgb;
#ifdef TINTABLE
	base *= tint;
	glow_color *= tint.rgb * glow;
#endif
	ALBEDO = base.rgb;
	ROUGHNESS = 1.0;
	EMISSION = glow_color * emission_energy;
}
