// Light cast by the CRT face onto its surroundings.
//
// The screen is a rectangle (center, half-extent vectors right/up, emitting
// along cross(right, up)). It is split into CELLS_X x CELLS_Y small patches and
// each patch is treated as a point-ish Lambertian emitter:
//     E += L * A * cos(theta_emitter) * cos(theta_receiver) / (d^2 + A)
// The "+ A" term keeps the result finite on surfaces touching the glass.
//
// M0: uniform radiance across the face. M2 replaces VRT_SCREEN_RADIANCE with a
// lookup into the raster's lowest mip, one texel per cell.

global uniform vec3 VRT_SCREEN_CENTER;
global uniform vec3 VRT_SCREEN_RIGHT;
global uniform vec3 VRT_SCREEN_UP;
global uniform vec3 VRT_SCREEN_RADIANCE;

const int VRT_CELLS_X = 4;
const int VRT_CELLS_Y = 3;

vec3 vrt_screen_irradiance(vec3 world_pos, vec3 world_normal) {
	vec3 n_screen = normalize(cross(VRT_SCREEN_RIGHT, VRT_SCREEN_UP));
	float cell_area = 4.0 * length(VRT_SCREEN_RIGHT) * length(VRT_SCREEN_UP)
			/ float(VRT_CELLS_X * VRT_CELLS_Y);
	float sum = 0.0;
	for (int y = 0; y < VRT_CELLS_Y; y++) {
		for (int x = 0; x < VRT_CELLS_X; x++) {
			vec2 c = (vec2(float(x), float(y)) + 0.5) / vec2(float(VRT_CELLS_X), float(VRT_CELLS_Y)) * 2.0 - 1.0;
			vec3 p = VRT_SCREEN_CENTER + VRT_SCREEN_RIGHT * c.x + VRT_SCREEN_UP * c.y;
			vec3 to_recv = world_pos - p;
			float d2 = dot(to_recv, to_recv);
			vec3 l = to_recv * inversesqrt(max(d2, 1e-6));
			float cos_e = max(dot(n_screen, l), 0.0);
			float cos_r = max(dot(world_normal, -l), 0.0);
			sum += cos_e * cos_r / (d2 + cell_area);
		}
	}
	return VRT_SCREEN_RADIANCE * sum * cell_area;
}
