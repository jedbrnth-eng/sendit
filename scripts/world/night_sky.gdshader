shader_type sky;
// City-night panorama above the horizon; below it, fade to dark ground haze so the HDRI's
// own ground (promenade, people) never shows past the end of our geometry.

uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform float energy = 0.55;
uniform float rotation = 0.0;
uniform float horizon_lift = 0.012;
uniform vec3 ground_color : source_color = vec3(0.012, 0.012, 0.018);
uniform vec3 haze_color : source_color = vec3(0.10, 0.07, 0.12);

void sky() {
	vec3 d = EYEDIR;
	float c = cos(rotation), s = sin(rotation);
	d.xz = mat2(vec2(c, -s), vec2(s, c)) * d.xz;
	float y = d.y + horizon_lift;
	vec2 uv = vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(y, -1.0, 1.0)) / PI);
	vec3 pano = texture(panorama, uv).rgb * energy;
	float above = smoothstep(-0.005, 0.03, y);
	float haze = exp(-abs(y) * 28.0);
	vec3 below = mix(ground_color, haze_color, haze);
	COLOR = mix(below, pano, above) + haze_color * haze * 0.35 * above;
}
