# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name EngineProfiles
## Engine sound profiles (loops made by tools/audio/synth_engine.py) and which car uses which.
## Kept here, not in CarCatalog, so garage edits never collide with sound: a catalog spec may
## still name one with an optional "engine" field, which wins.

## RPM each loop was rendered at (must match synth_engine.py RPMS).
const RPM_POINTS := [1000.0, 1900.0, 2900.0, 3900.0, 5000.0, 6200.0, 7500.0]
const DIR := "engine/"
## crackle: overrun pops 0..1, turbo: whistle/blow-off 0..1, whine: straight-cut gear whine 0..1.
const PROFILES := {
	"v8": {"crackle": 1.0, "turbo": 0.0, "whine": 0.25},
	"i6t": {"crackle": 0.35, "turbo": 1.0, "whine": 0.2},
	"rotary": {"crackle": 0.85, "turbo": 0.45, "whine": 0.15},
}
const BY_CAR := {
	"voltage": "v8", "naga": "v8", "naga_xr": "v8", "kaze": "i6t", "kaiju": "i6t",
	"rotor": "rotary", "soi_rocket": "rotary",
}
const DEFAULT := "v8"


static func for_car(id: String, spec: Dictionary = {}) -> String:
	var p := String(spec.get("engine", BY_CAR.get(id, DEFAULT)))
	return p if PROFILES.has(p) else DEFAULT


static func params(profile: String) -> Dictionary:
	return PROFILES.get(profile, PROFILES[DEFAULT])


## Path under assets/sfx/ of loop `i` (RPM_POINTS index), on-load or overrun.
static func loop_file(profile: String, i: int, on_load: bool) -> String:
	return "%s%s_%d_%s.wav" % [DIR, profile, int(RPM_POINTS[i]), "on" if on_load else "off"]


static func loop_files() -> Array[String]:
	var out: Array[String] = []
	for p in PROFILES:
		for i in RPM_POINTS.size():
			out.append(loop_file(p, i, true))
			out.append(loop_file(p, i, false))
	return out
