shader_type spatial;
// Camera-facing lamp flare: soft core + horizontal streak, grows with distance so far-off lamps
// still read, and fades out when the lamp points away from the camera.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float size = 0.35;          // metres, near
uniform float grow = 0.006;         // extra metres per metre of distance
uniform float strength = 1.0;
uniform float streak = 0.5;
uniform float facing_sign = -1.0;   // lamp points along local -Z (head) or +Z (tail)
uniform float idle = 1.0;           // brightness with boost = 0
uniform float boost_gain = 1.5;
instance uniform float boost = 0.0;

varying float v_face;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(-c);
	vec3 fwd = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, facing_sign, 0.0)).xyz);
	v_face = smoothstep(0.05, 0.6, dot(fwd, to_cam));
	float s = (size + length(c) * grow) * (1.0 + boost * 0.6);
	c += to_cam * 0.35;  // pull toward camera so the car body does not clip the flare
	POSITION = PROJECTION_MATRIX * vec4(c + vec3(VERTEX.x * s * 4.0, VERTEX.y * s, 0.0), 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 q = p * vec2(4.0, 1.0);  // undo the 4:1 quad so the core is round
	float core = exp(-dot(q, q) * 2.2) * 0.8 + exp(-dot(q, q) * 14.0);
	float line = exp(-abs(p.y) * 14.0) * pow(1.0 - abs(p.x), 3.0) * streak;
	float a = (core + line) * strength * (idle + boost * boost_gain) * v_face;
	ALBEDO = color * a;
}
