shader_type canvas_item;
// Full-screen post: speed-scaled radial blur and chromatic aberration at the edges only (the
// centre, where the player looks, stays sharp), faint radial speed lines, vignette, film grain.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount = 0.0;            // 0..1 speed intensity, driven by SpeedFx
uniform vec2 focus = vec2(0.5, 0.47);
uniform float blur = 0.035;
uniform float aberration = 0.0035;
uniform float vignette = 0.38;
uniform float grain = 0.03;
uniform float lines = 0.07;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 d = uv - focus;
	float r = length(d * aspect) / length(vec2(0.5) * aspect);   // 0 centre .. ~1 corners
	float edge = smoothstep(0.3, 0.95, r);

	// Radial blur toward the focus point.
	float k = blur * edge * amount;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		col += texture(screen, uv - d * k * float(i) / 7.0).rgb;
	}
	col /= 8.0;

	// Chromatic aberration grows with distance from centre and with speed.
	float ca = aberration * edge * (0.35 + 0.65 * amount);
	col.r = mix(col.r, texture(screen, uv + d * ca).r, 0.8);
	col.b = mix(col.b, texture(screen, uv - d * ca).b, 0.8);

	// Speed lines: sparse angular streaks flickering in the outer ring.
	float ang = atan(d.y * aspect.y, d.x * aspect.x);
	float seg = floor(ang * 90.0);
	float on = step(0.93, hash(vec2(seg, floor(TIME * 24.0))));
	col += vec3(0.85, 0.9, 1.0) * on * smoothstep(0.55, 1.0, r) * amount * lines;

	col *= 1.0 - vignette * smoothstep(0.45, 1.15, r);
	col += (hash(uv * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
