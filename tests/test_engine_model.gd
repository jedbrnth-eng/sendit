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
	runner.check(p10 <= 2.01, "capped at one octave")


func test_rolling_start_picks_gear() -> void:
	var m := EngineModel.new()
	m.update(120.0, 1.0, 1.0 / 120.0)
	runner.check(m.gear >= 2, "120 km/h starts in 3rd or higher, got %d" % (m.gear + 1))
	runner.check(m.rpm > 3000.0 and m.rpm < 7000.0, "rpm in the band, got %d" % m.rpm)
