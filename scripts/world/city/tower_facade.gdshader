shader_type spatial;
render_mode fog_disabled;
// Night curtain-wall towers matched to the Shanghai HDRI. Dark blue-grey glass that mirrors the
// sky radiance (the HDRI city), lit office floors with per-floor variation, slab light bands, LED
// pinstripes, lit podium storefronts and LED crowns. Our own atmospheric haze replaces the depth
// fog so mid towers sit in the photo's indigo/lavender horizon glow, and towers far down the road
// dissolve (screen-door) so the HDRI skyline stays the hero instead of being walled off.
// Per-vertex data from TowerKit: see tower_kit.gd header.

uniform vec3 glass_color : source_color = vec3(0.012, 0.016, 0.026);
uniform vec3 haze_low : source_color = vec3(0.2, 0.19, 0.3);   // HDRI horizon glow (x energy)
uniform vec3 haze_high : source_color = vec3(0.09, 0.085, 0.21); // HDRI sky a few degrees up
uniform float haze_density = 0.0024;
uniform float haze_max = 0.8;
uniform float fade_start = 380.0;  // m from camera: begin dissolving into the panorama
uniform float fade_end = 560.0;
uniform float floor_h = 3.7;
uniform float bay_w = 1.5;
uniform float window_energy = 0.65;
uniform float crown_energy = 1.8;

