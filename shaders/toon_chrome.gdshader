// Cartoon chrome (the outro's 1950s toaster, client/outro/): instead of a real reflection, three
// painted bands that follow the view: a bright sky band on top, a dark horizon line, a warm floor
// band below, with a hard white glint. Toon lighting on top (toon_light.gdshaderinc), so lamps still
// colour it; `sky` and `floor` let a scene tint the bands (warm at sunrise, blue at night).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform vec4 sky : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec4 horizon : source_color = vec4(0.16, 0.18, 0.24, 1.0);
uniform vec4 floor_color : source_color = vec4(0.78, 0.66, 0.52, 1.0);
uniform float glint = 0.9;  // the white glint's strength (its only light of its own)
uniform float reflect_mix = 0.88;  // how much of the colour is the painted reflection (vs lit grey)

varying vec3 view_normal;

void vertex() {
	view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(view_normal);
	// The reflected direction's height in view space picks the band.
	vec3 r = reflect(normalize(-VIEW), n);
	float h = r.y;
	vec3 band = mix(floor_color.rgb, horizon.rgb, smoothstep(-0.5, -0.08, h));
	band = mix(band, sky.rgb, smoothstep(-0.02, 0.06, h));
	float spot = smoothstep(0.9, 0.94, dot(r, normalize(vec3(-0.35, 0.75, 0.55))));
	ALBEDO = mix(vec3(0.7, 0.72, 0.76), band, reflect_mix);
	EMISSION = vec3(spot) * glint;
	ROUGHNESS = 1.0;
}
