// Full-screen ink lines (ASSETS §1), Forward+ only: drawn by a screen-covering quad (common/screen_ink.gd)
// from the depth and normal buffers, so every object gets the same lines, outlined or not.
// A pixel is inked when its neighbour `line_width` pixels away lies across an edge:
//  - a silhouette: the neighbour is farther away and the two pixels are not on one plane: the
//    neighbour is well behind this pixel's surface, or this pixel well in front of the neighbour's
//    (the second catches the edges of round things, whose surface turns away from the camera there).
//    The sky is always behind. Measuring against planes rather than comparing depths keeps floors and
//    walls seen at a grazing angle clean.
//  - a crease: the surface turns by more than `crease_angle` (box edges, a pillar against a wall, a
//    crate on the floor). Only the nearer pixel of the two inks it (at about the same distance, the
//    one left of or below the crease, so the line doesn't break into dashes), so creases are as thin
//    as silhouettes.
// Lines keep the same width in pixels at any distance (scaled with the window height) and fade out
// far away, where they would only be noise.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 line_color : source_color = vec4(0.07, 0.06, 0.09, 1.0);  // the ink of outline.gdshader
uniform float line_width : hint_range(0.5, 6.0) = 2.5;  // pixels at 720p
uniform float depth_threshold : hint_range(0.001, 0.2) = 0.03;  // a gap this fraction of the distance is a silhouette
uniform float crease_angle : hint_range(5.0, 90.0) = 50.0;  // degrees: below it, bevels and faceted curves stay clean
uniform float fade_start = 60.0;  // metres
uniform float fade_end = 120.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);  // the 2 × 2 quad covers the screen, at the near plane (reversed Z)
}

vec3 view_position(vec2 uv, float depth, mat4 inv_projection) {
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return p.xyz / p.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_roughness_texture, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 pos = view_position(SCREEN_UV, depth, INV_PROJECTION_MATRIX);
	vec3 normal = view_normal(SCREEN_UV);
	float dist = -pos.z;
	vec2 step_uv = vec2(line_width * VIEWPORT_SIZE.y / 720.0) / VIEWPORT_SIZE;
	float crease_cos = cos(radians(crease_angle));
	vec2 offsets[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	float ink = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offsets[i] * step_uv;
		float other_depth = texture(depth_texture, uv).r;
		vec3 other = view_position(uv, other_depth, INV_PROJECTION_MATRIX);
		vec3 other_normal = view_normal(uv);
		float gap = dot(other - pos, normal) / dist;  // > 0: in front of this surface's plane, < 0: behind
		float other_gap = dot(pos - other, other_normal) / dist;  // the same, seen from the neighbour
		float closer_by = (-other.z - dist) / dist;
		float nearer = closer_by > 0.01 ? 1.0 : (closer_by < -0.01 ? 0.0 : float(i % 2 == 0));
		float behind = max(-gap, other_gap * nearer);
		float silhouette = other_depth <= 0.0 ? 1.0 : smoothstep(depth_threshold, depth_threshold * 2.0, behind);
		float turn = smoothstep(crease_cos + 0.05, crease_cos - 0.05, dot(normal, other_normal));
		float touching = 1.0 - smoothstep(depth_threshold, depth_threshold * 2.0, abs(gap));
		ink = max(ink, max(silhouette, turn * touching * nearer));
	}
	ink *= 1.0 - smoothstep(fade_start, fade_end, dist);
	if (depth <= 0.0) {
		ink = 0.0;  // the sky
	}
	ALBEDO = line_color.rgb;
	ALPHA = ink * line_color.a;
}
