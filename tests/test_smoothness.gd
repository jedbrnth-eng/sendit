# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Smoothness guarantees behind the "laggy / shaky / cars glitching" playtest reports.

var runner


func test_keyboard_steer_ramps_not_snaps() -> void:
	var s := 0.0
	var dt := 1.0 / 120.0
	s = PlayerCar.ramp_steer(s, 1.0, dt)
	runner.check(s > 0.0 and s < 0.1, "one tick moves only a little (%.3f)" % s)
	var ticks := 1
	while s < 1.0 and ticks < 200:
		s = PlayerCar.ramp_steer(s, 1.0, dt)
		ticks += 1
	runner.check(ticks >= 20 and ticks <= 30, "full lock in ~0.2 s (%d ticks)" % ticks)
	var back := 0
	while s > 0.0 and back < 200:
		s = PlayerCar.ramp_steer(s, 0.0, dt)
		back += 1
	runner.check(back < ticks, "release recentres faster than it builds (%d vs %d)" % [back, ticks])


func test_lane_change_eases_in_and_out_without_overshoot() -> void:
	var x := 0.0
	var v := 0.0
	var target := RoadSpec.LANE_W
	var dt := 1.0 / 120.0
	var max_dv := 0.0
	var max_x := 0.0
	var t := 0.0
	var settled_at := -1.0
	while t < 6.0:
		var r := TrafficCar.lateral_step(x, target, v, dt)
		max_dv = maxf(max_dv, absf(r.y - v))
		x = r.x
		v = r.y
		max_x = maxf(max_x, x)
		t += dt
		if settled_at < 0.0 and absf(target - x) < 0.05 and absf(v) < 0.05:
			settled_at = t
	runner.check(max_x <= target + 0.05, "no overshoot past the lane centre (%.3f)" % max_x)
	runner.check(settled_at > 1.5 and settled_at < 4.5, "settles in a natural 1.5-4.5 s (%.2f)" % settled_at)
	runner.check(max_dv < 0.06, "lateral velocity changes smoothly per tick (max %.4f m/s)" % max_dv)


func test_lane_yaw_follows_lateral_velocity_and_is_bounded() -> void:
	runner.check(is_equal_approx(TrafficCar.lane_yaw(0.0, 30.0), 0.0), "straight when not moving sideways")
	runner.check(TrafficCar.lane_yaw(1.8, 30.0) > 0.0, "signed with lateral motion")
	runner.check(absf(TrafficCar.lane_yaw(50.0, 0.0)) <= 0.15, "capped even when stopped")


func test_analog_stick_steers_directly_keys_still_ramp() -> void:
	var dt := 1.0 / 120.0
	runner.check(is_equal_approx(PlayerCar.steer_from_input(0.0, 1.0, true, dt), 1.0), "full stick: full lock on the first tick (no 0.2 s ramp)")
	var half := PlayerCar.steer_from_input(0.0, 0.5, true, dt)
	runner.check(half > 0.3 and half < 0.5, "half stick: a little under half lock at once (gentle centre curve, %.3f)" % half)
	runner.check(is_equal_approx(PlayerCar.steer_from_input(0.8, 0.0, true, dt), 0.0), "stick released: straight back to centre")
	runner.check(is_equal_approx(PlayerCar.steer_from_input(0.0, -1.0, true, dt), -1.0), "and the same to the left")
	runner.check(absf(PlayerCar.steer_from_input(0.0, 0.03, true, dt)) < 0.001, "a resting stick's noise does not steer")
	var key := PlayerCar.steer_from_input(0.0, 1.0, false, dt)
	runner.check(is_equal_approx(key, PlayerCar.ramp_steer(0.0, 1.0, dt)), "keys keep the ramp (%.3f)" % key)


func test_steer_source_follows_the_last_device() -> void:
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.7
	runner.check(PlayerCar.analog_after(false, stick) == true, "a stick push switches to analog steering")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.05
	runner.check(PlayerCar.analog_after(false, drift) == false, "stick drift under the deadzone does not steal the keyboard")
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_RIGHT
	trig.axis_value = 1.0
	runner.check(PlayerCar.analog_after(false, trig) == false, "the throttle trigger is not steering")
	for a in ["steer_left", "steer_right"]:  # no Boot autoload in the test runner
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var ka := InputEventKey.new()
	ka.physical_keycode = KEY_A
	if not InputMap.action_has_event("steer_left", ka):
		InputMap.action_add_event("steer_left", ka)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_A
	k.pressed = true
	runner.check(PlayerCar.analog_after(true, k) == false, "a steer key press switches back to the keyboard ramp")
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	runner.check(PlayerCar.analog_after(true, w) == true, "other keys (keyboard throttle with stick steering) keep analog")
