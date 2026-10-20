// Horizontal low-pass of the raster for viewing from a distance: a box 4
// samples wide (half-weight ends), which nulls the colour subcarrier exactly
// (4 samples a cycle) and with it the dot-crawl residue. The tube surface fades
// to this as a headset pixel's footprint grows, so fine signal structure is
// band-limited instead of aliasing into pixelation; up close it reads the
// full raster. Runs once per new core frame. (Viewport textures have no
// mipmaps, so this is the one extra level.)
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D raster_tex : filter_nearest, repeat_disable;
uniform float width = 764.0;

void fragment() {
	float t = 1.0 / width;
	vec3 c = 0.5 * texture(raster_tex, UV - vec2(2.0 * t, 0.0)).rgb
			+ texture(raster_tex, UV - vec2(t, 0.0)).rgb
			+ texture(raster_tex, UV).rgb
			+ texture(raster_tex, UV + vec2(t, 0.0)).rgb
			+ 0.5 * texture(raster_tex, UV + vec2(2.0 * t, 0.0)).rgb;
	COLOR = vec4(c * 0.25, 1.0);
}
