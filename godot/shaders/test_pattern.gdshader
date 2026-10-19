// M0 placeholder screen: cycles full-field colors so the light spill is easy to
// judge, with SMPTE-ish bars in between. Timing must match
// hello_xr.gd:_pattern_color(), which mirrors it on the CPU for lighting.
shader_type spatial;
render_mode unshaded, cull_back;

uniform float pattern_time = 0.0;
uniform float brightness = 1.0;

const vec3 FIELDS[5] = vec3[5](vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(1), vec3(0));

vec3 bars(vec2 uv) {
	const vec3 B[7] = vec3[7](vec3(0.75), vec3(0.75, 0.75, 0), vec3(0, 0.75, 0.75), vec3(0, 0.75, 0),
			vec3(0.75, 0, 0.75), vec3(0.75, 0, 0), vec3(0, 0, 0.75));
	return B[clamp(int(uv.x * 7.0), 0, 6)];
}

void fragment() {
	int slot = int(mod(floor(pattern_time / 2.0), 6.0));
	vec3 c = slot < 5 ? FIELDS[slot] : bars(UV);
	ALBEDO = c * brightness;
}
