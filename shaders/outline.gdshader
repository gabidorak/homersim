// Inverted-hull outline (ASSETS §1): the mesh drawn again, grown along its normals, front faces
// culled, flat black. Set as `next_pass` of a toon material.
//
// Hard-edged low-poly meshes have split normals, which would tear the hull open at every corner.
// Models exported by tools/blender/common.py therefore carry smoothed normals in their vertex
// colour (rgb = n * 0.5 + 0.5, alpha = 0 as the marker); meshes without them use NORMAL.
// The width is in metres at `reference_distance` and grows with distance up to `max_scale`, so the
// line stays about as thick on screen near and far.
// Drawn only while the global `outline_hull_enabled` is on (Config's "outlines" setting); the
// full-screen lines (screen_ink.gdshader) replace it otherwise.
shader_type spatial;
render_mode unshaded, cull_front, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.07, 0.06, 0.09, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.012;
uniform float reference_distance = 2.0;
uniform float min_scale = 0.6;
uniform float max_scale = 6.0;
global uniform bool outline_hull_enabled;

void vertex() {
	vec3 n = NORMAL;
	if (COLOR.a < 0.01) {
		n = normalize(COLOR.rgb * 2.0 - 1.0);
	}
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
	float scale = clamp(-VERTEX.z / reference_distance, min_scale, max_scale);
	VERTEX += view_normal * outline_width * scale;
	NORMAL = view_normal;
	if (!outline_hull_enabled) {
		VERTEX = vec3(0.0);  // every triangle shrinks to a point: nothing is drawn
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
