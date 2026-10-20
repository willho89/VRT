// CRT raster pass: what the phosphor layer holds after the beam's latest sweep.
//
// Runs once per new core frame into an RGBA16F target sized (source width,
// frame lines). Output is linear gun drive per channel (electron gun gamma
// applied), plus the decaying remainder of the previous sweep:
//   progressive: every line = new + prev * persistence
//   field mode (VRT field extension): only this field's lines are refreshed;
//     the other field's lines keep decaying, as on a real tube.
// The ping-pong partner's output arrives as prev_tex.
//
// Horizontally the beam spot is applied here, once per core frame: each source
// pixel is a held voltage level (a box one pixel wide) swept by a Gaussian
// spot that grows with drive, so bright detail spreads wider. Done as a
// gather over +-3 pixels; box * Gaussian keeps flat fields exactly level.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source_tex : filter_nearest, repeat_disable;
uniform sampler2D prev_tex : filter_nearest, repeat_disable;
uniform vec2 source_size = vec2(320.0, 240.0);
uniform float frame_lines = 240.0;
uniform int field = 0;              // 0 progressive, 1 top (even lines), 2 bottom (odd)
uniform vec3 persistence = vec3(0.02, 0.06, 0.01);
uniform float gamma = 2.4;
uniform bool has_prev = false;
// Horizontal spot sigma in 1/320ths of the picture width, at black and full drive.
uniform vec2 beam_sigma_h = vec2(0.25, 0.40);

vec3 gun(vec3 v) {
	return pow(clamp(v, vec3(0.0), vec3(1.0)), vec3(gamma));
}

// Standard normal CDF (tanh approximation, error < 3e-4).
float ncdf(float x) {
	return 0.5 + 0.5 * tanh(0.7978845 * (x + 0.044715 * x * x * x));
}

// One raster line at uv: gun drive per source pixel, spread by the beam spot.
vec3 sweep(vec2 uv) {
	float texel = 1.0 / source_size.x;
	float k = source_size.x / 320.0;
	vec3 sum = vec3(0.0);
	for (int i = -3; i <= 3; i++) {
		vec3 d = gun(texture(source_tex, uv + vec2(float(i) * texel, 0.0)).rgb);
		vec3 sigma = max(mix(vec3(beam_sigma_h.x), vec3(beam_sigma_h.y), sqrt(d)) * k, vec3(0.05));
		// Distance from this output pixel's centre to the source pixel's edges.
		float x0 = -float(i) - 0.5;
		float x1 = -float(i) + 0.5;
		vec3 w = vec3(
			ncdf(x1 / sigma.r) - ncdf(x0 / sigma.r),
			ncdf(x1 / sigma.g) - ncdf(x0 / sigma.g),
			ncdf(x1 / sigma.b) - ncdf(x0 / sigma.b));
		sum += d * w;
	}
	return sum;
}

void fragment() {
	vec3 prev = has_prev ? texture(prev_tex, UV).rgb : vec3(0.0);
	float line = floor(UV.y * frame_lines);
	vec3 outc;
	if (field == 0) {
		outc = sweep(UV) + prev * persistence;
	} else {
		float parity = mod(line, 2.0);
		bool ours = (field == 1 && parity < 0.5) || (field == 2 && parity > 0.5);
		if (ours) {
			float src_line = floor(line * 0.5);
			vec2 suv = vec2(UV.x, (src_line + 0.5) / source_size.y);
			outc = sweep(suv) + prev * persistence;
		} else {
			outc = prev * persistence;
		}
	}
	COLOR = vec4(outc, 1.0);
}
