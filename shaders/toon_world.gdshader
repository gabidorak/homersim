// Level surfaces (the baked POI shells): flat palette colours with patterns drawn from the world
// position, so walls, floors and ducts of any size need no UVs or textures, and every POI shares
// one shader with its own colours. Lighting comes from toon_light.gdshaderinc.
//
// pattern:
//   0 wall    vertical faces: a darker wainscot below `band_height`, panel seams every `cell.x` m and
//             a seam at `cell.y` m; ceilings: a panel grid; wall tops: the trim colour
//   1 floor   upward faces: tiles of `cell` m with seams and a faint checker; other faces: trim
//   2 metal   grating: dense cross lines on top, trim on the sides (catwalks, stairs)
//   3 stripes diagonal hazard stripes of `cell.x` m (base / trim colours)
//   4 duct    riveted sheet metal: seams every `cell.x` m along the run
//   5 plain   base colour only (outdoor ground, sludge)
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform int pattern : hint_range(0, 5) = 0;
uniform vec4 base_color : source_color = vec4(0.79, 0.72, 0.6, 1.0);
uniform vec4 trim_color : source_color = vec4(0.36, 0.42, 0.47, 1.0);
uniform vec4 line_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform float line_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 cell = vec2(2.0, 2.6);
uniform float line_width = 0.035;
uniform float band_height = 1.0;
uniform float checker_strength : hint_range(0.0, 0.3) = 0.05;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 1 on a grid line (cells of `size`), 0 elsewhere, anti-aliased.
float grid(vec2 p, vec2 size, float width) {
	vec2 f = abs(fract(p / size + 0.5) - 0.5) * size;
	float d = min(f.x, f.y);
	float aa = fwidth(d) + 1e-4;
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + aa, d);
}

float line_at(float v, float at, float width) {
	float d = abs(v - at);
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + fwidth(d) + 1e-4, d);
}

void fragment() {
	vec3 n = world_normal;
	vec3 p = world_pos;
	bool up = n.y > 0.6;
	bool down = n.y < -0.6;
	// The coordinate running along a vertical face.
	float along = abs(n.x) > abs(n.z) ? p.z : p.x;
	vec3 col = base_color.rgb;
	float lines = 0.0;
	if (pattern == 0) {
		if (up) {
			col = trim_color.rgb;
		} else if (down) {
			col = base_color.rgb * 0.8;
			lines = grid(p.xz, vec2(cell.x), line_width);
		} else {
			float h = p.y - floor(p.y / 50.0) * 50.0;  // tolerate raised floors (the roof block)
			col = h < band_height ? trim_color.rgb : base_color.rgb;
			lines = max(line_at(h, band_height, line_width * 1.5), line_at(h, cell.y, line_width));
			lines = max(lines, grid(vec2(along, 0.5), vec2(cell.x, 1000.0), line_width) * step(band_height, h));
			col *= mix(0.82, 1.0, smoothstep(0.0, 0.5, h));  // fake contact shadow at the floor
		}
	} else if (pattern == 1) {
		if (up) {
			vec2 c = floor(p.xz / cell);
			float checker = mod(c.x + c.y, 2.0);
			col = base_color.rgb * (1.0 - checker * checker_strength);
			lines = grid(p.xz, cell, line_width);
		} else {
			col = trim_color.rgb;
		}
	} else if (pattern == 2) {
		col = up ? base_color.rgb : trim_color.rgb;
		if (up) {
			lines = grid(p.xz, vec2(cell.x), line_width) * 0.7;
		}
	} else if (pattern == 3) {
		float s = (up || down) ? p.x + p.z : along + p.y;
		col = fract(s / cell.x) < 0.5 ? base_color.rgb : trim_color.rgb;
	} else if (pattern == 4) {
		col = base_color.rgb;
		float run = up || down ? max(abs(p.x), abs(p.z)) : along;
		lines = grid(vec2(run, 0.5), vec2(cell.x, 1000.0), line_width);
		if (down) {
			col *= 0.8;
		}
	}
	ALBEDO = mix(col, line_color.rgb, lines * line_strength);
	ROUGHNESS = 1.0;
	EMISSION = emission.rgb * emission_energy;
}
