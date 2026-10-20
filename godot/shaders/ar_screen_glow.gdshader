// Real-world surfaces (Meta scene mesh) in passthrough: adds the CRT's light on
// top of the camera image without hiding it.
//
// The main projection layer is composited premultiplied (project settings:
// composition_layer_settings alpha_blend ONE / ONE_MINUS_SRC_ALPHA), and this
// material writes ALPHA = 0, so its color is purely added to passthrough.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/include/screen_light.gdshaderinc"

// Assumed reflectance of real surfaces; passthrough camera access could
// estimate this per pixel later.
uniform float albedo = 0.5;
uniform float strength = 1.0;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = albedo * strength * vrt_screen_irradiance_coarse(world_pos, world_normal);
	ALPHA = 0.0;
}
