// Comfort vignette: darkens the edge of view during artificial movement
// (walking, smooth turning), which reduces vection-induced motion sickness.
// Drawn on a quad just in front of each eye; strength fades in and out.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.0;  // 0 off .. 1 strongest
uniform float inner = 0.55;                           // radius where darkening starts

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float edge = mix(1.25, inner, strength);
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(edge, edge + 0.35, r) * step(0.001, strength);
}
