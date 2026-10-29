# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name EngineModel extends RefCounted
## Sound-only drivetrain: picks a gear from road speed (with hysteresis so it never hunts),
## derives RPM, sweeps RPM down over a short shift, bounces off the rev limiter before a
## full-throttle upshift (ignition cut ~10 Hz), and tracks the overrun after a lift (crackle).
## Also the crossfade maths for the RPM/load loop layers. Unit-tested by
## tests/test_engine_model.gd and tests/test_audio_logic.gd.

## km/h at the redline in each gear.
const TOPS := [64.0, 108.0, 152.0, 200.0, 252.0, 330.0]
const LIMIT_CUT_S := 0.045      # ignition cut length per limiter bounce
const LIMIT_DIP_RPM := 260.0    # how far the revs fall during one cut
const LIMIT_HOLD_S := 0.2       # time spent bouncing on the limiter before a full-throttle upshift
## Pedal at or above this = flat out (rev to the limiter, bounce, shift). Below it the box upshifts
## early by load. Was "> 0.8": a scripted 0.8 arrived as 0.8000001 and rode the limiter at part throttle.
const FULL_THROTTLE := 0.95

var idle_rpm := 950.0
var redline_rpm := 7800.0
var gear := 0
var rpm := 950.0
var shift_t := 1.0          # seconds since the last gear change
var shift_up := false       # last change was an upshift
var shift_events := 0       # increments on every gear change (the audio watches it)
var load := 0.0             # smoothed throttle 0..1
var fuel_cut := false       # limiter cutting ignition right now
var hold_gear := false      # never upshift (tests / stuck in gear): sits on the limiter
var lift_t := 99.0          # seconds since the throttle was lifted (overrun clock)
var lift_rpm := 0.0         # rpm when the throttle was lifted
var _primed := false
var _limit_t := 0.0         # time in the current cut / recovery phase
var _on_limit_t := 0.0      # time spent on the limiter in this gear
var _last_throttle := 0.0


## RPM the engine would turn in gear `g` at `kmh`.
func rpm_in(g: int, kmh: float) -> float:
	return clampf(kmh / TOPS[g] * redline_rpm, idle_rpm, redline_rpm)


func update(kmh: float, throttle: float, delta: float) -> void:
	throttle = clampf(throttle, 0.0, 1.0)
	if not _primed:
		# First call: drop straight into the gear that suits a rolling start, no shift storm.
		_primed = true
		load = throttle
		while gear < TOPS.size() - 1 and rpm_in(gear, kmh) >= 6000.0:
			gear += 1
		rpm = rpm_in(gear, kmh)
	load = lerpf(load, throttle, clampf(delta * 2.5, 0.0, 1.0))
	shift_t += delta
	# Overrun clock: starts when a held throttle is let go.
	if throttle < 0.15 and _last_throttle >= 0.15:
		lift_t = 0.0
		lift_rpm = rpm
	elif throttle >= 0.15:
		lift_t = 99.0
	else:
		lift_t += delta
	_last_throttle = throttle
	# Upshift point moves with load: short-shift when cruising; under full throttle rev it out
	# all the way to the limiter, bounce a beat, then shift.
	var full := throttle >= FULL_THROTTLE
	var up_at := lerpf(5200.0, 7400.0, load)
	if shift_t > 0.25 and not hold_gear:
		var go_up := false
		if gear < TOPS.size() - 1:
			if full:
				go_up = rpm_in(gear, kmh) >= redline_rpm - 1.0 and _on_limit_t >= LIMIT_HOLD_S
			else:
				go_up = rpm_in(gear, kmh) >= up_at
		if go_up:
			_shift(1)
		elif gear > 0 and rpm_in(gear - 1, kmh) < up_at * 0.72:
			_shift(-1)
	var target := rpm_in(gear, kmh)
	if kmh < 3.0:
		target = idle_rpm
	# Rev limiter: on throttle at redline the ECU cuts ignition, revs dip, recover, repeat.
	if throttle > 0.5 and target >= redline_rpm - 1.0:
		_on_limit_t += delta
		_limit_t += delta
		if fuel_cut:
			target = redline_rpm - LIMIT_DIP_RPM
			if _limit_t >= LIMIT_CUT_S:
				fuel_cut = false
				_limit_t = 0.0
		elif _limit_t >= LIMIT_CUT_S and rpm >= redline_rpm - 40.0:
			fuel_cut = true
			_limit_t = 0.0
	else:
		fuel_cut = false
		_limit_t = 0.0
		if target < redline_rpm - 200.0:
			_on_limit_t = 0.0
	# Clutch-in sweep: fast fall on upshifts, quick blip on downshifts, otherwise track closely.
	var rate := 14.0 if shift_t < 0.18 else 30.0
	if fuel_cut:
		rate = 40.0
	rpm = clampf(lerpf(rpm, target, clampf(delta * rate, 0.0, 1.0)), idle_rpm, redline_rpm)


func _shift(dir: int) -> void:
	gear += dir
	shift_t = 0.0
	shift_up = dir > 0
	shift_events += 1
	fuel_cut = false
	_on_limit_t = 0.0
	_limit_t = 0.0


## 0..1 volume factor: a short throttle cut right after an upshift.
func shift_cut() -> float:
	if not shift_up or shift_t > 0.14:
		return 1.0
	return lerpf(0.45, 1.0, shift_t / 0.14)


## 0..1 position in the rev range.
func rev() -> float:
	return (rpm - idle_rpm) / (redline_rpm - idle_rpm)


## Effective load for the on/off loop blend: the ignition cut and the shift cut drop it.
func sound_load() -> float:
	if fuel_cut:
		return 0.0
	return load * shift_cut()


## Overrun pops per second for a profile with `crackle` 0..1: only off throttle, at revs,
## strongest right after the lift and gone after ~2.5 s.
func crackle_rate(crackle: float) -> float:
	if crackle <= 0.0 or lift_t > 2.5 or _last_throttle >= 0.15:
		return 0.0
	var revs := clampf((maxf(rpm, lift_rpm * 0.8) - 3200.0) / 4300.0, 0.0, 1.0)
	return crackle * 9.0 * revs * (1.0 - lift_t / 2.5)


## Equal-power crossfade weights over loops recorded at `points` rpm: the two loops bracketing
## `rpm_now` share it (sum of squares = 1), every other loop is silent.
static func rpm_weights(rpm_now: float, points: Array) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(points.size())
	if rpm_now <= float(points[0]):
		w[0] = 1.0
		return w
	if rpm_now >= float(points[-1]):
		w[points.size() - 1] = 1.0
		return w
	var hi := 1
	while rpm_now > float(points[hi]):
		hi += 1
	var x := (rpm_now - float(points[hi - 1])) / (float(points[hi]) - float(points[hi - 1]))
	w[hi - 1] = cos(x * PI * 0.5)
	w[hi] = sin(x * PI * 0.5)
	return w


## Equal-power on-load (x) / overrun (y) blend.
static func load_weights(l: float) -> Vector2:
	var k := clampf(l, 0.0, 1.0)
	return Vector2(sin(k * PI * 0.5), cos(k * PI * 0.5))
