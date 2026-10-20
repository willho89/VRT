// CRT faceplate: beam reconstruction on a band-limited phosphor mask, seen
// through thick tinted glass. One shader from 2 cm to across the room.
//
// Coordinates: UV is the visible picture area on the glass (0..1, top-left).
// Everything physical is in millimetres on the tube (m = uv * visible_mm).
// Anything periodic is box-filtered analytically over the pixel footprint
// (fwidth), so it is crisp up close and settles to its true average far away
// instead of aliasing. See docs/m2-crt-design.md.
//
// Beam profile and parameter ranges follow crt-guest-advanced / crt-royale
// (GPL-2.0+); beam width by drive and convergence follow TSUISHI/CRTshader (MIT).
shader_type spatial;
render_mode cull_back, shadows_disabled;

uniform sampler2D raster_tex : filter_linear, repeat_disable;
uniform sampler2D halation_tex : filter_linear, repeat_disable;
uniform float halation = 0.06;
uniform vec2 raster_size = vec2(320.0, 240.0);   // (source px, frame lines)
uniform bool powered = false;

group_uniforms tube;
uniform vec2 visible_mm = vec2(508.0, 381.0);
uniform float corner_radius_mm = 28.0;
uniform float glass_thickness_mm = 12.0;
uniform float glass_ior = 1.52;
uniform vec2 overscan = vec2(0.06, 0.05);
uniform float pincushion = 0.012;

group_uniforms mask;
uniform int mask_type = 0;                // 0 slot, 1 dot, 2 aperture grille
uniform float mask_pitch_mm = 0.82;
uniform float mask_vpitch_mm = 0.82;
uniform float phosphor_duty = 0.62;
uniform float slot_duty = 0.78;
uniform float edge_soft = 0.06;           // phosphor edge blur, fraction of a stripe
uniform float filter_width = 1.0;         // filter width in pixels (tent of 2x this)
// Mask contrast fades to its average as a period shrinks from fade_px.y to
// fade_px.x pixels. The margin is wide because the headset compositor
// resamples the eye buffer again (lens distortion, reprojection): anything
// left near the eye buffer's Nyquist limit re-aliases there as moire.
uniform vec2 fade_px = vec2(3.0, 6.0);
// Extra blur for scanlines as they approach that limit (footprint multiplier).
uniform float scanline_filter = 2.0;

group_uniforms beam;
uniform float beam_sigma_dark = 0.22;
uniform float beam_sigma_bright = 0.42;
uniform vec2 convergence_r_mm = vec2(0.35, -0.2);
uniform vec2 convergence_b_mm = vec2(-0.3, 0.25);

group_uniforms color;
uniform mat3 phosphor_to_rec709 = mat3(1.0);
uniform float exposure = 1.0;
uniform vec3 glass_tint : source_color = vec3(0.42, 0.44, 0.43);
uniform float glass_roughness = 0.06;
uniform float glass_transmission = 0.75;
uniform float corner_falloff = 0.78;

varying vec3 obj_normal;

const float SQRT_2PI = 2.50662827463;

void vertex() {
	obj_normal = NORMAL;
}

// Integral of a pulse train (period T, pulse [s, s+d) in each period).
float pulse_integral(float x, float T, float s, float d) {
	float k = floor((x - s) / T);
	return k * d + clamp(x - s - k * T, 0.0, d);
}

// Mean of the pulse train over [x - w/2, x + w/2]: an exact box filter.
float pulse_box1(float x, float T, float s, float d, float w) {
	w = max(w, 1e-4 * T);
	return (pulse_integral(x + 0.5 * w, T, s, d) - pulse_integral(x - 0.5 * w, T, s, d)) / w;
}

// Approximate tent filter of width 2w (three boxes, weights 1:2:1). A box
// alone leaks the sharp stripe edges' harmonics past Nyquist as moire.
float pulse_box(float x, float T, float s, float d, float w) {
	return 0.25 * (pulse_box1(x - 0.5 * w, T, s, d, w) + 2.0 * pulse_box1(x, T, s, d, w)
			+ pulse_box1(x + 0.5 * w, T, s, d, w));
}

// Per-channel phosphor coverage at m (mm), filtered over footprint fw (mm).
// Normalised so its far-field average is 1 for every channel.
vec3 phosphor_mask(vec2 m, vec2 fw) {
	float P = mask_pitch_mm;
	float V = mask_vpitch_mm;
	float stripe = P / 3.0;
	float lit = phosphor_duty * stripe;
	vec2 w = fw * filter_width + vec2(edge_soft * stripe);
	// Per-axis contrast: x by triad pitch, y by slot/row period, in pixels.
	vec2 contrast = smoothstep(fade_px.x, fade_px.y, vec2(P, V) / max(fw, vec2(1e-5)));
	vec3 h0;
	vec3 h1;
	for (int c = 0; c < 3; c++) {
		float s = (float(c) + 0.5) * stripe - 0.5 * lit;
		float a = pulse_box(m.x, P, s, lit, w.x);
		float b = pulse_box(m.x + 0.5 * P, P, s, lit, w.x);  // half-pitch shifted rows (dot mask)
		if (c == 0) { h0.r = a; h1.r = b; }
		else if (c == 1) { h0.g = a; h1.g = b; }
		else { h0.b = a; h1.b = b; }
	}
	float mean_h = lit / P;
	h0 = mix(vec3(mean_h), h0, contrast.x);
	h1 = mix(vec3(mean_h), h1, contrast.x);
	if (mask_type == 2) {
		return h0 / mean_h;
	}
	float open = slot_duty * V;
	if (mask_type == 0) {
		// Slot: slots in each triad column, odd columns staggered by half a period.
		float v_even = mix(slot_duty, pulse_box(m.y, V, 0.0, open, w.y), contrast.y);
		float v_odd = mix(slot_duty, pulse_box(m.y + 0.5 * V, V, 0.0, open, w.y), contrast.y);
		float odd_cols = mix(0.5, pulse_box(m.x, 2.0 * P, P, P, w.x), contrast.x);
		return h0 * mix(v_even, v_odd, odd_cols) / (mean_h * slot_duty);
	}
	// Dot (delta): rows of dots, odd rows shifted half a pitch.
	float v = mix(slot_duty, pulse_box(m.y, V, 0.0, open, w.y), contrast.y);
	float odd_rows = mix(0.5, pulse_box(m.y, 2.0 * V, V, V, w.y), contrast.y);
	return mix(h0, h1, odd_rows) * v / (mean_h * slot_duty);
}

