# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name MirrorConfig
## Mirror rules (pure, unit-tested by tests/test_mirrors.gd): modes, render/display sizes and the
## per-car camera anchors. Anchors are in car space (the car faces -Z, sits on y = 0); defaults
## derive from the catalog's length / hitbox half extents / hood-cam height, and a catalog entry
## may pin them with "mirror_rear" (Vector3) and "mirror_side" (left mirror, Vector3; the right
## one is its x-mirror).

enum { OFF, TOP, SIDES, ALL }
## Settings/menu labels, in M-key cycle order (OFF -> TOP ONLY -> SIDES ONLY -> ALL).
const MODE_NAMES := ["OFF", "TOP ONLY", "SIDES ONLY", "ALL"]
## settings.cfg schema: v1 stored 0 off / 1 rear-view / 2 all; v2 is the enum above.
const SETTINGS_VERSION := 2
const SIZE_NAMES := ["SMALL", "MEDIUM", "LARGE"]
const SIZE_SCALE := [0.8, 1.0, 1.2]
## Medium render targets: low-res on purpose (the mirrors are small and a bit soft anyway).
const RENDER_REAR := Vector2i(512, 192)
const RENDER_SIDE := Vector2i(256, 176)
## Medium on-screen sizes at 1080p (the HUD's design height).
const DISPLAY_REAR := Vector2(500, 170)
const DISPLAY_SIDE := Vector2(300, 196)
const HOOD_REAR_SCALE := 1.18
const SIDE_OUT := 0.14            # side mirror glass this far outside the body half width
const REAR_BACK := 0.2            # rear camera this far behind the tail (never sees its own car)


static func clamp_mode(m) -> int:
	return clampi(int(m), OFF, ALL)


static func clamp_size(s) -> int:
	return clampi(int(s), 0, SIZE_SCALE.size() - 1)


static func next_mode(m: int) -> int:
	return (clamp_mode(m) + 1) % MODE_NAMES.size()


## A saved "mirrors" value from a settings file of schema `version` -> today's mode.
static func migrate_mode(v, version: int) -> int:
	if version < 2:
		return [OFF, TOP, ALL][clampi(int(v), 0, 2)]
	return clamp_mode(v)


## --mirrors=off|top|sides|all (rear = top, for older scripts); -1 = not given or unknown.
static func parse_mode(s: String) -> int:
	match s.to_lower():
		"off", "0":
			return OFF
		"top", "rear", "1":
			return TOP
		"sides", "side", "2":
			return SIDES
		"all", "3":
			return ALL
	return -1


static func shows_rear(m: int) -> bool:
	return m == TOP or m == ALL


static func shows_sides(m: int) -> bool:
	return m == SIDES or m == ALL


## Update schedule: every shown mirror renders every frame (smooth; the old round-robin at
## 15-30 Hz looked choppy). The per-pass cost is cut instead: see Mirrors (no shadows, no glow,
## short far plane, skyline layer culled).
static func renders_on(kind: String, m: int, _frame: int) -> bool:
	return shows_rear(m) if kind == "rear" else shows_sides(m)


## Render-target size (pixels) for "rear" or "side" at a size option.
static func render_size(kind: String, size: int) -> Vector2i:
	var base := RENDER_REAR if kind == "rear" else RENDER_SIDE
	var k: float = SIZE_SCALE[clamp_size(size)]
	return Vector2i(int(round(base.x * k / 8.0)) * 8, int(round(base.y * k / 8.0)) * 8)


## On-screen size (1080p HUD units). The hood-cam rear-view sits bigger, like the real one.
static func display_size(kind: String, size: int, hood: bool) -> Vector2:
	var base := DISPLAY_REAR if kind == "rear" else DISPLAY_SIDE
	var k: float = SIZE_SCALE[clamp_size(size)]
	if hood and kind == "rear":
		k *= HOOD_REAR_SCALE
	return base * k


## Camera anchors in car space: {rear, left, right}. `model_half` = the built model's measured
## half extents (CarModel meta "half_extents", mirrors/fenders included) when known: the cameras
## then sit outside the widest/longest point of the real mesh, not just the hitbox.
static func anchors(spec: Dictionary, model_half := Vector2.ZERO) -> Dictionary:
	var half_len: float = float(spec.get("length", 4.5)) * 0.5
	var hb: Vector2 = spec.get("hitbox", Vector2(1.0, half_len))
	hb = Vector2(maxf(hb.x, model_half.x), maxf(hb.y, model_half.y))
	var eye: float = (spec.get("hood_cam", Vector3(0, 1.15, -1.0)) as Vector3).y
	var rear: Vector3 = spec.get("mirror_rear", Vector3(0.0, clampf(eye * 0.92, 0.7, 2.2), maxf(half_len, hb.y) + REAR_BACK))
	var side: Vector3
	if spec.has("mirror_side"):
		side = spec.mirror_side
		side.x = -absf(side.x)
	else:
		side = Vector3(-(hb.x + SIDE_OUT), clampf(eye * 0.8, 0.6, 1.9), -half_len * 0.18)
	return {"rear": rear, "left": side, "right": Vector3(-side.x, side.y, side.z)}


## Police cue (0..1): how strongly a lit cop at `rel` (car space, +z behind) should flash the
## frame of mirror `kind` ("rear"/"left"/"right"). Only cops behind you, in that mirror's sector.
const CUE_REAR_M := 220.0
const CUE_SIDE_M := 90.0
const CUE_SIDE_X := 1.6          # lateral offset that puts a cop in a side mirror


static func cop_cue(kind: String, rel: Vector3) -> float:
	if rel.z <= 1.0:
		return 0.0  # alongside or ahead: you can see it through the windscreen
	var d := Vector2(rel.x, rel.z).length()
	match kind:
		"rear":
			return 0.0 if d > CUE_REAR_M else lerpf(1.0, 0.35, d / CUE_REAR_M)
		"left":
			return 0.0 if d > CUE_SIDE_M or rel.x > -CUE_SIDE_X else lerpf(1.0, 0.35, d / CUE_SIDE_M)
		"right":
			return 0.0 if d > CUE_SIDE_M or rel.x < CUE_SIDE_X else lerpf(1.0, 0.35, d / CUE_SIDE_M)
	return 0.0
