# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ChaseCamera extends Camera3D
## Low chase cam: lags on lateral moves, widens FOV with speed, shakes on crashes,
## and a hood cam toggle ("camera" action). Proof shots: launch arg --cam=rear|front|side|wheel
## parks the camera close to the player car.

var target: PlayerCar
var shake := 0.0
var hood := false
var proof := ""
var _vel_x := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0
var _kick := Vector3.ZERO           # crash recoil offset, springs back

const PROOF := {
	"rear": [Vector3(-2.6, 0.9, 5.2), Vector3(0, 0.6, -1.0)],
	"front": [Vector3(2.8, 1.0, -6.0), Vector3(0, 0.5, 0.0)],
	"side": [Vector3(4.6, 0.8, 0.4), Vector3(0, 0.5, 0.0)],
	"wheel": [Vector3(2.2, 0.45, -2.8), Vector3(0.9, 0.35, -1.4)],
}


var _steer := 0.0                    # camera's own smoothed steer (bank / look offset)


func _ready() -> void:
	# Updated every rendered frame from the target's interpolated transform; interpolating the
	# camera itself again would add a frame of lag.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.1
	far = 4000.0
	_noise.frequency = 3.0
	proof = String(LaunchArgs.get_value("cam", ""))
	if proof == "hood":
		hood = true  # proof shot of the in-car view the "camera" action toggles


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("camera"):
		hood = not hood


func _process(delta: float) -> void:
	if target == null:
		return
	_t += delta
	if PROOF.has(proof):
		var basis_t := target.global_basis
		global_position = target.global_position + basis_t * PROOF[proof][0]
		look_at(target.global_position + basis_t * PROOF[proof][1], Vector3.UP)
		fov = 50.0
		return
	var kmh := target.kmh()
	var sp := clampf(kmh / 280.0, 0.0, 1.0)
	fov = lerpf(fov, lerpf(62.0, 84.0, sp * sp), delta * 3.0)
	# Physics runs at 120 Hz, rendering at the display rate: follow the *interpolated* car or it
	# judders against the camera (the "laggy, shaky" steering players reported).
	var xf := target.get_global_transform_interpolated()
	var tp := xf.origin
	var heading := -xf.basis.z
	heading.y = 0.0
	heading = heading.normalized()
	_steer = lerpf(_steer, target.steer_input, clampf(delta * 4.0, 0.0, 1.0))
	var want: Vector3
	var look: Vector3
	cull_mask = (0xFFFFF & ~2) if hood else 0xFFFFF  # layer 2 = hero DRL blades
	if hood:
		want = tp + xf.basis * Vector3(0, 1.18, -1.05)  # NFS-style hood cam (the old in-cabin view showed a flat red interior)
		look = want + xf.basis * Vector3(0, -0.02, -10)
	else:
		var back := lerpf(6.4, 7.6, sp)
		var up := lerpf(2.0, 1.75, sp)
		want = tp + Vector3(0, up, 0) - heading * back
		# Look a touch into the turn so lane darts read without the horizon swinging.
		look = tp + Vector3(0, 1.0, 0) + heading * 12.0 + Vector3(_steer * sp * 0.5, 0, 0)
	var p := global_position
	p.x = lerpf(p.x, want.x, delta * (30.0 if hood else 7.0))
	p.y = lerpf(p.y, want.y, delta * 10.0)
	p.z = want.z  # never lag along the road: at 300 km/h lag reads as stutter
	_kick = _kick.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	var jitter := Vector3.ZERO
	shake = maxf(0.0, shake - delta * 1.8)
	var rumble := sp * sp * 0.003
	var amp := shake * shake * 0.45 + rumble
	if amp > 0.0:
		jitter = Vector3(_noise.get_noise_2d(_t * 18.0, 0.0), _noise.get_noise_2d(0.0, _t * 18.0), 0) * amp
	global_position = p + jitter + _kick
	look_at(look + jitter * 0.5, Vector3.UP)
	# Bank slightly with the car's yaw rate for a sense of lateral g.
	rotate_object_local(Vector3.BACK, -_steer * sp * 0.015)


func add_shake(amount: float) -> void:
	shake = clampf(shake + amount, 0.0, 1.2)
	# Big hits also punch the camera back and up a little.
	if amount > 0.25:
		_kick += Vector3(0, amount * 0.25, amount * 0.9)
