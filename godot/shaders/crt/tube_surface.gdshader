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
// raster_tex low-passed horizontally (raster_lowpass.gdshader), for distance.
uniform sampler2D raster_lo_tex : filter_linear, repeat_disable;
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
uniform float mask_scale = 1.0;           // Exaggerated detail: coarser than the real tube
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
// Scanlines fade separately (period in pixels per *swept* line). They are a
// colourless, coarser pattern than the RGB mask, so they can stay visible much
// closer to the pixel limit before beating turns into moire.
uniform vec2 scan_fade_px = vec2(3.0, 6.0);
// Extra blur for scanlines as they approach that limit (footprint multiplier).
uniform float scanline_filter = 2.0;

group_uniforms beam;
uniform float beam_sigma_dark = 0.22;
uniform float beam_sigma_bright = 0.42;
// Beam sigmas are in scanline heights of a ~240-line picture; a raster with
// more lines (480 frame lines in field mode, 480p) has a physically identical
// spot, so it covers proportionally more raster lines.
uniform float beam_scale = 1.0;
// Detail level's beam thinning (< 1: narrower spot, darker gaps). Each line's
// Gaussian stays normalised, so overall brightness is unchanged.
uniform float beam_sharp = 1.0;
// Raster lines between lines of one sweep: 2 in field mode, where each field
// lights every other line and the other half has decayed. That 2-line period
// is the structure actually on the tube at any instant, so fade by it.
uniform float sweep_lines = 1.0;
uniform vec2 convergence_r_mm = vec2(0.35, -0.2);
uniform vec2 convergence_b_mm = vec2(-0.3, 0.25);

group_uniforms color;
uniform mat3 phosphor_to_rec709 = mat3(1.0);
uniform float exposure = 1.0;
uniform vec3 glass_tint : source_color = vec3(0.42, 0.44, 0.43);
uniform float glass_roughness = 0.06;
uniform float glass_transmission = 0.75;
uniform float corner_falloff = 0.78;

group_uniforms glass;
// Glass on the tube (TV menu > GLASS): 0 off, 1 normal. Two parts, both added
// to what the glass shows: a soft "window" highlight that slides across the
// curved face as you move (the strongest cue that this is a glass bulb) and a
// sheen toward grazing angles. Real room reflections come on top from the PBR
// specular and the room's reflection probe (VR).
uniform float glass_reflect = 1.0;
uniform vec3 glass_light_dir = vec3(-0.45, 0.6, 1.0);  // tube space, +Z out of the screen
uniform vec3 glass_light_color : source_color = vec3(1.0, 0.96, 0.9);
// Wear on the glass: hairline scratches and faint wiping arcs, procedural in
// millimetres on the glass. They only show where they catch light (the window
// highlight or the edge sheen), and are band-limited like the mask, so from
// afar they fade instead of sparkling. 0 = pristine.
uniform float glass_scratches = 0.5;
const float SCRATCH_CELL_MM = 40.0;

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
	float P = mask_pitch_mm * mask_scale;
	float V = mask_vpitch_mm * mask_scale;
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

// One raster line at x, band-limited horizontally by the footprint: lo is
// the weight of the low-passed copy (0 up close, 1 far away).
vec3 raster_line(vec2 uv, float lo) {
	if (lo <= 0.0) {
		return texture(raster_tex, uv).rgb;
	}
	vec3 far = texture(raster_lo_tex, uv).rgb;
	return lo >= 1.0 ? far : mix(texture(raster_tex, uv).rgb, far, lo);
}

