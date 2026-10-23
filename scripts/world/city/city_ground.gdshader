shader_type spatial;
render_mode fog_disabled;
// Ground beside the highway: dark damp city blocks cut by a street grid lined with sodium and
// white LED street lights, fading into the same horizon haze as the towers and the HDRI so the
// ground meets the panorama without a black band. Pattern is anti-aliased: sub-pixel lights
// average out into a soft glow instead of sparkling.

uniform vec3 base_color : source_color = vec3(0.02, 0.022, 0.028);
uniform vec3 haze_color : source_color = vec3(0.13, 0.11, 0.2);
uniform float haze_density = 0.0028;
uniform float haze_max = 0.85;
uniform float block = 70.0;        // street grid pitch (m)
uniform float street_w = 10.0;
uniform float light_pitch = 22.0;  // street light spacing along a street (m)
uniform float lamp_energy = 5.0;

varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Street lights on both kerbs of one street: `a` runs along the street, `b` across it (metres
// inside the block cell). A lamp never shrinks below about a pixel, so the far grid still reads
// as a carpet of points rather than vanishing or sparkling.
vec3 street_lights(float a, float b, vec2 cell_id, float fw) {
	float r = max(0.45, fw * 0.8);
	float energy = lamp_energy * sqrt(0.45 / r);
	float kerb = min(abs(b - street_w * 0.1), abs(b - street_w * 0.9));
	float along = abs(fract(a / light_pitch) - 0.5) * light_pitch;
	float lamp = (1.0 - smoothstep(r * 0.5, r, kerb)) * (1.0 - smoothstep(r * 0.5, r, along));
	vec3 col = mix(vec3(1.0, 0.62, 0.3), vec3(0.85, 0.92, 1.0), step(0.55, h2(cell_id)));
	return col * lamp * energy;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 cell = p / block;
	vec2 id = floor(cell);
	vec2 q = fract(cell) * block;  // metres inside the cell
	float fw = max(fwidth(p.x), fwidth(p.y));
	vec3 emit = street_lights(q.y, q.x, id, fw) * step(q.x, street_w)
		+ street_lights(q.x, q.y, id + 17.0, fw) * step(q.y, street_w);
	// Lit plazas / car parks: a faint warm or cool pool in some blocks.
	float plaza = step(0.75, h2(id + 3.0)) * step(street_w, q.x) * step(street_w, q.y);
	emit += mix(vec3(0.5, 0.35, 0.2), vec3(0.3, 0.4, 0.6), h2(id + 9.0)) * plaza * 0.015;

	float d = length(VERTEX);
	float haze = haze_max * (1.0 - exp(-d * haze_density));
	ALBEDO = base_color * (1.0 - haze);
	ROUGHNESS = 0.35;  // damp: the towers and HDRI smear into it
	SPECULAR = 0.4 * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.85) + haze_color * haze;
}
