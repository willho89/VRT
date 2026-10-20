// CRT raster pass: what the phosphor layer holds after the beam's latest sweep.
//
// Runs once per new core frame into an RGBA16F target sized (source width,
// frame lines). Output is linear gun drive per channel (electron gun gamma
// applied), plus the decaying remainder of the previous sweep:
//   progressive: every line = new + prev * persistence
//   field mode (VRT field extension): only this field's lines are refreshed;
//     the other field's lines keep decaying, as on a real tube.
// The ping-pong partner's output arrives as prev_tex.
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

vec3 gun(vec3 v) {
	return pow(clamp(v, vec3(0.0), vec3(1.0)), vec3(gamma));
}

void fragment() {
	vec3 prev = has_prev ? texture(prev_tex, UV).rgb : vec3(0.0);
	float line = floor(UV.y * frame_lines);
	vec3 outc;
	if (field == 0) {
		outc = gun(texture(source_tex, UV).rgb) + prev * persistence;
	} else {
		float parity = mod(line, 2.0);
		bool ours = (field == 1 && parity < 0.5) || (field == 2 && parity > 0.5);
		if (ours) {
			float src_line = floor(line * 0.5);
			vec2 suv = vec2(UV.x, (src_line + 0.5) / source_size.y);
			outc = gun(texture(source_tex, suv).rgb) + prev * persistence;
		} else {
			outc = prev * persistence;
		}
	}
	COLOR = vec4(outc, 1.0);
}
