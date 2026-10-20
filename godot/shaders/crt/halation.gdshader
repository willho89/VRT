// Halation: light from bright phosphors scattered inside the faceplate glass.
// A wide, soft blur of the raster at reduced resolution (13 taps per axis via
// bilinear pairs); tube_surface adds it under the mask.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D raster_tex : filter_linear, repeat_disable;
uniform vec2 raster_size = vec2(320.0, 240.0);
uniform float radius_px = 6.0;  // in raster pixels

void fragment() {
	vec2 texel = radius_px / (6.0 * raster_size);
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int y = -3; y <= 3; y++) {
		for (int x = -3; x <= 3; x++) {
			float w = exp(-0.25 * float(x * x + y * y));
			sum += texture(raster_tex, UV + vec2(float(x), float(y)) * 2.0 * texel).rgb * w;
			wsum += w;
		}
	}
	COLOR = vec4(sum / wsum, 1.0);
}
