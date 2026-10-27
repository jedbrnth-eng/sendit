# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PoliceFleet
## Heat-gated police models (Meshy, tools/meshy/specs/cop_*.py). At heat 1-2 the fleet is exactly
## CopCar.MODELS; higher heat adds the interceptor SUV, then the pursuit coupe. Same row shape as
## CopCar.MODELS ([path, length m, collision width m]) plus the minimum heat. Fictional liveries,
## no light bar in the mesh: CopCar puts its LightBar on the roof.

const MODELS := [
	["res://assets/traffic/police_meshy/cop_suv.glb", 5.0, 2.0, 3],
	["res://assets/traffic/police_meshy/cop_coupe.glb", 4.6, 1.95, 4],
]


## Model rows available at `heat`: the base patrol cars first (index-stable at low heat), then
## the heat-gated ones.
static func pool(base: Array, heat: int) -> Array:
	var out := base.duplicate()
	for m in MODELS:
		if heat >= int(m[3]):
			out.append([m[0], m[1], m[2]])
	return out
