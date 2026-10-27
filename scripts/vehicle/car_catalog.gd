# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarCatalog
## The garage: every drivable vehicle, its model, hitbox and (modest) handling differences.
## Models are built by tools/blender/*.py (fictional brands only). Unit-tested by
## tests/test_car_catalog.gd. Selection order: in-session choice (car select screen) >
## `--car=<id>` launch arg > last choice saved in user://garage.cfg > DEFAULT_ID.

const DEFAULT_ID := "voltage"

## hitbox = collision half extents (x half width without mirrors, z half length), metres. It must
## cover the body measured from the mesh (CarModel body_half_width; tests/test_contacts_yaw.gd).
## roll = body roll per unit steer at speed (negative leans into the turn, like a bike).
## scrape_crash_kmh = barrier impact speed that becomes a crash; crash_keep scales speed kept.
## Optional mirror anchors (car space, car faces -Z): "mirror_rear" (rear-view camera) and
## "mirror_side" (left mirror; the right is its x-mirror). Omitted = derived from length, hitbox,
## the model's measured half extents and the hood-cam height (MirrorConfig.anchors).
const VEHICLES := [
	{
		"id": "voltage", "name": "VOLTAGE GT", "tagline": "Lime-and-black hypercoupe. The benchmark.",
		"model": "res://assets/cars/voltage/voltage_gt.glb", "length": 4.55, "wheels": 4,
		"hitbox": Vector2(1.18, 2.29),  # body sides 1.17 m (mirrors 1.21, front tyres 1.31 excluded)
		"max_kmh": 310.0, "accel": 9.5, "steer_rate": 1.9, "brake_decel": 16.0,
		"scrape_crash_kmh": 30.0, "crash_keep": 1.0, "roll": 0.045,
		"paints": {"Paint Voltage": Color(0.42, 0.95, 0.05), "Gloss Black": Color(0.02, 0.022, 0.026)},
		"coat": [], "signature": true, "hood_cam": Vector3(0, 1.18, -1.05), "cam_lift": 0.0, "cam_scale": 1.0, "engine_pitch": 1.0,
	},
	{
		"id": "naga", "name": "NAGA X", "tagline": "Slammed widebody street pickup. Heavy, wide, unbothered.",
		"model": "res://assets/cars/naga/naga_x.glb", "length": 5.42, "wheels": 4,
		"hitbox": Vector2(1.05, 2.71),
		"max_kmh": 285.0, "accel": 8.6, "steer_rate": 1.7, "brake_decel": 14.5,
		"scrape_crash_kmh": 38.0, "crash_keep": 1.15, "roll": 0.07,
		"paints": {}, "coat": ["Wrap Naga", "Gloss Black"], "signature": false,
		"hood_cam": Vector3(0, 1.42, -1.5), "cam_lift": 0.35, "cam_scale": 1.05, "engine_pitch": 0.85,
	},
	{
		"id": "kaze", "name": "KAZE RT", "tagline": "90s twin-turbo fastback. Fast, balanced, big wing.",
		"model": "res://assets/cars/kaze/kaze_rt.glb", "length": 4.64, "wheels": 4,  # Meshy model, tools/meshy/specs/kaze.py
		"hitbox": Vector2(1.18, 2.29),  # hero-width floor 1.18 (Meshy body 1.18 incl. mirrors)
		"max_kmh": 318.0, "accel": 9.9, "steer_rate": 1.95, "brake_decel": 16.0,
		"scrape_crash_kmh": 30.0, "crash_keep": 1.0, "roll": 0.05,
		"paints": {}, "coat": ["Paint Kaze"], "signature": false,
		"hood_cam": Vector3(0, 1.12, -0.95), "cam_lift": 0.0, "cam_scale": 1.0, "engine_pitch": 1.05,
	},
	{
		"id": "kaiju", "name": "KAIJU R", "tagline": "Boxy AWD super-coupe. Heavy, planted, hard to kill.",
		# same id as 0.2 so saved garages/unlocks stay valid; Meshy model, tools/meshy/specs/kaiju.py
		"model": "res://assets/cars/kaiju/kaiju_r.glb", "length": 4.74, "wheels": 4,
		"hitbox": Vector2(1.18, 2.37),  # Meshy body: mirrors 1.16, hero-width floor 1.18
		"max_kmh": 300.0, "accel": 9.7, "steer_rate": 1.7, "brake_decel": 17.0,
		"scrape_crash_kmh": 36.0, "crash_keep": 1.12, "roll": 0.035,
		"paints": {}, "coat": ["Paint Kaiju"], "signature": false,
		"hood_cam": Vector3(0, 1.2, -0.95), "cam_lift": 0.05, "cam_scale": 1.0, "engine_pitch": 0.92,
	},
	{
		"id": "rotor", "name": "ROTOR FX", "tagline": "Light rotary screamer. Twitchy, quick, fragile.",
		"model": "res://assets/cars/rotor/rotor_fx.glb", "length": 4.39, "wheels": 4,
		"hitbox": Vector2(1.18, 2.16),  # body 1.11 measured (rear haunch), mirrors 1.20
		"max_kmh": 295.0, "accel": 9.3, "steer_rate": 2.25, "brake_decel": 15.5,
		"scrape_crash_kmh": 25.0, "crash_keep": 0.9, "roll": 0.06,
		"paints": {}, "coat": ["Paint Rotor"], "signature": false,
		"hood_cam": Vector3(0, 1.05, -0.85), "cam_lift": 0.0, "cam_scale": 0.97, "engine_pitch": 1.3,
	},
	{
		# Meshy Pro image-to-3D, scrubbed of real badges and rebuilt for the game by tools/meshy/*.
		"id": "naga_xr", "name": "NAGA XR", "tagline": "Widebody Thai street pickup, full wrap. Big, planted, loud.",
		"model": "res://assets/cars/naga_xr/naga_xr.glb", "length": 5.4, "wheels": 4,
		"hitbox": Vector2(1.18, 2.7),
		"max_kmh": 298.0, "accel": 9.0, "steer_rate": 1.72, "brake_decel": 15.0,
		"scrape_crash_kmh": 40.0, "crash_keep": 1.18, "roll": 0.065,
		"paints": {}, "coat": ["Wrap NagaXR"], "signature": false,
		"hood_cam": Vector3(0, 1.5, -1.45), "cam_lift": 0.35, "cam_scale": 1.06, "engine_pitch": 0.82,
	},

]

