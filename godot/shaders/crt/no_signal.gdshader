// What the set shows with nothing on its input, at 60 Hz:
//   blue  the "blue back" mute screen of 90s sets
//   snow  an untuned channel: wideband noise, smeared a little along the
//         line by the set's bandwidth, with slow horizontal banding. The
//         colour killer drops chroma without a burst, so it is grey.
shader_type canvas_item;
render_mode blend_disabled;

uniform int mode = 0;            // 0 blue, 1 snow
uniform float frame_count = 0.0;
uniform vec3 blue = vec3(0.0, 0.08, 0.72);

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	if (mode == 0) {
		COLOR = vec4(blue, 1.0);
	} else {
		vec2 px = floor(FRAGCOORD.xy);
		float f = frame_count;
		// Three overlapping noise samples along the line: ~3-sample grain.
		float n = (hash(vec3(px, f)) + hash(vec3(px.x - 1.0, px.y, f)) * 0.7
				+ hash(vec3(px.x + 1.0, px.y, f)) * 0.4) / 2.1;
		float band = 0.85 + 0.15 * sin(px.y * 0.05 + f * 0.21) + 0.08 * (hash(vec3(px.y, f, 7.0)) - 0.5);
		float v = pow(n, 1.6) * band;
		COLOR = vec4(vec3(v), 1.0);
	}
}
