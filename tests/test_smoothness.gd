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
