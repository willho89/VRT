// Virtual room surfaces: lit only by a dim ambient term and the CRT.
shader_type spatial;
render_mode unshaded;

#include "res://shaders/include/screen_light.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.55, 0.52, 0.48);
uniform float ambient = 0.02;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = albedo * (ambient + vrt_screen_irradiance(world_pos, world_normal));
}
