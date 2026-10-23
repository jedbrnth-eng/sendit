extends RefCounted

var runner


func test_speed_fx_off_at_cruise_full_at_top_speed() -> void:
	runner.check(SpeedFx.amount_for(0.0) == 0.0, "no effect when stopped")
	runner.check(SpeedFx.amount_for(SpeedFx.START_KMH) == 0.0, "no effect at the start threshold")
	runner.check(is_equal_approx(SpeedFx.amount_for(SpeedFx.FULL_KMH), 1.0), "full effect at FULL_KMH")
	runner.check(is_equal_approx(SpeedFx.amount_for(400.0), 1.0), "clamped above FULL_KMH")


func test_speed_fx_is_monotonic() -> void:
	var prev := -1.0
	for kmh in range(0, 320, 10):
		var a := SpeedFx.amount_for(kmh)
		runner.check(a >= prev, "non-decreasing at %d km/h" % kmh)
		prev = a