// Light deposited by one gun at picture position pic (0..1), from the raster.
// Gaussian spot per scanline, widened by the pixel footprint (exact for
// Gaussians: variance adds the box filter's w^2/12).
float beam(vec2 pic, int c, float footprint_lines) {
	float y = pic.y * raster_size.y - 0.5;
	float l0 = floor(y);
	float sum = 0.0;
	for (int k = -1; k <= 2; k++) {
		float l = l0 + float(k);
		if (l < 0.0 || l >= raster_size.y) {
			continue;
		}
		vec3 rgb = texture(raster_tex, vec2(pic.x, (l + 0.5) / raster_size.y)).rgb;
		float drive = c == 0 ? rgb.r : (c == 1 ? rgb.g : rgb.b);
		float sigma = mix(beam_sigma_dark, beam_sigma_bright, sqrt(clamp(drive, 0.0, 1.0)));
		// As lines approach the resolvable limit, merge them (sigma 0.55 lines is
		// flat) rather than let them beat against the pixel grid.
		float px_per_line = 1.0 / max(footprint_lines, 1e-5);
		sigma = mix(0.55, sigma, smoothstep(fade_px.x, fade_px.y, px_per_line));
		float fp = footprint_lines * scanline_filter;
		float var = sigma * sigma + fp * fp / 12.0;
		float d = y - l;
		sum += drive * exp(-0.5 * d * d / var) * inversesqrt(var) / SQRT_2PI;
	}
	return sum;
}

float rounded_rect(vec2 m) {
	vec2 half_size = 0.5 * visible_mm;
	vec2 q = abs(m - half_size) - (half_size - vec2(corner_radius_mm));
	float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius_mm;
	return clamp(0.5 - dist / max(fwidth(dist), 1e-4), 0.0, 1.0);
}

void fragment() {
	ALBEDO = glass_tint * 0.12;   // dark phosphor coat behind tinted glass
	ROUGHNESS = glass_roughness;
	SPECULAR = 0.5;
	METALLIC = 0.0;

	if (powered) {
		// Parallax: the phosphor layer sits glass_thickness behind this surface.
		vec3 v_world = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		vec3 v_obj = normalize(transpose(mat3(MODEL_MATRIX)) * v_world);
		vec3 n = normalize(obj_normal);
		vec3 vt = v_obj - n * dot(v_obj, n);
		float sin_i = length(vt);
		float sin_t = sin_i / glass_ior;
		float tan_t = sin_t * inversesqrt(max(1.0 - sin_t * sin_t, 1e-4));
		vec2 shift_mm = sin_i > 1e-5 ? -(vt.xy / sin_i) * tan_t * glass_thickness_mm : vec2(0.0);
		vec2 uv = UV + vec2(shift_mm.x, -shift_mm.y) / visible_mm;

		vec2 m = uv * visible_mm;
		vec2 fw = fwidth(m);
		float inside = rounded_rect(m);

		// Deflection: overscan crops the active picture; residual pincushion.
		vec2 c = uv * 2.0 - 1.0;
		c *= 1.0 - 2.0 * overscan;
		c *= 1.0 + pincushion * dot(c, c);
		vec2 pic = c * 0.5 + 0.5;
		vec2 corner = uv * 2.0 - 1.0;  // convergence error grows toward the corners
		float footprint_lines = fwidth(pic.y) * raster_size.y;

		vec3 drive = vec3(
			beam(pic + convergence_r_mm * corner / visible_mm, 0, footprint_lines),
			beam(pic, 1, footprint_lines),
			beam(pic + convergence_b_mm * corner / visible_mm, 2, footprint_lines));
		float in_pic = step(0.0, pic.x) * step(pic.x, 1.0) * step(0.0, pic.y) * step(pic.y, 1.0);

		float falloff = mix(1.0, corner_falloff, smoothstep(0.2, 1.6, dot(corner, corner)));
		vec3 phosphor = drive * phosphor_mask(m, fw) * in_pic * inside * falloff;
		// Scattered glow is not masked: it lives in the glass, in front of the phosphors.
		vec3 glow = texture(halation_tex, clamp(pic, 0.0, 1.0)).rgb * halation * inside * falloff;
		EMISSION = max(phosphor_to_rec709 * (phosphor + glow), vec3(0.0)) * exposure * glass_transmission;
	}
}
