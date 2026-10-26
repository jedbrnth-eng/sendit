# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name UnlockCatalog
## Everything the player can earn: cars (unlocked by level) and customisation parts per slot.
## An item has `level` (gate: needs that player level) and `price` (credits; 0 = free once the level
## is reached). Level 1 + price 0 = owned from the start (one free default per slot). Pure data,
## unit-tested by tests/test_progression.gd. Names are fictional; no real brands.
##
## Item data by slot:
##   paint      color (Color; alpha 0 = factory finish of that car)
##   finish     metallic, roughness, coat (clearcoat), pearl (0..1 hue-shift sheen), flake
##   pattern    pattern (int, see car_paint.gdshader)
##   wheels     color, metallic, roughness, glow (lip emission colour; alpha 0 = none)
##   underglow  color (alpha 0 = off), cycle (rainbow)
##   headlights color
##   flame      color, cycle
##   engine     pitch (engine pitch multiplier)
##   plate      bg, fg

const SLOTS := ["car", "paint", "finish", "pattern", "wheels", "underglow", "headlights", "flame", "engine", "plate"]
const TABS := {
	"CAR": ["car"],
	"PAINT": ["paint", "finish", "pattern"],
	"WHEELS": ["wheels"],
	"LIGHTS": ["headlights", "underglow"],
	"EXTRAS": ["flame", "engine", "plate"],
}
const SLOT_NAMES := {"car": "CAR", "paint": "COLOUR", "finish": "FINISH", "pattern": "WRAP", "wheels": "RIMS",
	"underglow": "UNDERGLOW", "headlights": "HEADLIGHTS", "flame": "EXHAUST FLAME", "engine": "ENGINE TONE", "plate": "PLATE"}

