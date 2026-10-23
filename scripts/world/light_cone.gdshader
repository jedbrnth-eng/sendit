shader_type spatial;
// Fake volumetric lamp cone: additive open cylinder, brightest under the head, soft at the
// silhouette edge (view rim) and faded out when the camera drives through it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.6, 0.28);
uniform float intensity = 0.1;
uniform float height = 10.0;
uniform float near_fade = 28.0;

varying float h;

void vertex() {
	h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0); // 0 at ground, 1 at lamp head
}

void fragment() {
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(rim, 2.5) * (0.15 + 0.85 * h * h);
	a *= smoothstep(near_fade * 0.4, near_fade, length(VERTEX));
	ALBEDO = color;
	ALPHA = a * intensity;
}
