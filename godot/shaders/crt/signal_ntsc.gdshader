// VRT signal stage: NTSC encode -> cable/RF -> TV decode.
//
// Runs once per core frame at 4 samples per colour-subcarrier cycle
// (14.318 MHz, 4 x fsc), so every parameter below that is "in samples" is the
// same physical time for every console. The output is that many samples wide;
// the raster pass consumes it directly, so the decoder's fine dot pattern is
// not resampled away.
//
//   encode   each sample integrates the held console pixels under it (one
//            bilinear fetch), RGB -> YIQ, chroma = I cos + Q sin of the
//            subcarrier at this sample's phase. Phase = per-system line and
//            frame steps (scripts/crt/system_timing.gd) + sample / 4.
//   cable    composite: Y + C on one wire.  S-Video: Y and C kept apart.
//            RF: + ghost, noise, snow, AGC wobble, sync and burst jitter.
//   decode   demodulate with the burst-locked carrier and low-pass I/Q
//            (Gaussian, chroma_sigma samples). Luma = signal minus the
//            re-modulated chroma estimate, i.e. a notch exactly as wide as
//            the chroma band. On flat colour the estimate is exact and luma
//            is clean; at colour and luma edges it is not, which is where a
//            real set shows dot crawl and rainbowing.
//            Comb mode separates with the line above instead (2-line comb).
//
// Signal model after LMP88959/NTSC-CRT (public domain style licence) and the
// standard NTSC decoder structure; the RF effects (ghost, snow, AGC, sync,
// burst, tuning) follow TSUISHI/CRTshader's Stage 1 (MIT, Copyright (c) 2026
// Ken TSUISHI; see LICENSE-CRTshader-MIT.txt).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 source_size = vec2(256.0, 240.0);   // console pixels, lines
uniform float out_width = 683.0;                  // samples per line
uniform float frame_count = 0.0;

// Subcarrier phase, in cycles: frame_phase + line * line_step + sample / 4.
uniform float frame_phase = 0.0;
uniform float line_step = 0.5;

uniform int mode = 0;                    // 0 composite (notch), 1 composite (comb), 2 S-Video
uniform float signal_amount : hint_range(0.0, 1.0) = 1.0;  // strength: mix with the clean picture
uniform float chroma_sigma = 2.6;        // decoder I/Q low-pass, samples
uniform float encoder_chroma_sigma = 0.0; // console-side chroma low-pass, samples (0 = none)
uniform float noise = 0.004;

group_uniforms rf;
uniform float rf_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ghost_strength = 0.0;
uniform float ghost_delay = 24.0;        // samples
uniform float rf_snow = 0.0;
uniform float rf_gain_wobble = 0.0;
uniform float sync_jitter = 0.0;         // samples
uniform float burst_phase_noise = 0.0;   // cycles
uniform float rf_tuning_error = 0.0;     // cycles across a line

const int R = 8;                         // decoder taps each side (>= 3 sigma)
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

// Console output under sample s of a line: the held pixels it spans, area
// weighted. One linear fetch: the two pixels' blend at the right offset.
vec3 held_rgb(float s, float line) {
	float r = source_size.x / out_width;           // source px per sample
	float a = s * r;
	float b = a + r;
	float p = floor(a);
	float w = clamp((b - (p + 1.0)) / r, 0.0, 1.0); // share of the next pixel
	float u = (p + 0.5 + w) / source_size.x;
	return texture(source_texture, vec2(u, (line + 0.5) / source_size.y)).rgb;
}

float line_phase(float line) {
	float burst = (hash(vec3(line, floor(frame_count * 0.25), 71.0)) - 0.5) * burst_phase_noise;
	return frame_phase + line * line_step + rf_amount * burst;
}

float carrier(float s, float lphase) {
	float drift = rf_amount * rf_tuning_error * (s / out_width + frame_count * 0.006);
	return TAU * (lphase + s * 0.25 + drift);
}