const ITEMS := [
	# --- cars ---
	{"id": "car_voltage", "slot": "car", "name": "VOLTAGE GT", "level": 1, "price": 0, "car": "voltage"},
	{"id": "car_naga", "slot": "car", "name": "NAGA X", "level": 3, "price": 0, "car": "naga"},
	{"id": "car_kaze", "slot": "car", "name": "KAZE RT", "level": 5, "price": 2500, "car": "kaze"},
	{"id": "car_kaiju", "slot": "car", "name": "KAIJU R", "level": 10, "price": 5000, "car": "kaiju"},
	{"id": "car_rotor", "slot": "car", "name": "ROTOR FX", "level": 15, "price": 8000, "car": "rotor"},
	# --- paint colour ---
	{"id": "paint_factory", "slot": "paint", "name": "Factory", "level": 1, "price": 0, "color": Color(0, 0, 0, 0)},
	{"id": "paint_black", "slot": "paint", "name": "Midnight Black", "level": 1, "price": 400, "color": Color(0.012, 0.012, 0.016)},
	{"id": "paint_white", "slot": "paint", "name": "Arctic White", "level": 1, "price": 400, "color": Color(0.85, 0.87, 0.9)},
	{"id": "paint_red", "slot": "paint", "name": "Pulse Red", "level": 1, "price": 600, "color": Color(0.75, 0.02, 0.03)},
	{"id": "paint_cobalt", "slot": "paint", "name": "Cobalt", "level": 1, "price": 600, "color": Color(0.03, 0.15, 0.75)},
	{"id": "paint_yellow", "slot": "paint", "name": "Sunburst", "level": 1, "price": 800, "color": Color(1.0, 0.72, 0.02)},
	{"id": "paint_tuktuk", "slot": "paint", "name": "Tuk-Tuk Orange", "level": 2, "price": 0, "color": Color(1.0, 0.36, 0.02)},
	{"id": "paint_magma", "slot": "paint", "name": "Magma", "level": 4, "price": 900, "color": Color(0.9, 0.12, 0.02)},
	{"id": "paint_grape", "slot": "paint", "name": "Grape Soda", "level": 7, "price": 1200, "color": Color(0.32, 0.05, 0.62)},
	{"id": "paint_pink", "slot": "paint", "name": "Hot Pink", "level": 9, "price": 1200, "color": Color(1.0, 0.1, 0.48)},
	{"id": "paint_mint", "slot": "paint", "name": "Mint Chip", "level": 12, "price": 1500, "color": Color(0.35, 0.95, 0.72)},
	{"id": "paint_gunmetal", "slot": "paint", "name": "Gunmetal", "level": 15, "price": 1500, "color": Color(0.12, 0.13, 0.15)},
	{"id": "paint_bloodorange", "slot": "paint", "name": "Blood Orange", "level": 18, "price": 1800, "color": Color(0.6, 0.06, 0.02)},
	{"id": "paint_uv", "slot": "paint", "name": "Ultraviolet", "level": 22, "price": 2400, "color": Color(0.42, 0.1, 1.0)},
	{"id": "paint_gold", "slot": "paint", "name": "Gold Rush", "level": 26, "price": 3000, "color": Color(0.85, 0.6, 0.12)},
	{"id": "paint_phantom", "slot": "paint", "name": "Phantom", "level": 30, "price": 4000, "color": Color(0.05, 0.02, 0.09)},
	{"id": "paint_prism", "slot": "paint", "name": "Prism White", "level": 40, "price": 6000, "color": Color(0.95, 0.95, 1.0)},
	# --- finish ---
	{"id": "finish_gloss", "slot": "finish", "name": "Gloss", "level": 1, "price": 0, "metallic": 0.45, "roughness": 0.3, "coat": 0.7, "pearl": 0.0, "flake": 0.0},
	{"id": "finish_matte", "slot": "finish", "name": "Matte", "level": 1, "price": 500, "metallic": 0.05, "roughness": 0.78, "coat": 0.0, "pearl": 0.0, "flake": 0.0},
	{"id": "finish_metallic", "slot": "finish", "name": "Metallic", "level": 3, "price": 800, "metallic": 0.85, "roughness": 0.28, "coat": 0.6, "pearl": 0.0, "flake": 0.35},
	{"id": "finish_satin", "slot": "finish", "name": "Satin", "level": 6, "price": 1000, "metallic": 0.35, "roughness": 0.55, "coat": 0.15, "pearl": 0.0, "flake": 0.0},
	{"id": "finish_pearl", "slot": "finish", "name": "Pearl", "level": 10, "price": 1800, "metallic": 0.4, "roughness": 0.22, "coat": 0.9, "pearl": 0.8, "flake": 0.1},
	{"id": "finish_chrome", "slot": "finish", "name": "Liquid Chrome", "level": 20, "price": 4000, "metallic": 1.0, "roughness": 0.06, "coat": 0.4, "pearl": 0.0, "flake": 0.0},
	{"id": "finish_flake", "slot": "finish", "name": "Glitter Flake", "level": 35, "price": 5000, "metallic": 0.8, "roughness": 0.25, "coat": 1.0, "pearl": 0.3, "flake": 1.0},
	# --- wrap / stripes ---
	{"id": "pattern_none", "slot": "pattern", "name": "None", "level": 1, "price": 0, "pattern": 0},
	{"id": "pattern_twin", "slot": "pattern", "name": "Twin Stripes", "level": 1, "price": 800, "pattern": 1},
	{"id": "pattern_center", "slot": "pattern", "name": "Centre Stripe", "level": 1, "price": 900, "pattern": 2},
	{"id": "pattern_sideflash", "slot": "pattern", "name": "Side Flash", "level": 8, "price": 1400, "pattern": 3},
	{"id": "pattern_checker", "slot": "pattern", "name": "Finish Line", "level": 12, "price": 1600, "pattern": 4},
	{"id": "pattern_camo", "slot": "pattern", "name": "Pixel Camo", "level": 16, "price": 2200, "pattern": 5},
	{"id": "pattern_tiger", "slot": "pattern", "name": "Tiger", "level": 24, "price": 3000, "pattern": 6},
	{"id": "pattern_split", "slot": "pattern", "name": "Two-Tone Split", "level": 29, "price": 2600, "pattern": 7},
	# --- wheels ---
	{"id": "wheels_stock", "slot": "wheels", "name": "Stock", "level": 1, "price": 0, "color": Color(0, 0, 0, 0), "metallic": 0.0, "roughness": 0.0, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_black", "slot": "wheels", "name": "Matte Black", "level": 1, "price": 400, "color": Color(0.015, 0.015, 0.017), "metallic": 0.2, "roughness": 0.75, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_chrome", "slot": "wheels", "name": "Mirror Chrome", "level": 1, "price": 900, "color": Color(0.92, 0.92, 0.95), "metallic": 1.0, "roughness": 0.05, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_bronze", "slot": "wheels", "name": "Bronze", "level": 5, "price": 1100, "color": Color(0.55, 0.36, 0.14), "metallic": 0.9, "roughness": 0.3, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_white", "slot": "wheels", "name": "Gloss White", "level": 7, "price": 1200, "color": Color(0.85, 0.86, 0.88), "metallic": 0.1, "roughness": 0.25, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_neon", "slot": "wheels", "name": "Neon Lime", "level": 11, "price": 1800, "color": Color(0.03, 0.03, 0.035), "metallic": 0.6, "roughness": 0.3, "glow": Color(0.45, 1.0, 0.1)},
	{"id": "wheels_gold", "slot": "wheels", "name": "Gold", "level": 14, "price": 2200, "color": Color(0.95, 0.68, 0.22), "metallic": 1.0, "roughness": 0.18, "glow": Color(0, 0, 0, 0)},
	{"id": "wheels_ice", "slot": "wheels", "name": "Ice Neon", "level": 19, "price": 2600, "color": Color(0.03, 0.03, 0.035), "metallic": 0.6, "roughness": 0.3, "glow": Color(0.3, 0.8, 1.0)},
	{"id": "wheels_carbon", "slot": "wheels", "name": "Forged Carbon", "level": 27, "price": 2800, "color": Color(0.06, 0.06, 0.065), "metallic": 0.5, "roughness": 0.45, "glow": Color(1.0, 0.24, 0.52)},
	{"id": "wheels_platinum", "slot": "wheels", "name": "Platinum", "level": 50, "price": 8000, "color": Color(0.8, 0.82, 0.88), "metallic": 1.0, "roughness": 0.12, "glow": Color(0.9, 0.95, 1.0)},
	# --- underglow ---
	{"id": "glow_off", "slot": "underglow", "name": "Off", "level": 1, "price": 0, "color": Color(0, 0, 0, 0)},
	{"id": "glow_pink", "slot": "underglow", "name": "Hot Pink", "level": 1, "price": 900, "color": Color(1.0, 0.15, 0.55)},
	{"id": "glow_ice", "slot": "underglow", "name": "Ice Blue", "level": 1, "price": 900, "color": Color(0.25, 0.75, 1.0)},
	{"id": "glow_lime", "slot": "underglow", "name": "Acid Lime", "level": 1, "price": 1000, "color": Color(0.45, 1.0, 0.1)},
	{"id": "glow_purple", "slot": "underglow", "name": "Purple Haze", "level": 6, "price": 1100, "color": Color(0.55, 0.15, 1.0)},
	{"id": "glow_red", "slot": "underglow", "name": "Red Line", "level": 11, "price": 1200, "color": Color(1.0, 0.05, 0.05)},
	{"id": "glow_gold", "slot": "underglow", "name": "Honey Glow", "level": 13, "price": 1500, "color": Color(1.0, 0.7, 0.15)},
	{"id": "glow_white", "slot": "underglow", "name": "Moonlight", "level": 21, "price": 1500, "color": Color(0.85, 0.9, 1.0)},
	{"id": "glow_rainbow", "slot": "underglow", "name": "Rainbow Cycle", "level": 25, "price": 4000, "color": Color(1, 1, 1), "cycle": true},
	# --- headlights ---
	{"id": "head_stock", "slot": "headlights", "name": "Halogen Warm", "level": 1, "price": 0, "color": Color(1.0, 0.93, 0.8)},
	{"id": "head_ice", "slot": "headlights", "name": "Ice White", "level": 1, "price": 400, "color": Color(0.85, 0.95, 1.0)},
	{"id": "head_xenon", "slot": "headlights", "name": "Xenon Blue", "level": 1, "price": 700, "color": Color(0.55, 0.75, 1.0)},
	{"id": "head_amber", "slot": "headlights", "name": "Amber", "level": 1, "price": 800, "color": Color(1.0, 0.68, 0.15)},
	{"id": "head_lime", "slot": "headlights", "name": "Lime", "level": 10, "price": 1200, "color": Color(0.6, 1.0, 0.3)},
	{"id": "head_pink", "slot": "headlights", "name": "Pink", "level": 14, "price": 1400, "color": Color(1.0, 0.45, 0.75)},
	{"id": "head_purple", "slot": "headlights", "name": "Purple", "level": 20, "price": 1600, "color": Color(0.7, 0.45, 1.0)},
	{"id": "head_gold", "slot": "headlights", "name": "Champagne", "level": 28, "price": 1800, "color": Color(1.0, 0.82, 0.4)},
	# --- exhaust flame ---
	{"id": "flame_stock", "slot": "flame", "name": "Classic Orange", "level": 1, "price": 0, "color": Color(1.0, 0.45, 0.08)},
	{"id": "flame_blue", "slot": "flame", "name": "Blue Fire", "level": 4, "price": 0, "color": Color(0.2, 0.5, 1.0)},
	{"id": "flame_green", "slot": "flame", "name": "Toxic Green", "level": 8, "price": 1200, "color": Color(0.35, 1.0, 0.15)},
	{"id": "flame_pink", "slot": "flame", "name": "Pink Fire", "level": 12, "price": 1400, "color": Color(1.0, 0.2, 0.6)},
	{"id": "flame_purple", "slot": "flame", "name": "Purple Fire", "level": 17, "price": 1600, "color": Color(0.6, 0.2, 1.0)},
	{"id": "flame_white", "slot": "flame", "name": "White Hot", "level": 23, "price": 2500, "color": Color(0.95, 0.95, 1.0)},
	{"id": "flame_rainbow", "slot": "flame", "name": "Rainbow Fire", "level": 45, "price": 6000, "color": Color(1, 1, 1), "cycle": true},
	# --- engine tone ---
	{"id": "engine_stock", "slot": "engine", "name": "Stock", "level": 1, "price": 0, "pitch": 1.0},
	{"id": "engine_deep", "slot": "engine", "name": "Low & Slow", "level": 5, "price": 1000, "pitch": 0.86},
	{"id": "engine_scream", "slot": "engine", "name": "Track Scream", "level": 9, "price": 1500, "pitch": 1.12},
	{"id": "engine_rasp", "slot": "engine", "name": "Redline Rasp", "level": 18, "price": 2000, "pitch": 1.22},
	# --- plate style (text is free, profanity-filtered: see PlateText) ---
	{"id": "plate_stock", "slot": "plate", "name": "Classic White", "level": 1, "price": 0, "bg": Color(0.92, 0.92, 0.88), "fg": Color(0.05, 0.05, 0.08)},
	{"id": "plate_black", "slot": "plate", "name": "Blackout", "level": 3, "price": 300, "bg": Color(0.03, 0.03, 0.04), "fg": Color(0.92, 0.92, 0.95)},
	{"id": "plate_neon", "slot": "plate", "name": "Neon Pink", "level": 7, "price": 600, "bg": Color(0.06, 0.02, 0.08), "fg": Color(1.0, 0.3, 0.65)},
	{"id": "plate_gold", "slot": "plate", "name": "Gold Leaf", "level": 15, "price": 1200, "bg": Color(0.75, 0.55, 0.15), "fg": Color(0.08, 0.05, 0.02)},
]

static var _by_id := {}


static func _index() -> Dictionary:
	if _by_id.is_empty():
		for it in ITEMS:
			_by_id[it.id] = it
	return _by_id


static func has_item(id: String) -> bool:
	return _index().has(id)


static func get_item(id: String) -> Dictionary:
	return _index().get(id, {})


static func items(slot: String) -> Array:
	var out := []
	for it in ITEMS:
		if it.slot == slot:
			out.append(it)
	return out


## The free level-1 item of a slot (the "stock" part).
static func default_for(slot: String) -> String:
	for it in ITEMS:
		if it.slot == slot and int(it.level) == 1 and int(it.price) == 0:
			return it.id
	return ""


## Items whose level gate is in (from_level, to_level], in catalog order.
static func unlocked_between(from_level: int, to_level: int) -> Array:
	var out := []
	for it in ITEMS:
		if int(it.level) > from_level and int(it.level) <= to_level:
			out.append(it.id)
	return out


## "LVL 7" / "1,200 CR" / "LVL 7 · 1,200 CR" / "FREE".
static func requirement_text(it: Dictionary) -> String:
	var parts := []
	if int(it.level) > 1:
		parts.append("LVL %d" % int(it.level))
	if int(it.price) > 0:
		parts.append("%s CR" % _fmt(int(it.price)))
	return " · ".join(parts) if parts.size() > 0 else "FREE"


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
