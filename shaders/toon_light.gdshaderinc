// Shared cartoon lighting (ASSETS §1), included by every toon shader: a stepped light ramp (shadow,
// mid and lit bands, or a `toon_ramp` texture) and a soft rim light on the lit side.
// Each light's contribution is stepped on its own (N·L times its attenuation and shadow), so omni
// lights draw flat rings of light instead of smooth gradients. Ambient light comes from the
// WorldEnvironment as usual.

uniform bool use_ramp_texture = false;
uniform sampler2D toon_ramp : hint_default_white, filter_linear, repeat_disable;
uniform float shade_mid : hint_range(0.0, 1.0) = 0.55;  // brightness of the middle band
uniform float band_low : hint_range(0.0, 1.0) = 0.06;  // light below this: the shadow band
uniform float band_high : hint_range(0.0, 1.0) = 0.38;  // light above this: fully lit
uniform float band_soft : hint_range(0.0, 0.2) = 0.025;  // edge softness between bands
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;

float toon_band(float lit) {
	if (use_ramp_texture) {
		return texture(toon_ramp, vec2(clamp(lit, 0.0, 1.0), 0.5)).r;
	}
	// The ramp must be exactly 0 without light: Forward+ only runs a light in the screen tiles it
	// touches, so any light left over at zero shows up as blocks along the tile edges.
	float mid = smoothstep(max(band_low - band_soft, 0.0), band_low + band_soft, lit) * shade_mid;
	float full = smoothstep(max(band_high - band_soft, 0.0), band_high + band_soft, lit);
	return mix(mid, 1.0, full) * step(1e-4, lit);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = toon_band(ndl * ATTENUATION);
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = smoothstep(1.0 - rim_width - 0.03, 1.0 - rim_width + 0.03, rim) * rim_strength;
	DIFFUSE_LIGHT += (band + rim * band) * LIGHT_COLOR / PI;
}
