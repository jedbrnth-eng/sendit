# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Mirrors the scoring tests of the earlier Unreal Engine prototype so both engines score identically.

var runner


func _s() -> GapScorer:
	return GapScorer.new()


func test_base_gap_is_100_points() -> void:
	var s := _s()
	runner.check(s.on_pass(80.0, 2.5) == 100, "80 km/h at max clearance = base 100")
	runner.check(s.combo_count == 1, "combo count 1")


func test_closer_and_faster_score_more() -> void:
	runner.check(_s().on_pass(200.0, 0.3) > _s().on_pass(200.0, 2.0), "closer scores more")
	runner.check(_s().on_pass(250.0, 1.0) > _s().on_pass(120.0, 1.0), "faster scores more")
	runner.check(_s().on_pass(150.0, 1.0, true) > _s().on_pass(150.0, 1.0, false), "split bonus")


func test_ignored_inputs() -> void:
	var s := _s()
	runner.check(s.on_pass(79.0, 0.5) == 0, "too slow")
	runner.check(s.on_pass(150.0, 2.6) == 0, "too wide")
	runner.check(s.on_pass(150.0, -1.0) == 0, "negative clearance")
	runner.check(s.on_pass(NAN, 1.0) == 0, "NaN speed")
	runner.check(s.combo_count == 0 and s.combo_points == 0, "nothing counted")


func test_multiplier_steps_and_caps() -> void:
	var s := _s()
	s.on_pass(150.0, 1.0)
	runner.check(is_equal_approx(s.multiplier, 1.25), "one step")
	for i in 100:
		s.on_pass(150.0, 1.0)
	runner.check(is_equal_approx(s.multiplier, 10.0), "capped at 10")


func test_combo_banks_after_window() -> void:
	var s := _s()
	s.on_pass(150.0, 1.0)
	s.on_pass(150.0, 1.0)
	var live := s.combo_points
	s.tick(2.9)
	runner.check(s.banked_total == 0, "not banked inside window")
	s.on_pass(150.0, 1.0)  # resets window
	s.tick(2.9)
	runner.check(s.banked_total == 0, "window reset by new gap")
	s.tick(0.2)
	runner.check(s.banked_total > live, "banked after window")
	runner.check(s.combo_count == 0 and is_equal_approx(s.multiplier, 1.0), "combo reset after bank")


func test_crash_wipes_unbanked_only() -> void:
	var s := _s()
	s.on_pass(150.0, 1.0)
	s.tick(3.1)
	var bank := s.banked_total
	s.on_pass(200.0, 0.2)
	s.on_crash()
	runner.check(s.banked_total == bank, "banked kept")
	runner.check(s.combo_points == 0 and is_equal_approx(s.multiplier, 1.0), "live wiped")


func test_tick_ignores_bad_delta() -> void:
	var s := _s()
	s.on_pass(150.0, 1.0)
	s.tick(-5.0)
	s.tick(NAN)
	runner.check(s.banked_total == 0 and s.combo_count == 1, "bad delta ignored")
