shader_type spatial;
// Red aviation obstruction light: slow blink, phase per instance so the skyline twinkles.
render_mode unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.06, 0.03);
uniform float energy = 14.0;
instance uniform float phase = 0.0;
varying float v_phase;

void vertex() {
	// MultiMesh instances: derive a stable phase from the instance id.
	v_phase = phase + fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
}

void fragment() {
	float t = fract(TIME * 0.6 + v_phase);
	float on = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.35, 0.5, t));
	ALBEDO = color * energy * (0.08 + 0.92 * on);
}
