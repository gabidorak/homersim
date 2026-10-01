// Screen-edge tint for the plant alarm (HUD). `strength` 0 = invisible.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.55, 1.05, max(d.x, d.y));
	COLOR = vec4(tint.rgb, edge * strength * tint.a);
}
