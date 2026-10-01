// Revealed players (cheese lure, radiation): a coloured inverted-hull silhouette drawn on top of
// everything, so the enemy team sees the body through walls. Used as material_overlay on the
// body's meshes, only on clients that should see it (see Player._update_reveal).
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.1, 0.55);
uniform float grow = 0.03;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.75 + 0.25 * sin(TIME * 6.0));
}
