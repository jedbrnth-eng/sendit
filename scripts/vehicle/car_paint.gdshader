// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of SendIt: https://github.com/jedbrnth-eng/sendit

shader_type spatial;
// Player car paint: colour + finish (metallic/roughness/clearcoat, pearl hue shift, metal flake) and
// a procedural wrap pattern evaluated in car model space, so it needs no UVs and lines up across the
// separate door/hood/bumper meshes. Each MeshInstance3D passes its transform to the model root in
// xf_x/xf_y/xf_z (instance uniforms). Model space: x = width, y = up, z = length (front = +z).

uniform vec3 albedo : source_color = vec3(0.4, 0.9, 0.05);
uniform bool use_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tex_tint : source_color = vec3(1.0);
uniform float metallic = 0.45;
uniform float roughness = 0.3;
uniform float coat = 0.7;
uniform float pearl = 0.0;
uniform float flake = 0.0;
uniform int pattern = 0;
uniform vec3 accent : source_color = vec3(0.02);
uniform float half_len = 2.3;
uniform float half_w = 1.0;
uniform float ground = 0.0;
uniform float height = 1.2;

instance uniform vec4 xf_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 xf_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 xf_z = vec4(0.0, 0.0, 1.0, 0.0);

varying vec3 car_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	vec4 v = vec4(VERTEX, 1.0);
	car_pos = vec3(dot(xf_x, v), dot(xf_y, v), dot(xf_z, v));
}

// 0 = paint, 1 = accent, 0.5 = halfway (pixel camo mid tone).
float pattern_mask(vec3 p) {
	float u = p.x / half_w;                  // -1..1 across
	float v = p.z / half_len;                // -1 rear .. +1 front
	float h = (p.y - ground) / height;       // 0 ground .. 1 roof
	float au = abs(u);
	if (pattern == 1) {   // twin stripes nose to tail
		return step(0.07, au) * step(au, 0.2);
	} else if (pattern == 2) {   // one wide centre stripe with thin pinstripes
		return step(au, 0.13) + step(0.17, au) * step(au, 0.2);
	} else if (pattern == 3) {   // side flash: a rising diagonal band down each flank
		float c = 0.32 + 0.16 * v;
		float band = step(c, h) * step(h, c + 0.11) * step(-0.75, v) * step(v, 0.85);
		return band * step(0.72, au);
	} else if (pattern == 4) {   // chequered hood
		vec2 cell = floor(vec2(p.x, p.z) / 0.22);
		float chk = mod(cell.x + cell.y, 2.0);
		return chk * step(0.5, h) * step(0.3, v);
	} else if (pattern == 5) {   // pixel camo: 3-tone cube cells
		float n = hash3(floor(p / 0.28));
		return n < 0.33 ? 0.0 : (n < 0.66 ? 0.5 : 1.0);
	} else if (pattern == 6) {   // tiger stripes
		float w = sin(p.z * 7.0 + 2.2 * sin(p.y * 4.0 + p.x * 1.5) + 1.3 * sin(p.x * 3.1));
		return smoothstep(0.55, 0.7, w);
	} else if (pattern == 7) {   // two-tone: lower body in the accent colour
		return 1.0 - smoothstep(0.37, 0.39, h);
	}
	return 0.0;
}

void fragment() {
	vec3 base = albedo;
	if (use_tex) {
		base = texture(tex, UV).rgb * tex_tint;
	}
	float m = pattern_mask(car_pos);
	vec3 col = mix(base, accent, clamp(m, 0.0, 1.0));
	float rough = roughness;
	float metal = metallic;
	if (pearl > 0.0) {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		vec3 shifted = mix(col.gbr, col.brg, 0.5) * 0.9 + 0.1;
		col = mix(col, shifted, pearl * fres * 0.85);
	}
	if (flake > 0.0) {
		float s = hash3(floor(car_pos * 140.0));
		float spark = step(1.0 - 0.06 * flake, s);
		rough = mix(rough, 0.02, spark);
		metal = mix(metal, 1.0, spark);
		col = mix(col, col * 1.6 + 0.08, spark * 0.6);
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.12;
}