// Light deposited by one gun at picture position pic (0..1), from the raster.
// Gaussian spot per scanline, widened by the pixel footprint (exact for
// Gaussians: variance adds the box filter's w^2/12).
float beam(vec2 pic, int c, float footprint_lines, float lo) {
	float y = pic.y * raster_size.y - 0.5;
	float l0 = floor(y);
	float sum = 0.0;
	for (int k = -1; k <= 2; k++) {
		float l = l0 + float(k);
		if (l < 0.0 || l >= raster_size.y) {
			continue;
		}
		vec3 rgb = raster_line(vec2(pic.x, (l + 0.5) / raster_size.y), lo);
		float drive = c == 0 ? rgb.r : (c == 1 ? rgb.g : rgb.b);
		float sigma = mix(beam_sigma_dark, beam_sigma_bright, sqrt(clamp(drive, 0.0, 1.0))) * beam_scale * beam_sharp;
		// As lines approach the resolvable limit, merge them (sigma 0.55 lines is
		// flat) rather than let them beat against the pixel grid.
		float px_per_line = sweep_lines / max(footprint_lines, 1e-5);
		sigma = mix(0.55 * sweep_lines, sigma, smoothstep(scan_fade_px.x, scan_fade_px.y, px_per_line));
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

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Coverage of a line of width w_mm at distance d_mm, box-filtered over the
// pixel footprint fw_mm (a hairline narrower than a pixel just dims).
float hairline(float d_mm, float w_mm, float fw_mm) {
	float w = max(w_mm, fw_mm);
	return (w_mm / w) * (1.0 - smoothstep(0.0, w, d_mm));
}

// Scratch and wipe-mark intensity at glass position g (mm). 3x3 cells around
// g, each with up to two straight scratches and one arc segment.
float glass_wear(vec2 g, float fw_mm) {
	vec2 cell = floor(g / SCRATCH_CELL_MM);
	float s = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			for (int k = 0; k < 2; k++) {
				float h = hash12(c * 1.37 + float(k) * 17.1);
				if (h > 0.55) {
					continue;  // most cells are clean
				}
				vec2 o = (c + vec2(hash12(c + 3.1 + float(k)), hash12(c + 7.7 + float(k)))) * SCRATCH_CELL_MM;
				float ang = hash12(c + 11.3 + float(k)) * 3.14159;
				vec2 dir = vec2(cos(ang), sin(ang));
				float len = mix(6.0, 45.0, hash12(c + 5.9 + float(k)));
				vec2 rel = g - o;
				float t = clamp(dot(rel, dir), -len * 0.5, len * 0.5);
				float d = length(rel - dir * t);
				// Fade toward the ends, and vary depth per scratch.
				float ends = 1.0 - smoothstep(0.35, 0.5, abs(t) / len);
				s += hairline(d, 0.05, fw_mm) * ends * mix(0.4, 1.0, h / 0.55);
			}
			// A wiping arc: part of a large circle (cloth swirl), very faint.
			float ha = hash12(c * 2.71 + 41.0);
			if (ha < 0.18) {
				vec2 ctr = (c + vec2(hash12(c + 19.0), hash12(c + 23.0))) * SCRATCH_CELL_MM;
				float radius = mix(25.0, 70.0, hash12(c + 29.0));
				vec2 rel = g - ctr;
				float a = atan(rel.y, rel.x);
				float a0 = hash12(c + 31.0) * 6.2832;
				float on_arc = 1.0 - smoothstep(0.5, 0.9, abs(mod(a - a0 + 3.1416, 6.2832) - 3.1416));
				s += hairline(abs(length(rel) - radius), 0.08, fw_mm) * on_arc * 0.35;
			}
		}
	}
	return min(s, 1.0);
}

vec3 glass_reflection(vec3 v_obj, vec3 n, vec2 glass_mm, float glass_fw) {
	if (glass_reflect <= 0.0) {
		return vec3(0.0);
	}
	float ndv = clamp(dot(n, v_obj), 0.0, 1.0);
	vec3 r = reflect(-v_obj, n);
	float d = dot(r, normalize(glass_light_dir));
	// A soft-edged window: bright core, wide falloff.
	float window = smoothstep(0.93, 0.995, d) * 0.55 + smoothstep(0.6, 0.98, d) * 0.06;
	// Glass reflects more at grazing angles (Schlick, glass F0 ~0.04), seen as a
	// faint lighter band toward the curved edges; brighter where it faces up.
	float fresnel = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	float sheen = fresnel * (0.10 + 0.08 * clamp(r.y, 0.0, 1.0));
	// Scratches scatter light: lit by a wider lobe of the same window, so they
	// glint around the highlight, plus a little of the edge sheen.
	float lit = smoothstep(0.75, 0.99, d) * 0.9 + sheen * 2.0;
	float wear = glass_scratches > 0.0 ? glass_wear(glass_mm, glass_fw) * lit * glass_scratches : 0.0;
	return glass_light_color * (window + sheen + wear) * glass_reflect;
}

void fragment() {
	ALBEDO = glass_tint * 0.12;   // dark phosphor coat behind tinted glass
	ROUGHNESS = glass_roughness;
	SPECULAR = 0.5 * clamp(glass_reflect, 0.0, 1.0);
	METALLIC = 0.0;
	vec3 view_obj = normalize(transpose(mat3(MODEL_MATRIX)) * (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec2 glass_mm = UV * visible_mm;  // the glass surface itself, not the phosphors behind
	vec3 glass = glass_reflection(view_obj, normalize(obj_normal), glass_mm, length(fwidth(glass_mm)));
	EMISSION = glass;

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
		// The finest horizontal structure is the 4-sample subcarrier residue:
		// fade it out over the same pixel periods as the mask (fade_px).
		float footprint_x = fwidth(pic.x) * raster_size.x;
		float lo = 1.0 - smoothstep(fade_px.x, fade_px.y, 4.0 / max(footprint_x, 1e-5));

		vec3 drive = vec3(
			beam(pic + convergence_r_mm * corner / visible_mm, 0, footprint_lines, lo),
			beam(pic, 1, footprint_lines, lo),
			beam(pic + convergence_b_mm * corner / visible_mm, 2, footprint_lines, lo));
		float in_pic = step(0.0, pic.x) * step(pic.x, 1.0) * step(0.0, pic.y) * step(pic.y, 1.0);

		float falloff = mix(1.0, corner_falloff, smoothstep(0.2, 1.6, dot(corner, corner)));
		vec3 phosphor = drive * phosphor_mask(m, fw) * in_pic * inside * falloff;
		// Scattered glow is not masked: it lives in the glass, in front of the phosphors.
		vec3 glow = texture(halation_tex, clamp(pic, 0.0, 1.0)).rgb * halation * inside * falloff;
		EMISSION = max(phosphor_to_rec709 * (phosphor + glow), vec3(0.0)) * exposure * glass_transmission + glass;
	}
}
