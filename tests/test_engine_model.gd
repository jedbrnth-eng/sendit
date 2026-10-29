# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Engine sound model: gears with hysteresis, RPM drop on upshift, combo ding pitch.

var runner


func _sweep(m: EngineModel, from: float, to: float, throttle: float, seconds: float) -> Array:
	var gears := []
	var steps := int(seconds * 120.0)
	for i in steps:
		var kmh := lerpf(from, to, float(i) / steps)
		m.update(kmh, throttle, 1.0 / 120.0)
		gears.append(m.gear)
	return gears


func test_gears_rise_with_speed() -> void:
	var m := EngineModel.new()
	var gears := _sweep(m, 0.0, 300.0, 1.0, 20.0)
	var ok := true
	for i in range(1, gears.size()):
		if gears[i] < gears[i - 1]:
			ok = false
	runner.check(ok, "never downshifts while accelerating")
	runner.check(m.gear == EngineModel.TOPS.size() - 1, "top gear at 300 km/h, got %d" % m.gear)


func test_upshift_drops_rpm() -> void:
	var m := EngineModel.new()
	var before := 0.0
	var dropped := false
	for i in 1200:
		m.update(i * 0.1, 1.0, 1.0 / 120.0)
		if m.shift_t == 0.0 and before > 0.0:
			# Settle a little and compare: rpm must fall after a shift.
			var g := m.gear
			for k in 20:
				m.update(i * 0.1, 1.0, 1.0 / 120.0)
			dropped = m.rpm < before - 1000.0 and m.gear == g
			break
		before = m.rpm
	runner.check(dropped, "rpm falls by >1000 after the first upshift")


func test_rpm_stays_in_range() -> void:
	var m := EngineModel.new()
	var ok := true
	for kmh in [0.0, 5.0, 60.0, 140.0, 230.0, 310.0, 400.0]:
		for i in 240:
			m.update(kmh, 1.0, 1.0 / 120.0)
		if m.rpm < m.idle_rpm - 1.0 or m.rpm > m.redline_rpm + 1.0:
			ok = false
	runner.check(ok, "idle <= rpm <= redline")


func test_steady_speed_holds_gear() -> void:
	var m := EngineModel.new()
	_sweep(m, 0.0, 230.0, 1.0, 12.0)
	for i in 240:  # lift to cruise: one short-shift here is expected
		m.update(230.0, 0.3, 1.0 / 120.0)
	var shifts := 0
	var g := m.gear
	for i in 600:
		m.update(230.0 + sin(i * 0.3) * 2.0, 0.3, 1.0 / 120.0)
		if m.gear != g:
			shifts += 1
			g = m.gear
	runner.check(shifts == 0, "no gear hunting at cruise, shifts=%d" % shifts)


func test_ding_pitch_rises_with_multiplier() -> void:
	var p1 := CarAudio.ding_pitch(1.0)
	var p2 := CarAudio.ding_pitch(2.0)
	var p10 := CarAudio.ding_pitch(10.0)
	runner.check(is_equal_approx(p1, 1.0), "x1 is the base pitch")
	runner.check(p2 > p1 and p10 > p2, "rises with multiplier")
	runner.check(p10 <= pow(2.0, 21.0 / 12.0) + 0.001, "capped at the ladder top (D5 -> B6)")


func test_rolling_start_picks_gear() -> void:
	var m := EngineModel.new()
	m.update(120.0, 1.0, 1.0 / 120.0)
	runner.check(m.gear >= 2, "120 km/h starts in 3rd or higher, got %d" % (m.gear + 1))
	runner.check(m.rpm > 3000.0 and m.rpm < 7000.0, "rpm in the band, got %d" % m.rpm)


## Regression (audio scenario after a crash): speed falls 252 -> 35 km/h, then the car pulls
## back up hard (~25 km/h/s) at part throttle. Part throttle must never sit on the limiter
## or scream near the redline in a low gear; it upshifts on time.
func test_part_throttle_recovery_after_crash_never_hits_limiter() -> void:
	for thr in [0.8, 0.8000001, 0.85, 0.9]:  # the scenario's 0.8 arrived as 0.8000001 and rode the limiter
		_recover_at(thr)


func _recover_at(thr: float) -> void:
	var m := EngineModel.new()
	var dt := 1.0 / 60.0
	for i in 60 * 30:
		m.update(minf(252.0, i * 0.15), 1.0, dt)
	var kmh := 35.0
	var max_rpm := 0.0
	var cut := false
	var at_66 := 0.0
	for i in 60 * 4:
		kmh += 25.0 * dt
		m.update(kmh, thr, dt)
		if i > 30:  # allow the post-drop downshift settle
			max_rpm = maxf(max_rpm, m.rpm)
		cut = cut or m.fuel_cut
		if absf(kmh - 66.0) < 0.3:
			at_66 = m.rpm
	runner.check(not cut, "throttle %.7f never cuts on the limiter" % thr)
	runner.check(max_rpm < 7500.0, "throttle %.7f stays under 7500 rpm, max %d" % [thr, max_rpm])
	runner.check(at_66 > 2500.0 and at_66 < 7000.0, "66 km/h at throttle %.7f reads a sane rpm, got %d" % [thr, at_66])


## Same recovery at a 60 Hz audio tick with the speed dropping in one frame (crash): the gear
## settles within ~1 s to one whose rpm sits in the working band, not idle and not redline.
func test_gear_settles_quickly_after_a_sudden_speed_drop() -> void:
	var m := EngineModel.new()
	var dt := 1.0 / 60.0
	for i in 60 * 30:
		m.update(minf(252.0, i * 0.15), 1.0, dt)
	for i in 60:
		m.update(35.0, 0.8, dt)
	runner.check(m.rpm > 2200.0 and m.rpm < 6000.0, "rpm in the working band 1 s after the drop, got %d (gear %d)" % [m.rpm, m.gear + 1])
