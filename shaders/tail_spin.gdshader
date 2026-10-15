// A rat's tail spin (Vfx.tail_spin): cartoon speed streaks drawn on an open cylinder (or cone)
// around the rat. Each of `streaks` arcs has a crisp leading edge and a tail that fades out behind
// it; the node spins, so the streaks whirl. `fade` (per instance) fades the whole whirl in and out.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.98, 0.92, 0.7);
uniform float streaks = 4.0;
uniform float sharpness = 6.0;  // higher = shorter tails
uniform float edge_soft = 0.4;  // how much of the band's top and bottom fades out
instance uniform float fade = 1.0;

void fragment() {
	float along = fract(UV.x * streaks);  // 0 at a streak's end, 1 at its leading edge
	float streak = pow(along, sharpness);
	float band = smoothstep(0.0, edge_soft, UV.y) * smoothstep(1.0, 1.0 - edge_soft, UV.y);
	ALBEDO = color.rgb;
	ALPHA = clamp(streak * band * fade * color.a, 0.0, 1.0);
}
