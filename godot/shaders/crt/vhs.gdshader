// VRT tape stage: what a VHS recording does to a picture before it reaches
// the TV (VRT's own model; the parameters follow the format's known limits).
// Runs at source resolution once per frame, in front of the composite/RF
// signal stage, like a VCR in the chain.
//
//   luma      ~3 MHz on tape (~240 TV lines): soft horizontally, then the
//             deck's sharpening puts a bright halo on edges
//   chroma    colour-under, ~0.5 MHz: smeared and late (shifted right), and
//             averaged with the line above (the deck's chroma comb)
//   noise     streaky grain, stretched along the line
//   timebase  lines land slightly off horizontally (the deck has no TBC):
//             verticals wiggle
//   head      the last lines of each field are torn sideways and noisy where
//   switch    the video heads hand over
//   worn      dropouts (white streaks) and a slow rolling tracking-noise bar
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 source_size = vec2(640.0, 480.0);
uniform float frame_count = 0.0;
uniform float wear = 0.0;            // 0 good tape .. 1 worn tape

const mat3 RGB_TO_YIQ = mat3(
	vec3(0.2989, 0.5959, 0.2115),
	vec3(0.5870, -0.2744, -0.5229),
	vec3(0.1140, -0.3216, 0.3114));
const mat3 YIQ_TO_RGB = mat3(
	vec3(1.0, 1.0, 1.0),
	vec3(0.956, -0.272, -1.106),
	vec3(0.621, -0.647, 1.705));

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 yiq_at(vec2 uv) {
	return RGB_TO_YIQ * texture(source_texture, uv).rgb;
}

void fragment() {
	// Scale "pixels" to a 640-wide picture so the look doesn't depend on the
	// source resolution (a 256 px game recorded to tape smears the same).
	float px = 1.0 / source_size.x;
	float k = source_size.x / 640.0;
	float lines = source_size.y;
	float line = floor(UV.y * lines);
	float f = frame_count;

	// Timebase: slow wobble plus per-line jitter (pixels of a 640 picture).
	float shift = sin(line * 0.045 + f * 0.21) * (0.6 + 1.2 * wear)
			+ (hash(vec3(line, f, 3.0)) - 0.5) * (0.5 + 1.5 * wear);
	// Head switching: the bottom ~2% of lines, torn and noisy.
	float hs_start = lines * 0.975;
	float in_hs = step(hs_start, line);
	float hs = in_hs * ((line - hs_start) / (lines - hs_start));
	shift += hs * (6.0 + 10.0 * hash(vec3(floor(f * 0.5), line, 9.0))) ;
	// Worn tape: a tracking-noise band rolling up the screen.
	float band_y = fract(f * 0.0025) * (lines * 1.4) - lines * 0.2;
	float in_band = wear * (1.0 - smoothstep(0.0, 6.0, abs(line - band_y)));
	shift += in_band * (hash(vec3(line, f, 17.0)) - 0.5) * 14.0;

	vec2 uv = vec2(UV.x + shift * k * px, (line + 0.5) / lines);

	// Luma: tape bandwidth (Gaussian, ~1.1 px at 640) ...
	float sy = mix(1.0, 1.4, wear) * k;
	float y_soft = 0.0;
	float y_wide = 0.0;
	float wsum = 0.0;
	float wwide = 0.0;
	for (int i = -4; i <= 4; i++) {
		float d = float(i);
		float yv = yiq_at(uv + vec2(d * px, 0.0)).x;
		float w = exp(-0.5 * d * d / (sy * sy));
		float ww = exp(-0.5 * d * d / (2.6 * k * 2.6 * k));
		y_soft += yv * w;
		wsum += w;
		y_wide += yv * ww;
		wwide += ww;
	}
	y_soft /= wsum;
	y_wide /= wwide;
	// ... then the deck's sharpening (edge halos).
	float luma = y_soft + (y_soft - y_wide) * mix(0.55, 0.8, wear);

	// Chroma: very narrow and late, averaged with the line above.
	float sc = mix(4.0, 6.0, wear) * k;
	float delay = mix(2.5, 4.0, wear) * k * px;
	vec2 iq = vec2(0.0);
	float csum = 0.0;
	vec2 up = vec2(0.0, -1.0 / lines);
	for (int i = -5; i <= 5; i++) {
		float d = float(i) * 2.0;
		float w = exp(-0.5 * d * d / (sc * sc));
		vec2 at = uv + vec2(d * px - delay, 0.0);
		iq += (yiq_at(at).yz + yiq_at(at + up).yz) * 0.5 * w;
		csum += w;
	}
	iq /= csum;
	iq *= mix(0.92, 0.82, wear);   // tape loses some saturation

	// Grain: stretched along the line (tape moves past the heads).
	float g = hash(vec3(floor(UV.x * source_size.x / (3.0 * k)), line, f)) - 0.5;
	luma += g * mix(0.03, 0.07, wear);
	iq += (vec2(hash(vec3(floor(UV.x * source_size.x / (8.0 * k)), line, f + 5.0)),
			hash(vec3(floor(UV.x * source_size.x / (8.0 * k)), line, f + 9.0))) - 0.5) * mix(0.015, 0.04, wear);

	// Head-switch and tracking noise: snow in the torn lines.
	float snow = hash(vec3(UV.x * source_size.x, line, f + 21.0));
	luma = mix(luma, snow, hs * 0.5 + in_band * 0.6);
	// Worn tape: dropouts, short white streaks.
	float drop = step(1.0 - 0.0015 * wear, hash(vec3(line, f, 31.0)));
	float drop_x = hash(vec3(line, f, 37.0));
	luma = mix(luma, 0.95, drop * step(abs(UV.x - drop_x), 0.04));

	COLOR = vec4(clamp(YIQ_TO_RGB * vec3(luma, iq), vec3(0.0), vec3(1.0)), 1.0);
}
