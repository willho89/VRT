// Virtual room surfaces: lit only by a dim ambient term and the CRT.
// Screen light is evaluated per vertex (16x12 cells) on subdivided meshes;
// it varies smoothly, and per pixel it would cost billions of ops per frame.
shader_type spatial;
render_mode unshaded;

#include "res://shaders/include/screen_light.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.55, 0.52, 0.48);
uniform float ambient = 0.07;
uniform bool flip_normals = false;

varying vec3 screen_light;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	screen_light = vrt_screen_irradiance(world_pos, flip_normals ? -world_normal : world_normal);
}

void fragment() {
	ALBEDO = albedo * (ambient + screen_light);
}
