# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarBody extends Node3D
## Root of a built car visual (see CarModel.build). Drives the per-car bits that change at runtime:
## brake-light boost, wheel spin and front-wheel steer.

var lamp_geoms: Array[GeometryInstance3D] = []   # tail lenses, tail flares, brake pools ("boost")
var wheels: Array[Node3D] = []                   # spin pivots, one per wheel node
var wheel_axis: Array[Vector3] = []              # car X in each pivot's parent space
var wheel_up: Array[Vector3] = []                # car Y in each pivot's parent space
var wheel_front: Array[bool] = []
var wheel_rest: Array[Basis] = []                # undoes a turned rest pose
var wheel_radius := 0.33
var spin := 0.0
var brake := 0.0


## Brake-light level 0..1 (0 = running lights only).
func set_brake(b: float) -> void:
	b = clampf(b, 0.0, 1.0)
	if absf(b - brake) < 0.02 and not (b == 0.0 and brake != 0.0):
		return
	brake = b
	for g in lamp_geoms:
		g.set_instance_shader_parameter("boost", b)


## Advance wheel roll by distance travelled; `steer` turns the front wheels (radians).
func roll(speed_mps: float, delta: float, steer := 0.0) -> void:
	spin = wrap_spin(spin, speed_mps, delta, wheel_radius)
	for i in wheels.size():
		var b := Basis(wheel_axis[i], -spin) * wheel_rest[i]  # forward roll: tyre top moves toward -Z
		if wheel_front[i] and steer != 0.0:
			b = Basis(wheel_up[i], steer) * b
		wheels[i].basis = b


static func wrap_spin(angle: float, speed_mps: float, delta: float, radius: float) -> float:
	return fposmod(angle + speed_mps / maxf(radius, 0.05) * delta, TAU)