## Shelved (too easy: it slips between cars). Model, generator and rider stay in the repo;
## move this entry back into VEHICLES to re-enable once the gap-slipping is balanced.
const SHELVED_SOI_ROCKET := {
		"id": "soi_rocket", "name": "SOI ROCKET", "tagline": "Underbone moped. Fits gaps nothing else can. Don't touch anything.",
		"model": "res://assets/cars/soi_rocket/soi_rocket.glb", "length": 1.92, "wheels": 2,
		"hitbox": Vector2(0.34, 0.96),
		"max_kmh": 255.0, "accel": 10.8, "steer_rate": 2.3, "brake_decel": 17.5,
		"scrape_crash_kmh": 22.0, "crash_keep": 0.8, "roll": -0.42,
		"paints": {}, "coat": ["Paint White", "Helmet Pink"], "signature": false,
		"hood_cam": Vector3(0, 1.74, -0.32), "cam_lift": 0.0, "cam_scale": 0.72, "engine_pitch": 1.45,
	}

## Set by the car select screen; a static so it survives reload_current_scene.
static var chosen := ""
static var _coats := {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for v in VEHICLES:
		out.append(v.id)
	return out


static func has(id: String) -> bool:
	return ids().has(id)


static func spec(id: String) -> Dictionary:
	for v in VEHICLES:
		if v.id == id:
			return v
	return VEHICLES[0]


static func index_of(id: String) -> int:
	return maxi(ids().find(id), 0)


## Pure selection rule (tested): choice > arg > saved > default, skipping unknown ids.
static func resolve(choice: String, arg: String, saved: String) -> String:
	for id in [choice, arg, saved]:
		if has(id):
			return id
	return DEFAULT_ID


static func current_id() -> String:
	var arg := String(LaunchArgs.get_value("car", ""))
	var id := resolve(chosen, arg, GarageStore.load_last())
	# A car still locked in the player's profile falls back to the hero (--car is a dev override).
	if id != arg and not ProfileStore.get_current().can_drive(id):
		return DEFAULT_ID
	return id


## 0..1 bars for the select screen, derived from the real handling numbers (not marketing).
static func stats(id: String) -> Dictionary:
	var s := spec(id)
	return {
		"SPEED": clampf(s.max_kmh / 320.0, 0.05, 1.0),
		"ACCEL": clampf(s.accel / 11.5, 0.05, 1.0),
		"HANDLING": clampf(s.steer_rate / 2.4, 0.05, 1.0),
		"TOUGHNESS": clampf(s.scrape_crash_kmh / 40.0 * (0.5 + 0.5 * s.crash_keep), 0.05, 1.0),
	}


## Build the vehicle visual with its finish (baked paints recoloured, clearcoat where wanted).
static func build(id: String, lamps := true) -> CarBody:
	var s := spec(id)
	var car := CarModel.build(s.model, s.length, 0.0, 0.0, Color(0, 0, 0, 0), lamps)
	for mat_name in s.paints:
		CarModel.paint_material(car, mat_name, s.paints[mat_name])
	for mat_name in s.coat:
		_coat(car, mat_name)
	return car


## Clearcoat a baked glTF material in place of the importer's copy (keeps its texture/colour).
static func _coat(n: Node, mat_name: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name == mat_name:
				var key := m.get_instance_id()
				if not _coats.has(key):
					var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					d.clearcoat_enabled = true
					d.clearcoat = 0.8
					d.clearcoat_roughness = 0.12
					_coats[key] = d
				mi.set_surface_override_material(i, _coats[key])
	for c in n.get_children():
		_coat(c, mat_name)


static func release() -> void:
	_coats.clear()
