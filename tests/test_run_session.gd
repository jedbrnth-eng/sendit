# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Run flow: countdown -> 3-minute run (or 3 wrecks) -> results. Pure logic, no nodes.

var runner


func test_countdown_then_running() -> void:
	var r := RunSession.new()
	r.start()
	runner.check(r.state == RunSession.State.COUNTDOWN, "starts in countdown")
	runner.check(r.countdown_number() == 3, "shows 3 first")
	r.tick(1.5, 120.0)
	runner.check(r.countdown_number() == 2, "shows 2 after 1.5 s")
	runner.check(r.distance_m == 0.0, "no distance counted during countdown")
	r.tick(1.6, 120.0)
	runner.check(r.state == RunSession.State.RUNNING, "running after 3 s")
	runner.check(is_equal_approx(r.time_left, r.duration_s), "clock starts full")


func test_skip_countdown() -> void:
	var r := RunSession.new()
	r.start(false)
	runner.check(r.state == RunSession.State.RUNNING, "straight into the run")


func test_time_runs_out() -> void:
	var r := RunSession.new()
	r.start(false)
	for i in 179:
		r.tick(1.0, 200.0)
	runner.check(r.state == RunSession.State.RUNNING, "still running at 179 s")
	runner.check(r.clock_text() == "0:01", "clock 0:01, got " + r.clock_text())
	r.tick(1.0, 200.0)
	runner.check(r.state == RunSession.State.RESULTS and r.end_reason == "time", "time up")
	runner.check(is_equal_approx(r.max_kmh, 200.0), "max speed tracked")
	runner.check(absf(r.distance_m - 200.0 / 3.6 * 180.0) < 1.0, "distance integrated")


func test_three_wrecks_end_the_run() -> void:
	var r := RunSession.new()
	r.start(false)
	r.on_wreck()
	r.on_wreck()
	runner.check(r.state == RunSession.State.RUNNING and r.wrecks_left() == 1, "one wreck left")
	r.on_wreck()
	runner.check(r.state == RunSession.State.RESULTS and r.end_reason == "wrecks", "wrecked out")
	r.on_wreck()
	runner.check(r.wrecks == 3, "wrecks after the end are ignored")


func test_events_only_count_while_running() -> void:
	var r := RunSession.new()
	r.on_gap()
	r.on_wreck()
	r.tick(1.0, 300.0)
	runner.check(r.gaps == 0 and r.wrecks == 0 and r.max_kmh == 0.0, "attract mode counts nothing")
	r.start()
	r.on_gap()
	runner.check(r.gaps == 0, "no gaps during countdown")


func test_clock_text() -> void:
	var r := RunSession.new()
	r.start(false)
	runner.check(r.clock_text() == "3:00", "full clock, got " + r.clock_text())
	r.tick(0.4, 0.0)
	runner.check(r.clock_text() == "3:00", "rounds up partial seconds")
	r.tick(50.0, 0.0)
	runner.check(r.clock_text() == "2:10", "got " + r.clock_text())


func test_bad_delta_ignored() -> void:
	var r := RunSession.new()
	r.start(false)
	r.tick(NAN, 100.0)
	r.tick(-3.0, 100.0)
	runner.check(is_equal_approx(r.time_left, r.duration_s), "bad delta ignored")