varying vec4 v_win;
varying vec4 v_c0;
varying vec4 v_c1;
varying vec3 wpos;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Anti-aliased [a, b] window inside a unit cell coordinate x (w = filter width in cells).
float band(float a, float b, float x, float w) {
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(p) % 4;
	int i = q.x + q.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void vertex() {
	v_win = COLOR;
	v_c0 = CUSTOM0;
	v_c1 = CUSTOM1;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float seed = v_c0.x;
	int style = int(v_c0.y + 0.5);
	float top = v_c0.z;
	float tier_top = v_c0.w;
	vec3 wcol = v_win.rgb;
	float lit_ratio = v_win.a;
	vec3 crown = v_c1.rgb;
	float crown_h = v_c1.a;
	float y = UV.y;
	float u = UV.x;

	// Derivatives first: they are undefined after a non-uniform discard.
	vec2 cell = vec2(u / bay_w, y / floor_h);
	vec2 fw = fwidth(cell);
	float fw_fin = fwidth(u / 1.2);
	float fw_line = fwidth(y / 1.6);
	float d = length(VERTEX);
	if (smoothstep(fade_start, fade_end, d) > bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	// 0 when a cell spans many pixels, 1 when it is sub-pixel: then use the pattern's average.
	float far = smoothstep(0.25, 0.7, max(fw.x, fw.y));
	float floor_rand = h2(vec2(id.y, seed));
	float win_rand = h2(id + seed * 3.1);
	// Per-floor tint: office floors drift between the base colour and a cooler/warmer cast.
	vec3 tint = mix(wcol, wcol * vec3(0.85, 0.95, 1.1), h2(vec2(id.y, seed + 2.0)));

	vec3 emit = vec3(0.0);
	float glass = 1.0; // 1 = reflective curtain wall, 0 = matte
	float rough = mix(0.02, 0.08, h1(seed));

	if (style == 0) { // OFFICE: dark curtain wall, lit floors where most bays glow, a few lit bays elsewhere
		float pane = band(0.05, 0.95, f.x, fw.x) * band(0.22, 0.9, f.y, fw.y);
		pane = mix(pane, 0.6, far);
		float floor_lit = step(1.0 - lit_ratio, floor_rand);
		float bay_lit = step(mix(0.93, 0.2, floor_lit), win_rand);
		float on = mix(0.015, 1.0, mix(bay_lit, mix(0.07, 0.8, floor_lit), far));
		float ceiling = mix(0.7, 1.0, smoothstep(0.3, 0.9, f.y));
		float bright = mix(0.5, 1.1, h2(vec2(id.y, seed + 7.0))) * mix(0.75, 1.0, win_rand);
		emit = tint * pane * on * mix(ceiling, 0.85, far) * bright * window_energy;
	} else if (style == 1) { // BANDS: bright slab-edge strip each floor, faint interiors
		float slab = mix(band(0.0, 0.14, f.y, fw.y), 0.14, far);
		float interior = mix(band(0.2, 0.95, f.y, fw.y) * step(1.0 - lit_ratio * 0.4, win_rand), 0.4 * lit_ratio, far) * 0.25;
		emit = tint * (slab * 1.8 + interior) * window_energy * mix(0.7, 1.1, floor_rand);
	} else if (style == 2) { // WARM: residential punched windows, gold-floodlit base
		float hole = mix(band(0.3, 0.7, f.x, fw.x) * band(0.3, 0.76, f.y, fw.y), 0.18, far);
		float on = mix(step(1.0 - lit_ratio, win_rand), lit_ratio, far);
		// Curtains / lamps: brightness and a warm-to-TV-blue spread per window.
		float tv = step(0.86, h1(win_rand * 9.0));
		vec3 c = mix(wcol, vec3(0.55, 0.7, 1.0), tv) * mix(0.3, 1.1, h1(win_rand * 5.0));
		c *= mix(0.75, 1.0, smoothstep(0.3, 0.76, f.y));
		emit = c * hole * on * window_energy * 1.3;
		glass = 0.35 + 0.65 * hole;
		emit += vec3(1.0, 0.72, 0.38) * 0.18 * exp(-max(y, 0.0) / 5.0);
	} else if (style == 3) { // LED: vertical pinstripes with a slow travelling wave
		float pin = mix(band(0.44, 0.56, f.x, fw.x), 0.12, far);
		float wave = 0.55 + 0.45 * sin(y * 0.05 - TIME * 0.6 + seed * 4.0);
		float faint = mix(band(0.2, 0.95, f.y, fw.y) * step(1.0 - lit_ratio * 0.5, win_rand), 0.3 * lit_ratio, far) * 0.25;
		emit = tint * (pin * wave * 2.4 + faint) * window_energy;
	} else if (style == 4) { // PODIUM: bright storefront band, signage panels, dark upper wall
		float shop = 1.0 - smoothstep(4.0, 5.0, y);
		float panel_id = floor(u / 9.0);
		float panel = step(0.55, h2(vec2(panel_id, seed))) * step(6.5, y) * (1.0 - step(tier_top - 1.5, y))
			* step(0.1, fract(u / 9.0)) * step(fract(u / 9.0), 0.9);
		vec3 sign_col = mix(crown, wcol, 0.5 + 0.5 * sin(u * 0.2 + y * 0.3 + TIME * 0.4 + panel_id));
		float mull = mix(band(0.12, 0.92, fract(u / 2.4), fw.x * 0.6), 0.8, far);
		float shop_lit = mix(0.25, 1.0, step(0.35, h2(vec2(floor(u / 7.0), seed))));  // some shops shut
		emit = vec3(1.0, 0.84, 0.62) * shop * mull * shop_lit * 0.6 + sign_col * panel * 0.9;
		glass = 0.5;
	} else if (style == 5) { // SPIRE: lit metal mast
		emit = crown * 0.5;
		glass = 0.0;
		rough = 0.4;
	} else { // ROOF
		glass = 0.0;
		rough = 0.8;
	}

	// LED crown on the top `crown_h` metres of the tower, plus a thin strip at every setback.
	if (style <= 3) {
		float has_crown = step(0.5, crown_h);
		float in_crown = step(top - crown_h, y) * has_crown;
		// LED fins and ledger lines on dark glass, brightening toward the top: kept below the
		// tonemap shoulder so magenta / violet stay saturated instead of washing to pastel.
		float t = clamp((y - (top - crown_h)) / max(crown_h, 0.01), 0.0, 1.0);
		float fins = band(0.0, 0.18, fract(u / 1.2), fw_fin);
		float lines = band(0.0, 0.12, fract(y / 1.6), fw_line);
		float led = mix(max(fins, lines * 0.8), 0.3, far);
		float pulse = 0.8 + 0.2 * sin(TIME * 0.8 + seed * 2.0);
		emit = mix(emit, crown * (led * mix(0.35, 1.0, t) + 0.04) * pulse * crown_energy, in_crown);
		float strip = 1.0 - smoothstep(0.35, 0.6, tier_top - y);
		emit += crown * strip * crown_energy * 0.6 * has_crown;
		// Corner pins on band / LED towers.
		float edge = min(UV2.x, UV2.y - UV2.x);
		emit += crown * (1.0 - smoothstep(0.15, 0.45, edge)) * 1.2 * float(style == 1 || style == 3);
	}

	// Atmospheric perspective toward the HDRI horizon colour.
	float haze = haze_max * (1.0 - exp(-d * haze_density));
	haze *= mix(1.0, 0.6, smoothstep(20.0, 220.0, wpos.y));
	vec3 haze_col = mix(haze_low, haze_high, smoothstep(10.0, 260.0, wpos.y));

	ALBEDO = glass_color * (1.0 - haze);
	// Dielectric glass: faint face-on, mirror-bright at grazing angles (the HDRI city in it).
	METALLIC = 0.0;
	ROUGHNESS = mix(0.8, rough, glass);
	SPECULAR = mix(0.04, 0.35, glass) * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.8) + haze_col * haze;
}
