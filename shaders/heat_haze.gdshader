// Heat shimmering over a hot toaster (client/outro/outro_fx.gd): a camera-facing quad that bends what
// is behind it in slow rising waves, strongest in its middle and fading to nothing at its edges.
// `strength` (0..1) and `phase` (the clock, s) are set per instance, so it's the same at the same time.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
instance uniform float strength = 0.0;
instance uniform float phase = 0.0;

void vertex() {
	// Face the camera, keep upright.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], vec4(0.0, 1.0, 0.0, 0.0), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x) * smoothstep(1.0, 0.65, UV.y) * smoothstep(0.0, 0.25, UV.y);
	float wave = sin(UV.y * 38.0 + phase * 9.0) * 0.6 + sin(UV.y * 17.0 - phase * 5.0 + UV.x * 6.0) * 0.4;
	vec2 offset = vec2(wave * 0.0035, wave * 0.0012) * strength * edge;
	ALBEDO = textureLod(screen_texture, SCREEN_UV + offset, 0.0).rgb;
	ALPHA = edge * strength;
}
