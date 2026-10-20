// Surfaces of a user room model (rooms/*.json): the model's own colour and
// textures, lit like the built-in room by a dim ambient fill plus the CRT.
// Per pixel with the coarse 4x3 screen-light grid, since imported meshes are
// rarely dense enough for the per-vertex version (room_lit.gdshader).
// Emissive parts (lamps, signs) keep their glow.
shader_type spatial;
render_mode unshaded;

#include "res://shaders/include/screen_light.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec3 emission : source_color = vec3(0.0);
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float emission_energy = 1.0;
uniform float ambient = 0.07;
uniform float alpha_scissor = 0.5;
uniform bool use_alpha_scissor = false;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 base = albedo * texture(albedo_texture, UV);
	if (use_alpha_scissor && base.a < alpha_scissor) {
		discard;
	}
	vec3 n = normalize(world_normal);
	n = FRONT_FACING ? n : -n;
	float fill = 0.5 + 0.5 * max(dot(n, normalize(vec3(0.35, 0.8, 0.5))), 0.0);
	vec3 light = ambient * fill + vrt_screen_irradiance_coarse(world_pos, n);
	ALBEDO = base.rgb * light + emission * texture(emission_texture, UV).rgb * emission_energy;
}
