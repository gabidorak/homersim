// TV static for broken CCTV feeds (the CCTV view and the Control Room wall screens).
shader_type canvas_item;

uniform vec2 cells = vec2(240.0, 135.0);
uniform float alpha = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * cells);
	float frame = floor(TIME * 20.0);
	float noise = hash(cell + vec2(frame * 1.37, frame * 2.11));
	float band = 0.8 + 0.2 * sin(UV.y * 30.0 - TIME * 8.0);
	COLOR = vec4(vec3(noise * band), alpha);
}
