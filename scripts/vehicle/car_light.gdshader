shader_type spatial;
// Lamp lens: the model's own head/tail-light geometry, glowing. `boost` (per instance) brightens brake lights.
render_mode cull_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.04, 0.02);
uniform float energy = 4.0;
uniform float boost_gain = 2.5;
instance uniform float boost = 0.0;

void fragment() {
	ALBEDO = color * 0.2;
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
	EMISSION = color * energy * (1.0 + boost * boost_gain);
}
