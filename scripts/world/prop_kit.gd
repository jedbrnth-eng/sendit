# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PropKit
## Meshy-made props (generated + cleaned by tools/meshy/meshy_props.py + prop_build.py, catalogue
## tools/meshy/props.py). Each GLB is game-ready: metres, origin bottom-centre, front toward -Z,
## one material named Prop_<id>. Used by ShoulderHazards (hazard visuals) and RoadsideProps.

const DIR := "res://assets/props/"
## id -> max triangles (the catalogue budget; tests hold every file to it).
const TRIS := {
	"cone_a": 1200, "cone_b": 1200, "barrel": 2000, "tyre": 1500, "crate": 1500, "plank": 1200,
	"ladder": 1500, "pallet": 2500, "water": 2500, "jersey": 1500, "aframe": 2500, "triangle": 800,
	"hulk": 9000,
	"tuktuk": 6000, "signal_head": 600, "palm": 3000, "bus_shelter": 3000, "moto_stand": 3000,
	"shrine": 3000, "food_stall": 3000, "pier": 1200,
}
## Vehicles get the vehicle file budget (4 MB), everything else the prop budget (1.5 MB).
const VEHICLES := ["hulk", "tuktuk"]
## Props whose texture also drives emission (energy): LED arrows glow; road-safety kit gets a low
## value standing in for retro-reflective sheeting catching headlights (the old primitives did too).
const GLOW := {"signal_head": 6.0, "cone_a": 0.45, "cone_b": 0.45, "barrel": 0.45, "aframe": 0.5,
	"triangle": 1.2, "water": 0.3}

static var _cache := {}  # id -> PackedScene
static var _glow_mats := {}


static func path(id: String) -> String:
	return DIR + id + ".glb"


static func has(id: String) -> bool:
	return TRIS.has(id) and ResourceLoader.exists(path(id))


## A fresh instance of prop `id` (Node3D at the origin). Null when the file is missing.
static func make(id: String, shadows := true) -> Node3D:
	if not _cache.has(id):
		if not has(id):
			return null
		_cache[id] = load(path(id))
	var n := (_cache[id] as PackedScene).instantiate() as Node3D
	_setup(n, id, shadows)
	return n


static func _setup(n: Node, id: String, shadows: bool) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if GLOW.has(id) and mi.mesh:
			mi.material_override = _glow(id, mi.mesh.surface_get_material(0))
	for c in n.get_children():
		_setup(c, id, shadows)


static func _glow(id: String, src: Material) -> Material:
	if _glow_mats.has(id):
		return _glow_mats[id]
	var m := StandardMaterial3D.new()
	if src is BaseMaterial3D:
		m.albedo_texture = (src as BaseMaterial3D).albedo_texture
		m.emission_texture = m.albedo_texture
	m.emission_enabled = true
	m.emission_energy_multiplier = GLOW[id]
	m.roughness = 0.4
	_glow_mats[id] = m
	return m


## Drop cached scenes/materials (statics outlive the tree and trip the exit leak check).
static func release() -> void:
	_cache.clear()
	_glow_mats.clear()
