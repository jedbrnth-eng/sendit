shader_type spatial;
// Damp night asphalt. World-space UVs (seamless across streamed chunks), a low-frequency
// puddle mask plus wetter wheel ruts in every lane: wet areas go dark, near-mirror smooth and
// flat-normalled so SSR and the lamp speculars stretch into long streaks toward the camera.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.5, 0.53);
uniform float tile_m = 6.0;
uniform float wetness = 0.55;        // 0 dry .. 1 soaked
uniform float puddle_scale = 0.07;   // puddle noise frequency (1/m)
uniform float lane0 = 1.6;           // x of first lane edge (RoadSpec.MEDIAN_HALF + INNER_SHOULDER)
uniform float lane_w = 3.7;
uniform float dry_rough = 0.62;
uniform float wet_rough = 0.05;

varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 3.3) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile_m;
	vec3 base = texture(albedo_tex, uv).rgb * tint;
	float r_tex = texture(rough_tex, uv).r;

	// Puddles: stretched along the road so they read as long sheens at speed.
	float p = fbm(wpos.xz * vec2(puddle_scale, puddle_scale * 0.35));
	float puddle = smoothstep(0.52, 0.66, p);
	// Wheel ruts: two polished bands per lane, 0.9 m either side of lane centre.
	float lx = fract((abs(wpos.x) - lane0) / lane_w) * lane_w;
	float rut = max(exp(-pow((lx - 0.95) / 0.38, 2.0)), exp(-pow((lx - 2.75) / 0.38, 2.0)));
	rut *= step(lane0, abs(wpos.x)) * step(abs(wpos.x), lane0 + lane_w * 4.0);
	float wet = clamp(wetness * (0.45 + 0.55 * rut) + puddle, 0.0, 1.0);

	ALBEDO = base * mix(1.0, 0.45, wet);
	ROUGHNESS = mix(dry_rough * (0.75 + 0.5 * r_tex), wet_rough, wet);
	SPECULAR = 0.5;
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), wet * 0.85);
	NORMAL_MAP_DEPTH = 1.0;
}
