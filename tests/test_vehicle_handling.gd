extends RefCounted
## Handling and car-visual maths that does not need a scene.

var runner

const DT := 1.0 / 120.0


## Full-steer tap of `tap_s` at `kmh`, then hands off. Returns [lateral m, settle s].
func _tap(kmh: float, tap_s: float) -> Array:
	var yaw := 0.0
	var x := 0.0
	var v := kmh / 3.6
	var t := 0.0
	var settled := -1.0
	while t < 4.0:
		var steer := 1.0 if t < tap_s else 0.0
		yaw = PlayerCar.steer_step(yaw, steer, v, 1.0, DT)
		x += -sin(yaw) * v * DT
		t += DT
		if t > tap_s and settled < 0.0 and absf(yaw) < 0.004:
			settled = t
	return [absf(x), settled]


func test_tap_at_250_is_about_one_lane_and_settles() -> void:
	var r := _tap(250.0, 0.25)
	runner.check(r[0] > 2.5 and r[0] < 5.5, "0.25 s tap moves ~one lane (got %.2f m)" % r[0])
	runner.check(r[1] > 0.0 and r[1] < 1.3, "heading settles within 1.3 s (got %.2f s)" % r[1])


func test_steering_still_bites_at_300() -> void:
	var r := _tap(300.0, 0.4)
	runner.check(r[0] > 3.0, "0.4 s tap at 300 km/h still clears a lane (got %.2f m)" % r[0])


func test_yaw_is_clamped() -> void:
	var yaw := 0.0
	for i in 600:
		yaw = PlayerCar.steer_step(yaw, 1.0, 10.0, 1.0, DT)
	runner.check(absf(yaw) <= deg_to_rad(28) + 1e-4, "yaw never exceeds max")


func test_wheel_spin_matches_distance() -> void:
	# 1 s at 2*PI*r m/s is exactly one revolution.
	var a := CarBody.wrap_spin(0.0, TAU * 0.33, 1.0, 0.33)
	runner.check(is_equal_approx(a, 0.0) or is_equal_approx(a, TAU), "one revolution wraps to 0")
	runner.check(is_equal_approx(CarBody.wrap_spin(0.0, 0.33, 0.5, 0.33), 0.5), "half a radian")


func test_brake_light_levels() -> void:
	runner.check(TrafficCar.brake_light(0.5) == 0.0, "accelerating: off")
	runner.check(TrafficCar.brake_light(-0.2) == 0.0, "gentle lift: off")
	runner.check(TrafficCar.brake_light(-1.0) > 0.4, "braking: on")
	runner.check(TrafficCar.brake_light(-6.0) == 1.0, "hard braking: full")


func test_autopilot_stop_need_grows_with_closing_speed() -> void:
	var slow := Autopilot.stop_need(64.0, 60.0)
	var fast := Autopilot.stop_need(64.0, 18.0)
	runner.check(fast > slow + 50.0, "closing on a truck needs far more road (%.0f vs %.0f)" % [fast, slow])
	# Must be able to stop from the closing speed with the car's real 16 m/s^2.
	runner.check(fast > (46.0 * 46.0) / (2.0 * 16.0), "need covers physical stopping distance")