// Luma and modulated chroma at sample s.
vec2 encode(float s, float line, float lphase) {
	vec3 yiq = RGB_TO_YIQ * held_rgb(s, line);
	if (encoder_chroma_sigma > 0.0) {
		// Cheap 3-tap chroma pre-filter (consoles with an RGB->NTSC encoder chip).
		float k = exp(-0.5 / (encoder_chroma_sigma * encoder_chroma_sigma));
		vec2 iq = yiq.yz + k * ((RGB_TO_YIQ * held_rgb(s - 1.0, line)).yz
				+ (RGB_TO_YIQ * held_rgb(s + 1.0, line)).yz);
		yiq.yz = iq / (1.0 + 2.0 * k);
	}
	float ph = carrier(s, lphase);
	return vec2(yiq.x, yiq.y * cos(ph) + yiq.z * sin(ph));
}

// What arrives at the TV at sample s: (luma wire, chroma wire). Composite and
// RF carry everything on .x; S-Video keeps them apart.
vec2 cable(float s, float line, float lphase) {
	vec2 yc = encode(s, line, lphase);
	if (rf_amount > 0.0 && ghost_strength > 0.0) {
		yc += encode(s - ghost_delay, line, lphase) * ghost_strength * rf_amount;
	}
	vec2 n = vec2(hash(vec3(s, line, frame_count)), hash(vec3(s, line, frame_count + 61.0))) - 0.5;
	yc += n * noise;
	if (rf_amount > 0.0) {
		float snow = hash(vec3(s * 1.7, line * 2.3, frame_count + 211.0));
		yc.x += rf_amount * rf_snow * ((snow - 0.5) * 0.35 + max((snow - 0.985) / 0.015, 0.0) * 1.2);
		float wob = sin(frame_count * 0.037 + line * 0.013) * 0.65
				+ (hash(vec3(floor(frame_count * 0.125), line * 0.031, 93.0)) - 0.5) * 0.35;
		yc *= 1.0 + rf_amount * rf_gain_wobble * wob;
	}
	return mode == 2 ? yc : vec2(yc.x + yc.y, 0.0);
}

void fragment() {
	float s0 = floor(FRAGCOORD.x);
	float line = floor(UV.y * source_size.y);
	vec3 clean = held_rgb(s0, line);
	if (signal_amount <= 0.0001) {
		COLOR = vec4(clean, 1.0);
	} else {
		// Horizontal sync PLL residual: the whole line lands a little off.
		float jitter = sin(line * 0.093 + frame_count * 0.018) * 0.65
				+ (hash(vec3(line, floor(frame_count * 0.25), 41.0)) - 0.5) * 0.7;
		float s_c = s0 + rf_amount * sync_jitter * jitter;
		float lp = line_phase(line);
		float lp_prev = line_phase(line - 1.0);

		vec2 iq = vec2(0.0);
		float wsum = 0.0;
		float centre = 0.0;     // signal at s_c (luma wire)
		for (int k = -R; k <= R; k++) {
			float s = s_c + float(k);
			vec2 a = cable(s, line, lp);
			float chroma;
			if (mode == 2) {
				chroma = a.y;
			} else if (mode == 1) {
				// 2-line comb: chroma cancels against the line above only when
				// the line step is half a cycle (broadcast timing, PC Engine,
				// DVD); with the NES/SNES third-cycle step it leaves dots.
				vec2 b = cable(s, line - 1.0, lp_prev);
				chroma = 0.5 * (a.x - b.x);
			} else {
				chroma = a.x;
			}
			float w = exp(-0.5 * float(k * k) / (chroma_sigma * chroma_sigma));
			float ph = carrier(s, lp);
			iq += w * chroma * 2.0 * vec2(cos(ph), sin(ph));
			wsum += w;
			if (k == 0) {
				centre = a.x;
			}
		}
		iq /= wsum;
		float ph0 = carrier(s_c, lp);
		float y;
		if (mode == 2) {
			y = centre;
		} else {
			// Notch / comb luma: the signal minus the chroma the decoder found.
			y = centre - (iq.x * cos(ph0) + iq.y * sin(ph0));
		}
		vec3 decoded = clamp(YIQ_TO_RGB * vec3(y, iq), vec3(0.0), vec3(1.0));
		COLOR = vec4(mix(clean, decoded, signal_amount), 1.0);
	}
}
