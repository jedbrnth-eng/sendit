shader_type spatial;
// Additive spill of a lamp on the road: an elliptical pool brightest near the lamp.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.92, 0.8);
uniform float strength = 0.18;
uniform float boost_gain = 2.0;
instance uniform float boost = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // UV.y = 0 at the far end, 1 next to the car
	float r = length(vec2(p.x * (1.15 - UV.y * 0.5), p.y));
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2) * mix(0.25, 1.0, UV.y);
	ALBEDO = color * a * strength * (1.0 + boost * boost_gain);
}
