// See-through glass (windows, gauges, the CCTV booth): a pale tint, brighter at grazing angles,
// toon-lit. No outline.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert, specular_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform vec4 glass_color : source_color = vec4(0.75, 0.89, 0.95, 0.15);
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = glass_color.rgb;
	ALPHA = mix(glass_color.a, edge_alpha, fresnel);
	ROUGHNESS = 1.0;
}
