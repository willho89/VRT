// Light cast by the CRT face onto its surroundings.
//
// The screen is a rectangle (center, half-extent vectors right/up, emitting
// along cross(right, up)) split into a grid of small patches, each a
// Lambertian emitter:
//     E += L * A * cos(theta_emitter) * cos(theta_receiver) / (d^2 + A)
// The "+ A" term keeps the result finite on surfaces touching the glass.
//
// Cell radiance comes from the picture itself (linear, top-left origin), so a
// bright left half lights the left wall:
//   VRT_SCREEN_CELLS        16x12 - evaluate per VERTEX on subdivided meshes
//   VRT_SCREEN_CELLS_COARSE  4x3  - cheap enough per pixel (AR scene planes)

global uniform vec3 VRT_SCREEN_CENTER;
global uniform vec3 VRT_SCREEN_RIGHT;
global uniform vec3 VRT_SCREEN_UP;
global uniform vec3 VRT_SCREEN_RADIANCE;
global uniform sampler2D VRT_SCREEN_CELLS : filter_nearest;
global uniform sampler2D VRT_SCREEN_CELLS_COARSE : filter_nearest;

vec3 vrt_screen_light(vec3 world_pos, vec3 world_normal, sampler2D cells, int nx, int ny) {
	vec3 n_screen = normalize(cross(VRT_SCREEN_RIGHT, VRT_SCREEN_UP));
	float cell_area = 4.0 * length(VRT_SCREEN_RIGHT) * length(VRT_SCREEN_UP) / float(nx * ny);
	vec3 sum = vec3(0.0);
	for (int y = 0; y < ny; y++) {
		for (int x = 0; x < nx; x++) {
			vec2 c = (vec2(float(x), float(y)) + 0.5) / vec2(float(nx), float(ny)) * 2.0 - 1.0;
			vec3 p = VRT_SCREEN_CENTER + VRT_SCREEN_RIGHT * c.x + VRT_SCREEN_UP * c.y;
			vec3 to_recv = world_pos - p;
			float d2 = dot(to_recv, to_recv);
			vec3 l = to_recv * inversesqrt(max(d2, 1e-6));
			float cos_e = max(dot(n_screen, l), 0.0);
			float cos_r = max(dot(world_normal, -l), 0.0);
			// Cell (x, y) counts up from the bottom; the texture is top-left origin.
			vec3 cell = texelFetch(cells, ivec2(x, ny - 1 - y), 0).rgb;
			sum += cell * cos_e * cos_r / (d2 + cell_area);
		}
	}
	return VRT_SCREEN_RADIANCE * sum * cell_area;
}

vec3 vrt_screen_irradiance(vec3 world_pos, vec3 world_normal) {
	return vrt_screen_light(world_pos, world_normal, VRT_SCREEN_CELLS, 16, 12);
}

vec3 vrt_screen_irradiance_coarse(vec3 world_pos, vec3 world_normal) {
	return vrt_screen_light(world_pos, world_normal, VRT_SCREEN_CELLS_COARSE, 4, 3);
}
